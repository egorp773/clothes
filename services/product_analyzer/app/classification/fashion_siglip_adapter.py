from __future__ import annotations

import logging
import threading
from dataclasses import dataclass

import numpy as np
from PIL import Image

from app.catalog import CATEGORIES, CategoryDefinition
from app.config import Settings


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class FashionCandidate:
    definition: CategoryDefinition
    confidence: float


@dataclass(frozen=True)
class FashionEmbeddingResult:
    embedding: np.ndarray
    candidates: list[FashionCandidate]


class FashionSiglipAdapter:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._model = None
        self._processor = None
        self._device = "cpu"
        self._prompt_embeddings = None
        self._prompt_slices: list[tuple[int, int]] = []
        self._ocr_target_embeddings = None
        self._ocr_target_labels = ("garment", "tag", "label", "logo")
        self._text_embedding_cache: dict[tuple[str, ...], np.ndarray] = {}

    @property
    def model_name(self) -> str:
        return self.settings.fashion_model_id

    @property
    def available(self) -> bool:
        return True

    @property
    def loaded(self) -> bool:
        return self._loaded

    @property
    def detail(self) -> str | None:
        return self._load_error

    def load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            try:
                import torch
                from transformers import AutoConfig, AutoModel, AutoProcessor

                self._device = "cuda" if torch.cuda.is_available() else "cpu"
                # Marqo's repository intentionally exposes its OpenCLIP weights
                # through ``hf-hub:`` in custom model code, rather than a
                # transformers ``model.safetensors`` file.  ``from_pretrained``
                # therefore always fails after downloading only config.py.
                config = AutoConfig.from_pretrained(
                    self.settings.fashion_model_id,
                    revision=self.settings.fashion_model_revision,
                    trust_remote_code=True,
                )
                self._model = AutoModel.from_config(
                    config,
                    trust_remote_code=True,
                ).to(self._device)
                self._model.eval()
                self._processor = AutoProcessor.from_pretrained(
                    self.settings.fashion_model_id,
                    revision=self.settings.fashion_model_revision,
                    trust_remote_code=True,
                )
                prompts: list[str] = []
                for category in CATEGORIES:
                    start = len(prompts)
                    # Several legacy Russian prompts in the catalog were
                    # stored with broken encoding. They dilute otherwise good
                    # FashionSigLIP matches. The two canonical English prompts
                    # are stable and preserve the existing category taxonomy.
                    stable_prompts = [prompt for prompt in category.prompts if prompt.isascii()]
                    prompts.extend(stable_prompts or category.prompts[:2])
                    self._prompt_slices.append((start, len(prompts)))
                encoded = self._processor(
                    text=prompts,
                    padding="max_length",
                    return_tensors="pt",
                )
                input_ids = encoded["input_ids"].to(self._device)
                with torch.inference_mode():
                    self._prompt_embeddings = self._model.get_text_features(
                        input_ids,
                        normalize=True,
                    )
                    target_inputs = self._processor(
                        text=[
                            "a photograph of a garment or fashion item",
                            "a photograph of a clothing hang tag",
                            "a photograph of a clothing care label or size label",
                            "a close-up photograph of a brand logo on clothing",
                        ],
                        padding="max_length",
                        return_tensors="pt",
                    )
                    self._ocr_target_embeddings = self._model.get_text_features(
                        target_inputs["input_ids"].to(self._device),
                        normalize=True,
                    )
                self._loaded = True
                self._load_error = None
                LOGGER.info("Loaded %s on %s", self.model_name, self._device)
            except Exception as error:
                self._load_error = f"{type(error).__name__}: {error}"
                LOGGER.exception("Unable to load FashionSigLIP")
                raise

    def classify(self, image: Image.Image, top_k: int | None = None) -> list[FashionCandidate]:
        return self.embed_and_classify(image, top_k=top_k).candidates

    def classify_many(
        self,
        images: list[Image.Image],
        top_k: int | None = None,
    ) -> list[list[FashionCandidate]]:
        """Classify several garment crops in one image-tower forward pass."""
        return [
            result.candidates
            for result in self.embed_and_classify_many(images, top_k=top_k)
        ]

    @property
    def embedding_dimension(self) -> int:
        self.load()
        return int(self._prompt_embeddings.shape[-1])

    def embed(self, image: Image.Image) -> np.ndarray:
        return self.embed_and_classify(image, top_k=0).embedding

    def embed_and_classify(
        self,
        image: Image.Image,
        top_k: int | None = None,
    ) -> FashionEmbeddingResult:
        """Run the image tower once and return its normalized embedding."""
        return self.embed_and_classify_many([image], top_k=top_k)[0]

    def embed_and_classify_many(
        self,
        images: list[Image.Image],
        top_k: int | None = None,
    ) -> list[FashionEmbeddingResult]:
        """Return embeddings and category candidates for a small image batch.

        FashionSigLIP preprocessing accepts a batch natively.  Using it here is
        substantially cheaper than acquiring the model lock and running the
        image tower once for every garment in a multi-item photo.
        """
        if not images:
            return []
        self.load()
        with self._lock:
            import torch

            processed = self._processor(
                images=[image.convert("RGB") for image in images],
                return_tensors="pt",
            )
            pixel_values = processed["pixel_values"].to(self._device)
            with torch.inference_mode():
                image_features = self._model.get_image_features(pixel_values, normalize=True)
                prompt_scores = image_features @ self._prompt_embeddings.T
                category_scores = torch.stack(
                    [
                        prompt_scores[:, start:end].mean(dim=1)
                        for start, end in self._prompt_slices
                    ],
                    dim=1,
                )
                probabilities = torch.softmax(category_scores * 30.0, dim=1)
            requested = self.settings.classification_top_k if top_k is None else top_k
            limit = min(max(requested, 0), len(CATEGORIES))
            if limit:
                values, indices = torch.topk(probabilities, k=limit, dim=1)
                candidate_batches = [
                    [
                        FashionCandidate(CATEGORIES[int(index)], float(value))
                        for value, index in zip(row_values, row_indices)
                    ]
                    for row_values, row_indices in zip(values.cpu(), indices.cpu())
                ]
            else:
                candidate_batches = [[] for _ in images]
            embeddings = image_features.detach().float().cpu().numpy()
            norms = np.linalg.norm(embeddings, axis=1, keepdims=True)
            embeddings /= np.maximum(norms, 1e-12)
            return [
                FashionEmbeddingResult(embedding=embedding, candidates=candidates)
                for embedding, candidates in zip(embeddings, candidate_batches)
            ]

    def warmup(self) -> None:
        self.load()
        self.classify(Image.new("RGB", (224, 224), "white"), top_k=1)

    def classify_ocr_target(self, image: Image.Image) -> str | None:
        """Return an OCR-worthy image type only when SigLIP is confident."""
        self.load()
        with self._lock:
            import torch

            processed = self._processor(images=[image.convert("RGB")], return_tensors="pt")
            with torch.inference_mode():
                features = self._model.get_image_features(
                    processed["pixel_values"].to(self._device),
                    normalize=True,
                )
                scores = (features @ self._ocr_target_embeddings.T).squeeze(0)
                probabilities = torch.softmax(scores * 10.0, dim=0)
                confidence, index = torch.max(probabilities, dim=0)
            label = self._ocr_target_labels[int(index)]
            return label if label != "garment" and float(confidence) >= 0.55 else None

    def score_text_options(
        self,
        embedding: np.ndarray,
        options: dict[str, tuple[str, ...]],
        *,
        temperature: float = 12.0,
    ) -> dict[str, float]:
        """Score a small closed vocabulary without loading another model.

        Prompt embeddings are cached for the lifetime of the worker. This is
        used only by asynchronous enrichment, never on the publish request.
        """
        if not options:
            return {}
        self.load()
        labels = list(options)
        prompts: list[str] = []
        slices: list[tuple[int, int]] = []
        for label in labels:
            start = len(prompts)
            prompts.extend(options[label])
            slices.append((start, len(prompts)))
        cache_key = tuple(prompts)
        with self._lock:
            text_embeddings = self._text_embedding_cache.get(cache_key)
            if text_embeddings is None:
                import torch

                encoded = self._processor(
                    text=prompts,
                    padding="max_length",
                    return_tensors="pt",
                )
                with torch.inference_mode():
                    features = self._model.get_text_features(
                        encoded["input_ids"].to(self._device),
                        normalize=True,
                    )
                text_embeddings = features.detach().float().cpu().numpy()
                self._text_embedding_cache[cache_key] = text_embeddings
        vector = np.asarray(embedding, dtype=np.float32)
        raw = vector @ text_embeddings.T
        grouped = np.asarray(
            [float(raw[start:end].mean()) for start, end in slices],
            dtype=np.float64,
        )
        grouped = (grouped - grouped.max()) * temperature
        probabilities = np.exp(grouped)
        probabilities /= max(float(probabilities.sum()), 1e-12)
        return {
            label: float(probability)
            for label, probability in zip(labels, probabilities, strict=True)
        }
