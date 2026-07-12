---
title: Clothes Product Analyzer
emoji: "👕"
colorFrom: yellow
colorTo: green
sdk: docker
app_port: 7860
pinned: false
license: mit
---

# Clothes Product Analyzer

CPU-only FastAPI service for authenticated product analysis and public visual
catalog search. The required `rembg/u2netp` and
`Marqo/marqo-fashionSigLIP` models are downloaded during the Docker build,
loaded at startup, and warmed before `/ready` returns HTTP 200.

## API

- `GET /health` is a liveness endpoint.
- `GET /ready` reports model and Supabase readiness.
- `POST /v1/analyze` requires a Supabase JWT.
- `POST /v1/visual-search` searches the published catalog by photo.

Qwen, PaddleOCR, Grounded-SAM, Grounding DINO, CUDA and bitsandbytes are
disabled in this free CPU deployment. Secrets are configured only as Hugging
Face Space secrets and are not part of this repository.

Repeat deployment from the application repository with:

```powershell
python services/product_analyzer/deployment/deploy.py
```
