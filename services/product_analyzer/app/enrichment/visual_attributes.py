from __future__ import annotations

from dataclasses import dataclass

import numpy as np


ATTRIBUTE_PROMPTS: dict[str, dict[str, tuple[str, ...]]] = {
    "material": {
        "cotton": ("cotton fabric clothing",),
        "wool": ("wool fabric clothing", "knitted wool garment"),
        "linen": ("linen fabric clothing",),
        "denim": ("denim fabric clothing",),
        "leather": ("leather clothing or accessory",),
        "polyester": ("synthetic polyester sportswear",),
        "mixed": ("mixed fabric clothing",),
    },
    "pattern": {
        "solid": ("plain solid color clothing",),
        "logo": ("clothing with a visible logo",),
        "striped": ("striped clothing pattern",),
        "checked": ("checked plaid clothing pattern",),
        "floral": ("floral clothing pattern",),
        "graphic": ("graphic print clothing",),
        "other": ("abstract patterned clothing",),
    },
    "fit": {
        "slim": ("slim fit clothing",),
        "regular": ("regular fit clothing",),
        "relaxed": ("relaxed loose fit clothing",),
        "oversized": ("oversized clothing",),
    },
    "style": {
        "casual": ("casual everyday fashion",),
        "sport": ("sportswear athletic fashion",),
        "classic": ("classic timeless fashion",),
        "streetwear": ("streetwear fashion",),
        "business": ("business formal fashion",),
        "evening": ("evening occasion fashion",),
    },
    "sleeve_length": {
        "sleeveless": ("sleeveless garment",),
        "short": ("short sleeve garment",),
        "three_quarter": ("three quarter sleeve garment",),
        "long": ("long sleeve garment",),
    },
    "closure": {
        "none": ("garment without a closure",),
        "zip": ("clothing with a zipper",),
        "buttons": ("clothing with buttons",),
        "laces": ("shoes or clothing with laces",),
        "velcro": ("shoes or clothing with velcro",),
        "buckle": ("accessory or clothing with a buckle",),
    },
    "collar": {
        "round": ("round crew neck garment",),
        "v_neck": ("v neck garment",),
        "polo": ("polo collar garment",),
        "shirt": ("shirt collar garment",),
        "stand": ("stand collar garment", "turtleneck garment"),
        "hood": ("hooded garment",),
        "none": ("collarless garment",),
    },
    "rise": {
        "low": ("low rise trousers or skirt",),
        "mid": ("mid rise trousers or skirt",),
        "high": ("high waist trousers or skirt",),
    },
}


CATEGORY_ATTRIBUTES: dict[str, tuple[str, ...]] = {
    "t_shirt": ("material", "pattern", "fit", "sleeve_length", "collar"),
    "hoodie": ("material", "pattern", "fit", "closure"),
    "shirt": ("material", "pattern", "fit", "sleeve_length", "collar", "closure"),
    "jacket": ("material", "fit", "collar", "closure", "season"),
    "jeans": ("material", "fit", "rise", "closure"),
    "trousers": ("material", "pattern", "fit", "rise", "closure"),
    "dress": ("material", "pattern", "fit", "sleeve_length", "collar", "closure"),
    "skirt": ("material", "pattern", "fit", "rise", "closure"),
    "sneakers": ("material", "pattern", "closure", "style"),
    "boots": ("material", "closure", "season", "style"),
    "bag": ("material", "pattern", "closure", "style"),
    "accessory": ("material", "pattern", "style"),
}


MODERATION_PROMPTS: dict[str, tuple[str, ...]] = {
    "safe": ("a normal clothing resale product photograph",),
    "adult": ("explicit adult nudity",),
    "weapon": ("a weapon or firearm",),
    "drugs": ("illegal drugs or drug paraphernalia",),
}


@dataclass(frozen=True)
class AttributeSuggestion:
    key: str
    value: str
    confidence: float


class VisualAttributeSuggester:
    version = "fashion_siglip_visual_attributes_v1"

    def __init__(self, classifier) -> None:
        self.classifier = classifier

    def suggest(
        self,
        embedding: np.ndarray,
        normalized_category: str,
    ) -> list[AttributeSuggestion]:
        suggestions: list[AttributeSuggestion] = []
        for key in CATEGORY_ATTRIBUTES.get(normalized_category, ()):
            scores = self.classifier.score_text_options(
                embedding,
                ATTRIBUTE_PROMPTS[key],
            )
            if not scores:
                continue
            value, confidence = max(scores.items(), key=lambda item: item[1])
            # Closed-vocabulary probabilities below this level are too
            # ambiguous to put in front of a seller as a proposed value.
            if confidence < 0.34:
                continue
            suggestions.append(
                AttributeSuggestion(key, value, round(confidence, 4))
            )
        return suggestions

    def moderation_risk(self, embedding: np.ndarray) -> dict[str, object]:
        scores = self.classifier.score_text_options(
            embedding,
            MODERATION_PROMPTS,
            temperature=10.0,
        )
        safe = scores.get("safe", 0.0)
        risks = {key: round(value, 4) for key, value in scores.items() if key != "safe"}
        top_label, top_score = max(risks.items(), key=lambda item: item[1])
        return {
            "score": round(max(0.0, min(1.0, 1.0 - safe)), 4),
            "label": top_label if top_score >= 0.55 else "low",
            "signals": risks,
            "model_version": self.version,
        }
