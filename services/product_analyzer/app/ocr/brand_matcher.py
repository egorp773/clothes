from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass

from rapidfuzz import fuzz
from unidecode import unidecode

from app.catalog import BRANDS


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value)
    normalized = unidecode(normalized).casefold()
    normalized = normalized.replace("1", "i").replace("5", "s").replace("0", "o")
    return re.sub(r"[^a-z0-9]+", " ", normalized).strip()


@dataclass(frozen=True)
class BrandMatch:
    brand_id: str
    display_name: str
    confidence: float
    matched_text: str


class BrandMatcher:
    def __init__(self, threshold: float = 78.0) -> None:
        self.threshold = threshold
        self._choices = {
            brand_id: normalize_text(display_name)
            for brand_id, display_name in BRANDS.items()
            if brand_id != "no_brand"
        }

    def match(self, texts: list[str]) -> BrandMatch | None:
        best: BrandMatch | None = None
        for raw in texts:
            candidate = normalize_text(raw)
            if len(candidate) < 3:
                continue
            compact_candidate = candidate.replace(" ", "")
            for brand_id, normalized_brand in self._choices.items():
                compact_brand = normalized_brand.replace(" ", "")
                if len(compact_brand) <= 3:
                    padded_candidate = f" {candidate} "
                    score = (
                        100.0
                        if compact_candidate == compact_brand
                        or f" {normalized_brand} " in padded_candidate
                        else 0.0
                    )
                else:
                    score = max(
                        fuzz.ratio(candidate, normalized_brand),
                        fuzz.partial_ratio(candidate, normalized_brand),
                    )
                if score < self.threshold:
                    continue
                match = BrandMatch(
                    brand_id=brand_id,
                    display_name=BRANDS[brand_id],
                    confidence=min(0.98, score / 100.0),
                    matched_text=raw,
                )
                if best is None or match.confidence > best.confidence:
                    best = match
        return best
