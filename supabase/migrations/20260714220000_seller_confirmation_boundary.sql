-- Seller-confirmed values form the public product projection. ML proposals
-- stay in listing_analysis/product_attributes until the seller reviews them.

alter table public.products
  add column if not exists defects_reviewed boolean not null default false;

-- Published legacy rows predate the explicit choice and are preserved as an
-- already completed disclosure. Recoverable drafts still require a choice.
update public.products
set defects_reviewed = true
where status = 'published'
   or has_defects
   or btrim(coalesce(defects_description, '')) <> '';

alter table public.products alter column status set default 'draft';

create or replace function public.get_product_public_attributes(
  p_product_id uuid
)
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
    and p.status = 'published'
    and a.user_confirmed
    and a.value <> 'null'::jsonb
    and a.value <> '""'::jsonb
  order by s.position
  limit 6;
$$;

revoke all on function public.get_product_public_attributes(uuid) from public;
grant execute on function public.get_product_public_attributes(uuid)
  to anon, authenticated, service_role;

-- A visible product may become published only inside publish_listing. Hidden
-- closet items remain backward-compatible with the existing outfit flow.
create or replace function public.guard_visible_product_publication()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  exposes_product boolean :=
    new.status = 'published' and not coalesce(new.is_hidden, false);
  starts_publication boolean := tg_op = 'INSERT';
begin
  if tg_op = 'UPDATE' then
    starts_publication := old.status <> 'published'
      or coalesce(old.is_hidden, false);
  end if;

  if exposes_product
     and starts_publication
     and auth.role() <> 'service_role'
     and coalesce(
       current_setting('clothes.publish_listing', true), ''
     ) <> 'allowed' then
    raise exception using
      errcode = '42501',
      message = 'publish_listing_rpc_required';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_visible_product_publication on public.products;
create trigger guard_visible_product_publication
before insert or update on public.products
for each row execute function public.guard_visible_product_publication();

create or replace function public.publish_listing(p_listing_id uuid)
returns public.products
language plpgsql
security definer
set search_path = public
as $$
declare
  listing_row public.products%rowtype;
  address_row public.listing_addresses%rowtype;
  resolved_main_image text;
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
  if char_length(coalesce(listing_row.description, '')) > 2000 then
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
  if not listing_row.defects_reviewed then
    raise exception using errcode = '23514', message = 'defects_review_required';
  end if;
  if listing_row.has_defects
     and btrim(coalesce(listing_row.defects_description, '')) = '' then
    raise exception using
      errcode = '23514', message = 'defects_description_required';
  end if;
  if cardinality(coalesce(listing_row.delivery_methods, '{}'::text[])) < 1
     or exists (
       select 1
       from unnest(listing_row.delivery_methods) method
       where method not in (
         'cdek','yandex_delivery','russian_post','meetup'
       )
     ) then
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

  if listing_row.shipping_address_id is null then
    raise exception using errcode = '23514', message = 'shipping_address_required';
  end if;
  select * into address_row
  from public.listing_addresses a
  where a.id = listing_row.shipping_address_id
    and a.user_id = auth.uid();
  if not found
     or btrim(address_row.city) = ''
     or btrim(address_row.address) = '' then
    raise exception using errcode = '23514', message = 'shipping_address_required';
  end if;

  perform set_config('clothes.publish_listing', 'allowed', true);
  update public.products
  set status = 'published',
      main_image = resolved_main_image,
      original_image = coalesce(
        nullif(btrim(original_image), ''), resolved_main_image
      ),
      image = coalesce(nullif(btrim(image), ''), resolved_main_image),
      normalized_brand = coalesce(
        nullif(normalized_brand, ''), public.normalize_product_brand(brand)
      ),
      city = address_row.city,
      shipping_address = address_row.address,
      is_hidden = false,
      defects_description = case
        when has_defects then defects_description else ''
      end,
      published_at = coalesce(published_at, now()),
      enrichment_status = 'enrichment_pending',
      enrichment_completed_at = null,
      last_autosaved_at = now()
  where id = p_listing_id
  returning * into listing_row;

  insert into public.product_images (product_id, original_url, role, position)
  select p_listing_id, image_url,
    case when image_url = resolved_main_image then 'main' else 'gallery' end,
    ordinality::integer - 1
  from unnest(listing_row.images)
    with ordinality as image_rows(image_url, ordinality)
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
