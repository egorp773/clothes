from __future__ import annotations

import argparse
import hashlib
import io
import json
import statistics
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Sequence

from PIL import Image, ImageEnhance, ImageFilter


SERVICE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = SERVICE_ROOT.parents[1]
sys.path.insert(0, str(SERVICE_ROOT))

REPORT_SCHEMA_VERSION = 1
DEFAULT_REPORTED_RESULT_COUNT = 20


@dataclass(frozen=True)
class BenchmarkCase:
    case_id: str
    query_image: str
    expected_product_ids: tuple[str, ...]
    filters: dict[str, Any]
    background_group: str | None = None
    background_reference: bool = False


def _round_rate(value: float) -> float:
    return round(value, 6)


def _as_non_empty_string(value: Any, field: str, case_id: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"Case {case_id!r}: {field} must be a non-empty string")
    return value.strip()


def load_manifest(path: Path) -> tuple[str, list[BenchmarkCase]]:
    """Load the documented manifest while accepting a few harmless key aliases.

    Minimal manifest::

        {"cases": [{"query_image": "query.jpg", "expected_product_id": "uuid"}]}

    For background invariance, give variants of the same foreground an identical
    ``background_group``.  One case may set ``background_reference`` to true;
    otherwise the first case in that group is the reference.
    """

    raw = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(raw, list):
        rows = raw
        manifest_name = path.stem
        default_filters: dict[str, Any] = {}
    elif isinstance(raw, dict):
        rows = raw.get("cases", raw.get("queries"))
        manifest_name = str(raw.get("name") or path.stem)
        default_filters = raw.get("filters") or {}
    else:
        raise ValueError("Manifest must be a JSON object or a list of cases")

    if not isinstance(rows, list) or not rows:
        raise ValueError("Manifest must contain a non-empty 'cases' (or 'queries') list")
    if not isinstance(default_filters, dict):
        raise ValueError("Top-level 'filters' must be an object")

    cases: list[BenchmarkCase] = []
    seen_ids: set[str] = set()
    reference_by_group: dict[str, str] = {}
    expected_by_group: dict[str, frozenset[str]] = {}
    for index, row in enumerate(rows, start=1):
        if not isinstance(row, dict):
            raise ValueError(f"Manifest case #{index} must be an object")
        query_value = row.get("query_image", row.get("image", row.get("image_path")))
        provisional_id = str(row.get("id") or row.get("case") or f"case_{index}")
        query_image = _as_non_empty_string(query_value, "query_image", provisional_id)
        case_id = _as_non_empty_string(
            row.get("id", row.get("case", Path(query_image).stem or f"case_{index}")),
            "id",
            provisional_id,
        )
        if case_id in seen_ids:
            raise ValueError(f"Duplicate case id: {case_id!r}")
        seen_ids.add(case_id)

        expected_value = row.get("expected_product_ids", row.get("expected_product_id"))
        if isinstance(expected_value, str):
            expected_ids = (expected_value.strip(),)
        elif isinstance(expected_value, (int, float)) and not isinstance(expected_value, bool):
            expected_ids = (str(expected_value),)
        elif isinstance(expected_value, list):
            expected_ids = tuple(
                str(product_id).strip()
                for product_id in expected_value
                if str(product_id).strip()
            )
        else:
            expected_ids = ()
        expected_ids = tuple(dict.fromkeys(expected_ids))
        if not expected_ids:
            raise ValueError(
                f"Case {case_id!r}: expected_product_id or expected_product_ids is required"
            )

        case_filters = row.get("filters") or {}
        if not isinstance(case_filters, dict):
            raise ValueError(f"Case {case_id!r}: filters must be an object")
        filters = {**default_filters, **case_filters}
        group_value = row.get("background_group", row.get("invariance_group"))
        background_group = (
            _as_non_empty_string(group_value, "background_group", case_id)
            if group_value is not None
            else None
        )
        background_reference = bool(
            row.get("background_reference", row.get("is_reference", False))
        )
        if background_reference and background_group is None:
            raise ValueError(
                f"Case {case_id!r}: background_reference requires background_group"
            )
        if background_group is not None:
            expected_set = frozenset(expected_ids)
            prior_expected = expected_by_group.setdefault(background_group, expected_set)
            if prior_expected != expected_set:
                raise ValueError(
                    f"Background group {background_group!r} must use the same expected product ids"
                )
            if background_reference:
                previous = reference_by_group.setdefault(background_group, case_id)
                if previous != case_id:
                    raise ValueError(
                        f"Background group {background_group!r} has multiple reference cases"
                    )

        cases.append(
            BenchmarkCase(
                case_id=case_id,
                query_image=query_image,
                expected_product_ids=expected_ids,
                filters=filters,
                background_group=background_group,
                background_reference=background_reference,
            )
        )
    return manifest_name, cases


