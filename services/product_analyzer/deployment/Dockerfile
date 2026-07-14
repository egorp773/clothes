FROM python:3.10.18-slim-bookworm AS dependencies

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
    VISUAL_SEARCH_REGION_TIMEOUT_SECONDS=15 \
    VISUAL_SEARCH_ENABLE_CLOTHING_PARSER=false \
    VISUAL_SEARCH_PRELOAD_REGION_MODEL=false \
    REMBG_MODEL_NAME=u2netp \
    BACKGROUND_REMOVAL_MODEL_NAME=u2netp \
    BACKGROUND_REMOVAL_MAX_SIDE=1600 \
    BACKGROUND_REMOVAL_TIMEOUT_SECONDS=60 \
    MAX_MAIN_IMAGE_SIDE=768 \
    VISUAL_SEARCH_MAX_SIDE=768 \
    ENRICHMENT_WORKER_ENABLED=true \
    ENRICHMENT_EMBEDDING_BATCH_SIZE=4

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl libglib2.0-0 libgl1 libgomp1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY deployment/requirements-space.txt ./requirements-space.txt
RUN python -m pip install --upgrade pip==25.1.1 \
    && python -m pip install -r requirements-space.txt

FROM dependencies AS model-runtime
COPY app ./app
COPY deployment/scripts ./scripts
RUN mkdir -p /opt/models/huggingface /opt/models/rembg \
    && python scripts/preload_models.py \
    && useradd --system --uid 10001 --create-home app \
    && chown -R app:app /app /opt/models \
    && chmod +x scripts/start.sh

FROM model-runtime AS test
COPY deployment/requirements-test.txt ./requirements-test.txt
RUN python -m pip install -r requirements-test.txt
COPY tests ./tests
COPY pytest.ini ./pytest.ini
ENV EAGER_LOAD_MODELS=false \
    WARMUP_ON_START=false \
    REQUIRE_CORE_MODELS=false \
    REQUIRE_ANALYSIS_AUTH=false \
    ENRICHMENT_WORKER_ENABLED=false
USER app
CMD ["python", "-m", "pytest", "-q"]

FROM model-runtime AS production
EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=5 \
  CMD curl --fail --silent http://127.0.0.1:${PORT}/ready || exit 1
USER app
CMD ["/app/scripts/start.sh"]
