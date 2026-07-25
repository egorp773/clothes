-- Close the remaining public-listing and legacy mutation paths.
--
-- This migration deliberately never unhides a listing. A listing quarantined
-- because its seller became ineligible must pass the authoritative publication
-- flow again after an explicit moderation decision.

begin;

-- Historical rows were marked as published before seller accounts and seller
-- verification existed. Fail closed before replacing the public SELECT policy.
update public.products product
set is_hidden = true
where product.status = 'published'
  and not coalesce(product.is_hidden, false)
  and not public.listing_is_public(product.id);

drop policy if exists "Published products are readable" on public.products;
create policy "Published products are readable"
  on public.products for select
  to anon, authenticated
  using (
    seller_id = (select auth.uid())
    or (
      public.listing_is_public(id)
      and (
        (select auth.uid()) is null
        or not public.users_are_blocked(
          (select auth.uid()),
          seller_id
        )
      )
    )
  );

-- A seller restriction and its listing quarantine belong to one transaction.
-- Restoring seller eligibility intentionally does not restore visibility.
create or replace function public.hide_ineligible_seller_listings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.seller_type <> 'private_individual'
     or new.status <> 'verified'
     or new.verification_status <> 'verified'
     or new.moderation_status <> 'clear' then
    update public.products product
    set is_hidden = true
    where product.seller_id = new.user_id
      and product.status = 'published'
      and not coalesce(product.is_hidden, false);
  end if;
  return new;
end;
$$;

drop trigger if exists hide_ineligible_seller_listings_after_change
  on public.seller_accounts;
create trigger hide_ineligible_seller_listings_after_change
after insert or update of
  seller_type,
  status,
  verification_status,
  moderation_status
on public.seller_accounts
for each row execute function public.hide_ineligible_seller_listings();

revoke all on function public.hide_ineligible_seller_listings()
  from public, anon, authenticated;

-- Final product media is readable only through a listing-linked policy. The
-- owner_id-only fallback made arbitrary legacy objects a permanent side door.
drop policy if exists "Owners read legacy product media" on storage.objects;

-- These pre-authoritative RPCs can mutate enrichment state without the current
-- seller-entitlement and publication boundary. Workers keep service-role access.
revoke execute on function public.set_product_attribute(
  uuid,
  text,
  jsonb,
  boolean,
  text,
  double precision,
  text
) from authenticated;

revoke execute on function public.enqueue_product_enrichment_job(
  uuid,
  text,
  boolean
) from authenticated;

-- Moderation history is evidence, not mutable application state.
drop trigger if exists seller_moderation_actions_are_immutable
  on public.seller_moderation_actions;
create trigger seller_moderation_actions_are_immutable
before update or delete on public.seller_moderation_actions
for each row execute function public.prevent_immutable_ledger_mutation();

create or replace function public.prevent_published_legal_version_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('published', 'retired') then
    raise exception 'published_legal_version_is_immutable'
      using errcode = '42501';
  end if;
  return old;
end;
$$;

drop trigger if exists prevent_published_legal_version_delete_before_delete
  on public.legal_document_versions;
create trigger prevent_published_legal_version_delete_before_delete
before delete on public.legal_document_versions
for each row execute function public.prevent_published_legal_version_delete();

revoke all on function public.prevent_published_legal_version_delete()
  from public, anon, authenticated;

-- Catalog search touches only public.products and public helper functions, so
-- it can safely execute with caller privileges and inherit the products RLS.
alter function public.search_catalog_products(
  text,
  text,
  text[],
  numeric,
  numeric,
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  text[],
  integer,
  integer
) security invoker;

-- Similar search also reads the internal product_similarities table, which is
-- intentionally not granted to clients. Keep SECURITY DEFINER, but make every
-- source and candidate row cross the canonical public-listing boundary.
create or replace function public.get_similar_catalog_products(
  p_product_id uuid,
  p_limit integer default 8
)
returns setof public.products
language sql
stable
security definer
set search_path = ''
as $$
  with source as (
    select product.*
    from public.products product
    where product.id = p_product_id
      and public.listing_is_public(product.id)
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
  where public.listing_is_public(candidate.id)
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

-- Visual search is called by the private analyzer with service_role, so table
-- RLS cannot protect its result. Keep vector access internal and wrap the
-- historical function with the same canonical visibility predicate.
alter function public.search_product_visual_candidates(
  extensions.vector, text, integer, text, text[], numeric, numeric,
  text[], text[], text[], text[]
) rename to search_product_visual_candidates_unfiltered;

revoke all on function public.search_product_visual_candidates_unfiltered(
  extensions.vector, text, integer, text, text[], numeric, numeric,
  text[], text[], text[], text[]
) from public, anon, authenticated, service_role;

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
set search_path = ''
as $$
  select candidate.*
  from public.search_product_visual_candidates_unfiltered(
    p_query_embedding,
    p_model_version,
    p_match_count,
    p_category,
    p_related_subcategories,
    p_min_price,
    p_max_price,
    p_sizes,
    p_brands,
    p_conditions,
    p_colors
  ) candidate
  where public.listing_is_public(candidate.product_id);
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

commit;