def _rank(top_ids: Sequence[str], targets: set[str]) -> int | None:
    for index, product_id in enumerate(top_ids, start=1):
        if product_id in targets:
            return index
    return None


def calculate_metrics(case_results: Sequence[dict[str, Any]]) -> dict[str, Any]:
    if not case_results:
        raise ValueError("At least one benchmark result is required")
    ranks = [row.get("rank") for row in case_results]
    latencies = [float(row["latency_ms"]) for row in case_results]

    grouped: dict[str, list[dict[str, Any]]] = {}
    for row in case_results:
        group = row.get("background_group")
        if group:
            grouped.setdefault(str(group), []).append(row)

    invariance_groups: list[dict[str, Any]] = []
    stable = 0
    comparisons = 0
    for group_name, rows in grouped.items():
        if len(rows) < 2:
            continue
        reference = next(
            (row for row in rows if row.get("background_reference")), rows[0]
        )
        reference_ids = reference.get("top_ids") or []
        reference_top_1 = reference_ids[0] if reference_ids else None
        group_stable = 0
        group_comparisons = 0
        for row in rows:
            if row is reference:
                continue
            top_ids = row.get("top_ids") or []
            candidate_top_1 = top_ids[0] if top_ids else None
            group_comparisons += 1
            if reference_top_1 is not None and candidate_top_1 == reference_top_1:
                group_stable += 1
        comparisons += group_comparisons
        stable += group_stable
        invariance_groups.append(
            {
                "group": group_name,
                "reference_case": reference["case_id"],
                "reference_top_1": reference_top_1,
                "comparisons": group_comparisons,
                "stable": group_stable,
                "rate": _round_rate(group_stable / group_comparisons),
            }
        )

    count = len(case_results)
    return {
        "queries": count,
        "recall_at_1": _round_rate(sum(rank == 1 for rank in ranks) / count),
        "recall_at_5": _round_rate(
            sum(rank is not None and rank <= 5 for rank in ranks) / count
        ),
        "mrr": _round_rate(
            sum(1 / rank if rank is not None else 0 for rank in ranks) / count
        ),
        "background_invariance_rate": (
            _round_rate(stable / comparisons) if comparisons else None
        ),
        "background_invariance_comparisons": comparisons,
        "average_latency_ms": round(statistics.fmean(latencies), 3),
        "background_invariance": {
            "groups_evaluated": len(invariance_groups),
            "comparisons": comparisons,
            "stable": stable,
            "groups": invariance_groups,
        },
    }


def _ranked_product_ids(response: Any) -> list[str]:
    """Return public results in API order, including the similar-only fallback."""

    ranked: list[str] = []
    seen: set[str] = set()
    for product in [*response.products, *response.similar_products]:
        product_id = str(product.product_id)
        if product_id not in seen:
            seen.add(product_id)
            ranked.append(product_id)
    return ranked


def _load_query_image(service: Any, source: str, manifest_dir: Path) -> tuple[bytes, Image.Image]:
    if source.lower().startswith(("http://", "https://")):
        return service._download_image(source)
    path = Path(source)
    if not path.is_absolute():
        path = manifest_dir / path
    payload = path.read_bytes()
    with Image.open(io.BytesIO(payload)) as opened:
        image = opened.convert("RGB")
    return payload, image


