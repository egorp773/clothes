from __future__ import annotations

import json
import logging
import threading
from dataclasses import dataclass

from PIL import Image

from app.catalog import (
    ALLOWED_ATTRIBUTES,
    CATEGORY_ATTRIBUTES,
    attribute_options_for,
    normalize_category,
)
from app.config import Settings


LOGGER = logging.getLogger(__name__)


@dataclass(frozen=True)
class VlmAttributes:
    values: dict[str, str | None]
    confidence: float
    model: str


class QwenAdapter:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._model = None
        self._processor = None
        self._model_id = settings.qwen_model_id

    @property
    def model_name(self) -> str:
        return self._model_id

    @property
    def available(self) -> bool:
        if not self.settings.enable_qwen:
            return False
        try:
            import torch

            return torch.cuda.is_available() or self.settings.allow_qwen_cpu
        except ImportError:
            return False

    @property
    def loaded(self) -> bool:
        return self._loaded

    @property
    def detail(self) -> str | None:
        if not self.settings.enable_qwen:
            return "disabled by ENABLE_QWEN"
        if not self.available:
            return "no CUDA device; set ALLOW_QWEN_CPU=true to force CPU"
        return self._load_error

    def load(self) -> None:
        if self._loaded:
            return
        with self._lock:
            if self._loaded:
                return
            if not self.available:
                raise RuntimeError(self.detail)
            try:
                self._load_model(
                    self.settings.qwen_model_id,
                    self.settings.qwen_model_revision,
                )
            except Exception:
                LOGGER.exception("Unable to load primary Qwen model; trying 2B fallback")
                self._load_model(
                    self.settings.qwen_fallback_model_id,
                    self.settings.qwen_fallback_model_revision,
                )

    def _load_model(self, model_id: str, revision: str) -> None:
        import torch
        from transformers import (
            AutoModelForImageTextToText,
            AutoProcessor,
            BitsAndBytesConfig,
        )

        kwargs: dict[str, object] = {"dtype": "auto", "device_map": "auto"}
        if self.settings.qwen_load_in_4bit and torch.cuda.is_available():
            kwargs["quantization_config"] = BitsAndBytesConfig(
                load_in_4bit=True,
                bnb_4bit_compute_dtype=torch.bfloat16,
                bnb_4bit_quant_type="nf4",
            )
        self._model = AutoModelForImageTextToText.from_pretrained(
            model_id,
            revision=revision,
            **kwargs,
        )
        self._processor = AutoProcessor.from_pretrained(
            model_id,
            revision=revision,
        )
        self._model_id = model_id
        self._model.eval()
        self._loaded = True
        self._load_error = None
        LOGGER.info("Loaded %s", model_id)

    def analyze(
        self,
        images: list[Image.Image],
        cutout: Image.Image | None,
        category: str,
    ) -> VlmAttributes:
        self.load()
        with self._lock:
            content: list[dict[str, object]] = [
                {"type": "image", "image": image.convert("RGB")} for image in images
            ]
            if cutout is not None:
                content.append({"type": "image", "image": cutout.convert("RGB")})
            normalized_category = normalize_category(category) or category
            relevant_keys = CATEGORY_ATTRIBUTES.get(normalized_category, ())
            schema = {
                key: list(attribute_options_for(normalized_category, key))
                for key, values in ALLOWED_ATTRIBUTES.items()
                if key in relevant_keys or key == "gender"
            }
            prompt = (
                "Analyze only visible properties of the fashion item. "
                f"Known item type: {category}. Allowed values: {json.dumps(schema, ensure_ascii=False)}. "
                f"Return one strict JSON object with exactly these keys: {', '.join(schema)}. "
                "Each value must be one allowed identifier or null. Never guess an invisible property."
            )
            content.append({"type": "text", "text": prompt})
            messages = [{"role": "user", "content": content}]
            inputs = self._processor.apply_chat_template(
                messages,
                tokenize=True,
                add_generation_prompt=True,
                return_dict=True,
                return_tensors="pt",
            ).to(self._model.device)
            generated = self._model.generate(
                **inputs,
                max_new_tokens=self.settings.qwen_max_new_tokens,
                do_sample=False,
            )
            trimmed = [out[len(source) :] for source, out in zip(inputs.input_ids, generated)]
            text = self._processor.batch_decode(
                trimmed,
                skip_special_tokens=True,
                clean_up_tokenization_spaces=False,
            )[0]
            payload = self._parse_json(text)
            values: dict[str, str | None] = {}
            for key, allowed in ALLOWED_ATTRIBUTES.items():
                value = payload.get(key)
                category_allowed = schema.get(key, allowed)
                values[key] = (
                    value
                    if isinstance(value, str) and value in category_allowed
                    else None
                )
            return VlmAttributes(values=values, confidence=0.68, model=self._model_id)

    def _parse_json(self, text: str) -> dict[str, object]:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise ValueError("Qwen response does not contain JSON")
        value = json.loads(text[start : end + 1])
        if not isinstance(value, dict):
            raise ValueError("Qwen response JSON is not an object")
        return value
