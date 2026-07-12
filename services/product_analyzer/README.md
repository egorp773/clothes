# Product Analyzer Service

Локальный сервис анализа одежды. Flutter вызывает `POST /v1/analyze` и
`POST /v1/visual-search`; детали моделей и service-role изолированы от
приложения.

## Зафиксированные официальные источники

| Компонент | Источник | Версия |
|---|---|---|
| Grounding DINO + SAM 2.1 | [IDEA-Research/Grounded-SAM-2](https://github.com/IDEA-Research/Grounded-SAM-2) | commit `b7a9c29f196edff0eb54dbe14588d7ae5e3dde28` |
| FashionSigLIP | [marqo-ai/marqo-FashionCLIP](https://github.com/marqo-ai/marqo-FashionCLIP), [Marqo/marqo-fashionSigLIP](https://huggingface.co/Marqo/marqo-fashionSigLIP) | repo commit `d0b3bdfb62fb4964537cb582e76d6ddab0be8450`, HF revision `c56244cc94f92419e8369fa71efdaf403b124ce8` |
| OCR | [PaddlePaddle/PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR) | repo commit `211989f046cc1878460f9e65574690c00a127a1a`, package `3.7.0` |
| Дополнительные атрибуты | [QwenLM/Qwen3-VL](https://github.com/QwenLM/Qwen3-VL), [Qwen/Qwen3-VL-4B-Instruct](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct) | repo commit `96588727e44c78b25ba03ea03b8e12f7e64fd0da`, HF 4B `ebb281ec…`, 2B `89644892…`, `transformers==4.57.6` |

Код моделей и веса не копируются в Flutter и не коммитятся. Grounded-SAM-2
клонируется в `vendor/`, checkpoints скачиваются только официальными
`checkpoints/download_ckpts.sh` и `gdino_checkpoints/download_ckpts.sh`.

## Pipeline

```text
multipart images
  → Grounding DINO → SAM 2.1 mask/cutout
  → FashionSigLIP closed-category top-k
  → OpenCV LAB/HSV + MiniBatchKMeans inside mask
  → PaddleOCR → normalized brand/size/composition
  → optional Qwen3-VL strict JSON over allowed values
  → one stable API response
```

Цвет никогда не вычисляется без Grounded-SAM mask: при недоступной
сегментации поле остаётся `null`. Qwen также необязателен; его отказ не ломает
категорию, цвет или OCR.

## Рекомендуемый запуск: Docker + NVIDIA

Требуется Docker с NVIDIA Container Toolkit и достаточно диска под модели.

```bash
cd services/product_analyzer
cp .env.example .env
docker build -t clothes-product-analyzer .
docker run --gpus all --env-file .env -p 8090:8090 \
  -v analyzer-models:/root/.cache/huggingface \
  -v analyzer-vendor:/service/vendor \
  clothes-product-analyzer
```

При первом запуске entrypoint клонирует строго зафиксированный commit
Grounded-SAM-2 и запускает оба официальных checkpoint-скрипта. Повторные
запуски используют volume.

## Локальная установка

Grounded-SAM-2 официально рекомендует Python 3.10, PyTorch 2.3.1,
TorchVision 0.18.1 и CUDA 12.1. Для Grounding DINO требуется компиляция
Deformable Attention, поэтому Windows лучше запускать через WSL2 или Docker.

```bash
cd services/product_analyzer
python3.10 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt
python scripts/setup_models.py --download-checkpoints
cp .env.example .env
uvicorn app.main:app --host 0.0.0.0 --port 8090
```

Опциональная предварительная загрузка HF-моделей:

```bash
python scripts/setup_models.py --prefetch-huggingface
python scripts/setup_models.py --prefetch-huggingface --include-qwen
```

## CPU и нехватка VRAM

- Grounding DINO/SAM и FashionSigLIP могут работать на CPU, но медленно.
- Qwen по умолчанию не загружается без CUDA.
- На GPU сначала используется Qwen 4B в 4-bit; при ошибке загрузки адаптер
  пробует официальный `Qwen3-VL-2B-Instruct`.
- Чтобы сознательно разрешить очень медленный CPU Qwen, задайте
  `ALLOW_QWEN_CPU=true` и при необходимости `QWEN_LOAD_IN_4BIT=false`.
- Любая ошибка отдельного адаптера записывается в `warnings`; доступные
  результаты всё равно возвращаются.

## API

Для локального запуска с персистентными job-результатами не копируйте
`service_role` вручную. После `supabase login` и `supabase link` используйте:

```powershell
.\scripts\run_with_linked_supabase.ps1
```

Скрипт получает ключ через Supabase CLI только в окружение процесса. Для
Docker/production задайте `SUPABASE_URL` и `SUPABASE_SERVICE_ROLE_KEY` через
secret manager платформы.

```bash
curl http://localhost:8090/health
curl -X POST http://localhost:8090/warmup
curl -X POST http://localhost:8090/v1/analyze \
  -F "files=@front.jpg" \
  -F "files=@label.jpg"
```

Ответ содержит совместимые с Flutter поля `category`, `subcategory`,
`item_type`, `primary_color`, `brand`, `material`, `pattern`, `season`,
`style`, а также `category_top_k`, OCR-данные и дополнительные атрибуты.

Flutter по умолчанию использует Android Emulator URL `http://10.0.2.2:8090`.
Для iOS Simulator, web или реального устройства задайте адрес явно:

```bash
flutter run --dart-define=PRODUCT_ANALYZER_URL=http://localhost:8090
# Реальное устройство: используйте HTTPS URL сервиса или LAN IP с подходящей
# platform network policy.
```

### Поиск по фотографии

После применения миграций выполните идемпотентный backfill каталога:

```powershell
.\scripts\backfill_visual_embeddings_linked.ps1
```

Полная переиндексация выполняется той же командой; конкретные товары можно
передать через `-ProductId`. Поиск использует фактический 768-мерный
нормализованный embedding `Marqo/marqo-fashionSigLIP`, HNSW cosine index и
защищённую service-role RPC. Оба endpoint требуют Supabase access JWT:

```bash
curl -X POST http://localhost:8090/v1/visual-search \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -F "file=@query.jpg" \
  -F 'filters={"min_price":1000,"colors":["black"]}'

curl -X POST http://localhost:8090/v1/products/PRODUCT_ID/embeddings \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN"
```

Для воспроизводимого замера на связанном Supabase:

```powershell
.\scripts\benchmark_visual_search_linked.ps1
.\scripts\smoke_visual_search_http_linked.ps1
```

## Тесты

Синтетические изображения в тестах являются реальными RGB fixtures и
проверяют масочный color pipeline без загрузки многогигабайтных весов:

```bash
pytest -q
```

Покрыты чёрный/тёмно-синий, белый/светло-серый, серый с тенями, цветной фон,
двухцветная вещь и маленький контрастный логотип. Фото одежды на человеке и
полная Grounded-SAM/FashionSigLIP интеграция проверяются после установки весов
интеграционным smoke-запросом к `/v1/analyze`.

## Production

- Не открывайте сервис напрямую в интернет без TLS, auth и rate limiting.
- Ограничения количества/размера фото уже применяются в API.
- Для нескольких worker-процессов каждый worker загрузит собственную копию
  моделей; обычно нужен один worker на GPU.
- `POST /warmup` загружает модели один раз. Можно включить
  `EAGER_LOAD_MODELS=true` и `WARMUP_ON_START=true`.
