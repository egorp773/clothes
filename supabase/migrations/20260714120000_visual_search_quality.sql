-- Improve multi-view visual retrieval and expose embedding taxonomy to reranking.

drop function if exists public.search_product_visual_candidates(
  extensions.vector, text, integer, text, text[], numeric, numeric,
  text[], text[], text[], text[]
);

create function public.search_product_visual_candidates(
  p_query_embedding extensions.vector(768),
  p_model_version text,
  p_match_count integer default 200,
  p_category text default null,
  p_related_subcategories text[] default null,
  p_min_price numeric default null,
  p_max_price numeric default null,
  p_sizes text[] default null,
  p_brands text[] default null,
  p_conditions text[] default null,
  p_colors text[] default null
)
returns table (
  product_id uuid,
  image_url text,
  view_type text,
  visual_similarity double precision,
  title text,
  description text,
  price numeric,
  images text[],
  main_image text,
  category text,
  subcategory text,
  item_type text,
  brand text,
  size text,
  condition text,
  primary_color text,
  secondary_colors text[],
  gender text,
  published_at timestamptz,
  favorite_count bigint,
  visual_category text,
  visual_subcategory text,
  visual_item_type text
)
language sql
stable
security definer
set search_path = public, extensions
as $$
  with nearest_embeddings as (
    select
      e.product_id,
      e.image_url,
      e.view_type,
      e.detected_category,
      e.detected_subcategory,
      e.detected_item_type,
      1 - (e.embedding <=> p_query_embedding) as similarity
    from public.product_visual_embeddings e
    join public.products p on p.id = e.product_id
    where e.model_version = p_model_version
      and p.status = 'published'
      and coalesce(p.is_hidden, false) = false
      and (p_min_price is null or p.price >= p_min_price)
      and (p_max_price is null or p.price <= p_max_price)
      and (p_sizes is null or cardinality(p_sizes) = 0 or p.size = any(p_sizes))
      and (p_brands is null or cardinality(p_brands) = 0 or p.brand = any(p_brands))
      and (p_conditions is null or cardinality(p_conditions) = 0 or p.condition = any(p_conditions))
      and (
        p_colors is null or cardinality(p_colors) = 0
        or p.primary_color = any(p_colors)
        or p.secondary_colors && p_colors
      )
      and (
        p_category is null
        or e.detected_category = p_category
        or p.category = p_category
        or (
          p_related_subcategories is not null
          and (
            e.detected_subcategory = any(p_related_subcategories)
            or p.subcategory = any(p_related_subcategories)
          )
        )
      )
    order by e.embedding <=> p_query_embedding
    limit least(greatest(coalesce(p_match_count, 200) * 3, 1), 600)
  ), ranked_products as (
    select
      nearest_embeddings.*,
      row_number() over (
        partition by nearest_embeddings.product_id
        order by nearest_embeddings.similarity desc
      ) as product_rank
    from nearest_embeddings
  ), nearest as (
    select *
    from ranked_products
    where product_rank = 1
    order by similarity desc
    limit least(greatest(coalesce(p_match_count, 200), 1), 300)
  )
  select
    n.product_id,
    n.image_url,
    n.view_type,
    n.similarity,
    p.title,
    p.description,
    p.price,
    p.images,
    p.main_image,
    p.category,
    coalesce(nullif(p.subcategory, ''), n.detected_subcategory),
    coalesce(nullif(p.item_type, ''), n.detected_item_type),
    p.brand,
    p.size,
    p.condition,
    p.primary_color,
    p.secondary_colors,
    p.gender,
    p.published_at,
    (select count(*) from public.product_favorites f where f.product_id = p.id::text),
    n.detected_category,
    n.detected_subcategory,
    n.detected_item_type
  from nearest n
  join public.products p on p.id = n.product_id
  order by n.similarity desc;
$$;

revoke all on function public.search_product_visual_candidates(
  extensions.vector, text, integer, text, text[], numeric, numeric,
  text[], text[], text[], text[]
) from public, anon, authenticated;
grant execute on function public.search_product_visual_candidates(
  extensions.vector, text, integer, text, text[], numeric, numeric,
  text[], text[], text[], text[]
) to service_role;

notify pgrst, 'reload schema';