def run_manifest_benchmark(
    manifest_path: Path,
    *,
    reported_result_count: int = DEFAULT_REPORTED_RESULT_COUNT,
) -> dict[str, Any]:
    from app.config import get_settings
    from app.model_manager import ModelManager
    from app.visual_search.schemas import VisualSearchFilters
    from app.visual_search.service import VisualSearchService
    from app.visual_search.store import SupabaseVisualSearchStore

    manifest_name, cases = load_manifest(manifest_path)
    settings = get_settings()
    models = ModelManager(settings)
    store = SupabaseVisualSearchStore(settings)
    service = VisualSearchService(settings, models, store)
    try:
        models.load_enabled()
        models.warmup()
        results: list[dict[str, Any]] = []
        for case in cases:
            payload, image = _load_query_image(service, case.query_image, manifest_path.parent)
            filters = VisualSearchFilters.model_validate(case.filters)
            started = time.perf_counter()
            response = service.search(
                image,
                hashlib.sha256(payload).hexdigest(),
                filters,
            )
            latency_ms = round((time.perf_counter() - started) * 1000, 3)
            ranked_ids = _ranked_product_ids(response)
            rank = _rank(ranked_ids, set(case.expected_product_ids))
            results.append(
                {
                    "case_id": case.case_id,
                    "query_image": case.query_image,
                    "expected_product_ids": list(case.expected_product_ids),
                    "background_group": case.background_group,
                    "background_reference": case.background_reference,
                    "rank": rank,
                    "top_ids": ranked_ids[:reported_result_count],
                    "latency_ms": latency_ms,
                    "category": response.category,
                    "category_confidence": response.category_confidence,
                    "candidate_count": response.candidate_count,
                    "match_status": response.match_status,
                    "cached": response.cached,
                    "timings_ms": response.timings_ms,
                    "warnings": response.warnings,
                }
            )

        metrics = calculate_metrics(results)
        # ``quality`` keeps the useful fields consumed by older report tooling.
        quality = {
            "queries_with_ground_truth": metrics["queries"],
            "top_1": metrics["recall_at_1"],
            "top_5": metrics["recall_at_5"],
            "mrr": metrics["mrr"],
        }
        return {
            "schema_version": REPORT_SCHEMA_VERSION,
            "report_type": "visual_search_benchmark",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "manifest": str(manifest_path),
            "name": manifest_name,
            "model_version": service.model_version,
            "metrics": metrics,
            "quality": quality,
            "cases": results,
        }
    finally:
        service.close()
        store.close()
        models.close()


def _report_metric(report: dict[str, Any], key: str) -> float | None:
    metrics = report.get("metrics") or {}
    if metrics.get(key) is not None:
        return float(metrics[key])
    quality = report.get("quality") or {}
    legacy_keys = {
        "recall_at_1": "top_1",
        "recall_at_5": "top_5",
        "mrr": "mrr",
    }
    legacy_key = legacy_keys.get(key)
    if legacy_key and quality.get(legacy_key) is not None:
        return float(quality[legacy_key])
    if key == "average_latency_ms":
        latencies = [
            float(row["latency_ms"])
            for row in report.get("cases", [])
            if row.get("latency_ms") is not None
        ]
        if latencies:
            return statistics.fmean(latencies)
    return None


