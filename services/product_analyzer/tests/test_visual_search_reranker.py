from __future__ import annotations

import logging

from app.config import Settings
from app.visual_search.reranker import VisualSearchReranker


def _row(product_id: str, similarity: float, **overrides):
    return {
        "product_id": product_id,
        "image_url": f"https://example.com/{product_id}.jpg",
        "visual_similarity": similarity,
        "title": "Худи",
        "description": "Подробное описание вещи в отличном состоянии",
        "price": 3500,
        "images": ["one", "two"],
        "main_image": "one",
        "category": "clothing",
        "subcategory": "tops",
        "item_type": "hoodie",
        "brand": "nike",
        "size": "m",
        "condition": "excellent",
        "primary_color": "black",
        "secondary_colors": [],
        "gender": "unisex",
        "favorite_count": 3,
        **overrides,
    }


def test_collapses_multiple_views_and_keeps_best_visual_match():
    reranker = VisualSearchReranker(Settings())
    results = reranker.collapse_and_rerank(
        [_row("same", 0.71), _row("same", 0.91), _row("other", 0.80)],
        query_category="clothing",
        query_subcategory="tops",
        query_item_type="hoodie",
        limit=20,
    )
    assert len(results) == 2
    same = next(item for item in results if item.product_id == "same")
    assert same.visual_similarity == 0.91


def test_visual_similarity_remains_the_main_ranking_factor():
    reranker = VisualSearchReranker(Settings())
    results = reranker.collapse_and_rerank(
        [
            _row("visual", 0.95, item_type="shirt", category="accessories"),
            _row("metadata", 0.65),
        ],
        query_category="clothing",
        query_subcategory="tops",
        query_item_type="hoodie",
        limit=20,
    )
    assert results[0].product_id == "visual"


def test_small_catalog_is_not_returned_whole_when_candidate_limit_is_larger(caplog):
    caplog.set_level(logging.DEBUG, logger="app.visual_search.reranker")
    reranker = VisualSearchReranker(Settings(visual_search_candidate_count=200))
    candidates = [
        _row("sweater-1", 0.80, item_type="sweater", title="Бордовая кофта"),
        _row("sweater-2", 0.76, item_type="sweatshirt", title="Свитшот"),
        _row("sweater-3", 0.72, item_type="hoodie", title="Худи"),
        _row("shirt", 0.75, item_type="shirt", title="Рубашка"),
        _row("puffer", 0.74, item_type="jacket", title="Пуховик"),
        *[
            _row(
                f"irrelevant-{index}",
                0.55 - index * 0.01,
                item_type="sneakers",
                category="shoes",
                subcategory="shoes_all",
                title=f"Нерелевантный товар {index}",
            )
            for index in range(16)
        ],
    ]
    results = reranker.collapse_and_rerank(
        candidates,
        query_category="clothing",
        query_subcategory="tops",
        query_item_type="sweater",
        limit=30,
        confident_category=True,
    )
    assert {item.product_id for item in results} == {
        "sweater-1",
        "sweater-2",
        "sweater-3",
    }
    assert len(results) == 3
    assert len(results) < len(candidates)
    debug_output = "\n".join(record.getMessage() for record in caplog.records)
    assert "raw_cosine=" in debug_output
    assert "rerank_score=" in debug_output
    assert "title='Рубашка'" in debug_output and "item_type_mismatch" in debug_output
    assert "title='Пуховик'" in debug_output and "decision=exclude" in debug_output


def test_returns_empty_when_every_candidate_is_below_relevance_threshold():
    reranker = VisualSearchReranker(Settings())
    results = reranker.collapse_and_rerank(
        [_row("shirt", 0.48, item_type="shirt", title="Рубашка")],
        query_category="clothing",
        query_subcategory="tops",
        query_item_type="sweater",
        limit=30,
        confident_category=True,
    )
    assert results == []
