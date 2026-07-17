-- Decouple public view counters from clearable recently-viewed history and
-- make checkout server-authoritative. A view is one authenticated, non-owner
-- viewer opening the detail screen; deleting history never changes counters.

create table if not exists public.product_views (
  product_id uuid not null references public.products(id) on delete cascade,
  viewer_id uuid not null,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  primary key (product_id, viewer_id)
);

create table if not exists public.outfit_views (
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  viewer_id uuid not null,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  primary key (outfit_id, viewer_id)
);

create index if not exists product_views_viewer_idx
  on public.product_views (viewer_id, last_viewed_at desc);
create index if not exists outfit_views_viewer_idx
  on public.outfit_views (viewer_id, last_viewed_at desc);

alter table public.product_views enable row level security;
alter table public.outfit_views enable row level security;

-- View events are written only through the validating functions below.
revoke all on table public.product_views from anon, authenticated;
revoke all on table public.outfit_views from anon, authenticated;

-- Preserve already counted unique history while moving it into the durable
-- analytics tables. Ignore legacy/local ids and owner self-views.
insert into public.product_views (
  product_id,
  viewer_id,
  first_viewed_at,
  last_viewed_at
)
select
  product.id,
  recent.user_id,
  recent.viewed_at,
  recent.viewed_at
from public.recent_products recent
join public.products product on product.id::text = recent.product_id
where product.seller_id is distinct from recent.user_id
on conflict (product_id, viewer_id) do update
set last_viewed_at = greatest(
  public.product_views.last_viewed_at,
  excluded.last_viewed_at
);

insert into public.outfit_views (
  outfit_id,
  viewer_id,
  first_viewed_at,
  last_viewed_at
)
select
  outfit.id,
  recent.user_id,
  recent.viewed_at,
  recent.viewed_at
from public.recent_outfits recent
join public.outfits outfit on outfit.id = recent.outfit_id
where outfit.owner_id is distinct from recent.user_id
on conflict (outfit_id, viewer_id) do update
set last_viewed_at = greatest(
  public.outfit_views.last_viewed_at,
  excluded.last_viewed_at
);

-- The legacy triggers incorrectly treated clearable history as analytics.
drop trigger if exists sync_product_views_count_change
  on public.recent_products;
drop trigger if exists sync_outfit_views_count_insert
  on public.recent_outfits;
drop trigger if exists sync_outfit_views_count_delete
  on public.recent_outfits;

-- Rebuild counters from durable unique events. Keeping the previous maximum
-- would preserve the old scroll/history-trigger inflation forever.
update public.products product
set views_count = (
  select count(*)::integer
  from public.product_views view_event
  where view_event.product_id = product.id
);

update public.outfits outfit
set views_count = (
  select count(*)::integer
  from public.outfit_views view_event
  where view_event.outfit_id = outfit.id
);

