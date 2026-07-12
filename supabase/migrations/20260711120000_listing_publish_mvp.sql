-- Automated listing publication MVP.
-- This migration keeps legacy products published by default while allowing
-- the new flow to create explicit draft rows.

create table if not exists public.listing_addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null default '',
  city text not null default '',
  address text not null default '',
  postal_code text not null default '',
  comment text not null default '',
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists listing_addresses_one_default_per_user_idx
  on public.listing_addresses (user_id)
  where is_default;

create index if not exists listing_addresses_user_updated_idx
  on public.listing_addresses (user_id, updated_at desc);

create table if not exists public.listing_publish_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  default_address_id uuid references public.listing_addresses(id) on delete set null,
  delivery_methods text[] not null default array[
    'cdek',
    'yandex_delivery',
    'russian_post'
  ]::text[],
  allow_personal_meeting boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.products
  add column if not exists status text,
  add column if not exists section text,
  add column if not exists subcategory text,
  add column if not exists item_type text,
  add column if not exists gender text,
  add column if not exists primary_color text,
  add column if not exists secondary_colors text[],
  add column if not exists material text,
  add column if not exists pattern text,
  add column if not exists season text,
  add column if not exists style text,
  add column if not exists city text,
  add column if not exists shipping_address_id uuid references public.listing_addresses(id) on delete set null,
  add column if not exists delivery_methods text[],
  -- Some production deployments predate the legacy ``image`` mirror while
  -- this migration still normalizes from it. Keep it nullable for backward
  -- compatibility instead of failing before the draft schema is created.
  add column if not exists image text,
  add column if not exists main_image text,
  add column if not exists published_at timestamptz,
  add column if not exists analysis_status text,
  add column if not exists analysis_completed_at timestamptz,
  add column if not exists draft_step text,
  add column if not exists last_autosaved_at timestamptz;

-- Existing rows predate drafts and are therefore treated as already published.
update public.products
set status = 'published'
where status is null;

update public.products
set analysis_status = case
  when status = 'published' then 'completed'
  else 'pending'
end
where analysis_status is null;

update public.products
set secondary_colors = '{}'
where secondary_colors is null;

update public.products
set delivery_methods = '{}'
where delivery_methods is null;

update public.products
set draft_step = 'photos'
where draft_step is null;

update public.products
set main_image = coalesce(
  nullif(btrim(original_image), ''),
  nullif(btrim(image), ''),
  images[1]
)
where main_image is null or btrim(main_image) = '';

update public.products
set primary_color = nullif(btrim(color), '')
where primary_color is null;

update public.products
set city = nullif(btrim(location), '')
where city is null;

update public.products
set published_at = coalesce(created_at, now())
where status = 'published' and published_at is null;

