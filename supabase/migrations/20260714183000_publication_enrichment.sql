-- Final publication flow and durable post-publication enrichment.
-- This migration is intentionally additive: legacy product columns and all
-- existing images/embeddings remain available during the rollout.

create extension if not exists vector with schema extensions;

create table if not exists public.product_categories (
  code text primary key,
  display_name text not null,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.product_categories (code, display_name, sort_order)
values
  ('t_shirt', 'Футболка', 10),
  ('hoodie', 'Худи', 20),
  ('shirt', 'Рубашка', 30),
  ('jacket', 'Куртка', 40),
  ('jeans', 'Джинсы', 50),
  ('trousers', 'Брюки', 60),
  ('dress', 'Платье', 70),
  ('skirt', 'Юбка', 80),
  ('sneakers', 'Кроссовки', 90),
  ('boots', 'Ботинки', 100),
  ('bag', 'Сумка', 110),
  ('accessory', 'Аксессуар', 120)
on conflict (code) do update
set display_name = excluded.display_name,
    sort_order = excluded.sort_order,
    is_active = true;

create table if not exists public.product_category_aliases (
  alias text primary key,
  category_code text not null references public.product_categories(code)
    on update cascade on delete cascade
);

insert into public.product_category_aliases (alias, category_code)
values
  ('t_shirt', 't_shirt'), ('tshirt', 't_shirt'), ('t-shirt', 't_shirt'),
  ('tee', 't_shirt'), ('top', 't_shirt'), ('футболка', 't_shirt'),
  ('майка', 't_shirt'),
  ('hoodie', 'hoodie'), ('sweatshirt', 'hoodie'), ('худи', 'hoodie'),
  ('толстовка', 'hoodie'), ('свитшот', 'hoodie'), ('sweater', 'hoodie'),
  ('shirt', 'shirt'), ('blouse', 'shirt'), ('рубашка', 'shirt'),
  ('блузка', 'shirt'),
  ('jacket', 'jacket'), ('coat', 'jacket'), ('outerwear', 'jacket'),
  ('куртка', 'jacket'), ('пальто', 'jacket'), ('пуховик', 'jacket'),
  ('jeans', 'jeans'), ('denim', 'jeans'), ('джинсы', 'jeans'),
  ('trousers', 'trousers'), ('pants', 'trousers'), ('брюки', 'trousers'),
  ('штаны', 'trousers'),
  ('dress', 'dress'), ('платье', 'dress'), ('сарафан', 'dress'),
  ('skirt', 'skirt'), ('юбка', 'skirt'),
  ('sneakers', 'sneakers'), ('trainers', 'sneakers'),
  ('кроссовки', 'sneakers'), ('кеды', 'sneakers'),
  ('boots', 'boots'), ('shoes', 'boots'), ('ботинки', 'boots'),
  ('сапоги', 'boots'), ('туфли', 'boots'),
  ('bag', 'bag'), ('handbag', 'bag'), ('сумка', 'bag'), ('рюкзак', 'bag'),
  ('accessory', 'accessory'), ('accessories', 'accessory'),
  ('аксессуар', 'accessory'), ('украшение', 'accessory')
on conflict (alias) do update set category_code = excluded.category_code;

create table if not exists public.product_category_attribute_schemas (
  category_code text not null references public.product_categories(code)
    on update cascade on delete cascade,
  attribute_key text not null,
  display_name text not null,
  value_type text not null default 'enum'
    check (value_type in ('enum', 'text', 'boolean', 'number')),
  options jsonb not null default '[]'::jsonb,
  position integer not null default 0,
  is_searchable boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (category_code, attribute_key)
);

with attribute_sets(category_code, attribute_keys) as (
  values
    ('t_shirt', array['material','pattern','fit','sleeve_length','collar']),
    ('hoodie', array['material','pattern','fit','closure']),
    ('shirt', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('jacket', array['material','fit','collar','closure','season']),
    ('jeans', array['material','fit','rise','closure']),
    ('trousers', array['material','pattern','fit','rise','closure']),
    ('dress', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('skirt', array['material','pattern','fit','rise','closure']),
    ('sneakers', array['material','pattern','closure','style']),
    ('boots', array['material','closure','season','style']),
    ('bag', array['material','pattern','closure','style']),
    ('accessory', array['material','pattern','style'])
), expanded as (
  select category_code, attribute_key, ordinality::integer as position
  from attribute_sets,
       unnest(attribute_keys) with ordinality as keys(attribute_key, ordinality)
)
insert into public.product_category_attribute_schemas (
  category_code, attribute_key, display_name, position
)
select
  category_code,
  attribute_key,
  case attribute_key
    when 'material' then 'Материал'
    when 'pattern' then 'Рисунок'
    when 'fit' then 'Крой'
    when 'sleeve_length' then 'Длина рукава'
    when 'collar' then 'Воротник'
    when 'rise' then 'Посадка'
    when 'closure' then 'Тип застёжки'
    when 'style' then 'Стиль'
    else attribute_key
  end,
  position
from expanded
on conflict (category_code, attribute_key) do update
set display_name = excluded.display_name,
    position = excluded.position;

create table if not exists public.product_brands (
  code text primary key,
  display_name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.product_brands (code, display_name)
values
  ('no_brand', 'Без бренда'),
  ('adidas', 'Adidas'), ('nike', 'Nike'), ('puma', 'Puma'),
  ('zara', 'Zara'), ('hm', 'H&M'), ('uniqlo', 'Uniqlo'),
  ('mango', 'Mango'), ('reebok', 'Reebok'), ('new_balance', 'New Balance'),
  ('converse', 'Converse'), ('vans', 'Vans'), ('levis', 'Levi''s')
on conflict (code) do update set display_name = excluded.display_name;

create table if not exists public.product_brand_aliases (
  alias text primary key,
  brand_code text not null references public.product_brands(code)
    on update cascade on delete cascade
);

insert into public.product_brand_aliases (alias, brand_code)
values
  ('no_brand', 'no_brand'), ('без бренда', 'no_brand'),
  ('безбренда', 'no_brand'), ('no brand', 'no_brand'),
  ('nobrand', 'no_brand'), ('other_brand', 'no_brand'),
  ('adidas', 'adidas'), ('адидас', 'adidas'),
  ('nike', 'nike'), ('найк', 'nike'),
  ('puma', 'puma'), ('пума', 'puma'),
  ('zara', 'zara'), ('зара', 'zara'),
  ('h&m', 'hm'), ('h and m', 'hm'), ('hm', 'hm'), ('эйч энд эм', 'hm'),
  ('uniqlo', 'uniqlo'), ('юникло', 'uniqlo'),
  ('mango', 'mango'), ('манго', 'mango'),
  ('reebok', 'reebok'), ('рибок', 'reebok'),
  ('new balance', 'new_balance'), ('new_balance', 'new_balance'),
  ('нью баланс', 'new_balance'),
  ('converse', 'converse'), ('конверс', 'converse'),
  ('vans', 'vans'), ('ванс', 'vans'),
  ('levi''s', 'levis'), ('levis', 'levis'), ('левис', 'levis')
on conflict (alias) do update set brand_code = excluded.brand_code;

create or replace function public.normalize_product_category(raw_value text)
returns text
language sql
stable
set search_path = public
as $$
  select a.category_code
  from public.product_category_aliases a
  where a.alias = lower(btrim(coalesce(raw_value, '')))
  limit 1;
$$;

create or replace function public.normalize_product_brand(raw_value text)
returns text
language plpgsql
stable
set search_path = public
as $$
declare
  cleaned text := lower(btrim(coalesce(raw_value, '')));
  resolved text;
begin
  if cleaned = '' then return null; end if;
  select a.brand_code into resolved
  from public.product_brand_aliases a
  where a.alias = cleaned
  limit 1;
  return coalesce(resolved, regexp_replace(cleaned, '[^[:alnum:]]+', '_', 'g'));
end;
$$;

alter table public.products
  add column if not exists normalized_category text,
  add column if not exists normalized_brand text,
  add column if not exists audience text,
  add column if not exists has_defects boolean not null default false,
  add column if not exists defects_description text not null default '',
  add column if not exists enrichment_status text not null default 'enrichment_pending',
  add column if not exists enrichment_version text,
  add column if not exists enrichment_completed_at timestamptz,
  add column if not exists photo_quality_score double precision,
  add column if not exists moderation_risk jsonb not null default '{}'::jsonb,
  add column if not exists recommendation_tags text[] not null default '{}',
  add column if not exists search_text text not null default '',
  add column if not exists search_document tsvector not null default ''::tsvector;

update public.products
set normalized_category = coalesce(
      public.normalize_product_category(normalized_category),
      public.normalize_product_category(item_type),
      public.normalize_product_category(subcategory),
      public.normalize_product_category(category)
    ),
    normalized_brand = coalesce(
      nullif(normalized_brand, ''),
      public.normalize_product_brand(brand)
    ),
    audience = coalesce(
      nullif(audience, ''),
      case lower(coalesce(gender, section, ''))
        when 'women' then 'female'
        when 'woman' then 'female'
        when 'female' then 'female'
        when 'женское' then 'female'
        when 'men' then 'male'
        when 'man' then 'male'
        when 'male' then 'male'
        when 'мужское' then 'male'
        when 'kids' then 'kids'
        when 'children' then 'kids'
        when 'детское' then 'kids'
        when 'unisex' then 'unisex'
        when 'унисекс' then 'unisex'
        else null
      end
    ),
    enrichment_status = case
      when enrichment_status in ('enrichment_pending','processing','completed','failed')
        then enrichment_status
      else 'enrichment_pending'
    end,
    search_text = btrim(concat_ws(' ', title, description, brand, category,
      subcategory, item_type, size, condition, primary_color, color));

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_normalized_category_fk'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_normalized_category_fk
      foreign key (normalized_category) references public.product_categories(code)
      not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_audience_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_audience_check
      check (audience is null or audience in ('male','female','unisex','kids'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_enrichment_status_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_enrichment_status_check
      check (enrichment_status in ('enrichment_pending','processing','completed','failed'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'products_photo_quality_score_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_photo_quality_score_check
      check (photo_quality_score is null or photo_quality_score between 0 and 1);
  end if;
end;
$$;

alter table public.products
  validate constraint products_normalized_category_fk;

create index if not exists products_normalized_category_idx
  on public.products (normalized_category) where status = 'published';
create index if not exists products_normalized_brand_idx
  on public.products (normalized_brand) where status = 'published';
create index if not exists products_hard_filters_idx
  on public.products (normalized_category, audience, condition, price)
  where status = 'published' and coalesce(is_hidden, false) = false;
create index if not exists products_search_document_gin_idx
  on public.products using gin (search_document);

create or replace function public.refresh_product_search_document()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  category_terms text;
  brand_terms text;
begin
  select string_agg(alias, ' ') into category_terms
  from public.product_category_aliases
  where category_code = new.normalized_category;
  select string_agg(alias, ' ') into brand_terms
  from public.product_brand_aliases
  where brand_code = new.normalized_brand;
  new.search_document := to_tsvector(
    'simple',
    concat_ws(' ', new.search_text, new.title, new.description, new.brand,
      new.normalized_brand, new.normalized_category, category_terms, brand_terms,
      new.size, new.condition, new.audience, new.primary_color,
      array_to_string(new.secondary_colors, ' '), new.material, new.pattern,
      new.fit, new.style)
  );
  return new;
end;
$$;

drop trigger if exists refresh_product_search_document on public.products;
create trigger refresh_product_search_document
before insert or update of search_text, title, description, brand,
  normalized_brand, normalized_category, size, condition, audience,
  primary_color, secondary_colors, material, pattern, fit, style
on public.products
for each row execute function public.refresh_product_search_document();

update public.products set search_text = search_text;

alter table public.listing_analysis
  add column if not exists user_confirmed boolean not null default false,
  add column if not exists model_version text not null default '';

create table if not exists public.product_attributes (
  product_id uuid not null references public.products(id) on delete cascade,
  attribute_key text not null check (btrim(attribute_key) <> ''),
  value jsonb not null,
  source text not null default 'computed'
    check (source in (
      'user','manual','confirmed','label','tag','visual','computed','legacy'
    )),
  confidence double precision not null default 0
    check (confidence between 0 and 1),
  user_confirmed boolean not null default false,
  model_version text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (product_id, attribute_key)
);

create index if not exists product_attributes_key_value_idx
  on public.product_attributes (attribute_key, value);
create index if not exists product_attributes_product_idx
  on public.product_attributes (product_id);

create or replace function public.product_attribute_priority(
  attribute_source text,
  is_user_confirmed boolean
)
returns integer
language sql
immutable
as $$
  select case
    when attribute_source in ('user', 'manual') then 500
    when is_user_confirmed or attribute_source = 'confirmed' then 400
    when attribute_source in ('label', 'tag') then 300
    when attribute_source = 'visual' then 200
    when attribute_source = 'legacy' then 150
    else 100
  end;
$$;

create or replace function public.protect_product_attribute_priority()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if public.product_attribute_priority(new.source, new.user_confirmed)
     < public.product_attribute_priority(old.source, old.user_confirmed) then
    return old;
  end if;
  if old.user_confirmed and not new.user_confirmed
     and public.product_attribute_priority(new.source, new.user_confirmed)
       = public.product_attribute_priority(old.source, old.user_confirmed) then
    return old;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists protect_product_attribute_priority
  on public.product_attributes;
create trigger protect_product_attribute_priority
before update on public.product_attributes
for each row execute function public.protect_product_attribute_priority();

insert into public.product_attributes (
  product_id, attribute_key, value, source, confidence,
  user_confirmed, model_version
)
select p.id, values.attribute_key, to_jsonb(values.attribute_value),
  'manual', 1, true, 'legacy-backfill-v1'
from public.products p
cross join lateral (
  values
    ('material', p.material),
    ('pattern', p.pattern),
    ('fit', p.fit),
    ('sleeve_length', p.sleeve_length),
    ('closure', p.closure),
    ('season', p.season),
    ('style', p.style)
) as values(attribute_key, attribute_value)
where btrim(coalesce(values.attribute_value, '')) <> ''
on conflict (product_id, attribute_key) do nothing;

create or replace function public.set_product_attribute(
  p_product_id uuid,
  p_attribute_key text,
  p_value jsonb,
  p_confirmed boolean default true,
  p_source text default 'manual',
  p_confidence double precision default 1,
  p_model_version text default ''
)
returns public.product_attributes
language plpgsql
security definer
set search_path = public
as $$
declare
  result public.product_attributes%rowtype;
  resolved_source text := case
    when p_source in ('user','manual','confirmed','label','tag','visual','computed','legacy')
      then p_source
    else 'computed'
  end;
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.products p
    where p.id = p_product_id and p.seller_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'product_not_owned';
  end if;
  if btrim(coalesce(p_attribute_key, '')) = '' or p_value is null then
    raise exception using errcode = '23514', message = 'invalid_attribute';
  end if;
  insert into public.product_attributes (
    product_id, attribute_key, value, source, confidence,
    user_confirmed, model_version
  ) values (
    p_product_id, p_attribute_key, p_value, resolved_source,
    least(1, greatest(0, coalesce(p_confidence, 0))),
    coalesce(p_confirmed, false), coalesce(p_model_version, '')
  )
  on conflict (product_id, attribute_key) do update
  set value = excluded.value,
      source = excluded.source,
      confidence = excluded.confidence,
      user_confirmed = excluded.user_confirmed,
      model_version = excluded.model_version,
      updated_at = now()
  returning * into result;
  return result;
end;
$$;

create or replace function public.get_product_public_attributes(p_product_id uuid)
returns table (attribute_key text, value jsonb)
language sql
stable
security definer
set search_path = public
as $$
  select a.attribute_key, a.value
  from public.product_attributes a
  join public.products p on p.id = a.product_id
  join public.product_category_attribute_schemas s
    on s.category_code = p.normalized_category
   and s.attribute_key = a.attribute_key
  where a.product_id = p_product_id
    and (p.status = 'published' or p.seller_id = auth.uid())
  order by s.position
  limit 6;
$$;

revoke all on function public.set_product_attribute(
  uuid, text, jsonb, boolean, text, double precision, text
) from public, anon;
grant execute on function public.set_product_attribute(
  uuid, text, jsonb, boolean, text, double precision, text
) to authenticated, service_role;
revoke all on function public.get_product_public_attributes(uuid) from public;
grant execute on function public.get_product_public_attributes(uuid)
  to anon, authenticated, service_role;

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  original_url text not null check (btrim(original_url) <> ''),
  no_background_url text,
  role text not null default 'gallery'
    check (role in ('main','gallery','label','defect','detail')),
  position integer not null default 0 check (position >= 0),
  quality_score double precision check (
    quality_score is null or quality_score between 0 and 1
  ),
  quality_details jsonb not null default '{}'::jsonb,
  original_embedding extensions.vector(768),
  foreground_embedding extensions.vector(768),
  original_image_hash text,
  foreground_image_hash text,
  embedding_model_version text not null default '',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (product_id, original_url)
);

create index if not exists product_images_product_position_idx
  on public.product_images (product_id, position) where is_active;
create index if not exists product_images_original_embedding_hnsw_idx
  on public.product_images using hnsw
  (original_embedding extensions.vector_cosine_ops)
  where original_embedding is not null;
create index if not exists product_images_foreground_embedding_hnsw_idx
  on public.product_images using hnsw
  (foreground_embedding extensions.vector_cosine_ops)
  where foreground_embedding is not null;

with raw_images as (
  select p.id as product_id, candidate.url, min(candidate.ordinality) as ordinality,
    bool_or(candidate.url = coalesce(nullif(p.main_image, ''), p.images[1])) as is_main
  from public.products p
  cross join lateral unnest(
    array_remove(
      array[p.original_image, p.main_image, p.image] || coalesce(p.images, '{}'::text[]),
      null
    )
  ) with ordinality as candidate(url, ordinality)
  where btrim(candidate.url) <> ''
  group by p.id, candidate.url
), ranked_images as (
  select *, row_number() over (
    partition by product_id order by is_main desc, ordinality
  ) - 1 as resolved_position
  from raw_images
)
insert into public.product_images (
  product_id, original_url, role, position
)
select product_id, url,
  case when resolved_position = 0 then 'main' else 'gallery' end,
  resolved_position::integer
from ranked_images
on conflict (product_id, original_url) do update
set role = excluded.role,
    position = excluded.position,
    is_active = true;

update public.product_images pi
set no_background_url = p.cutout_image
from public.products p
where p.id = pi.product_id
  and pi.role = 'main'
  and btrim(coalesce(p.cutout_image, '')) <> ''
  and pi.no_background_url is null;

with latest_original as (
  select distinct on (e.product_id, e.image_url)
    e.product_id, e.image_url, e.embedding, e.image_hash, e.model_version
  from public.product_visual_embeddings e
  order by e.product_id, e.image_url, e.updated_at desc
)
update public.product_images pi
set original_embedding = e.embedding,
    original_image_hash = e.image_hash,
    embedding_model_version = e.model_version
from latest_original e
where e.product_id = pi.product_id
  and e.image_url = pi.original_url
  and pi.original_embedding is null;

with latest_foreground as (
  select distinct on (e.product_id, e.image_url)
    e.product_id, e.image_url, e.embedding, e.image_hash, e.model_version
  from public.product_visual_embeddings e
  order by e.product_id, e.image_url, e.updated_at desc
)
update public.product_images pi
set foreground_embedding = e.embedding,
    foreground_image_hash = e.image_hash,
    embedding_model_version = e.model_version
from latest_foreground e
where e.product_id = pi.product_id
  and e.image_url = pi.no_background_url
  and pi.foreground_embedding is null;

drop trigger if exists touch_product_images_updated_at on public.product_images;
create trigger touch_product_images_updated_at
before update on public.product_images
for each row execute function public.touch_listing_updated_at();

create table if not exists public.product_enrichment_jobs (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending','processing','retry','completed','failed')),
  reason text not null default 'publication',
  pipeline_version text not null default 'publication-enrichment-v1',
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 7 check (max_attempts > 0),
  available_at timestamptz not null default now(),
  locked_by text,
  lease_until timestamptz,
  last_error text,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (product_id, pipeline_version)
);

create index if not exists product_enrichment_jobs_claim_idx
  on public.product_enrichment_jobs (status, available_at, lease_until, created_at);
create index if not exists product_enrichment_jobs_product_idx
  on public.product_enrichment_jobs (product_id, created_at desc);

insert into public.product_enrichment_jobs (product_id, reason)
select p.id, 'additive_backfill'
from public.products p
where p.status = 'published'
  and exists (
    select 1 from public.product_images i
    where i.product_id = p.id and i.is_active
  )
on conflict (product_id, pipeline_version) do nothing;

drop trigger if exists touch_product_enrichment_jobs_updated_at
  on public.product_enrichment_jobs;
create trigger touch_product_enrichment_jobs_updated_at
before update on public.product_enrichment_jobs
for each row execute function public.touch_listing_updated_at();

create table if not exists public.product_similarities (
  product_id uuid not null references public.products(id) on delete cascade,
  similar_product_id uuid not null references public.products(id) on delete cascade,
  score double precision not null check (score between 0 and 1),
  model_version text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (product_id, similar_product_id),
  check (product_id <> similar_product_id)
);

create index if not exists product_similarities_rank_idx
  on public.product_similarities (product_id, score desc);

drop trigger if exists touch_product_similarities_updated_at
  on public.product_similarities;
create trigger touch_product_similarities_updated_at
before update on public.product_similarities
for each row execute function public.touch_listing_updated_at();

create or replace function public.enqueue_product_enrichment_job(
  p_product_id uuid,
  p_reason text default 'publication',
  p_force boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  job_id uuid;
  current_status text;
begin
  if auth.role() <> 'service_role' and not exists (
    select 1 from public.products p
    where p.id = p_product_id and p.seller_id = auth.uid()
  ) then
    raise exception using errcode = '42501', message = 'product_not_owned';
  end if;

  select id, status into job_id, current_status
  from public.product_enrichment_jobs
  where product_id = p_product_id
    and pipeline_version = 'publication-enrichment-v1'
  for update;

  if found then
    if p_force or current_status in ('failed', 'completed') then
      update public.product_enrichment_jobs
      set status = 'pending', reason = coalesce(nullif(p_reason, ''), 'publication'),
          attempt_count = 0, available_at = now(), locked_by = null,
          lease_until = null, last_error = null, result = '{}'::jsonb,
          completed_at = null
      where id = job_id;
    end if;
  else
    insert into public.product_enrichment_jobs (product_id, reason)
    values (p_product_id, coalesce(nullif(p_reason, ''), 'publication'))
    returning id into job_id;
  end if;

  update public.products
  set enrichment_status = 'enrichment_pending',
      enrichment_completed_at = null
  where id = p_product_id
    and (p_force or enrichment_status <> 'completed');
  return job_id;
end;
$$;

create or replace function public.claim_product_enrichment_job(
  p_worker_id text,
  p_lease_seconds integer default 900
)
returns setof public.product_enrichment_jobs
language plpgsql
security definer
set search_path = public
as $$
declare
  claimed_id uuid;
begin
  select j.id into claimed_id
  from public.product_enrichment_jobs j
  where j.attempt_count < j.max_attempts
    and (
      (j.status in ('pending','retry') and j.available_at <= now())
      or (j.status = 'processing' and j.lease_until < now())
    )
  order by j.available_at, j.created_at
  for update skip locked
  limit 1;

  if claimed_id is null then return; end if;

  update public.product_enrichment_jobs
  set status = 'processing',
      attempt_count = attempt_count + 1,
      locked_by = p_worker_id,
      lease_until = now() + make_interval(
        secs => least(3600, greatest(60, coalesce(p_lease_seconds, 900)))
      ),
      last_error = null
  where id = claimed_id;

  update public.products p
  set enrichment_status = 'processing'
  from public.product_enrichment_jobs j
  where j.id = claimed_id and p.id = j.product_id;

  return query select * from public.product_enrichment_jobs where id = claimed_id;
end;
$$;

create or replace function public.complete_product_enrichment_job(
  p_job_id uuid,
  p_worker_id text,
  p_result jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  update public.product_enrichment_jobs
  set status = 'completed', result = coalesce(p_result, '{}'::jsonb),
      locked_by = null, lease_until = null, completed_at = now()
  where id = p_job_id and status = 'processing' and locked_by = p_worker_id;
  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.retry_product_enrichment_job(
  p_job_id uuid,
  p_worker_id text,
  p_error text,
  p_retry_delay_seconds integer default 60
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  product_to_update uuid;
  terminal boolean;
begin
  update public.product_enrichment_jobs
  set status = case when attempt_count >= max_attempts then 'failed' else 'retry' end,
      available_at = now() + make_interval(
        secs => least(86400, greatest(1, coalesce(p_retry_delay_seconds, 60)))
      ),
      locked_by = null, lease_until = null,
      last_error = left(coalesce(p_error, 'unknown_error'), 2000)
  where id = p_job_id and status = 'processing' and locked_by = p_worker_id
  returning product_id, status = 'failed' into product_to_update, terminal;

  if product_to_update is null then return false; end if;
  update public.products
  set enrichment_status = case when terminal then 'failed' else 'enrichment_pending' end
  where id = product_to_update;
  return true;
end;
$$;

revoke all on function public.enqueue_product_enrichment_job(uuid, text, boolean)
  from public, anon;
grant execute on function public.enqueue_product_enrichment_job(uuid, text, boolean)
  to authenticated, service_role;
revoke all on function public.claim_product_enrichment_job(text, integer)
  from public, anon, authenticated;
grant execute on function public.claim_product_enrichment_job(text, integer)
  to service_role;
revoke all on function public.complete_product_enrichment_job(uuid, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.complete_product_enrichment_job(uuid, text, jsonb)
  to service_role;
revoke all on function public.retry_product_enrichment_job(uuid, text, text, integer)
  from public, anon, authenticated;
grant execute on function public.retry_product_enrichment_job(uuid, text, text, integer)
  to service_role;

create or replace function public.publish_listing(p_listing_id uuid)
returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  listing_row public.products%rowtype;
  resolved_main_image text;
  resolved_address_id uuid;
begin
  if auth.uid() is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select * into listing_row
  from public.products
  where id = p_listing_id and seller_id = auth.uid()
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'listing_not_found';
  end if;
  if listing_row.status = 'published' then return listing_row; end if;
  if listing_row.status not in ('draft','processing','ready') then
    raise exception using errcode = '23514', message = 'listing_not_publishable';
  end if;
  if btrim(coalesce(listing_row.title, '')) = ''
     or char_length(listing_row.title) > 80 then
    raise exception using errcode = '23514', message = 'invalid_title';
  end if;
  if listing_row.price is null or listing_row.price <= 0 then
    raise exception using errcode = '23514', message = 'invalid_price';
  end if;
  if btrim(coalesce(listing_row.description, '')) = ''
     or char_length(listing_row.description) > 2000 then
    raise exception using errcode = '23514', message = 'invalid_description';
  end if;
  if listing_row.normalized_category is null or not exists (
    select 1 from public.product_categories c
    where c.code = listing_row.normalized_category and c.is_active
  ) then
    raise exception using errcode = '23514', message = 'category_required';
  end if;
  if btrim(coalesce(listing_row.brand, '')) = '' then
    raise exception using errcode = '23514', message = 'brand_required';
  end if;
  if btrim(coalesce(listing_row.size, '')) = '' then
    raise exception using errcode = '23514', message = 'size_required';
  end if;
  if btrim(coalesce(listing_row.condition, '')) = '' then
    raise exception using errcode = '23514', message = 'condition_required';
  end if;
  if listing_row.audience is null
     or listing_row.audience not in ('male','female','unisex','kids') then
    raise exception using errcode = '23514', message = 'audience_required';
  end if;
  if btrim(coalesce(listing_row.primary_color, '')) = '' then
    raise exception using errcode = '23514', message = 'primary_color_required';
  end if;
  if listing_row.has_defects
     and btrim(coalesce(listing_row.defects_description, '')) = '' then
    raise exception using errcode = '23514', message = 'defects_description_required';
  end if;
  if btrim(coalesce(listing_row.city, '')) = '' then
    raise exception using errcode = '23514', message = 'city_required';
  end if;
  if cardinality(coalesce(listing_row.delivery_methods, '{}'::text[])) < 1 then
    raise exception using errcode = '23514', message = 'delivery_method_required';
  end if;
  if cardinality(coalesce(listing_row.images, '{}'::text[])) < 1 then
    raise exception using errcode = '23514', message = 'photo_required';
  end if;
  if exists (
    select 1 from unnest(listing_row.images) image_url
    where btrim(image_url) = '' or image_url !~* '^https?://'
  ) then
    raise exception using errcode = '23514', message = 'photo_not_uploaded';
  end if;

  resolved_main_image := coalesce(
    nullif(btrim(listing_row.main_image), ''), listing_row.images[1]
  );
  if not (resolved_main_image = any(listing_row.images)) then
    raise exception using errcode = '23514', message = 'main_photo_invalid';
  end if;

  resolved_address_id := listing_row.shipping_address_id;
  if resolved_address_id is null then
    select a.id into resolved_address_id
    from public.listing_addresses a
    where a.user_id = auth.uid()
    order by a.is_default desc, a.updated_at desc
    limit 1;
  end if;
  if resolved_address_id is null or not exists (
    select 1 from public.listing_addresses a
    where a.id = resolved_address_id and a.user_id = auth.uid()
  ) then
    raise exception using errcode = '23514', message = 'shipping_address_required';
  end if;

  update public.products
  set status = 'published', main_image = resolved_main_image,
      original_image = coalesce(nullif(btrim(original_image), ''), resolved_main_image),
      image = coalesce(nullif(btrim(image), ''), resolved_main_image),
      normalized_brand = coalesce(
        nullif(normalized_brand, ''), public.normalize_product_brand(brand)
      ),
      shipping_address_id = resolved_address_id, is_hidden = false,
      published_at = coalesce(published_at, now()),
      enrichment_status = 'enrichment_pending',
      enrichment_completed_at = null, last_autosaved_at = now()
  where id = p_listing_id
  returning * into listing_row;

  insert into public.product_images (product_id, original_url, role, position)
  select p_listing_id, image_url,
    case when image_url = resolved_main_image then 'main' else 'gallery' end,
    ordinality::integer - 1
  from unnest(listing_row.images) with ordinality as image_rows(image_url, ordinality)
  on conflict (product_id, original_url) do update
  set role = excluded.role, position = excluded.position, is_active = true;

  perform public.enqueue_product_enrichment_job(
    p_listing_id, 'publication', false
  );
  return listing_row;
end;
$$;

revoke all on function public.publish_listing(uuid) from public, anon;
grant execute on function public.publish_listing(uuid) to authenticated;

create or replace function public.search_catalog_products(
  p_query text default null,
  p_category text default null,
  p_sizes text[] default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_brands text[] default null,
  p_conditions text[] default null,
  p_audiences text[] default null,
  p_delivery_methods text[] default null,
  p_colors text[] default null,
  p_materials text[] default null,
  p_patterns text[] default null,
  p_fits text[] default null,
  p_styles text[] default null,
  p_limit integer default 60,
  p_offset integer default 0
)
returns setof public.products
language sql
stable
security definer
set search_path = public
as $$
  select p.*
  from public.products p
  where p.status = 'published' and coalesce(p.is_hidden, false) = false
    and (p_category is null or p.normalized_category = p_category)
    and (p_sizes is null or cardinality(p_sizes) = 0 or p.size = any(p_sizes))
    and (p_min_price is null or p.price >= p_min_price)
    and (p_max_price is null or p.price <= p_max_price)
    and (p_brands is null or cardinality(p_brands) = 0
      or p.normalized_brand = any(p_brands) or p.brand = any(p_brands))
    and (p_conditions is null or cardinality(p_conditions) = 0
      or p.condition = any(p_conditions))
    and (p_audiences is null or cardinality(p_audiences) = 0
      or p.audience = any(p_audiences))
    and (p_delivery_methods is null or cardinality(p_delivery_methods) = 0
      or p.delivery_methods && p_delivery_methods)
    and (p_query is null or btrim(p_query) = ''
      or p.search_document @@ websearch_to_tsquery('simple', p_query))
  order by
    case when p_colors is not null and (
      p.primary_color = any(p_colors) or p.secondary_colors && p_colors
    ) then 1 else 0 end
    + case when p_materials is not null and p.material = any(p_materials)
      then 1 else 0 end
    + case when p_patterns is not null and p.pattern = any(p_patterns)
      then 1 else 0 end
    + case when p_fits is not null and p.fit = any(p_fits)
      then 1 else 0 end
    + case when p_styles is not null and p.style = any(p_styles)
      then 1 else 0 end desc,
    case when p_query is null or btrim(p_query) = '' then 0
      else ts_rank_cd(p.search_document, websearch_to_tsquery('simple', p_query))
    end desc,
    p.published_at desc nulls last
  limit least(100, greatest(1, coalesce(p_limit, 60)))
  offset greatest(0, coalesce(p_offset, 0));
$$;

revoke all on function public.search_catalog_products(
  text, text, text[], numeric, numeric, text[], text[], text[], text[],
  text[], text[], text[], text[], text[], integer, integer
) from public;
grant execute on function public.search_catalog_products(
  text, text, text[], numeric, numeric, text[], text[], text[], text[],
  text[], text[], text[], text[], text[], integer, integer
) to anon, authenticated, service_role;

alter table public.product_categories enable row level security;
alter table public.product_category_aliases enable row level security;
alter table public.product_category_attribute_schemas enable row level security;
alter table public.product_brands enable row level security;
alter table public.product_brand_aliases enable row level security;
alter table public.product_attributes enable row level security;
alter table public.product_images enable row level security;
alter table public.product_enrichment_jobs enable row level security;
alter table public.product_similarities enable row level security;

drop policy if exists "Product categories are readable"
  on public.product_categories;
create policy "Product categories are readable"
  on public.product_categories for select using (true);
drop policy if exists "Product category aliases are readable"
  on public.product_category_aliases;
create policy "Product category aliases are readable"
  on public.product_category_aliases for select using (true);
drop policy if exists "Product attribute schemas are readable"
  on public.product_category_attribute_schemas;
create policy "Product attribute schemas are readable"
  on public.product_category_attribute_schemas for select using (true);
drop policy if exists "Product brands are readable" on public.product_brands;
create policy "Product brands are readable"
  on public.product_brands for select using (true);
drop policy if exists "Product brand aliases are readable"
  on public.product_brand_aliases;
create policy "Product brand aliases are readable"
  on public.product_brand_aliases for select using (true);

grant select on table public.product_categories,
  public.product_category_aliases,
  public.product_category_attribute_schemas,
  public.product_brands,
  public.product_brand_aliases
to anon, authenticated;

drop policy if exists "Public attributes are readable for visible products"
  on public.product_attributes;
create policy "Public attributes are readable for visible products"
  on public.product_attributes for select
  using (exists (
    select 1 from public.products p
    where p.id = product_id
      and (p.status = 'published' or p.seller_id = auth.uid())
  ));
drop policy if exists "Owners manage product attributes"
  on public.product_attributes;
create policy "Owners manage product attributes"
  on public.product_attributes for all to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_id and p.seller_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.products p
    where p.id = product_id and p.seller_id = auth.uid()
  ));

drop policy if exists "Product images are readable"
  on public.product_images;
create policy "Product images are readable"
  on public.product_images for select
  using (exists (
    select 1 from public.products p
    where p.id = product_id
      and (p.status = 'published' or p.seller_id = auth.uid())
  ));
drop policy if exists "Owners manage product images"
  on public.product_images;
create policy "Owners manage product images"
  on public.product_images for all to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_id and p.seller_id = auth.uid()
  ))
  with check (exists (
    select 1 from public.products p
    where p.id = product_id and p.seller_id = auth.uid()
  ));

drop policy if exists "Owners read enrichment jobs"
  on public.product_enrichment_jobs;
create policy "Owners read enrichment jobs"
  on public.product_enrichment_jobs for select to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = product_id and p.seller_id = auth.uid()
  ));

-- Similarities, vectors, confidence and worker state are internal. Buyer apps
-- receive only public product fields and the value-only attributes RPC.
revoke all on table public.product_enrichment_jobs from anon, authenticated;
grant select on table public.product_enrichment_jobs to authenticated;
revoke all on table public.product_attributes from anon, authenticated;
revoke all on table public.product_images from anon, authenticated;
revoke all on table public.product_similarities from anon, authenticated;
revoke all on table public.product_visual_embeddings from anon, authenticated;
grant all on table public.product_enrichment_jobs to service_role;
grant all on table public.product_similarities to service_role;
grant all on table public.product_images to service_role;
grant all on table public.product_attributes to service_role;

drop trigger if exists touch_product_categories_updated_at
  on public.product_categories;
create trigger touch_product_categories_updated_at
before update on public.product_categories
for each row execute function public.touch_listing_updated_at();
drop trigger if exists touch_product_category_attribute_schemas_updated_at
  on public.product_category_attribute_schemas;
create trigger touch_product_category_attribute_schemas_updated_at
before update on public.product_category_attribute_schemas
for each row execute function public.touch_listing_updated_at();
drop trigger if exists touch_product_brands_updated_at on public.product_brands;
create trigger touch_product_brands_updated_at
before update on public.product_brands
for each row execute function public.touch_listing_updated_at();

notify pgrst, 'reload schema';
