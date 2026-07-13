from __future__ import annotations

import logging
import math
from datetime import datetime, timezone
from typing import Any

from app.config import Settings
from app.visual_search.schemas import VisualSearchProduct


LOGGER = logging.getLogger(__name__)


_ITEM_GROUPS = (
    frozenset({"hoodie", "sweatshirt", "sweater"}),
    frozenset({"shirt", "tshirt", "top"}),
    frozenset({"jacket", "coat", "vest"}),
    frozenset({"jeans", "trousers", "shorts"}),
    frozenset({"skirt", "dress", "jumpsuit"}),
    frozenset({"sneakers", "boots", "shoes", "sandals"}),
    frozenset({"bag", "backpack", "belt", "scarf", "headwear"}),
    frozenset({"necklace", "ring", "bracelet", "earrings"}),
)

_ITEM_SUBCATEGORY = {
    "hoodie": "tops",
    "sweatshirt": "tops",
    "sweater": "tops",
    "shirt": "tops",
    "tshirt": "tops",
    "top": "tops",
    "jacket": "outerwear",
    "coat": "outerwear",
    "vest": "outerwear",
    "jeans": "bottoms",
    "trousers": "bottoms",
    "shorts": "bottoms",
    "skirt": "bottoms",
    "dress": "dresses",
    "jumpsuit": "dresses",
    "sneakers": "shoes_all",
    "boots": "shoes_all",
    "shoes": "shoes_all",
    "sandals": "shoes_all",
    "bag": "accessories_all",
    "backpack": "accessories_all",
    "belt": "accessories_all",
    "scarf": "accessories_all",
    "headwear": "accessories_all",
}

_TITLE_ITEM_HINTS = (
    (("пухов", "куртк"), "jacket"),
    (("пальто",), "coat"),
    (("кардиган", "свитер"), "sweater"),
    (("свитшот",), "sweatshirt"),
    (("худи", "толстов"), "hoodie"),
    (("лонгслив",), "top"),
    (("футбол",), "tshirt"),
    (("рубаш",), "shirt"),
    (("джинс",), "jeans"),
    (("брюк",), "trousers"),
    (("шорт",), "shorts"),
    (("юбк",), "skirt"),
    (("кед", "крос", "sneaker"), "sneakers"),
    (("ботин", "сапог"), "boots"),
    (("кошел", "косметич", "сумк"), "bag"),
)