alter table public.products
  alter column status set default 'published',
  alter column status set not null,
  alter column analysis_status set default 'pending',
  alter column analysis_status set not null,
  alter column secondary_colors set default '{}',
  alter column secondary_colors set not null,
  alter column delivery_methods set default '{}',
  alter column delivery_methods set not null,
  alter column draft_step set default 'photos',
  alter column draft_step set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_status_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_status_check
      check (status in ('draft', 'processing', 'ready', 'published', 'archived', 'sold'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_analysis_status_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_analysis_status_check
      check (analysis_status in ('pending', 'processing', 'completed', 'failed'));
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_draft_step_check'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_draft_step_check
      check (draft_step in ('photos', 'basics', 'attributes', 'delivery', 'preview', 'success'));
  end if;
end;
$$;

create index if not exists products_status_created_idx
  on public.products (status, created_at desc);

create index if not exists products_seller_status_updated_idx
  on public.products (seller_id, status, updated_at desc);

create table if not exists public.listing_analysis (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.products(id) on delete cascade,
  field_name text not null check (btrim(field_name) <> ''),
  predicted_value jsonb,
  confirmed_value jsonb,
  confidence double precision check (
    confidence is null or (confidence >= 0 and confidence <= 1)
  ),
  source text not null default 'unknown',
  was_edited boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (listing_id, field_name)
);

create index if not exists listing_analysis_listing_idx
  on public.listing_analysis (listing_id);

create or replace function public.touch_listing_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_products_updated_at on public.products;
create trigger touch_products_updated_at
before update on public.products
for each row execute function public.touch_listing_updated_at();

drop trigger if exists touch_listing_analysis_updated_at on public.listing_analysis;
create trigger touch_listing_analysis_updated_at
before update on public.listing_analysis
for each row execute function public.touch_listing_updated_at();

drop trigger if exists touch_listing_addresses_updated_at on public.listing_addresses;
create trigger touch_listing_addresses_updated_at
before update on public.listing_addresses
for each row execute function public.touch_listing_updated_at();

drop trigger if exists touch_listing_publish_preferences_updated_at
  on public.listing_publish_preferences;
create trigger touch_listing_publish_preferences_updated_at
before update on public.listing_publish_preferences
for each row execute function public.touch_listing_updated_at();

create or replace function public.validate_listing_address_ownership()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.shipping_address_id is not null and not exists (
    select 1
    from public.listing_addresses a
    where a.id = new.shipping_address_id
      and a.user_id = new.seller_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'shipping_address_not_owned';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_product_shipping_address on public.products;
create trigger validate_product_shipping_address
before insert or update of shipping_address_id, seller_id on public.products
for each row execute function public.validate_listing_address_ownership();

create or replace function public.validate_publish_preference_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.default_address_id is not null and not exists (
    select 1
    from public.listing_addresses a
    where a.id = new.default_address_id
      and a.user_id = new.user_id
  ) then
    raise exception using
      errcode = '23514',
      message = 'default_address_not_owned';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_listing_publish_preference_address
  on public.listing_publish_preferences;
create trigger validate_listing_publish_preference_address
before insert or update of default_address_id, user_id
on public.listing_publish_preferences
for each row execute function public.validate_publish_preference_address();

alter table public.products enable row level security;
alter table public.listing_analysis enable row level security;
alter table public.listing_addresses enable row level security;
alter table public.listing_publish_preferences enable row level security;

-- Replace unknown legacy product policies so draft rows can never become public.
do $$
declare
  policy_record record;
begin
  for policy_record in
    select policyname
    from pg_policies
    where schemaname = 'public' and tablename = 'products'
  loop
    execute format(
      'drop policy if exists %I on public.products',
      policy_record.policyname
    );
  end loop;
end;
$$;

create policy "Published products are readable"
  on public.products for select
  using (status = 'published' or auth.uid() = seller_id);

create policy "Authenticated users can create own products"
  on public.products for insert
  to authenticated
  with check (auth.uid() = seller_id);

create policy "Owners can update products"
  on public.products for update
  to authenticated
  using (auth.uid() = seller_id)
  with check (auth.uid() = seller_id);

create policy "Owners can delete products"
  on public.products for delete
  to authenticated
  using (auth.uid() = seller_id);

drop policy if exists "Owners can manage listing analysis"
  on public.listing_analysis;
create policy "Owners can manage listing analysis"
  on public.listing_analysis for all
  to authenticated
  using (
    exists (
      select 1
      from public.products p
      where p.id = listing_id and p.seller_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1
      from public.products p
      where p.id = listing_id and p.seller_id = auth.uid()
    )
  );

drop policy if exists "Users can manage own listing addresses"
  on public.listing_addresses;
create policy "Users can manage own listing addresses"
  on public.listing_addresses for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can manage own listing publish preferences"
  on public.listing_publish_preferences;
create policy "Users can manage own listing publish preferences"
  on public.listing_publish_preferences for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Keep legacy folders working, but prevent their broad policies from matching
-- the new owner-scoped users/<uid>/listings/... namespace.
drop policy if exists "Authenticated users can upload product images"
  on storage.objects;
create policy "Authenticated users can upload product images"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] is distinct from 'users'
  );

drop policy if exists "Authenticated users can update product images"
  on storage.objects;
create policy "Authenticated users can update product images"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] is distinct from 'users'
  )
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] is distinct from 'users'
  );

