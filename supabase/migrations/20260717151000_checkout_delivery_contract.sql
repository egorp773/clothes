-- Provider-neutral checkout request contract.
-- This migration deliberately does not enable live payments, provider quotes
-- or shipment creation. It makes order creation authoritative/idempotent and
-- keeps those external capabilities behind public feature flags.

alter table public.delivery_profiles
  add column if not exists pickup_provider text not null default '',
  add column if not exists pickup_point_id text not null default '',
  add column if not exists pickup_point_name text not null default '',
  add column if not exists pickup_point_address text not null default '';

alter table public.orders
  add column if not exists checkout_idempotency_key uuid,
  add column if not exists delivery_type text not null default 'address',
  add column if not exists delivery_provider text not null default 'unassigned',
  add column if not exists pickup_point_id text not null default '',
  add column if not exists pickup_point_name text not null default '',
  add column if not exists pickup_point_address text not null default '',
  add column if not exists currency text not null default 'RUB',
  add column if not exists subtotal_value integer not null default 0,
  add column if not exists total_value integer not null default 0,
  add column if not exists payment_status text not null default 'not_started';

create unique index if not exists orders_buyer_checkout_idempotency_idx
  on public.orders (buyer_id, checkout_idempotency_key)
  where checkout_idempotency_key is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_delivery_type_check'
  ) then
    alter table public.orders add constraint orders_delivery_type_check
      check (delivery_type in ('address', 'pickup_point')) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_delivery_provider_check'
  ) then
    alter table public.orders add constraint orders_delivery_provider_check
      check (delivery_provider in (
        'unassigned', 'cdek', 'russian_post', 'yandex_delivery'
      )) not valid;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.orders'::regclass
      and conname = 'orders_payment_status_check'
  ) then
    alter table public.orders add constraint orders_payment_status_check
      check (payment_status in (
        'not_started', 'pending', 'authorized', 'captured', 'canceled',
        'refunding', 'refunded', 'failed'
      )) not valid;
  end if;
end
$$;

-- Cached provider points are written only by trusted adapters. A selected
-- point is copied into an order so future provider catalog changes cannot
-- rewrite an already confirmed destination.
create table if not exists public.delivery_pickup_points (
  provider text not null check (provider in (
    'cdek', 'russian_post', 'yandex_delivery'
  )),
  external_id text not null check (btrim(external_id) <> ''),
  city text not null default '',
  name text not null default '',
  address text not null,
  latitude double precision,
  longitude double precision,
  services jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  refreshed_at timestamptz not null default now(),
  expires_at timestamptz,
  primary key (provider, external_id)
);

alter table public.delivery_pickup_points enable row level security;
revoke insert, update, delete on public.delivery_pickup_points
  from anon, authenticated;
drop policy if exists "Authenticated users can read active pickup points"
  on public.delivery_pickup_points;
create policy "Authenticated users can read active pickup points"
  on public.delivery_pickup_points for select to authenticated
  using (
    is_active
    and (expires_at is null or expires_at > now())
  );