class VisualSearchReranker:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def collapse_and_rerank(
        self,
        candidates: list[dict[str, Any]],
        *,
        query_category: str | None,
        query_subcategory: str | None,
        query_item_type: str | None,
        query_color: str | None = None,
        query_brand: str | None = None,
        query_gender: str | None = None,
        query_condition: str | None = None,
        limit: int,
        confident_category: bool = False,
        confident_item_type: bool = False,
    ) -> list[VisualSearchProduct]:
        best_by_product: dict[str, dict[str, Any]] = {}
        for row in candidates:
            product_id = str(row["product_id"])
            previous = best_by_product.get(product_id)
            if previous is None or float(row.get("visual_similarity") or 0) > float(
                previous.get("visual_similarity") or 0
            ):
                best_by_product[product_id] = row

        scored: list[tuple[VisualSearchProduct, dict[str, Any]]] = []
        for row in best_by_product.values():
            visual = max(0.0, min(1.0, float(row.get("visual_similarity") or 0)))
            candidate_item = self._candidate_item_type(row)
            category_match = self._category_match(
                query_category,
                query_subcategory,
                row,
                candidate_item,
            )
            item_match = self._item_match(query_item_type, candidate_item)
            quality = self._quality(row)
            freshness = self._freshness(row.get("published_at"))
            popularity = min(1.0, math.log1p(int(row.get("favorite_count") or 0)) / math.log(101))
            score = (
                self.settings.rerank_visual_weight * visual
                + self.settings.rerank_item_type_weight * item_match
                + self.settings.rerank_category_weight * (1.0 if category_match else 0.0)
                + self.settings.rerank_color_weight
                * self._color_match(query_color, row)
                + self.settings.rerank_brand_weight * self._match(query_brand, row.get("brand"))
                + self.settings.rerank_gender_weight * self._match(query_gender, row.get("gender"))
                + self.settings.rerank_condition_weight
                * self._match(query_condition, row.get("condition"))
                + self.settings.rerank_quality_weight * quality
                + self.settings.rerank_freshness_weight * freshness
                + self.settings.rerank_popularity_weight * popularity
            )
            images = [str(value) for value in (row.get("images") or []) if value]
            main_image = str(row.get("main_image") or "")
            if not main_image and images:
                main_image = images[0]
            product = VisualSearchProduct(
                    product_id=str(row["product_id"]),
                    score=round(score, 6),
                    visual_similarity=round(visual, 6),
                    matched_image_url=str(row.get("image_url") or main_image),
                    title=str(row.get("title") or ""),
                    description=str(row.get("description") or ""),
                    price=float(row.get("price") or 0),
                    images=images,
                    main_image=main_image,
                    category=str(row.get("category") or ""),
                    subcategory=str(row.get("subcategory") or ""),
                    item_type=candidate_item or str(row.get("item_type") or ""),
                    brand=str(row.get("brand") or ""),
                    size=str(row.get("size") or ""),
                    condition=str(row.get("condition") or ""),
                    primary_color=str(row.get("primary_color") or ""),
                    secondary_colors=[str(value) for value in (row.get("secondary_colors") or [])],
                    gender=str(row.get("gender") or ""),
                    published_at=str(row["published_at"]) if row.get("published_at") else None,
                    favorite_count=int(row.get("favorite_count") or 0),
                )
            scored.append(
                (
                    product,
                    {
                        "category_match": category_match,
                        "item_type_match": item_match,
                        "pool": str(row.get("_retrieval_pool") or "broad"),
                    },
                )
            )
        if not scored:
            return []
        reference = [
            entry
            for entry in scored
            if (not confident_category or entry[1]["category_match"])
            and (
                not confident_item_type
                or not query_item_type
                or entry[1]["item_type_match"] > 0
            )
        ]
        if not reference:
            reference = scored
        best_similarity = max(entry[0].visual_similarity for entry in reference)
        best_score = max(entry[0].score for entry in reference)
        included: list[VisualSearchProduct] = []
        for product, metadata in scored:
            reasons: list[str] = []
            taxonomy_override = (
                product.visual_similarity
                >= self.settings.visual_search_taxonomy_override_similarity
            )
            minimum_similarity = (
                self.settings.visual_search_fallback_min_similarity
                if metadata["pool"] == "fallback"
                else self.settings.visual_search_min_similarity
            )
            if product.visual_similarity < minimum_similarity:
                reasons.append("below_min_similarity")
            if (
                product.visual_similarity
                < best_similarity - self.settings.visual_search_max_similarity_gap
            ):
                reasons.append("too_far_from_top_similarity")
            if product.score < self.settings.visual_search_min_rerank_score:
                reasons.append("below_min_rerank_score")
            if product.score < best_score - self.settings.visual_search_max_rerank_gap:
                reasons.append("too_far_from_top_score")
            if (
                confident_category
                and not metadata["category_match"]
                and not taxonomy_override
            ):
                reasons.append("category_mismatch")
            if (
                confident_item_type
                and query_item_type
                and metadata["item_type_match"] <= 0
                and not taxonomy_override
            ):
                reasons.append("item_type_mismatch")
            decision = "include" if not reasons else "exclude"
            reason = "relevant" if not reasons else ",".join(reasons)
            LOGGER.debug(
                "visual_search_candidate product_id=%s title=%r raw_cosine=%.6f "
                "rerank_score=%.6f category_match=%s item_type_match=%.2f "
                "pool=%s decision=%s reason=%s",
                product.product_id,
                product.title,
                product.visual_similarity,
                product.score,
                metadata["category_match"],
                metadata["item_type_match"],
                metadata["pool"],
                decision,
                reason,
            )
            if not reasons:
                included.append(product)
        included.sort(key=lambda item: (item.score, item.visual_similarity), reverse=True)
        return included[:limit]

    @staticmethod
    def _candidate_item_type(row: dict[str, Any]) -> str | None:
        detected = str(row.get("item_type") or "").strip().lower()
        if detected:
            return detected
        title = str(row.get("title") or "").strip().lower()
        for hints, item_type in _TITLE_ITEM_HINTS:
            if any(hint in title for hint in hints):
                return item_type
        return None

    @staticmethod
    def _item_match(expected: str | None, actual: str | None) -> float:
        if not expected:
            return 0.5
        if expected == actual:
            return 1.0
        if not actual:
            return 0.0
        return 0.75 if any(expected in group and actual in group for group in _ITEM_GROUPS) else 0.0

    @staticmethod
    def _category_match(
        query_category: str | None,
        query_subcategory: str | None,
        row: dict[str, Any],
        candidate_item: str | None,
    ) -> bool:
        if not query_category:
            return True
        detected_category = str(row.get("visual_category") or "").lower()
        if detected_category:
            if detected_category != query_category:
                return False
            detected_subcategory = str(row.get("visual_subcategory") or "").lower()
            return not query_subcategory or not detected_subcategory or detected_subcategory == query_subcategory
        if candidate_item and query_subcategory:
            return _ITEM_SUBCATEGORY.get(candidate_item) == query_subcategory
        legacy = str(row.get("category") or "").strip().lower()
        if query_subcategory == "tops":
            return legacy in {"верх", "clothing"}
        if query_subcategory == "bottoms":
            return legacy in {"низ", "clothing"}
        if query_category == "shoes":
            return legacy in {"обувь", "shoes"}
        if query_category == "accessories":
            return legacy in {"аксессуары", "accessories"}
        return legacy == query_category

    @staticmethod
    def _match(expected: str | None, actual: Any) -> float:
        if not expected:
            return 0.5
        return 1.0 if expected == actual else 0.0

    @staticmethod
    def _color_match(expected: str | None, row: dict[str, Any]) -> float:
        if not expected:
            return 0.5
        if row.get("primary_color") == expected:
            return 1.0
        return 0.55 if expected in (row.get("secondary_colors") or []) else 0.0

    @staticmethod
    def _quality(row: dict[str, Any]) -> float:
        score = 0.0
        score += 0.25 if str(row.get("title") or "").strip() else 0
        score += 0.25 if len(str(row.get("description") or "").strip()) >= 40 else 0
        score += 0.25 if row.get("main_image") else 0
        score += 0.25 if len(row.get("images") or []) >= 2 else 0
        return score

    @staticmethod
    def _freshness(value: Any) -> float:
        if not value:
            return 0.0
        try:
            published = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
            days = max(0.0, (datetime.now(timezone.utc) - published).total_seconds() / 86400)
            return math.exp(-days / 90.0)
        except (TypeError, ValueError):
            return 0.0