drop policy if exists "Owners can upload listing images"
  on storage.objects;
create policy "Owners can upload listing images"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'listings'
  );

drop policy if exists "Owners can update listing images"
  on storage.objects;
create policy "Owners can update listing images"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'listings'
  )
  with check (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'listings'
  );

drop policy if exists "Owners can delete listing images"
  on storage.objects;
create policy "Owners can delete listing images"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'product-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'listings'
  );

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

  select *
  into listing_row
  from public.products
  where id = p_listing_id and seller_id = auth.uid()
  for update;

  if not found then
    raise exception using errcode = 'P0002', message = 'listing_not_found';
  end if;

  -- A repeated request returns the same row instead of creating a duplicate.
  if listing_row.status = 'published' then
    return listing_row;
  end if;

  if listing_row.status not in ('draft', 'processing', 'ready') then
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
    raise exception using errcode = '23514', message = 'description_too_long';
  end if;

  if btrim(coalesce(listing_row.size, '')) = '' then
    raise exception using errcode = '23514', message = 'size_required';
  end if;

  if btrim(coalesce(listing_row.condition, '')) = '' then
    raise exception using errcode = '23514', message = 'condition_required';
  end if;

  if btrim(coalesce(listing_row.category, '')) = '' then
    raise exception using errcode = '23514', message = 'category_required';
  end if;

  if btrim(coalesce(listing_row.section, '')) = '' then
    raise exception using errcode = '23514', message = 'section_required';
  end if;

  if btrim(coalesce(listing_row.subcategory, '')) = '' then
    raise exception using errcode = '23514', message = 'subcategory_required';
  end if;

  if btrim(coalesce(listing_row.item_type, '')) = '' then
    raise exception using errcode = '23514', message = 'item_type_required';
  end if;

  if btrim(coalesce(listing_row.gender, '')) = '' then
    raise exception using errcode = '23514', message = 'gender_required';
  end if;

  if btrim(coalesce(listing_row.primary_color, '')) = '' then
    raise exception using errcode = '23514', message = 'primary_color_required';
  end if;

  if btrim(coalesce(listing_row.brand, '')) = '' then
    raise exception using errcode = '23514', message = 'brand_required';
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
    select 1
    from unnest(listing_row.images) image_url
    where btrim(image_url) = '' or image_url !~* '^https?://'
  ) then
    raise exception using errcode = '23514', message = 'photo_not_uploaded';
  end if;

  resolved_main_image := coalesce(
    nullif(btrim(listing_row.main_image), ''),
    listing_row.images[1]
  );

  if not (resolved_main_image = any(listing_row.images)) then
    raise exception using errcode = '23514', message = 'main_photo_invalid';
  end if;

  resolved_address_id := listing_row.shipping_address_id;
  if resolved_address_id is null then
    select a.id
    into resolved_address_id
    from public.listing_addresses a
    where a.user_id = auth.uid()
    order by a.is_default desc, a.updated_at desc
    limit 1;
  end if;

  if resolved_address_id is null then
    raise exception using errcode = '23514', message = 'shipping_address_required';
  end if;

  if not exists (
    select 1
    from public.listing_addresses a
    where a.id = resolved_address_id
      and a.user_id = auth.uid()
  ) then
    raise exception using errcode = '23514', message = 'shipping_address_not_owned';
  end if;

  update public.products
  set status = 'published',
      main_image = resolved_main_image,
      original_image = coalesce(
        nullif(btrim(original_image), ''),
        resolved_main_image
      ),
      image = coalesce(nullif(btrim(image), ''), resolved_main_image),
      shipping_address_id = resolved_address_id,
      is_hidden = false,
      published_at = coalesce(published_at, now()),
      last_autosaved_at = now()
  where id = p_listing_id
  returning * into listing_row;

  return listing_row;
end;
$$;

revoke all on function public.publish_listing(uuid) from public;
revoke all on function public.publish_listing(uuid) from anon;
grant execute on function public.publish_listing(uuid) to authenticated;

notify pgrst, 'reload schema';
