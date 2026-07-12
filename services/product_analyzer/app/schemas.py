from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class AnalyzedField(BaseModel):
    value: str | None = None
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    source: str


class CategoryCandidate(BaseModel):
    category: str
    subcategory: str
    item_type: str
    confidence: float = Field(ge=0.0, le=1.0)


class OcrPayload(BaseModel):
    texts: list[str] = Field(default_factory=list)
    size: str | None = None
    composition: str | None = None


class AnalysisResponse(BaseModel):
    analysis_id: str | None = None
    enrichment_status: str = "not_scheduled"
    section: AnalyzedField
    category: AnalyzedField
    subcategory: AnalyzedField
    item_type: AnalyzedField
    gender: AnalyzedField
    primary_color: AnalyzedField
    secondary_colors: list[AnalyzedField]
    brand: AnalyzedField
    material: AnalyzedField
    pattern: AnalyzedField
    season: AnalyzedField
    style: AnalyzedField
    fit: AnalyzedField
    sleeve_length: AnalyzedField
    closure: AnalyzedField
    suggested_title: AnalyzedField
    suggested_description: AnalyzedField
    suggested_size: AnalyzedField
    category_top_k: list[CategoryCandidate] = Field(default_factory=list)
    ocr: OcrPayload = Field(default_factory=OcrPayload)
    warnings: list[str] = Field(default_factory=list)
    timings_ms: dict[str, int] = Field(default_factory=dict)


class ComponentHealth(BaseModel):
    loaded: bool
    available: bool
    model: str
    detail: str | None = None


class HealthResponse(BaseModel):
    status: str
    ready: bool
    components: dict[str, ComponentHealth]
    versions: dict[str, str]


class SegmentationOutput(BaseModel):
    score: float
    label: str
    bbox: tuple[int, int, int, int]
    metadata: dict[str, Any] = {}
