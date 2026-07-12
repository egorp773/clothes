#!/usr/bin/env bash
set -euo pipefail

cd /service
if [[ "${PRELOAD_GROUNDED_SAM:-false}" == "true" ]] && \
   { [[ ! -f vendor/Grounded-SAM-2/checkpoints/sam2.1_hiera_large.pt ]] || \
   [[ ! -f vendor/Grounded-SAM-2/gdino_checkpoints/groundingdino_swint_ogc.pth ]]; }; then
  python scripts/setup_models.py --download-checkpoints
fi

exec uvicorn app.main:app --host "${HOST:-0.0.0.0}" --port "${PORT:-8090}"
