#!/bin/sh
set -eu

exec uvicorn app.main:app \
  --host 0.0.0.0 \
  --port "${PORT:-7860}" \
  --workers 1 \
  --timeout-keep-alive 10 \
  --no-access-log
