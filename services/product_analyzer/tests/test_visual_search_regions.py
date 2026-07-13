from __future__ import annotations

from PIL import Image

from app.catalog import CategoryDefinition
from app.classification.fashion_siglip_adapter import FashionCandidate
from app.config import Settings
from app.segmentation.rembg_adapter import ForegroundProposal
from app.visual_search.regions import VisualSearchRegionDetector


def _candidate(
    item_type: str,
    confidence: float,
    *,
    subcategory: str = "tops",
    category: str = "clothing",
) -> FashionCandidate:
    return FashionCandidate(
        CategoryDefinition(item_type, subcategory, category, (item_type,)),
        confidence,
    )


class _Foregrounds:
    def __init__(self, proposals):
        self.proposals = proposals

    def propose_regions(self, image):
        return self.proposals


class _Clothing:
    def __init__(self, proposals=None, error: Exception | None = None):
        self.proposals = proposals or []
        self.error = error
        self.calls = 0

    def propose_clothing_regions(self, image):
        self.calls += 1
        if self.error:
            raise self.error
        return self.proposals


class _Classification:
    def __init__(self, single, batches=None):
        self.single = single
        self.batches = batches or []
        self.single_calls = 0
        self.batch_calls = 0

    def classify(self, image, top_k):
        self.single_calls += 1
        return self.single

    def classify_many(self, images, top_k):
        self.batch_calls += 1
        return self.batches


