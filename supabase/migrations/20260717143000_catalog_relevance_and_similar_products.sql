-- Keep structured catalogue filters strict and expose precomputed product
-- similarities without granting buyer clients access to the internal table.

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
  select product.*
  from public.products product
  where product.status = 'published'
    and not coalesce(product.is_hidden, false)
    and (
      auth.uid() is null
      or product.seller_id is null
      or auth.uid() = product.seller_id
      or not public.users_are_blocked(auth.uid(), product.seller_id)
    )
    and (p_category is null or product.normalized_category = p_category)
    and (p_sizes is null or cardinality(p_sizes) = 0
      or product.size = any(p_sizes))
    and (p_min_price is null or product.price >= p_min_price)
    and (p_max_price is null or product.price <= p_max_price)
    and (p_brands is null or cardinality(p_brands) = 0
      or product.normalized_brand = any(p_brands)
      or product.brand = any(p_brands))
    and (p_conditions is null or cardinality(p_conditions) = 0
      or product.condition = any(p_conditions))
    and (p_audiences is null or cardinality(p_audiences) = 0
      or product.audience = any(p_audiences))
    and (p_delivery_methods is null or cardinality(p_delivery_methods) = 0
      or product.delivery_methods && p_delivery_methods)
    -- A requested colour describes the main item colour. Secondary colours
    -- must not make a white listing match a "black trousers" query.
    and (p_colors is null or cardinality(p_colors) = 0
      or coalesce(
        nullif(product.primary_color, ''),
        nullif(product.color, '')
      ) = any(p_colors))
    and (p_materials is null or cardinality(p_materials) = 0
      or product.material = any(p_materials))
    and (p_patterns is null or cardinality(p_patterns) = 0
      or product.pattern = any(p_patterns))
    and (p_fits is null or cardinality(p_fits) = 0
      or product.fit = any(p_fits))
    and (p_styles is null or cardinality(p_styles) = 0
      or product.style = any(p_styles))
    and (p_query is null or btrim(p_query) = ''
      or product.search_document @@ websearch_to_tsquery('simple', p_query))
  order by
    case when p_query is null or btrim(p_query) = '' then 0
      else ts_rank_cd(
        product.search_document,
        websearch_to_tsquery('simple', p_query)
      )
    end desc,
    product.published_at desc nulls last,
    product.id
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

create or replace function public.get_similar_catalog_products(
  p_product_id uuid,
  p_limit integer default 8
)
returns setof public.products
language sql
stable
security definer
set search_path = public
as $$
  with source as (
    select product.*
    from public.products product
    where product.id = p_product_id
      and product.status = 'published'
      and not coalesce(product.is_hidden, false)
      and (
        auth.uid() is null
        or product.seller_id is null
        or auth.uid() = product.seller_id
        or not public.users_are_blocked(auth.uid(), product.seller_id)
      )
  )
  select candidate.*
  from source
  join public.products candidate
    on candidate.id <> source.id
  left join public.product_similarities similarity
    on similarity.product_id = source.id
   and similarity.similar_product_id = candidate.id
  where candidate.status = 'published'
    and not coalesce(candidate.is_hidden, false)
    and (
      auth.uid() is null
      or candidate.seller_id is null
      or auth.uid() = candidate.seller_id
      or not public.users_are_blocked(auth.uid(), candidate.seller_id)
    )
    and (
      similarity.similar_product_id is not null
      or (
        nullif(source.normalized_category, '') is not null
        and candidate.normalized_category = source.normalized_category
      )
    )
  order by
    (similarity.similar_product_id is not null) desc,
    similarity.score desc nulls last,
    (
      case when nullif(source.normalized_brand, '') is not null
        and candidate.normalized_brand = source.normalized_brand
        then 24 else 0 end
      + case when coalesce(
          nullif(source.primary_color, ''), nullif(source.color, '')
        ) is not null
        and coalesce(
          nullif(candidate.primary_color, ''), nullif(candidate.color, '')
        ) = coalesce(
          nullif(source.primary_color, ''), nullif(source.color, '')
        )
        then 18 else 0 end
      + case when nullif(source.material, '') is not null
        and candidate.material = source.material
        then 9 else 0 end
      + case when nullif(source.style, '') is not null
        and candidate.style = source.style
        then 7 else 0 end
      + case when nullif(source.fit, '') is not null
        and candidate.fit = source.fit
        then 5 else 0 end
      + case when nullif(source.pattern, '') is not null
        and candidate.pattern = source.pattern
        then 4 else 0 end
    ) desc,
    candidate.published_at desc nulls last,
    candidate.id
  limit least(24, greatest(1, coalesce(p_limit, 8)));
$$;

revoke all on function public.get_similar_catalog_products(uuid, integer)
  from public;
grant execute on function public.get_similar_catalog_products(uuid, integer)
  to anon, authenticated, service_role;

notify pgrst, 'reload schema';
