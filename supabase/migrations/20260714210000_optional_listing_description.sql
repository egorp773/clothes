-- Description is optional in the seller flow. Keep the existing publication
-- transaction and validations intact, changing only the obsolete non-empty
-- requirement. This is additive and does not rewrite existing products.
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