def test_separate_foregrounds_are_batch_labelled_without_clothing_parser():
    foregrounds = _Foregrounds(
        [
            ForegroundProposal((5, 5, 45, 55), 0.9),
            ForegroundProposal((55, 35, 95, 95), 0.8),
        ]
    )
    clothing = _Clothing()
    classification = _Classification(
        [],
        batches=[
            [_candidate("jacket", 0.55), _candidate("coat", 0.12)],
            [_candidate("jeans", 0.48), _candidate("trousers", 0.11)],
        ],
    )
    detector = VisualSearchRegionDetector(
        Settings(),
        foregrounds,  # type: ignore[arg-type]
        clothing,  # type: ignore[arg-type]
        classification,  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert [proposal.label for proposal in result.proposals] == ["jacket", "jeans"]
    assert clothing.calls == 0
    assert classification.batch_calls == 1
    assert set(result.timings_ms) == {
        "foreground_segmentation",
        "classification",
        "clothing_segmentation",
        "total",
    }


def test_clear_single_item_skips_expensive_clothing_parser():
    foregrounds = _Foregrounds([ForegroundProposal((30, 5, 70, 95), 0.9)])
    clothing = _Clothing()
    classification = _Classification(
        [_candidate("hoodie", 0.60), _candidate("sweater", 0.10)]
    )
    detector = VisualSearchRegionDetector(
        Settings(),
        foregrounds,  # type: ignore[arg-type]
        clothing,  # type: ignore[arg-type]
        classification,  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert result.proposals == foregrounds.proposals
    assert classification.single_calls == 1
    assert clothing.calls == 0
    assert result.timings_ms["clothing_segmentation"] == 0


def test_ambiguous_full_body_uses_warm_clothing_parser_and_keeps_regions():
    foregrounds = _Foregrounds([ForegroundProposal((30, 5, 70, 95), 0.9)])
    clothing = _Clothing(
        [
            ForegroundProposal((25, 15, 75, 55), 0.9, "upper_clothing"),
            ForegroundProposal((30, 50, 70, 98), 0.88, "lower_clothing"),
        ]
    )
    classification = _Classification(
        [
            _candidate("jacket", 0.20, subcategory="outerwear"),
            _candidate("hoodie", 0.18),
        ]
    )
    detector = VisualSearchRegionDetector(
        Settings(visual_search_enable_clothing_parser=True),
        foregrounds,  # type: ignore[arg-type]
        clothing,  # type: ignore[arg-type]
        classification,  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert [proposal.label for proposal in result.proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]
    assert clothing.calls == 1
    assert result.warnings == []


def test_clothing_parser_failure_degrades_to_fast_foreground():
    proposal = ForegroundProposal((30, 5, 70, 95), 0.9)
    detector = VisualSearchRegionDetector(
        Settings(visual_search_enable_clothing_parser=True),
        _Foregrounds([proposal]),  # type: ignore[arg-type]
        _Clothing(error=RuntimeError("unavailable")),  # type: ignore[arg-type]
        _Classification(
            [
                _candidate("jacket", 0.20, subcategory="outerwear"),
                _candidate("hoodie", 0.18),
            ]
        ),  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert [item.label for item in result.proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]
    assert result.warnings == ["clothing_region_fallback_unavailable"]


def test_empty_clothing_parser_result_uses_geometric_split():
    proposal = ForegroundProposal((30, 5, 70, 95), 0.9)
    clothing = _Clothing()
    detector = VisualSearchRegionDetector(
        Settings(visual_search_enable_clothing_parser=True),
        _Foregrounds([proposal]),  # type: ignore[arg-type]
        clothing,  # type: ignore[arg-type]
        _Classification(
            [
                _candidate("jacket", 0.20, subcategory="outerwear"),
                _candidate("hoodie", 0.18),
            ]
        ),  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert [item.label for item in result.proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]
    assert clothing.calls == 1
    assert result.warnings == []


def test_ambiguous_full_body_uses_geometric_split_when_parser_is_disabled():
    proposal = ForegroundProposal((30, 5, 70, 95), 0.9)
    clothing = _Clothing()
    detector = VisualSearchRegionDetector(
        Settings(visual_search_enable_clothing_parser=False),
        _Foregrounds([proposal]),  # type: ignore[arg-type]
        clothing,  # type: ignore[arg-type]
        _Classification(
            [
                _candidate("jacket", 0.20, subcategory="outerwear"),
                _candidate("hoodie", 0.18),
            ]
        ),  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (100, 100), "white"))

    assert [item.label for item in result.proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]
    assert result.proposals[0].bbox == (28, 10, 72, 59)
    assert result.proposals[1].bbox == (28, 50, 72, 95)
    assert clothing.calls == 0
    assert result.timings_ms["clothing_segmentation"] == 0
    assert result.warnings == []


def test_ambiguous_tall_standalone_garments_are_not_split():
    proposal = ForegroundProposal((30, 5, 70, 95), 0.9)
    candidate_sets = [
        [
            _candidate("jeans", 0.20, subcategory="bottoms"),
            _candidate("trousers", 0.18, subcategory="bottoms"),
        ],
        [
            _candidate("dress", 0.20, subcategory="dresses"),
            _candidate("jumpsuit", 0.18, subcategory="dresses"),
        ],
        [
            _candidate("coat", 0.20, subcategory="outerwear"),
            _candidate("jacket", 0.18, subcategory="outerwear"),
        ],
    ]

    for candidates in candidate_sets:
        clothing = _Clothing()
        detector = VisualSearchRegionDetector(
            Settings(visual_search_enable_clothing_parser=False),
            _Foregrounds([proposal]),  # type: ignore[arg-type]
            clothing,  # type: ignore[arg-type]
            _Classification(candidates),  # type: ignore[arg-type]
        )

        result = detector.detect(Image.new("RGB", (100, 100), "white"))

        assert result.proposals == [proposal]
        assert clothing.calls == 0


def test_ambiguous_wide_person_like_foreground_offers_upper_and_lower():
    # Mirrors the production geometry after max-side normalization:
    # roughly 519 px wide by 836 px high inside a 682x1024 photograph.
    proposal = ForegroundProposal((108, 168, 627, 1004), 0.9)
    detector = VisualSearchRegionDetector(
        Settings(visual_search_enable_clothing_parser=False),
        _Foregrounds([proposal]),  # type: ignore[arg-type]
        _Clothing(),  # type: ignore[arg-type]
        _Classification(
            [
                _candidate("jacket", 0.20, subcategory="outerwear"),
                _candidate("coat", 0.18, subcategory="outerwear"),
            ]
        ),  # type: ignore[arg-type]
    )

    result = detector.detect(Image.new("RGB", (682, 1024), "white"))

    assert [item.label for item in result.proposals] == [
        "upper_clothing",
        "lower_clothing",
    ]
