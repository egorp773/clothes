from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class VisualSearchFilters(BaseModel):
    min_price: float | None = None
    max_price: float | None = None
    sizes: list[str] = Field(default_factory=list)
    brands: list[str] = Field(default_factory=list)
    conditions: list[str] = Field(default_factory=list)
    colors: list[str] = Field(default_factory=list)


class VisualSearchProduct(BaseModel):
    product_id: str
    score: float
    visual_similarity: float
    matched_image_url: str
    title: str = ""
    description: str = ""
    price: float = 0
    images: list[str] = Field(default_factory=list)
    main_image: str = ""
    category: str = ""
    subcategory: str = ""
    item_type: str = ""
    brand: str = ""
    size: str = ""
    condition: str = ""
    primary_color: str = ""
    secondary_colors: list[str] = Field(default_factory=list)
    gender: str = ""
    published_at: str | None = None
    favorite_count: int = 0


class VisualSearchResponse(BaseModel):
    image_hash: str
    model_version: str
    category: str | None = None
    subcategory: str | None = None
    item_type: str | None = None
    category_confidence: float = 0
    candidate_count: int = 0
    products: list[VisualSearchProduct] = Field(default_factory=list)
    timings_ms: dict[str, int] = Field(default_factory=dict)
    cached: bool = False
    warnings: list[str] = Field(default_factory=list)


class VisualSearchRegion(BaseModel):
    id: str
    label: str | None = None
    confidence: float = Field(ge=0, le=1)
    bbox: tuple[float, float, float, float]


class VisualSearchRegionsResponse(BaseModel):
    width: int = Field(gt=0)
    height: int = Field(gt=0)
    regions: list[VisualSearchRegion] = Field(default_factory=list)


class ProductEmbeddingResponse(BaseModel):
    product_id: str
    model_version: str
    embedding_dimension: int
    indexed_images: int
    skipped_images: int
    idempotent: bool
    timings_ms: dict[str, int] = Field(default_factory=dict)


class AuthenticatedUser(BaseModel):
    id: str
    raw: dict[str, Any] = Field(default_factory=dict)