create or replace function public.record_product_view(p_product_id uuid)
returns table(views_count integer, first_view boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_viewer_id uuid := auth.uid();
  listing_owner_id uuid;
  authoritative_count integer := 0;
  is_first_view boolean := false;
begin
  if current_viewer_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select seller_id, greatest(coalesce(products.views_count, 0), 0)
    into listing_owner_id, authoritative_count
  from public.products
  where id = p_product_id and not coalesce(is_hidden, false);

  if not found then
    raise exception 'product_not_found' using errcode = 'P0002';
  end if;

  insert into public.recent_products (user_id, product_id, viewed_at)
  values (current_viewer_id, p_product_id::text, now())
  on conflict (user_id, product_id) do update
  set viewed_at = excluded.viewed_at;

  if listing_owner_id is not null and listing_owner_id = current_viewer_id then
    return query select authoritative_count, false;
    return;
  end if;

  with inserted as (
    insert into public.product_views (product_id, viewer_id)
    values (p_product_id, current_viewer_id)
    on conflict (product_id, viewer_id) do nothing
    returning 1
  )
  select exists(select 1 from inserted) into is_first_view;

  if is_first_view then
    update public.products
    set views_count = greatest(coalesce(products.views_count, 0), 0) + 1
    where id = p_product_id
    returning products.views_count into authoritative_count;
  else
    update public.product_views
    set last_viewed_at = now()
    where product_id = p_product_id
      and viewer_id = current_viewer_id;
    select greatest(coalesce(products.views_count, 0), 0)
      into authoritative_count
    from public.products
    where id = p_product_id;
  end if;

  return query select authoritative_count, is_first_view;
end;
$$;

create or replace function public.record_outfit_view(p_outfit_id uuid)
returns table(views_count integer, first_view boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  current_viewer_id uuid := auth.uid();
  outfit_owner_id uuid;
  authoritative_count integer := 0;
  is_first_view boolean := false;
begin
  if current_viewer_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select owner_id, greatest(coalesce(outfits.views_count, 0), 0)
    into outfit_owner_id, authoritative_count
  from public.outfits
  where id = p_outfit_id;

  if not found then
    raise exception 'outfit_not_found' using errcode = 'P0002';
  end if;

  insert into public.recent_outfits (user_id, outfit_id, viewed_at)
  values (current_viewer_id, p_outfit_id, now())
  on conflict (user_id, outfit_id) do update
  set viewed_at = excluded.viewed_at;

  if outfit_owner_id is not null and outfit_owner_id = current_viewer_id then
    return query select authoritative_count, false;
    return;
  end if;

  with inserted as (
    insert into public.outfit_views (outfit_id, viewer_id)
    values (p_outfit_id, current_viewer_id)
    on conflict (outfit_id, viewer_id) do nothing
    returning 1
  )
  select exists(select 1 from inserted) into is_first_view;

  if is_first_view then
    update public.outfits
    set views_count = greatest(coalesce(outfits.views_count, 0), 0) + 1
    where id = p_outfit_id
    returning outfits.views_count into authoritative_count;
  else
    update public.outfit_views
    set last_viewed_at = now()
    where outfit_id = p_outfit_id
      and viewer_id = current_viewer_id;
    select greatest(coalesce(outfits.views_count, 0), 0)
      into authoritative_count
    from public.outfits
    where id = p_outfit_id;
  end if;

  return query select authoritative_count, is_first_view;
end;
$$;

revoke all on function public.record_product_view(uuid) from public;
grant execute on function public.record_product_view(uuid) to authenticated;
revoke all on function public.record_outfit_view(uuid) from public;
grant execute on function public.record_outfit_view(uuid) to authenticated;

-- Client-side inserts can spoof price, seller and product snapshots. Checkout
-- now accepts only recipient/method input and resolves the listing server-side.
drop policy if exists "Buyers can create orders" on public.orders;
drop policy if exists "Order participants can update orders" on public.orders;

create or replace function public.create_delivery_order(
  p_product_id uuid,
  p_delivery_service text,
  p_delivery_address text,
  p_recipient_name text,
  p_recipient_phone text,
  p_recipient_email text default ''
)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  buyer_user_id uuid := auth.uid();
  listing public.products%rowtype;
  created_order public.orders%rowtype;
  clean_service text := btrim(coalesce(p_delivery_service, ''));
  clean_address text := btrim(coalesce(p_delivery_address, ''));
  clean_name text := btrim(coalesce(p_recipient_name, ''));
  clean_phone text := btrim(coalesce(p_recipient_phone, ''));
  resolved_delivery_price integer;
  resolved_image text;
begin
  if buyer_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select * into listing
  from public.products
  where id = p_product_id
    and status = 'published'
    and not coalesce(is_hidden, false)
  for update;

  if not found then
    raise exception 'product_unavailable' using errcode = 'P0002';
  end if;
  if listing.seller_id is null then
    raise exception 'listing_seller_required' using errcode = '23514';
  end if;
  if listing.seller_id = buyer_user_id then
    raise exception 'cannot_buy_own_listing' using errcode = '23514';
  end if;
  if clean_name = '' then
    raise exception 'recipient_name_required' using errcode = '23514';
  end if;
  if clean_phone = '' then
    raise exception 'recipient_phone_required' using errcode = '23514';
  end if;
  if clean_address = '' then
    raise exception 'delivery_destination_required' using errcode = '23514';
  end if;

  resolved_delivery_price := case clean_service
    when 'Почта России' then 122
    when 'Пункт выдачи' then 0
    else null
  end;
  if resolved_delivery_price is null then
    raise exception 'unsupported_delivery_service' using errcode = '23514';
  end if;

  resolved_image := coalesce(
    nullif(btrim(listing.main_image), ''),
    nullif(btrim(listing.image), ''),
    nullif(btrim(listing.original_image), ''),
    listing.images[1],
    ''
  );

  insert into public.orders (
    id,
    product_id,
    product_title,
    product_image,
    product_price,
    product_price_value,
    seller_id,
    buyer_id,
    tracking_number,
    delivery_service,
    delivery_address,
    recipient_name,
    recipient_phone,
    recipient_email,
    delivery_price,
    status,
    created_at,
    updated_at
  ) values (
    'order_' || gen_random_uuid()::text,
    listing.id::text,
    listing.title,
    resolved_image,
    listing.price::text,
    greatest(coalesce(listing.price, 0), 0),
    listing.seller_id,
    buyer_user_id,
    '',
    clean_service,
    clean_address,
    clean_name,
    clean_phone,
    btrim(coalesce(p_recipient_email, '')),
    resolved_delivery_price,
    'pendingConfirmation',
    now(),
    now()
  )
  returning * into created_order;

  return created_order;
end;
$$;

revoke all on function public.create_delivery_order(
  uuid, text, text, text, text, text
) from public;
grant execute on function public.create_delivery_order(
  uuid, text, text, text, text, text
) to authenticated;

-- Keep the legacy helper in migration history for installations that already
-- referenced it, but never expose it to a mobile client. Account deletion must
-- go through the authenticated Edge Function so owned Storage/UGC is removed
-- before the Auth row and its cascading foreign keys.
create or replace function public.delete_current_user()
returns void
language sql
security definer
set search_path = public, auth
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_current_user()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