-- A quote is immutable input to checkout. Provider adapters create quotes;
-- the mobile client can only read its own quote and pass its id later.
create table if not exists public.delivery_quotes (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  provider text not null check (provider in (
    'cdek', 'russian_post', 'yandex_delivery'
  )),
  delivery_type text not null check (delivery_type in (
    'address', 'pickup_point'
  )),
  pickup_point_id text not null default '',
  amount integer not null check (amount >= 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  provider_quote_id text not null default '',
  request_hash text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create unique index if not exists delivery_quotes_provider_id_idx
  on public.delivery_quotes (provider, provider_quote_id)
  where provider_quote_id <> '';

alter table public.delivery_quotes enable row level security;
revoke insert, update, delete on public.delivery_quotes from anon, authenticated;
drop policy if exists "Buyers can read own delivery quotes"
  on public.delivery_quotes;
create policy "Buyers can read own delivery quotes"
  on public.delivery_quotes for select to authenticated
  using (auth.uid() = buyer_id);

-- Early production installations created orders.id as uuid, while the
-- durable order workflow and the mobile contract use opaque text ids.
-- Normalize the legacy column before adding order foreign keys so this
-- migration is safe for both existing projects and clean installations.
do $$
declare
  legacy_reference record;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'orders'
      and column_name = 'id'
      and data_type <> 'text'
  ) then
    if exists (
      select 1
      from pg_constraint constraint_info
      join pg_attribute parent_column
        on parent_column.attrelid = constraint_info.confrelid
       and parent_column.attnum = any (constraint_info.confkey)
      where constraint_info.contype = 'f'
        and constraint_info.confrelid = 'public.orders'::regclass
        and parent_column.attname = 'id'
        and array_length(constraint_info.conkey, 1) <> 1
    ) then
      raise exception 'orders_id_composite_foreign_key_requires_manual_migration';
    end if;

    create temporary table checkout_order_fk_restore (
      child_schema text not null,
      child_table text not null,
      constraint_name text not null,
      child_column text not null,
      constraint_definition text not null
    ) on commit drop;

    insert into checkout_order_fk_restore (
      child_schema,
      child_table,
      constraint_name,
      child_column,
      constraint_definition
    )
    select
      child_namespace.nspname,
      child_table.relname,
      constraint_info.conname,
      child_column.attname,
      pg_get_constraintdef(constraint_info.oid, true)
    from pg_constraint constraint_info
    join pg_class child_table
      on child_table.oid = constraint_info.conrelid
    join pg_namespace child_namespace
      on child_namespace.oid = child_table.relnamespace
    join pg_attribute parent_column
      on parent_column.attrelid = constraint_info.confrelid
     and parent_column.attnum = constraint_info.confkey[1]
    join pg_attribute child_column
      on child_column.attrelid = constraint_info.conrelid
     and child_column.attnum = constraint_info.conkey[1]
    where constraint_info.contype = 'f'
      and constraint_info.confrelid = 'public.orders'::regclass
      and parent_column.attname = 'id';

    for legacy_reference in
      select * from checkout_order_fk_restore
    loop
      execute format(
        'alter table %I.%I drop constraint %I',
        legacy_reference.child_schema,
        legacy_reference.child_table,
        legacy_reference.constraint_name
      );
      execute format(
        'alter table %I.%I alter column %I type text using %I::text',
        legacy_reference.child_schema,
        legacy_reference.child_table,
        legacy_reference.child_column,
        legacy_reference.child_column
      );
    end loop;

    alter table public.orders
      alter column id type text using id::text;

    for legacy_reference in
      select * from checkout_order_fk_restore
    loop
      execute format(
        'alter table %I.%I add constraint %I %s',
        legacy_reference.child_schema,
        legacy_reference.child_table,
        legacy_reference.constraint_name,
        legacy_reference.constraint_definition
      );
    end loop;
  end if;
end;
$$;

create table if not exists public.inventory_reservations (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  order_id text not null references public.orders(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active'
    check (status in ('active', 'released', 'converted')),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (order_id)
);

create unique index if not exists inventory_one_active_reservation_idx
  on public.inventory_reservations (product_id)
  where status = 'active';

alter table public.inventory_reservations enable row level security;
revoke all on public.inventory_reservations from anon, authenticated;

create table if not exists public.order_events (
  id bigint generated always as identity primary key,
  order_id text not null references public.orders(id) on delete cascade,
  event_type text not null check (btrim(event_type) <> ''),
  actor_id uuid references auth.users(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.order_events enable row level security;
revoke insert, update, delete on public.order_events from anon, authenticated;
drop policy if exists "Order participants can read order events"
  on public.order_events;
create policy "Order participants can read order events"
  on public.order_events for select to authenticated
  using (
    exists (
      select 1 from public.orders target_order
      where target_order.id = order_id
        and auth.uid() in (target_order.buyer_id, target_order.seller_id)
    )
  );

insert into public.app_feature_flags (
  key, enabled, is_public, config, reason, rollout_percent
)
values
  (
    'checkout.order_requests_enabled', true, true,
    '{"charges_money":false,"delivery_price_mode":"after_confirmation"}'::jsonb,
    'Creates an order request without payment or a provider shipment', 100
  ),
  (
    'delivery.pickup_points.manual_fallback_enabled', true, true,
    '{"verified":false}'::jsonb,
    'Temporary preference capture until provider point adapters are enabled',
    100
  )
on conflict (key) do update set
  config = excluded.config,
  reason = excluded.reason;

-- No client may directly forge price, seller, status or payment fields.
revoke insert, update, delete on public.orders from anon, authenticated;

create or replace function public.create_order(p_checkout jsonb)
returns public.orders
language plpgsql
security definer
set search_path = public
as $$
declare
  buyer_user_id uuid := auth.uid();
  listing public.products%rowtype;
  selected_point public.delivery_pickup_points%rowtype;
  created_order public.orders%rowtype;
  existing_order public.orders%rowtype;
  product_id_value uuid;
  idempotency_key_value uuid;
  delivery_data jsonb := coalesce(p_checkout -> 'delivery', '{}'::jsonb);
  recipient_data jsonb := coalesce(p_checkout -> 'recipient', '{}'::jsonb);
  address_data jsonb := coalesce(
    p_checkout -> 'delivery' -> 'address', '{}'::jsonb
  );
  pickup_data jsonb := coalesce(
    p_checkout -> 'delivery' -> 'pickup_point', '{}'::jsonb
  );
  delivery_type_value text := btrim(coalesce(delivery_data ->> 'type', ''));
  provider_value text := btrim(coalesce(delivery_data ->> 'provider', ''));
  city_value text := btrim(coalesce(address_data ->> 'city', ''));
  address_value text := btrim(coalesce(address_data ->> 'line1', ''));
  pickup_id_value text := btrim(coalesce(pickup_data ->> 'id', ''));
  pickup_name_value text := btrim(coalesce(pickup_data ->> 'name', ''));
  pickup_address_value text := btrim(coalesce(pickup_data ->> 'address', ''));
  recipient_name_value text := btrim(coalesce(recipient_data ->> 'name', ''));
  recipient_phone_value text := btrim(coalesce(recipient_data ->> 'phone', ''));
  recipient_email_value text := btrim(coalesce(recipient_data ->> 'email', ''));
  destination_value text;
  service_label text;
  resolved_image text;
  subtotal integer;
  expired_reservation record;
  request_enabled boolean;
  manual_pickup_enabled boolean;
  live_enabled boolean;
begin
  if buyer_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select enabled into request_enabled
  from public.app_feature_flags
  where key = 'checkout.order_requests_enabled';
  if not coalesce(request_enabled, false) then
    raise exception 'checkout_temporarily_disabled' using errcode = '55000';
  end if;

  begin
    product_id_value := nullif(btrim(coalesce(p_checkout ->> 'product_id', '')), '')::uuid;
    idempotency_key_value := nullif(
      btrim(coalesce(p_checkout ->> 'idempotency_key', '')), ''
    )::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_checkout_identifier' using errcode = '22023';
  end;
  if product_id_value is null or idempotency_key_value is null then
    raise exception 'invalid_checkout_identifier' using errcode = '22023';
  end if;

  select * into existing_order
  from public.orders
  where buyer_id = buyer_user_id
    and checkout_idempotency_key = idempotency_key_value;
  if found then
    return existing_order;
  end if;

  if delivery_type_value not in ('address', 'pickup_point') then
    raise exception 'unsupported_delivery_service' using errcode = '23514';
  end if;
  if provider_value not in (
    'unassigned', 'cdek', 'russian_post', 'yandex_delivery'
  ) then
    raise exception 'unsupported_delivery_service' using errcode = '23514';
  end if;
  if recipient_name_value = '' then
    raise exception 'recipient_name_required' using errcode = '23514';
  end if;
  if length(regexp_replace(recipient_phone_value, '\D', '', 'g')) < 10 then
    raise exception 'recipient_phone_required' using errcode = '23514';
  end if;
  if recipient_email_value <> '' and recipient_email_value !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'recipient_email_invalid' using errcode = '23514';
  end if;
  if city_value = '' then
    raise exception 'delivery_destination_required' using errcode = '23514';
  end if;
  if delivery_type_value = 'address' and address_value = '' then
    raise exception 'delivery_destination_required' using errcode = '23514';
  end if;
  if delivery_type_value = 'pickup_point'
     and (pickup_id_value = '' or pickup_address_value = '') then
    raise exception 'pickup_point_required' using errcode = '23514';
  end if;

  if delivery_type_value = 'pickup_point' then
    if pickup_id_value like 'manual_%' then
      select enabled into manual_pickup_enabled
      from public.app_feature_flags
      where key = 'delivery.pickup_points.manual_fallback_enabled';
      if not coalesce(manual_pickup_enabled, false) then
        raise exception 'verified_delivery_selection_required'
          using errcode = '55000';
      end if;
    else
      select * into selected_point
      from public.delivery_pickup_points
      where provider = provider_value
        and external_id = pickup_id_value
        and is_active
        and (expires_at is null or expires_at > now());
      if not found then
        raise exception 'verified_delivery_selection_required'
          using errcode = '55000';
      end if;
      pickup_name_value := selected_point.name;
      pickup_address_value := selected_point.address;
      city_value := coalesce(nullif(btrim(selected_point.city), ''), city_value);
    end if;
  end if;

  select * into listing
  from public.products
  where id = product_id_value
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

  -- A simultaneous retry can pass the first lookup before the original
  -- request commits. The listing lock serializes those attempts; check the
  -- key again so both callers receive the same order instead of a temporary
  -- product_unavailable error.
  select * into existing_order
  from public.orders
  where buyer_id = buyer_user_id
    and checkout_idempotency_key = idempotency_key_value;
  if found then
    return existing_order;
  end if;

  if cardinality(coalesce(listing.delivery_methods, '{}'::text[])) > 0 then
    if provider_value = 'unassigned'
       or not (provider_value = any(listing.delivery_methods)) then
      raise exception 'delivery_method_not_offered' using errcode = '23514';
    end if;
  end if;

  select enabled into live_enabled
  from public.app_feature_flags
  where key = 'checkout.live_enabled';
  -- This contract creates a non-monetary order request only. A future
  -- provider migration must replace this guard when quotes, safe-deal
  -- payments, shipments and webhooks are implemented.
  if coalesce(live_enabled, false) then
    raise exception 'live_checkout_not_configured' using errcode = '55000';
  end if;

  for expired_reservation in
    update public.inventory_reservations
    set status = 'released', updated_at = now()
    where product_id = product_id_value
      and status = 'active'
      and expires_at <= now()
    returning order_id
  loop
    update public.orders
    set status = 'canceled'
    where id = expired_reservation.order_id
      and status = 'pendingConfirmation';
    insert into public.order_events (order_id, event_type, payload)
    values (
      expired_reservation.order_id,
      'reservation_expired',
      '{"source":"checkout"}'::jsonb
    );
  end loop;
  if exists (
    select 1 from public.inventory_reservations
    where product_id = product_id_value and status = 'active'
  ) then
    raise exception 'product_unavailable' using errcode = 'P0002';
  end if;

  destination_value := case delivery_type_value
    when 'pickup_point' then concat_ws(', ', city_value, pickup_address_value)
    else concat_ws(', ', city_value, address_value)
  end;
  service_label := case provider_value
    when 'cdek' then 'СДЭК'
    when 'russian_post' then 'Почта России'
    when 'yandex_delivery' then 'Яндекс Доставка'
    else 'служба доставки'
  end;
  service_label := case delivery_type_value
    when 'pickup_point' then 'Пункт выдачи · ' || service_label
    else 'До адреса · ' || service_label
  end;
  resolved_image := coalesce(
    nullif(btrim(listing.main_image), ''),
    nullif(btrim(listing.image), ''),
    nullif(btrim(listing.original_image), ''),
    listing.images[1],
    ''
  );
  subtotal := greatest(coalesce(listing.price, 0), 0);

  insert into public.orders (
    id, product_id, product_title, product_image, product_price,
    product_price_value, seller_id, buyer_id, tracking_number,
    delivery_service, delivery_address, recipient_name, recipient_phone,
    recipient_email, delivery_price, status, checkout_idempotency_key,
    delivery_type, delivery_provider, pickup_point_id, pickup_point_name,
    pickup_point_address, currency, subtotal_value, total_value,
    payment_status, created_at, updated_at
  ) values (
    'order_' || gen_random_uuid()::text,
    listing.id::text,
    listing.title,
    resolved_image,
    listing.price::text,
    subtotal,
    listing.seller_id,
    buyer_user_id,
    '',
    service_label,
    destination_value,
    recipient_name_value,
    recipient_phone_value,
    recipient_email_value,
    0,
    'pendingConfirmation',
    idempotency_key_value,
    delivery_type_value,
    provider_value,
    pickup_id_value,
    pickup_name_value,
    pickup_address_value,
    'RUB',
    subtotal,
    subtotal,
    'not_started',
    now(),
    now()
  ) returning * into created_order;

  insert into public.inventory_reservations (
    product_id, order_id, buyer_id, expires_at
  ) values (
    product_id_value, created_order.id, buyer_user_id, now() + interval '24 hours'
  );

  insert into public.order_events (order_id, event_type, actor_id, payload)
  values (
    created_order.id,
    'order_requested',
    buyer_user_id,
    jsonb_build_object(
      'delivery_type', delivery_type_value,
      'delivery_provider', provider_value,
      'charges_money', false
    )
  );

  return created_order;
exception
  when unique_violation then
    select * into existing_order
    from public.orders
    where buyer_id = buyer_user_id
      and checkout_idempotency_key = idempotency_key_value;
    if found then
      return existing_order;
    end if;
    raise exception 'product_unavailable' using errcode = 'P0002';
end;
$$;

revoke all on function public.create_order(jsonb) from public;
grant execute on function public.create_order(jsonb) to authenticated;

-- The earlier positional RPC cannot carry provider ids, verified pickup
-- points or an idempotency key. Keep it defined for schema compatibility but
-- stop exposing it to mobile clients.
revoke execute on function public.create_delivery_order(
  uuid, text, text, text, text, text
) from authenticated;

notify pgrst, 'reload schema';