def compare_reports(
    baseline: dict[str, Any],
    candidate: dict[str, Any],
    *,
    baseline_name: str = "baseline",
    candidate_name: str = "candidate",
) -> dict[str, Any]:
    comparisons: dict[str, Any] = {}
    for key in (
        "recall_at_1",
        "recall_at_5",
        "mrr",
        "background_invariance_rate",
        "average_latency_ms",
    ):
        baseline_value = _report_metric(baseline, key)
        candidate_value = _report_metric(candidate, key)
        delta = (
            candidate_value - baseline_value
            if baseline_value is not None and candidate_value is not None
            else None
        )
        relative_delta = (
            delta / baseline_value * 100
            if delta is not None and baseline_value not in (None, 0)
            else None
        )
        comparisons[key] = {
            "baseline": round(baseline_value, 6) if baseline_value is not None else None,
            "candidate": round(candidate_value, 6) if candidate_value is not None else None,
            "delta": round(delta, 6) if delta is not None else None,
            "relative_delta_percent": (
                round(relative_delta, 3) if relative_delta is not None else None
            ),
            "lower_is_better": key == "average_latency_ms",
        }
    return {
        "schema_version": REPORT_SCHEMA_VERSION,
        "report_type": "visual_search_benchmark_comparison",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "baseline": baseline_name,
        "candidate": candidate_name,
        "metrics": comparisons,
    }


def _encoded(image: Image.Image, quality: int = 90) -> tuple[bytes, Image.Image]:
    buffer = io.BytesIO()
    image.convert("RGB").save(buffer, format="JPEG", quality=quality)
    payload = buffer.getvalue()
    return payload, Image.open(io.BytesIO(payload)).convert("RGB")


