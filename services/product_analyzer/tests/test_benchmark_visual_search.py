from __future__ import annotations

import json

import pytest

from scripts.benchmark_visual_search import (
    calculate_metrics,
    compare_reports,
    load_manifest,
    main,
)


def test_load_manifest_accepts_minimal_cases_and_background_groups(tmp_path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "name": "background-set",
                "filters": {"conditions": ["new"]},
                "cases": [
                    {
                        "id": "reference",
                        "query_image": "images/reference.jpg",
                        "expected_product_id": "product-1",
                        "background_group": "shirt-1",
                        "background_reference": True,
                    },
                    {
                        "id": "variant",
                        "query_image": "images/variant.jpg",
                        "expected_product_ids": ["product-1"],
                        "invariance_group": "shirt-1",
                        "filters": {"colors": ["white"]},
                    },
                ],
            }
        ),
        encoding="utf-8",
    )

    name, cases = load_manifest(manifest)

    assert name == "background-set"
    assert cases[0].expected_product_ids == ("product-1",)
    assert cases[0].background_reference is True
    assert cases[1].background_group == "shirt-1"
    assert cases[1].filters == {
        "conditions": ["new"],
        "colors": ["white"],
    }


def test_load_manifest_rejects_mismatched_ground_truth_inside_background_group(
    tmp_path,
) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "cases": [
                    {
                        "id": "one",
                        "query_image": "one.jpg",
                        "expected_product_id": "product-1",
                        "background_group": "same-item",
                    },
                    {
                        "id": "two",
                        "query_image": "two.jpg",
                        "expected_product_id": "product-2",
                        "background_group": "same-item",
                    },
                ]
            }
        ),
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="same expected product ids"):
        load_manifest(manifest)


def test_load_manifest_normalizes_numeric_product_id(tmp_path) -> None:
    manifest = tmp_path / "manifest.json"
    manifest.write_text(
        json.dumps(
            {
                "cases": [
                    {
                        "query_image": "query.jpg",
                        "expected_product_id": 42,
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    _, cases = load_manifest(manifest)

    assert cases[0].expected_product_ids == ("42",)


def test_calculate_metrics_includes_relevance_invariance_and_wall_latency() -> None:
    results = [
        {
            "case_id": "reference",
            "rank": 1,
            "top_ids": ["product-1", "product-2"],
            "latency_ms": 100,
            "background_group": "same-foreground",
            "background_reference": True,
        },
        {
            "case_id": "stable",
            "rank": 1,
            "top_ids": ["product-1", "product-3"],
            "latency_ms": 200,
            "background_group": "same-foreground",
            "background_reference": False,
        },
        {
            "case_id": "changed",
            "rank": 2,
            "top_ids": ["product-4", "product-1"],
            "latency_ms": 300,
            "background_group": "same-foreground",
            "background_reference": False,
        },
    ]

    metrics = calculate_metrics(results)

    assert metrics["recall_at_1"] == pytest.approx(2 / 3, abs=1e-6)
    assert metrics["recall_at_5"] == 1
    assert metrics["mrr"] == pytest.approx(5 / 6, abs=1e-6)
    assert metrics["background_invariance_rate"] == 0.5
    assert metrics["background_invariance_comparisons"] == 2
    assert metrics["average_latency_ms"] == 200


def test_empty_rankings_are_not_counted_as_background_invariant() -> None:
    results = [
        {
            "case_id": "reference",
            "rank": None,
            "top_ids": [],
            "latency_ms": 1,
            "background_group": "empty",
            "background_reference": True,
        },
        {
            "case_id": "variant",
            "rank": None,
            "top_ids": [],
            "latency_ms": 1,
            "background_group": "empty",
            "background_reference": False,
        },
    ]

    metrics = calculate_metrics(results)

    assert metrics["background_invariance_rate"] == 0


def test_compare_reports_calculates_quality_and_latency_deltas() -> None:
    baseline = {
        "metrics": {
            "recall_at_1": 0.5,
            "recall_at_5": 0.8,
            "mrr": 0.6,
            "background_invariance_rate": 0.7,
            "average_latency_ms": 200,
        }
    }
    candidate = {
        "metrics": {
            "recall_at_1": 0.6,
            "recall_at_5": 0.9,
            "mrr": 0.7,
            "background_invariance_rate": 0.95,
            "average_latency_ms": 180,
        }
    }

    comparison = compare_reports(baseline, candidate)

    assert comparison["metrics"]["recall_at_1"]["delta"] == 0.1
    assert comparison["metrics"]["background_invariance_rate"]["delta"] == 0.25
    assert comparison["metrics"]["average_latency_ms"]["delta"] == -20
    assert comparison["metrics"]["average_latency_ms"]["lower_is_better"] is True


def test_compare_cli_writes_json_report(tmp_path, capsys) -> None:
    baseline = tmp_path / "baseline.json"
    candidate = tmp_path / "candidate.json"
    output = tmp_path / "comparison.json"
    baseline.write_text(
        json.dumps({"quality": {"top_1": 0.5, "top_5": 0.75, "mrr": 0.6}}),
        encoding="utf-8",
    )
    candidate.write_text(
        json.dumps({"quality": {"top_1": 0.75, "top_5": 1.0, "mrr": 0.8}}),
        encoding="utf-8",
    )

    result = main(
        [
            "--compare",
            str(baseline),
            str(candidate),
            "--output",
            str(output),
        ]
    )

    assert result == 0
    assert json.loads(output.read_text(encoding="utf-8"))["metrics"]["mrr"]["delta"] == 0.2
    assert "visual_search_benchmark_comparison" in capsys.readouterr().out
