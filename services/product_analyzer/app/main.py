from __future__ import annotations

import asyncio
import hashlib
import io
import json
import logging
import time
import uuid
from contextlib import asynccontextmanager
from contextlib import suppress

from fastapi import (
    FastAPI,
    File,
    Form,
    Header,
    HTTPException,
    Request,
    Response,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from PIL import Image, ImageOps

from app.analysis_store import SupabaseAnalysisStore
from app.config import get_settings
from app.enrichment.service import ProductEnrichmentService
from app.enrichment.store import SupabaseEnrichmentStore
from app.enrichment.worker import ProductEnrichmentWorker
from app.inference_gate import InferenceGate, InferenceQueueFull, InferenceQueueTimeout
from app.model_manager import ModelManager
from app.pipeline.analyzer_pipeline import AnalyzerPipeline
from app.schemas import AnalysisResponse, HealthResponse
from app.visual_search.auth import (
    AuthenticationError,
    SlidingWindowRateLimiter,
    SupabaseJwtVerifier,
)
from app.visual_search.schemas import (
    ProductEmbeddingResponse,
    VisualSearchFilters,
    VisualSearchRegion,
    VisualSearchRegionsResponse,
    VisualSearchResponse,
)
from app.visual_search.service import VisualSearchService
from app.visual_search.store import SupabaseVisualSearchStore


settings = get_settings()
logging.basicConfig(
    level=getattr(logging, settings.log_level.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
LOGGER = logging.getLogger(__name__)
models = ModelManager(settings)
analysis_store = SupabaseAnalysisStore(settings)
pipeline = AnalyzerPipeline(settings, models, result_sink=analysis_store.save_result)
visual_store = SupabaseVisualSearchStore(settings)
visual_search = VisualSearchService(settings, models, visual_store)
jwt_verifier = SupabaseJwtVerifier(settings)
visual_rate_limiter = SlidingWindowRateLimiter(
    settings.visual_search_rate_limit,
    settings.visual_search_rate_window_seconds,
)
visual_region_rate_limiter = SlidingWindowRateLimiter(
    settings.visual_search_rate_limit,
    settings.visual_search_rate_window_seconds,
)
background_rate_limiter = SlidingWindowRateLimiter(
    max(4, settings.visual_search_rate_limit // 2),
    settings.visual_search_rate_window_seconds,
)
inference_gate = InferenceGate(
    settings.inference_max_concurrency,
    settings.inference_queue_size,
    settings.inference_queue_timeout_seconds,
)
enrichment_store = SupabaseEnrichmentStore(settings)
enrichment_service = ProductEnrichmentService(settings, models, enrichment_store)
enrichment_worker = ProductEnrichmentWorker(
    settings,
    enrichment_store,
    enrichment_service,
    inference_gate,
)
startup_state: dict[str, object] = {"ready": False, "error": None}


async def _initialize_models() -> None:
    try:
        await asyncio.to_thread(models.load_enabled)
        await asyncio.to_thread(models.warmup)
        components = models.health()
        core_loaded = (
            components["fast_segmentation"]["loaded"]
            and components["classification"]["loaded"]
        )
        startup_state["ready"] = bool(
            core_loaded and analysis_store.enabled and visual_store.enabled
        )
        if not startup_state["ready"]:
            startup_state["error"] = "Core models or Supabase are unavailable"
    except Exception as error:
        startup_state["error"] = f"{type(error).__name__}: {error}"
        LOGGER.exception("Required model initialization failed")


@asynccontextmanager
async def lifespan(_: FastAPI):
    initialization_task = asyncio.create_task(_initialize_models())
    worker_task: asyncio.Task | None = None
    if settings.enrichment_worker_enabled and enrichment_store.enabled:

        async def start_worker_after_initialization() -> None:
            await initialization_task
            if startup_state["ready"]:
                await enrichment_worker.run()

        worker_task = asyncio.create_task(start_worker_after_initialization())
    yield
    enrichment_worker.stop()
    if worker_task is not None:
        worker_task.cancel()
        with suppress(asyncio.CancelledError):
            await worker_task
    if not initialization_task.done():
        initialization_task.cancel()
    analysis_store.close()
    visual_search.close()
    visual_store.close()
    jwt_verifier.close()
    enrichment_store.close()
    models.close()


app = FastAPI(title=settings.service_name, version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[],
    allow_origin_regex=settings.cors_origin_regex,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    components = models.health()
    core_ready = bool(startup_state["ready"])
    return HealthResponse(
        status="ok" if core_ready else "degraded",
        ready=bool(core_ready),
        components=components,
        versions={
            "grounded_sam_2": settings.grounded_sam_commit,
            "fashion_siglip": settings.fashion_model_id,
            "paddleocr": settings.paddleocr_repo_commit,
            "qwen3_vl": settings.qwen_model_id,
        },
    )


@app.get("/ready")
async def ready() -> dict[str, object]:
    if not startup_state["ready"]:
        raise HTTPException(
            503,
            {
                "ready": False,
                "initializing": startup_state["error"] is None,
                "error": startup_state["error"],
            },
        )
    return {
        "ready": True,
        "models": ["rembg/u2netp", settings.fashion_model_id],
        "supabase": True,
        "queue_pending": inference_gate.pending,
        "enrichment_worker": bool(
            settings.enrichment_worker_enabled and enrichment_store.enabled
        ),
    }


@app.post("/v1/enrichment/wakeup", status_code=202)
async def wake_enrichment_worker(
    authorization: str | None = Header(default=None),
) -> dict[str, bool]:
    # The durable DB row is created before this hint. If this request is lost,
    # polling still claims it; waking only removes the normal poll delay.
    await _authenticated_user(authorization)
    enrichment_worker.wake()
    return {"accepted": True}


@app.post("/warmup")
async def warmup(
    authorization: str | None = Header(default=None),
) -> dict[str, object]:
    if settings.require_analysis_auth:
        await _authenticated_user(authorization)
    await _initialize_models()
    return {"ok": True, "components": models.health()}


async def _authenticated_user(
    authorization: str | None,
    rate_limiter: SlidingWindowRateLimiter = visual_rate_limiter,
):
    try:
        user = await asyncio.to_thread(jwt_verifier.verify, authorization)
    except AuthenticationError as error:
        status = 503 if "not configured" in str(error) else 401
        raise HTTPException(status, str(error)) from error
    if not rate_limiter.allow(user.id):
        raise HTTPException(429, "Visual search rate limit exceeded")
    return user


async def _authorize_visual_search(
    authorization: str | None,
    request: Request,
    rate_limiter: SlidingWindowRateLimiter = visual_rate_limiter,
) -> None:
    """Authorize a search when a session exists, but keep public discovery usable.

    Visual search only reads already-published catalog data, so login is not a
    prerequisite. Authenticated callers are rate-limited by user id; guests by
    their connection address. Supplying an invalid token still fails loudly so
    a stale session is never silently treated as anonymous.
    """
    if authorization:
        await _authenticated_user(authorization, rate_limiter)
        return
    forwarded_for = request.headers.get("x-forwarded-for", "").split(",", 1)[0].strip()
    client_host = forwarded_for or (
        request.client.host if request.client else "unknown"
    )
    if not rate_limiter.allow(f"anonymous:{client_host}"):
        raise HTTPException(429, "Visual search rate limit exceeded")


def _decode_visual_filters(raw: str | None) -> VisualSearchFilters:
    if not raw:
        return VisualSearchFilters()
    try:
        return VisualSearchFilters.model_validate(json.loads(raw))
    except Exception as error:
        raise HTTPException(422, "Invalid visual search filters") from error


def _decode_rgb_image(payload: bytes) -> Image.Image:
    source = Image.open(io.BytesIO(payload))
    if source.width * source.height > settings.max_decoded_image_pixels:
        raise ValueError("Image dimensions are too large")
    image = ImageOps.exif_transpose(source).convert("RGB")
    image.load()
    return image


def _remove_background_png(image: Image.Image) -> bytes:
    # A lazily loaded clothing parser and the high-resolution background model
    # do not fit comfortably together on a small worker. Dedicated larger
    # deployments that explicitly preload the parser keep it resident.
    if not settings.visual_search_preload_region_model:
        models.clothing_regions.unload()
    try:
        cutout = models.background_removal.remove_background(image)
        output = io.BytesIO()
        cutout.save(output, format="PNG", optimize=True)
        return output.getvalue()
    finally:
        models.background_removal.unload()


@app.post("/v1/remove-background")
async def remove_image_background(
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
) -> Response:
    await _authenticated_user(authorization, background_rate_limiter)
    allowed_mime = {"image/jpeg", "image/png", "image/webp"}
    if file.content_type not in allowed_mime:
        raise HTTPException(415, f"Unsupported content type: {file.content_type}")
    payload = await file.read(settings.background_removal_max_image_bytes + 1)
    if len(payload) > settings.background_removal_max_image_bytes:
        raise HTTPException(413, "Background removal image is too large")
    try:
        image = _decode_rgb_image(payload)
        image.thumbnail(
            (
                settings.background_removal_max_side,
                settings.background_removal_max_side,
            ),
            Image.Resampling.LANCZOS,
        )
    except Exception as error:
        raise HTTPException(400, "Invalid background removal image") from error
    try:
        output = await inference_gate.run(
            lambda: _remove_background_png(image),
            timeout=settings.background_removal_timeout_seconds,
        )
    except InferenceQueueFull as error:
        raise HTTPException(503, str(error)) from error
    except InferenceQueueTimeout as error:
        raise HTTPException(429, str(error)) from error
    except asyncio.TimeoutError as error:
        raise HTTPException(504, "Background removal timed out") from error
    except Exception as error:
        LOGGER.exception("Background removal failed")
        raise HTTPException(
            503, "Background removal is temporarily unavailable"
        ) from error
    return Response(
        content=output,
        media_type="image/png",
        headers={
            "Cache-Control": "no-store",
            "X-Background-Model": settings.background_removal_model_name,
        },
    )


@app.post(
    "/v1/visual-search/regions",
    response_model=VisualSearchRegionsResponse,
)
async def detect_visual_search_regions(
    file: UploadFile = File(...),
    authorization: str | None = Header(default=None),
    request: Request = None,
) -> VisualSearchRegionsResponse:
    await _authorize_visual_search(
        authorization,
        request,
        visual_region_rate_limiter,
    )
    allowed_mime = {"image/jpeg", "image/png", "image/webp"}
    if file.content_type not in allowed_mime:
        raise HTTPException(415, f"Unsupported content type: {file.content_type}")
    payload = await file.read(settings.visual_search_max_image_bytes + 1)
    if len(payload) > settings.visual_search_max_image_bytes:
        raise HTTPException(413, "Visual search image is too large")
    try:
        image = _decode_rgb_image(payload)
        image.thumbnail(
            (settings.visual_search_max_side, settings.visual_search_max_side),
            Image.Resampling.LANCZOS,
        )
    except Exception as error:
        raise HTTPException(400, "Invalid visual search image") from error
    try:
        detection = await inference_gate.run(
            lambda: visual_search.detect_regions(image),
            timeout=settings.visual_search_region_timeout_seconds,
        )
    except InferenceQueueFull as error:
        raise HTTPException(503, str(error)) from error
    except InferenceQueueTimeout as error:
        raise HTTPException(429, str(error)) from error
    except asyncio.TimeoutError as error:
        raise HTTPException(504, "Object detection timed out") from error
    except Exception as error:
        LOGGER.exception("Visual search region detection failed")
        raise HTTPException(
            503, "Object detection is temporarily unavailable"
        ) from error

    width, height = image.size
    regions = [
        VisualSearchRegion(
            id=f"region-{index + 1}",
            label=proposal.label,
            confidence=proposal.confidence,
            bbox=(
                proposal.bbox[0] / width,
                proposal.bbox[1] / height,
                proposal.bbox[2] / width,
                proposal.bbox[3] / height,
            ),
        )
        for index, proposal in enumerate(detection.proposals)
    ]
    return VisualSearchRegionsResponse(
        width=width,
        height=height,
        regions=regions,
        timings_ms=detection.timings_ms,
        warnings=detection.warnings,
    )


@app.post("/v1/visual-search", response_model=VisualSearchResponse)
async def search_visually(
    file: UploadFile = File(...),
    filters: str | None = Form(default=None),
    authorization: str | None = Header(default=None),
    request: Request = None,
) -> VisualSearchResponse:
    # Request is supplied by FastAPI; the optional annotation keeps this
    # compatible with lightweight direct calls in existing tests.
    await _authorize_visual_search(authorization, request)
    allowed_mime = {"image/jpeg", "image/png", "image/webp"}
    if file.content_type not in allowed_mime:
        raise HTTPException(415, f"Unsupported content type: {file.content_type}")
    payload = await file.read(settings.visual_search_max_image_bytes + 1)
    if len(payload) > settings.visual_search_max_image_bytes:
        raise HTTPException(413, "Visual search image is too large")
    image_hash = hashlib.sha256(payload).hexdigest()
    try:
        image = _decode_rgb_image(payload)
    except Exception as error:
        raise HTTPException(400, "Invalid visual search image") from error
    try:
        return await inference_gate.run(
            lambda: visual_search.search(
                image,
                image_hash,
                _decode_visual_filters(filters),
            ),
            timeout=settings.visual_search_timeout_seconds,
        )
    except InferenceQueueFull as error:
        raise HTTPException(503, str(error)) from error
    except InferenceQueueTimeout as error:
        raise HTTPException(429, str(error)) from error
    except asyncio.TimeoutError as error:
        raise HTTPException(504, "Visual search timed out") from error
    except HTTPException:
        raise
    except Exception as error:
        LOGGER.exception("Visual search failed")
        raise HTTPException(503, "Visual search is temporarily unavailable") from error


@app.post(
    "/v1/products/{product_id}/embeddings",
    response_model=ProductEmbeddingResponse,
)
async def create_product_embeddings(
    product_id: str,
    authorization: str | None = Header(default=None),
) -> ProductEmbeddingResponse:
    user = await _authenticated_user(authorization)
    product = await asyncio.to_thread(visual_store.get_product, product_id)
    if product is None:
        raise HTTPException(404, "Product not found")
    if str(product.get("seller_id") or "") != user.id:
        raise HTTPException(403, "Only the product owner can create embeddings")
    if product.get("status") != "published" or bool(product.get("is_hidden")):
        raise HTTPException(409, "Only active published products can be indexed")
    try:
        return await inference_gate.run(
            lambda: visual_search.index_product(product_id),
            timeout=max(settings.visual_search_timeout_seconds * 3, 20),
        )
    except InferenceQueueFull as error:
        raise HTTPException(503, str(error)) from error
    except InferenceQueueTimeout as error:
        raise HTTPException(429, str(error)) from error
    except asyncio.TimeoutError as error:
        raise HTTPException(504, "Product embedding generation timed out") from error
    except ValueError as error:
        raise HTTPException(422, str(error)) from error
    except Exception as error:
        LOGGER.exception("Product embedding generation failed")
        raise HTTPException(503, "Product embedding generation failed") from error


@app.get("/v1/analyze/{image_hash}", response_model=AnalysisResponse)
async def get_analysis(
    image_hash: str,
    authorization: str | None = Header(default=None),
) -> AnalysisResponse:
    # Durable analysis results are user data, unlike public catalog search.
    # Auth is optional only for local/test deployments.
    if settings.require_analysis_auth:
        await _authenticated_user(authorization)
    result = pipeline.get_cached(image_hash)
    if result is None:
        context = await asyncio.to_thread(analysis_store.get_context, image_hash)
        if context is not None:
            content_hash, persisted = context
            # Durable API ids are UUIDs, while the live cache is keyed by the
            # image hash. Prefer the newly completed in-memory enrichment over
            # an older database snapshot for the same job.
            result = pipeline.get_cached(content_hash) or persisted
            result.analysis_id = image_hash
    if result is None:
        raise HTTPException(404, "Analysis result is not cached or has expired")
    return result


@app.post("/v1/analyze/{analysis_id}/enrich", status_code=202)
async def enrich(
    analysis_id: str,
    files: list[UploadFile] = File(...),
    authorization: str | None = Header(default=None),
) -> dict[str, object]:
    if settings.require_analysis_auth:
        await _authenticated_user(authorization)
    image_hash = analysis_id
    if pipeline.get_cached(image_hash) is None:
        context = await asyncio.to_thread(analysis_store.get_context, analysis_id)
        if context is None:
            raise HTTPException(404, "Run the main-image analysis before enrichment")
        image_hash, persisted = context
        # Durable analysis ids are UUIDs while the in-process cache is keyed
        # by the main image hash. Do not replace a newer completed background
        # result with the earlier persisted basic response.
        if pipeline.get_cached(image_hash) is None:
            pipeline.restore_cached(image_hash, persisted)
    images: list[Image.Image] = []
    for upload in files[: settings.max_images - 1]:
        if upload.content_type and not upload.content_type.startswith("image/"):
            continue
        payload = await upload.read(settings.max_image_bytes + 1)
        if len(payload) > settings.max_image_bytes:
            continue
        try:
            image = ImageOps.exif_transpose(Image.open(io.BytesIO(payload))).convert(
                "RGB"
            )
            image.load()
            images.append(image)
        except Exception:
            LOGGER.warning("Skipped invalid enrichment image: %s", upload.filename)
    queued = pipeline.schedule_extra_images(image_hash, images)
    return {"queued": queued, "image_count": len(images)}


@app.post("/v1/analyze", response_model=AnalysisResponse)
async def analyze(
    files: list[UploadFile] = File(...),
    listing_id: str | None = Form(default=None),
    main_image_url: str | None = Form(default=None),
    authorization: str | None = Header(default=None),
) -> AnalysisResponse:
    if settings.require_analysis_auth:
        await _authenticated_user(authorization)
    if not files or len(files) > settings.max_images:
        raise HTTPException(400, f"Provide 1..{settings.max_images} images")
    # The publication path deliberately consumes only the main image. Sending
    # labels/detail shots here would make multipart parsing and decoding part of
    # the critical path; they can be submitted to a later enrichment workflow.
    upload = files[0]
    if upload.content_type and not upload.content_type.startswith("image/"):
        raise HTTPException(415, f"Unsupported content type: {upload.content_type}")
    download_started = time.perf_counter()
    payload = await upload.read(settings.max_image_bytes + 1)
    download_ms = round((time.perf_counter() - download_started) * 1000)
    if len(payload) > settings.max_image_bytes:
        raise HTTPException(413, f"Image exceeds {settings.max_image_bytes} bytes")
    image_hash = hashlib.sha256(payload).hexdigest()
    job_id = (
        str(uuid.uuid5(uuid.NAMESPACE_URL, f"{listing_id}:{image_hash}"))
        if listing_id and analysis_store.enabled
        else image_hash
    )
    durable_job = bool(listing_id and analysis_store.enabled)
    if durable_job:
        durable_job_id = await asyncio.to_thread(
            analysis_store.create_pending,
            job_id,
            listing_id,
            image_hash,
            main_image_url,
        )
        durable_job = durable_job_id is not None
        if durable_job_id is not None:
            job_id = durable_job_id
        else:
            job_id = image_hash
    cached = pipeline.get_cached(image_hash)
    if cached is not None:
        cached.analysis_id = job_id
        cached.timings_ms = {**cached.timings_ms, "cache": 0, "download": download_ms}
        if durable_job:
            await asyncio.to_thread(analysis_store.save_basic, job_id, cached)
        return cached
    decode_started = time.perf_counter()
    try:
        image = ImageOps.exif_transpose(Image.open(io.BytesIO(payload))).convert("RGB")
        image.load()
    except Exception as error:
        raise HTTPException(400, f"Invalid image: {upload.filename}") from error
    decode_ms = round((time.perf_counter() - decode_started) * 1000)
    try:
        result = await inference_gate.run(
            lambda: pipeline.analyze(
                image,
                image_hash,
                download_ms=download_ms,
                decode_ms=decode_ms,
            ),
            timeout=settings.request_timeout_seconds,
        )
        result.analysis_id = job_id
        if durable_job:
            await asyncio.to_thread(analysis_store.save_basic, job_id, result)
        return result
    except InferenceQueueFull as error:
        raise HTTPException(503, str(error)) from error
    except InferenceQueueTimeout as error:
        raise HTTPException(429, str(error)) from error
    except asyncio.TimeoutError as error:
        LOGGER.error("Analysis timed out after %ss", settings.request_timeout_seconds)
        raise HTTPException(504, "Product analysis timed out") from error
    except Exception as error:
        LOGGER.exception("Product analysis failed")
        raise HTTPException(
            503, "Product analysis is temporarily unavailable"
        ) from error