def run_legacy_benchmark() -> dict[str, Any]:
    """Preserve the old no-argument smoke benchmark used by the linked script."""

    from app.config import get_settings
    from app.model_manager import ModelManager
    from app.visual_search.schemas import VisualSearchFilters
    from app.visual_search.service import VisualSearchService
    from app.visual_search.store import SupabaseVisualSearchStore

    settings = get_settings()
    models = ModelManager(settings)
    store = SupabaseVisualSearchStore(settings)
    service = VisualSearchService(settings, models, store)
    try:
        models.load_enabled()
        models.warmup()
        rows = store._request(
            "GET",
            f"{store._url}/rest/v1/product_visual_embeddings",
            headers=store.headers,
            params={
                "model_version": f"eq.{service.model_version}",
                "select": "product_id,image_url,view_type",
                "order": "product_id,view_type",
                "limit": "100",
            },
        ).json()
        if len(rows) < 2:
            raise SystemExit("Need at least two indexed catalog images")
        by_product: dict[str, list[str]] = {}
        for row in rows:
            by_product.setdefault(str(row["product_id"]), []).append(row["image_url"])
        first_product = next(product for product, urls in by_product.items() if urls)
        first_payload, first_image = service._download_image(by_product[first_product][0])
        alternate_url = next(
            (
                urls[1]
                for product, urls in by_product.items()
                if product == first_product and len(urls) > 1
            ),
            by_product[first_product][0],
        )
        alternate_payload, alternate_image = service._download_image(alternate_url)
        second_product = next(product for product in by_product if product != first_product)
        _, second_image = service._download_image(by_product[second_product][0])

        low_quality = first_image.resize((96, 96), Image.Resampling.BILINEAR).resize(
            first_image.size, Image.Resampling.BILINEAR
        )
        recolored = ImageEnhance.Color(first_image).enhance(0.15)
        blurred = first_image.filter(ImageFilter.GaussianBlur(radius=2.2))
        multiple = Image.new(
            "RGB",
            (first_image.width + second_image.width, max(first_image.height, second_image.height)),
            "white",
        )
        multiple.paste(first_image, (0, 0))
        multiple.paste(second_image, (first_image.width, 0))

        external_cases = [
            ("person_or_outfit", REPO_ROOT / "outfit.jpeg"),
            ("complex_background", REPO_ROOT / "assets" / "mock" / "outfit_hero.jpg"),
            ("wrong_category", REPO_ROOT / "assets" / "products" / "baggy_jeans.jpg"),
        ]
        cases: list[tuple[str, bytes, Image.Image, set[str]]] = [
            ("exact", first_payload, first_image, {first_product}),
            ("alternate_view", alternate_payload, alternate_image, {first_product}),
        ]
        for name, image, targets, quality in [
            ("low_quality", low_quality, {first_product}, 20),
            ("different_color", recolored, {first_product}, 75),
            ("blurred", blurred, {first_product}, 60),
            ("multiple_items", multiple, {first_product, second_product}, 75),
        ]:
            payload, decoded = _encoded(image, quality)
            cases.append((name, payload, decoded, targets))
        for name, path in external_cases:
            payload = path.read_bytes()
            cases.append((name, payload, Image.open(io.BytesIO(payload)).convert("RGB"), set()))

        output = []
        target_ranks = []
        for name, payload, image, targets in cases:
            response = service.search(
                image,
                hashlib.sha256(payload).hexdigest(),
                VisualSearchFilters(),
            )
            ranked_ids = _ranked_product_ids(response)
            rank = _rank(ranked_ids, targets) if targets else None
            if targets:
                target_ranks.append(rank)
            output.append(
                {
                    "case": name,
                    "rank": rank,
                    "category": response.category,
                    "confidence": response.category_confidence,
                    "candidates": response.candidate_count,
                    "top_ids": ranked_ids[:5],
                    "timings_ms": response.timings_ms,
                }
            )
        cache_started = time.perf_counter()
        cached_response = service.search(
            first_image,
            hashlib.sha256(first_payload).hexdigest(),
            VisualSearchFilters(),
        )
        cached_wall_ms = round((time.perf_counter() - cache_started) * 1000, 3)
        timing_keys = ["preparation", "embedding", "pgvector_retrieval", "reranking", "total"]
        warm_rows = output[1:]
        return {
            "cases": output,
            "warm_timing_median_ms": {
                key: round(statistics.median(row["timings_ms"][key] for row in warm_rows))
                for key in timing_keys
            },
            "quality": {
                "queries_with_ground_truth": len(target_ranks),
                "top_5": sum(rank is not None and rank <= 5 for rank in target_ranks)
                / len(target_ranks),
                "top_10": sum(rank is not None and rank <= 10 for rank in target_ranks)
                / len(target_ranks),
                "top_20": sum(rank is not None and rank <= 20 for rank in target_ranks)
                / len(target_ranks),
            },
            "index": store.index_stats(service.model_version),
            "cache": {
                "hit": cached_response.cached,
                "wall_ms": cached_wall_ms,
            },
        }
    finally:
        service.close()
        store.close()
        models.close()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Measure visual-search relevance, background invariance, and latency.",
        epilog=(
            "Manifest cases require query_image and expected_product_id. "
            "Set the same background_group on foreground-identical variants; "
            "optionally mark one background_reference=true. With no arguments, "
            "the previous production smoke benchmark is executed."
        ),
    )
    parser.add_argument("manifest", nargs="?", type=Path, help="JSON benchmark manifest")
    parser.add_argument("--output", type=Path, help="also write the JSON report to this path")
    parser.add_argument(
        "--compare",
        nargs=2,
        type=Path,
        metavar=("BASELINE", "CANDIDATE"),
        help="compare two previously generated JSON reports",
    )
    parser.add_argument(
        "--reported-results",
        type=int,
        default=DEFAULT_REPORTED_RESULT_COUNT,
        help=(
            "number of ranked product ids stored per case "
            f"(default: {DEFAULT_REPORTED_RESULT_COUNT})"
        ),
    )
    return parser


def _emit(report: dict[str, Any], output: Path | None) -> None:
    serialized = json.dumps(report, ensure_ascii=False, indent=2)
    if output is not None:
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(serialized + "\n", encoding="utf-8")
    print(serialized)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.reported_results < 5:
        raise SystemExit("--reported-results must be at least 5 to calculate Recall@5")
    if args.compare:
        if args.manifest is not None:
            raise SystemExit("manifest and --compare are mutually exclusive")
        baseline_path, candidate_path = args.compare
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        candidate = json.loads(candidate_path.read_text(encoding="utf-8"))
        report = compare_reports(
            baseline,
            candidate,
            baseline_name=str(baseline_path),
            candidate_name=str(candidate_path),
        )
    elif args.manifest is not None:
        report = run_manifest_benchmark(
            args.manifest.resolve(),
            reported_result_count=args.reported_results,
        )
    else:
        report = run_legacy_benchmark()
    _emit(report, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
