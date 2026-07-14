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
    "season": {
        "summer": ("lightweight clothing for warm summer weather",),
        "demi": ("clothing for mild spring or autumn weather",),
        "winter": ("warm insulated clothing for cold winter weather",),
        "all_season": ("versatile clothing suitable for every season",),
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
    version = "fashion_siglip_visual_attributes_v2"

    def __init__(self, classifier) -> None:
        self.classifier = classifier

    def suggest(
        self,
        embedding: np.ndarray,
        normalized_category: str,
        *,
        all_attributes: bool = False,
    ) -> list[AttributeSuggestion]:
        return self.suggest_many(
            [embedding],
            normalized_category,
            [1.0],
            all_attributes=all_attributes,
        )

    def suggest_many(
        self,
        embeddings: list[np.ndarray],
        normalized_category: str,
        weights: list[float] | None = None,
        *,
        all_attributes: bool = False,
    ) -> list[AttributeSuggestion]:
        if not embeddings:
            return []
        view_weights = weights or [1.0] * len(embeddings)
        if len(view_weights) != len(embeddings):
            raise ValueError("Every visual embedding must have a weight")
        total_weight = max(
            sum(max(0.0, weight) for weight in view_weights),
            1e-12,
        )
        suggestions: list[AttributeSuggestion] = []
        attribute_keys = (
            tuple(ATTRIBUTE_PROMPTS)
            if all_attributes
            else CATEGORY_ATTRIBUTES.get(normalized_category, ())
        )
        for key in attribute_keys:
            combined = {value: 0.0 for value in ATTRIBUTE_PROMPTS[key]}
            has_scores = False
            for embedding, weight in zip(embeddings, view_weights, strict=True):
                scores = self.classifier.score_text_options(
                    embedding,
                    ATTRIBUTE_PROMPTS[key],
                )
                has_scores = has_scores or bool(scores)
                for value, confidence in scores.items():
                    combined[value] += max(0.0, weight) * confidence
            if not has_scores:
                continue
            averaged = {
                value: confidence / total_weight
                for value, confidence in combined.items()
            }
            value, confidence = max(averaged.items(), key=lambda item: item[1])
            # These values are private seller-facing proposals, not facts
            # published without review. Always return the best category-
            # relevant option and preserve the real confidence so the caller
            # can rank or hide it in buyer-facing projections.
            suggestions.append(AttributeSuggestion(key, value, round(confidence, 4)))
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
