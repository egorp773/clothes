FROM python:3.10.18-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/opt/models/huggingface \
    U2NET_HOME=/opt/models/rembg \
    TRANSFORMERS_CACHE=/opt/models/huggingface \
    PYTHONPATH=/app \
    PORT=7860 \
    OMP_NUM_THREADS=2 \
    MKL_NUM_THREADS=2 \
    TOKENIZERS_PARALLELISM=false \
    ENABLE_QWEN=false \
    ENABLE_PADDLEOCR=false \
    ENABLE_GROUNDED_SAM=false \
    PRELOAD_SLOW_MODELS=false \
    EAGER_LOAD_MODELS=true \
    WARMUP_ON_START=true \
    REQUIRE_CORE_MODELS=true \
    REQUIRE_ANALYSIS_AUTH=true \
    BACKGROUND_WORKERS=1 \
    INFERENCE_MAX_CONCURRENCY=1 \
    INFERENCE_QUEUE_SIZE=4 \
    INFERENCE_QUEUE_TIMEOUT_SECONDS=25 \
    REQUEST_TIMEOUT_SECONDS=35 \
    FAST_PIPELINE_TIMEOUT_SECONDS=30 \
    FAST_SEGMENTATION_TIMEOUT_SECONDS=15 \
    CLASSIFICATION_TIMEOUT_SECONDS=12 \
    FALLBACK_SEGMENTATION_TIMEOUT_SECONDS=0.1 \
    VISUAL_SEARCH_TIMEOUT_SECONDS=35 \
    VISUAL_SEARCH_STAGE_TIMEOUT_SECONDS=20 \
    BACKGROUND_REMOVAL_MODEL_NAME=isnet-general-use \
    BACKGROUND_REMOVAL_MAX_SIDE=1600 \
    BACKGROUND_REMOVAL_TIMEOUT_SECONDS=60 \
    MAX_MAIN_IMAGE_SIDE=768 \
    VISUAL_SEARCH_MAX_SIDE=768

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl libglib2.0-0 libgl1 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY deployment/requirements-space.txt ./requirements-space.txt
RUN python -m pip install --upgrade pip==25.1.1 \
    && python -m pip install -r requirements-space.txt

COPY app ./app
COPY deployment/scripts ./scripts
RUN mkdir -p /opt/models/huggingface /opt/models/rembg \
    && python scripts/preload_models.py \
    && useradd --system --uid 10001 --create-home app \
    && chown -R app:app /app /opt/models \
    && chmod +x scripts/start.sh

EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=5 \
  CMD curl --fail --silent http://127.0.0.1:${PORT}/health || exit 1

USER app
CMD ["/app/scripts/start.sh"]
