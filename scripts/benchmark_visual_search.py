"""Repository-level entry point for the visual-search benchmark.

The implementation lives with the product-analyzer service so it can reuse the
service's production dependencies.  Keeping this small launcher at ``scripts/``
also makes the documented command work from the repository root.
"""

from __future__ import annotations

import runpy
from pathlib import Path


TARGET = (
    Path(__file__).resolve().parents[1]
    / "services"
    / "product_analyzer"
    / "scripts"
    / "benchmark_visual_search.py"
)


if __name__ == "__main__":
    runpy.run_path(str(TARGET), run_name="__main__")
