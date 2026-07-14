from __future__ import annotations

from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


SERVICE_ROOT = Path(__file__).resolve().parents[1]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=SERVICE_ROOT / ".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    service_name: str = "clothes-product-analyzer"
    log_level: str = "INFO"
    host: str = "0.0.0.0"
    port: int = 8090
    request_timeout_seconds: int = 15
    fast_pipeline_timeout_seconds: float = 12.0
    fast_segmentation_timeout_seconds: float = 4.0
    classification_timeout_seconds: float = 4.0
    fallback_segmentation_timeout_seconds: float = 5.0
    ocr_timeout_seconds: float = 6.0
    qwen_timeout_seconds: float = 20.0
    max_main_image_side: int = 1024
    analysis_cache_size: int = 512
    analysis_cache_ttl_seconds: int = 86400
    background_workers: int = 1
    inference_max_concurrency: int = 1
    inference_queue_size: int = 4
    inference_queue_timeout_seconds: float = 20.0
    require_analysis_auth: bool = False
    supabase_url: str | None = None
    supabase_service_role_key: str | None = None
    max_images: int = 8
    max_image_bytes: int = 15 * 1024 * 1024
    max_decoded_image_pixels: int = 40_000_000
    visual_search_timeout_seconds: float = 8.0
    visual_search_stage_timeout_seconds: float = 4.5
    visual_search_region_timeout_seconds: float = 15.0
    visual_search_max_image_bytes: int = 10 * 1024 * 1024
    visual_search_max_side: int = 1024
    visual_search_candidate_count: int = 200
    visual_search_result_count: int = 30
    visual_search_cache_size: int = 256
    visual_search_cache_ttl_seconds: int = 900
    visual_search_rate_limit: int = 20
    visual_search_rate_window_seconds: int = 60
    # FashionSigLIP probabilities are over fine-grained item types.  A value
    # around 0.15 is common for ambiguous outfits and must not be treated as a
    # hard broad-category decision.
    visual_search_high_category_confidence: float = 0.32
    visual_search_min_category_margin: float = 0.08
    visual_search_high_item_type_confidence: float = 0.36
    visual_search_min_item_type_margin: float = 0.08
    visual_search_focused_min_results: int = 4
    visual_search_min_similarity: float = 0.56
    visual_search_fallback_min_similarity: float = 0.60
    visual_search_max_similarity_gap: float = 0.12
    visual_search_min_rerank_score: float = 0.48
    visual_search_max_rerank_gap: float = 0.12
    visual_search_taxonomy_override_similarity: float = 0.80
    visual_search_alternate_similarity: float = 0.70
    visual_search_max_product_images: int = 5
    visual_search_strong_similarity: float = 0.70
    visual_search_strong_rerank_score: float = 0.58
    visual_search_similar_result_count: int = 12
    visual_search_download_timeout_seconds: float = 6.0
    # u2net_cloth_seg is useful on a roomy worker, but its CPU inference arena
    # is too large for the 4 GB production container. The fast geometric
    # upper/lower fallback is the safe default; larger deployments can opt in.
    visual_search_enable_clothing_parser: bool = False
    visual_search_preload_region_model: bool = False
    visual_search_region_single_item_confidence: float = 0.28
    visual_search_region_single_item_margin: float = 0.07
    visual_search_region_label_min_confidence: float = 0.16
    visual_search_region_label_min_margin: float = 0.03

    # Reranking weights sum to 1. Visual similarity intentionally dominates.
    rerank_visual_weight: float = 0.66
    rerank_item_type_weight: float = 0.09
    rerank_category_weight: float = 0.06
    rerank_color_weight: float = 0.05
    rerank_brand_weight: float = 0.025
    rerank_gender_weight: float = 0.025
    rerank_condition_weight: float = 0.02
    rerank_quality_weight: float = 0.025
    rerank_freshness_weight: float = 0.025
    rerank_popularity_weight: float = 0.02
    cors_origin_regex: str = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

    model_root: Path = SERVICE_ROOT / "models"
    grounded_sam_repo: Path = SERVICE_ROOT / "vendor" / "Grounded-SAM-2"
    grounded_sam_commit: str = "b7a9c29f196edff0eb54dbe14588d7ae5e3dde28"
    grounded_sam_prompt: str = (
        "clothing. garment. shirt. t-shirt. hoodie. sweater. jacket. coat. "
        "pants. jeans. skirt. dress. shoes. sneakers. bag. accessory."
    )
    grounding_dino_box_threshold: float = 0.28
    grounding_dino_text_threshold: float = 0.22
    grounding_dino_nms_threshold: float = 0.55
    grounded_sam_max_boxes: int = 6
    enable_grounded_sam: bool = False
    sam_checkpoint_name: str = "sam2.1_hiera_large.pt"
    sam_config: str = "configs/sam2.1/sam2.1_hiera_l.yaml"
    grounding_dino_checkpoint_name: str = "groundingdino_swint_ogc.pth"
    grounding_dino_config: str = (
        "grounding_dino/groundingdino/config/GroundingDINO_SwinT_OGC.py"
    )
    rembg_model_name: str = "u2netp"
    rembg_alpha_threshold: int = 160
    rembg_min_quality: float = 0.62
    rembg_min_area_share: float = 0.015
    rembg_max_area_share: float = 0.92
    # Multi-item photos often contain a secondary garment that is much
    # smaller than the main one.  Keep it when it is both sizeable in the
    # frame and sizeable relative to the dominant foreground; the relative
    # guard prevents small background fragments from becoming products.
    rembg_secondary_component_min_share: float = 0.025
    rembg_secondary_component_min_relative_area: float = 0.18
    max_detected_garments: int = 4
    clothing_region_model_name: str = "u2net_cloth_seg"
    # Production uses the same compact rembg model for masks and final PNGs.
    # Keeping one ONNX session resident is important on the 4 GB CPU VPS.
    background_removal_model_name: str = "u2netp"
    background_removal_max_image_bytes: int = 15 * 1024 * 1024
    background_removal_max_side: int = 1600
    background_removal_timeout_seconds: float = 60.0

    fashion_model_id: str = "Marqo/marqo-fashionSigLIP"
    fashion_model_revision: str = "c56244cc94f92419e8369fa71efdaf403b124ce8"
    classification_top_k: int = 3

    paddleocr_repo_commit: str = "211989f046cc1878460f9e65574690c00a127a1a"
    paddleocr_language: str = "en"
    paddleocr_version: str = "PP-OCRv6"
    enable_paddleocr: bool = False
    brand_match_threshold: float = 78.0

    enable_qwen: bool = False
    allow_qwen_cpu: bool = False
    # 2B keeps the optional background worker from competing with the fast
    # FashionSigLIP path on modest deployment GPUs.
    qwen_model_id: str = "Qwen/Qwen3-VL-2B-Instruct"
    qwen_model_revision: str = "89644892e4d85e24eaac8bacfd4f463576704203"
    qwen_fallback_model_id: str = "Qwen/Qwen3-VL-2B-Instruct"
    qwen_fallback_model_revision: str = "89644892e4d85e24eaac8bacfd4f463576704203"
    qwen_load_in_4bit: bool = True
    qwen_max_new_tokens: int = 450

    eager_load_models: bool = True
    warmup_on_start: bool = True
    preload_slow_models: bool = False
    require_core_models: bool = False

    enrichment_worker_enabled: bool = True
    enrichment_poll_seconds: float = 5.0
    enrichment_lease_seconds: int = 900
    enrichment_job_timeout_seconds: float = 720.0
    enrichment_retry_base_seconds: int = 60
    enrichment_max_images: int = 8
    enrichment_image_max_side: int = 1280
    enrichment_embedding_batch_size: int = 4
    enrichment_cutout_bucket: str = "product-images"

    @property
    def sam_checkpoint(self) -> Path:
        return self.grounded_sam_repo / "checkpoints" / self.sam_checkpoint_name

    @property
    def grounding_dino_checkpoint(self) -> Path:
        return (
            self.grounded_sam_repo
            / "gdino_checkpoints"
            / self.grounding_dino_checkpoint_name
        )


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
