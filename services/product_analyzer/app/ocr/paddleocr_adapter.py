from __future__ import annotations

import logging
import re
import threading
from dataclasses import dataclass
from typing import Any

import numpy as np
from PIL import Image

from app.config import Settings


LOGGER = logging.getLogger(__name__)
SIZE_PATTERN = re.compile(
    r"\b(?:XXS|XS|S|M|L|XL|XXL|XXXL|\d{2}(?:[.,]\d)?|\d{2}\s*[-–]\s*\d{2})\b",
    re.IGNORECASE,
)
COMPOSITION_PATTERN = re.compile(
    r"(?:cotton|хлопок|wool|шерсть|polyester|полиэстер|linen|л[её]н|"
    r"leather|кожа|viscose|вискоза|elastane|эластан|denim|деним)"
    r"[^\n]{0,80}",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class OcrResult:
    texts: list[str]
    size: str | None
    composition: str | None


class PaddleOcrAdapter:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._lock = threading.Lock()
        self._loaded = False
        self._load_error: str | None = None
        self._engine = None
        self._resolved_version = settings.paddleocr_version

    @property
    def model_name(self) -> str:
        return self._resolved_version

    @property
    def available(self) -> bool:
        if not self.settings.enable_paddleocr:
            return False
        try:
            import paddleocr  # noqa: F401

            return True
        except ImportError:
            return False

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
                from paddleocr import PaddleOCR

                # PaddleOCR 3.7 resolves the latest stable PP-OCR pipeline. The
                # explicit v6 name is attempted first and falls back to the
                # package's stable default when not published for this platform.
                try:
                    self._engine = PaddleOCR(
                        lang=self.settings.paddleocr_language,
                        ocr_version="PP-OCRv6",
                        use_doc_orientation_classify=False,
                        use_doc_unwarping=False,
                        use_textline_orientation=True,
                    )
                    self._resolved_version = "PP-OCRv6"
                except Exception:
                    LOGGER.warning("PP-OCRv6 unavailable; using stable PaddleOCR default")
                    self._engine = PaddleOCR(
                        lang=self.settings.paddleocr_language,
                        use_doc_orientation_classify=False,
                        use_doc_unwarping=False,
                        use_textline_orientation=True,
                    )
                    self._resolved_version = "PaddleOCR stable default"
                self._loaded = True
                self._load_error = None
                LOGGER.info("Loaded %s", self._resolved_version)
            except Exception as error:
                self._load_error = f"{type(error).__name__}: {error}"
                LOGGER.exception("Unable to load PaddleOCR")
                raise

    def recognize(self, images: list[Image.Image]) -> OcrResult:
        self.load()
        texts: list[str] = []
        with self._lock:
            for image in images:
                try:
                    result = self._engine.predict(np.asarray(image.convert("RGB")))
                    texts.extend(self._extract_text(result))
                except AttributeError:
                    result = self._engine.ocr(np.asarray(image.convert("RGB")), cls=True)
                    texts.extend(self._extract_text(result))
        unique = list(dict.fromkeys(text.strip() for text in texts if text.strip()))
        combined = "\n".join(unique)
        size_match = SIZE_PATTERN.search(combined)
        composition_match = COMPOSITION_PATTERN.search(combined)
        return OcrResult(
            texts=unique,
            size=size_match.group(0).upper() if size_match else None,
            composition=composition_match.group(0).strip() if composition_match else None,
        )

    def _extract_text(self, value: Any) -> list[str]:
        texts: list[str] = []
        if value is None:
            return texts
        if isinstance(value, str):
            return [value]
        if isinstance(value, dict):
            for key in ("rec_texts", "texts"):
                candidate = value.get(key)
                if isinstance(candidate, list):
                    texts.extend(str(item) for item in candidate)
            if "res" in value:
                texts.extend(self._extract_text(value["res"]))
            if "json" in value:
                texts.extend(self._extract_text(value["json"]))
            return texts
        if isinstance(value, (list, tuple)):
            # PaddleOCR 2.x line format: [box, [text, confidence]].
            if len(value) == 2 and isinstance(value[1], (list, tuple)) and value[1]:
                if isinstance(value[1][0], str):
                    texts.append(value[1][0])
            for item in value:
                texts.extend(self._extract_text(item))
            return texts
        json_value = getattr(value, "json", None)
        if json_value is not None:
            texts.extend(self._extract_text(json_value))
        return texts
