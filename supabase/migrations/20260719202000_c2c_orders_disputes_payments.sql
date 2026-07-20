-- C2C order state machine, dispute workflow and separated money ledgers.
-- Live acquiring and payouts remain fail-closed until an operator configures
-- distinct provider settlement accounts and explicitly enables feature flags.

begin;

-- Normalize the historical status vocabulary before enforcing the only
-- supported graph.
alter table public.orders
  drop constraint if exists orders_status_check;

update public.orders
set status = case lower(coalesce(status, ''))
  when 'pendingconfirmation' then 'created'
  when 'requested' then 'created'
  when 'pending' then 'created'
  when 'created' then 'created'
  when 'paid' then 'paid'
  when 'seller_confirmed' then 'seller_confirmed'
  when 'confirmed' then 'seller_confirmed'
  when 'shipped' then 'shipped'
  when 'delivered' then 'received'
  when 'received' then 'received'
  when 'inspection' then 'inspection'
  when 'completed' then 'completed'
  when 'dispute' then 'dispute'
  when 'canceled' then 'cancelled'
  when 'cancelled' then 'cancelled'
  else 'cancelled'
end;

alter table public.orders
  alter column status set default 'created',
  add column if not exists subtotal_minor bigint not null default 0,
  add column if not exists delivery_minor bigint not null default 0,
  add column if not exists total_minor bigint not null default 0,
  add column if not exists state_version integer not null default 0,
  add column if not exists paid_at timestamptz,
  add column if not exists seller_confirmed_at timestamptz,
  add column if not exists shipped_at timestamptz,
  add column if not exists received_at timestamptz,
  add column if not exists inspection_started_at timestamptz,
  add column if not exists completed_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists dispute_opened_at timestamptz;

update public.orders
set subtotal_minor = greatest(
      coalesce(subtotal_value, 0),
      coalesce(product_price_value, 0),
      0
    )::bigint * 100,
    delivery_minor = greatest(coalesce(delivery_price, 0), 0)::bigint * 100,
    total_minor = (
      greatest(
        coalesce(subtotal_value, 0),
        coalesce(product_price_value, 0),
        0
      )::bigint
      + greatest(coalesce(delivery_price, 0), 0)::bigint
    ) * 100
where subtotal_minor = 0 and total_minor = 0;

update public.orders
set paid_at = case when status in (
      'paid', 'seller_confirmed', 'shipped', 'received', 'inspection',
      'completed', 'dispute'
    ) then coalesce(paid_at, updated_at, created_at) else paid_at end,
    completed_at = case when status = 'completed'
      then coalesce(completed_at, updated_at, created_at)
      else completed_at end,
    cancelled_at = case when status = 'cancelled'
      then coalesce(cancelled_at, updated_at, created_at)
      else cancelled_at end,
    dispute_opened_at = case when status = 'dispute'
      then coalesce(dispute_opened_at, updated_at, created_at)
      else dispute_opened_at end;

alter table public.orders
  add constraint orders_status_check
  check (status in (
    'created',
    'paid',
    'seller_confirmed',
    'shipped',
    'received',
    'inspection',
    'completed',
    'dispute',
    'cancelled'
  )),
  add constraint orders_minor_amounts_check
  check (
    subtotal_minor >= 0
    and delivery_minor >= 0
    and total_minor = subtotal_minor + delivery_minor
  );

alter table public.orders
  drop constraint if exists orders_buyer_id_fkey,
  drop constraint if exists orders_seller_id_fkey;
alter table public.orders
  add constraint orders_buyer_id_fkey
    foreign key (buyer_id) references public.users(id) on delete restrict,
  add constraint orders_seller_id_fkey
    foreign key (seller_id) references public.users(id) on delete restrict;

alter table public.inventory_reservations
  drop constraint if exists inventory_reservations_buyer_id_fkey;
alter table public.inventory_reservations
  add constraint inventory_reservations_buyer_id_fkey
    foreign key (buyer_id) references public.users(id) on delete restrict;

alter table public.order_events
  drop constraint if exists order_events_order_id_fkey,
  drop constraint if exists order_events_actor_id_fkey;
alter table public.order_events
  add constraint order_events_order_id_fkey
    foreign key (order_id) references public.orders(id) on delete restrict,
  add constraint order_events_actor_id_fkey
    foreign key (actor_id) references public.users(id) on delete set null;

create table if not exists public.order_delivery_details (
  order_id text primary key references public.orders(id) on delete restrict,
  recipient_name text not null,
  recipient_phone text not null,
  recipient_email text not null default '',
  delivery_address text not null,
  pickup_point_id text not null default '',
  pickup_point_name text not null default '',
  pickup_point_address text not null default '',
  encrypted_payload jsonb not null default '{}'::jsonb,
  retention_until timestamptz,
  erased_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (erased_at is not null or btrim(recipient_name) <> ''),
  check (erased_at is not null or btrim(recipient_phone) <> '')
);

insert into public.order_delivery_details (
  order_id,
  recipient_name,
  recipient_phone,
  recipient_email,
  delivery_address,
  pickup_point_id,
  pickup_point_name,
  pickup_point_address,
  created_at,
  updated_at
)
select
  marketplace_order.id,
  marketplace_order.recipient_name,
  marketplace_order.recipient_phone,
  marketplace_order.recipient_email,
  marketplace_order.delivery_address,
  marketplace_order.pickup_point_id,
  marketplace_order.pickup_point_name,
  marketplace_order.pickup_point_address,
  marketplace_order.created_at,
  marketplace_order.updated_at
from public.orders marketplace_order
where btrim(marketplace_order.recipient_name) <> ''
  and btrim(marketplace_order.recipient_phone) <> ''
on conflict (order_id) do nothing;

-- PII is no longer duplicated in the broad order row.
update public.orders
set delivery_address = '',
    recipient_name = '',
    recipient_phone = '',
    recipient_email = '',
    pickup_point_id = '',
    pickup_point_name = '',
    pickup_point_address = '';

drop trigger if exists touch_order_delivery_details_updated_at
  on public.order_delivery_details;
create trigger touch_order_delivery_details_updated_at
before update on public.order_delivery_details
for each row execute function public.c2c_touch_updated_at();

alter table public.order_delivery_details enable row level security;
drop policy if exists "Order participants read necessary delivery details"
  on public.order_delivery_details;
create policy "Order participants read necessary delivery details"
  on public.order_delivery_details for select to authenticated
  using (
    exists (
      select 1
      from public.orders marketplace_order
      where marketplace_order.id = order_id
        and (
          marketplace_order.buyer_id = (select auth.uid())
          or (
            marketplace_order.seller_id = (select auth.uid())
            and marketplace_order.status in (
              'seller_confirmed', 'shipped', 'received', 'inspection',
              'completed', 'dispute'
            )
          )
        )
    )
  );
revoke all on public.order_delivery_details from anon, authenticated;
grant select on public.order_delivery_details to authenticated;

create table if not exists public.order_state_transitions (
  id bigint generated always as identity primary key,
  order_id text not null references public.orders(id) on delete restrict,
  from_status text not null,
  to_status text not null,
  actor_id uuid references public.users(id) on delete set null,
  actor_kind text not null check (actor_kind in (
    'buyer', 'seller', 'payment_provider', 'moderator', 'system'
  )),
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (from_status <> to_status),
  check (btrim(reason) <> '')
);

create index if not exists order_state_transitions_order_created_idx
  on public.order_state_transitions (order_id, created_at, id);

create or replace function public.order_transition_is_allowed(
  p_from_status text,
  p_to_status text
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select (p_from_status, p_to_status) in (
    ('created', 'paid'),
    ('created', 'cancelled'),
    ('paid', 'seller_confirmed'),
    ('paid', 'dispute'),
    ('paid', 'cancelled'),
    ('seller_confirmed', 'shipped'),
    ('seller_confirmed', 'dispute'),
    ('seller_confirmed', 'cancelled'),
    ('shipped', 'received'),
    ('shipped', 'dispute'),
    ('received', 'inspection'),
    ('received', 'dispute'),
    ('inspection', 'completed'),
    ('inspection', 'dispute'),
    ('completed', 'dispute'),
    ('dispute', 'completed'),
    ('dispute', 'cancelled')
  );
$$;

revoke all on function public.order_transition_is_allowed(text, text)
  from public;

create or replace function public.protect_order_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status is distinct from old.status
     and coalesce(
       current_setting('clothes.order_transition', true),
       ''
     ) <> 'allowed' then
    raise exception 'order_status_is_server_managed' using errcode = '42501';
  end if;
  if new.payment_status is distinct from old.payment_status
     and coalesce(
       current_setting('clothes.payment_transition', true),
       ''
     ) <> 'allowed' then
    raise exception 'payment_status_is_server_managed' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_order_state_before_update on public.orders;
create trigger protect_order_state_before_update
before update on public.orders
for each row execute function public.protect_order_state();

create or replace function public.prevent_immutable_ledger_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'immutable_ledger' using errcode = '42501';
end;
$$;

drop trigger if exists order_events_are_immutable on public.order_events;
create trigger order_events_are_immutable
before update or delete on public.order_events
for each row execute function public.prevent_immutable_ledger_mutation();

drop trigger if exists order_state_transitions_are_immutable
  on public.order_state_transitions;
create trigger order_state_transitions_are_immutable
before update or delete on public.order_state_transitions
for each row execute function public.prevent_immutable_ledger_mutation();

alter table public.order_state_transitions enable row level security;
drop policy if exists "Order participants read state transitions"
  on public.order_state_transitions;
create policy "Order participants read state transitions"
  on public.order_state_transitions for select to authenticated
  using (
    exists (
      select 1
      from public.orders marketplace_order
      where marketplace_order.id = order_id
        and (select auth.uid()) in (
          marketplace_order.buyer_id,
          marketplace_order.seller_id
        )
    )
  );
revoke all on public.order_state_transitions from anon, authenticated;
grant select on public.order_state_transitions to authenticated;

create or replace function public.apply_order_transition(
  p_order_id text,
  p_target_status text,
  p_actor_id uuid,
  p_actor_kind text,
  p_reason text,
  p_metadata jsonb default '{}'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  marketplace_order public.orders%rowtype;
  prior_status text;
begin
  select * into marketplace_order
  from public.orders target_order
  where target_order.id = p_order_id
  for update;
  if not found then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if not public.order_transition_is_allowed(
    marketplace_order.status,
    p_target_status
  ) then
    raise exception 'order_transition_not_allowed'
      using errcode = '23514',
        detail = marketplace_order.status || ' -> ' || p_target_status;
  end if;
  prior_status := marketplace_order.status;
  if p_actor_kind not in (
    'buyer', 'seller', 'payment_provider', 'moderator', 'system'
  ) or nullif(btrim(coalesce(p_reason, '')), '') is null
     or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'order_transition_evidence_invalid' using errcode = '22023';
  end if;

  perform set_config('clothes.order_transition', 'allowed', true);
  update public.orders
  set status = p_target_status,
      state_version = state_version + 1,
      paid_at = case
        when p_target_status = 'paid' then now() else paid_at end,
      seller_confirmed_at = case
        when p_target_status = 'seller_confirmed' then now()
        else seller_confirmed_at end,
      shipped_at = case
        when p_target_status = 'shipped' then now() else shipped_at end,
      received_at = case
        when p_target_status = 'received' then now() else received_at end,
      inspection_started_at = case
        when p_target_status = 'inspection' then now()
        else inspection_started_at end,
      completed_at = case
        when p_target_status = 'completed' then now() else completed_at end,
      cancelled_at = case
        when p_target_status = 'cancelled' then now() else cancelled_at end,
      dispute_opened_at = case
        when p_target_status = 'dispute' then now()
        else dispute_opened_at end
  where id = p_order_id
  returning * into marketplace_order;

  insert into public.order_state_transitions (
    order_id,
    from_status,
    to_status,
    actor_id,
    actor_kind,
    reason,
    metadata
  )
  values (
    p_order_id,
    prior_status,
    p_target_status,
    p_actor_id,
    p_actor_kind,
    p_reason,
    p_metadata
  );

  insert into public.order_events (
    order_id,
    event_type,
    actor_id,
    payload
  )
  values (
    p_order_id,
    'status_changed',
    p_actor_id,
    p_metadata || jsonb_build_object(
      'to_status', p_target_status,
      'actor_kind', p_actor_kind,
      'reason', p_reason
    )
  );

  if p_target_status = 'cancelled' then
    update public.inventory_reservations
    set status = 'released',
        updated_at = now()
    where order_id = p_order_id
      and status = 'active';
  elsif p_target_status = 'completed' then
    update public.inventory_reservations
    set status = 'converted',
        updated_at = now()
    where order_id = p_order_id
      and status = 'active';
    update public.products
    set status = 'sold',
        is_hidden = true
    where id::text = marketplace_order.product_id;
    update public.seller_payouts
    set status = 'pending',
        release_not_before = marketplace_order.completed_at
          + interval '48 hours',
        eligible_at = null,
        frozen_reason = '',
        updated_at = now()
    where order_id = p_order_id
      and status in ('pending', 'frozen')
      and not exists (
        select 1
        from public.disputes active_dispute
        where active_dispute.order_id = p_order_id
          and active_dispute.status in ('open', 'under_review')
      );

    -- Crossing a professional-selling threshold after a completed sale must
    -- restrict the seller immediately; publication-time checks alone leave a
    -- gap for already published inventory.
    perform set_config('clothes.risk_evaluation', 'allowed', true);
    perform public.evaluate_seller_risk(
      marketplace_order.seller_id,
      marketplace_order.product_id::uuid
    );
  end if;

  if p_target_status in ('completed', 'dispute', 'cancelled') then
    update public.profiles seller_profile
    set sales_count = (
      select count(*)::integer
      from public.orders completed_order
      where completed_order.seller_id = marketplace_order.seller_id
        and completed_order.status = 'completed'
    )
    where seller_profile.id = marketplace_order.seller_id;
  end if;

  return marketplace_order;
end;
$$;

revoke all on function public.apply_order_transition(
  text, text, uuid, text, text, jsonb
) from public, anon, authenticated;

-- Replace the old checkout implementation. The request contains delivery PII
-- only; price, seller, visibility and all initial state are server-resolved.
create or replace function public.create_order(p_checkout jsonb)
returns public.orders
language plpgsql
security definer
set search_path = ''
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
    p_checkout -> 'delivery' -> 'address',
    '{}'::jsonb
  );
  pickup_data jsonb := coalesce(
    p_checkout -> 'delivery' -> 'pickup_point',
    '{}'::jsonb
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
  resolved_image text;
  subtotal_minor_value bigint;
  request_enabled boolean;
  expired_reservation record;
begin
  if buyer_user_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(buyer_user_id, false) then
    raise exception 'buyer_not_eligible' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_checkout, '{}'::jsonb)) <> 'object'
     or exists (
       select 1
       from jsonb_object_keys(p_checkout) supplied_key
       where supplied_key not in (
         'product_id', 'idempotency_key', 'delivery', 'recipient'
       )
     ) then
    raise exception 'checkout_payload_invalid' using errcode = '22023';
  end if;

  select enabled into request_enabled
  from public.app_feature_flags
  where key = 'checkout.order_requests_enabled';
  if not coalesce(request_enabled, false) then
    raise exception 'checkout_temporarily_disabled' using errcode = '55000';
  end if;

  begin
    product_id_value := nullif(
      btrim(coalesce(p_checkout ->> 'product_id', '')),
      ''
    )::uuid;
    idempotency_key_value := nullif(
      btrim(coalesce(p_checkout ->> 'idempotency_key', '')),
      ''
    )::uuid;
  exception when invalid_text_representation then
    raise exception 'invalid_checkout_identifier' using errcode = '22023';
  end;
  if product_id_value is null or idempotency_key_value is null then
    raise exception 'invalid_checkout_identifier' using errcode = '22023';
  end if;

  select * into existing_order
  from public.orders marketplace_order
  where marketplace_order.buyer_id = buyer_user_id
    and marketplace_order.checkout_idempotency_key = idempotency_key_value;
  if found then
    return existing_order;
  end if;

  if delivery_type_value not in ('address', 'pickup_point')
     or provider_value not in (
       'cdek', 'russian_post', 'yandex_delivery'
     ) then
    raise exception 'unsupported_delivery_service' using errcode = '23514';
  end if;
  if recipient_name_value = ''
     or length(regexp_replace(recipient_phone_value, '\D', '', 'g')) < 10
     or city_value = ''
     or (
       recipient_email_value <> ''
       and recipient_email_value !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'
     ) then
    raise exception 'recipient_details_invalid' using errcode = '23514';
  end if;
  if delivery_type_value = 'address' and address_value = '' then
    raise exception 'delivery_destination_required' using errcode = '23514';
  end if;

  if delivery_type_value = 'pickup_point' then
    select * into selected_point
    from public.delivery_pickup_points point
    where point.provider = provider_value
      and point.external_id = pickup_id_value
      and point.is_active
      and (point.expires_at is null or point.expires_at > now());
    if not found then
      raise exception 'verified_delivery_selection_required'
        using errcode = '55000';
    end if;
    pickup_name_value := selected_point.name;
    pickup_address_value := selected_point.address;
    city_value := coalesce(nullif(btrim(selected_point.city), ''), city_value);
  end if;

  select * into listing
  from public.products product
  where product.id = product_id_value
    and public.listing_is_public(product.id)
  for update;
  if not found then
    raise exception 'product_unavailable' using errcode = 'P0002';
  end if;
  if listing.seller_id = buyer_user_id then
    raise exception 'cannot_buy_own_listing' using errcode = '23514';
  end if;
  if not public.marketplace_user_is_eligible(listing.seller_id, true) then
    raise exception 'seller_not_eligible' using errcode = '42501';
  end if;
  if not (provider_value = any(coalesce(
    listing.delivery_methods,
    '{}'::text[]
  ))) then
    raise exception 'delivery_method_not_offered' using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.inventory_reservations reservation
    where reservation.product_id = product_id_value
      and reservation.status = 'active'
      and reservation.expires_at > now()
  ) then
    raise exception 'product_unavailable' using errcode = 'P0002';
  end if;

  for expired_reservation in
    update public.inventory_reservations
    set status = 'released',
        updated_at = now()
    where product_id = product_id_value
      and status = 'active'
      and expires_at <= now()
    returning order_id
  loop
    if exists (
      select 1
      from public.orders expired_order
      where expired_order.id = expired_reservation.order_id
        and expired_order.status = 'created'
    ) then
      perform public.apply_order_transition(
        expired_reservation.order_id,
        'cancelled',
        null,
        'system',
        'inventory_reservation_expired',
        jsonb_build_object('from_status', 'created')
      );
    end if;
  end loop;

  destination_value := case delivery_type_value
    when 'pickup_point' then concat_ws(', ', city_value, pickup_address_value)
    else concat_ws(', ', city_value, address_value)
  end;
  resolved_image := coalesce(
    nullif(btrim(listing.main_image), ''),
    nullif(btrim(listing.image), ''),
    nullif(btrim(listing.original_image), ''),
    listing.images[1],
    ''
  );
  subtotal_minor_value := round(
    greatest(coalesce(listing.price, 0), 0) * 100
  )::bigint;

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
    checkout_idempotency_key,
    delivery_type,
    delivery_provider,
    pickup_point_id,
    pickup_point_name,
    pickup_point_address,
    currency,
    subtotal_value,
    total_value,
    subtotal_minor,
    delivery_minor,
    total_minor,
    payment_status,
    created_at,
    updated_at
  )
  values (
    'order_' || gen_random_uuid()::text,
    listing.id::text,
    listing.title,
    resolved_image,
    listing.price::text,
    greatest(round(listing.price), 0)::integer,
    listing.seller_id,
    buyer_user_id,
    '',
    provider_value,
    '',
    '',
    '',
    '',
    0,
    'created',
    idempotency_key_value,
    delivery_type_value,
    provider_value,
    '',
    '',
    '',
    'RUB',
    greatest(round(listing.price), 0)::integer,
    greatest(round(listing.price), 0)::integer,
    subtotal_minor_value,
    0,
    subtotal_minor_value,
    'not_started',
    now(),
    now()
  )
  returning * into created_order;

  insert into public.order_delivery_details (
    order_id,
    recipient_name,
    recipient_phone,
    recipient_email,
    delivery_address,
    pickup_point_id,
    pickup_point_name,
    pickup_point_address
  )
  values (
    created_order.id,
    recipient_name_value,
    recipient_phone_value,
    recipient_email_value,
    destination_value,
    pickup_id_value,
    pickup_name_value,
    pickup_address_value
  );

  insert into public.inventory_reservations (
    product_id,
    order_id,
    buyer_id,
    expires_at
  )
  values (
    product_id_value,
    created_order.id,
    buyer_user_id,
    now() + interval '24 hours'
  );

  insert into public.order_events (
    order_id,
    event_type,
    actor_id,
    payload
  )
  values (
    created_order.id,
    'order_created',
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
    from public.orders marketplace_order
    where marketplace_order.buyer_id = buyer_user_id
      and marketplace_order.checkout_idempotency_key = idempotency_key_value;
    if found then
      return existing_order;
    end if;
    raise;
end;
$$;

revoke all on function public.create_order(jsonb) from public, anon;
grant execute on function public.create_order(jsonb) to authenticated;
revoke execute on function public.create_delivery_order(
  uuid, text, text, text, text, text
) from authenticated;

create or replace function public.request_order_transition(
  p_order_id text,
  p_target_status text,
  p_metadata jsonb default '{}'::jsonb
)
returns public.orders
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  marketplace_order public.orders%rowtype;
  actor_kind text;
  reason text;
  transition_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'user_not_eligible' using errcode = '42501';
  end if;
  if jsonb_typeof(transition_metadata) <> 'object'
     or length(transition_metadata::text) > 8000
     or exists (
       select 1
       from jsonb_object_keys(transition_metadata) supplied_key
       where supplied_key <> 'tracking_number'
     )
     or (
       p_target_status <> 'shipped'
       and transition_metadata ? 'tracking_number'
     ) then
    raise exception 'transition_metadata_invalid' using errcode = '22023';
  end if;

  select * into marketplace_order
  from public.orders target_order
  where target_order.id = p_order_id
  for update;
  if not found then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  transition_metadata := transition_metadata
    || jsonb_build_object('from_status', marketplace_order.status);

  if actor_id = marketplace_order.buyer_id
     and marketplace_order.status = 'created'
     and p_target_status = 'cancelled' then
    actor_kind := 'buyer';
    reason := 'buyer_cancelled_before_payment';
  elsif actor_id = marketplace_order.seller_id
     and marketplace_order.status = 'paid'
     and p_target_status = 'seller_confirmed' then
    if not public.marketplace_user_is_eligible(actor_id, true) then
      raise exception 'seller_not_eligible' using errcode = '42501';
    end if;
    actor_kind := 'seller';
    reason := 'seller_confirmed_fulfilment';
  elsif actor_id = marketplace_order.seller_id
     and marketplace_order.status = 'seller_confirmed'
     and p_target_status = 'shipped' then
    if not public.marketplace_user_is_eligible(actor_id, true) then
      raise exception 'seller_not_eligible' using errcode = '42501';
    end if;
    if char_length(btrim(coalesce(
      transition_metadata ->> 'tracking_number',
      ''
    ))) not between 5 and 100
       or btrim(transition_metadata ->> 'tracking_number')
         !~ '^[A-Za-z0-9._ -]{5,100}$' then
      raise exception 'tracking_number_required' using errcode = '23514';
    end if;
    update public.orders
    set tracking_number = btrim(
      transition_metadata ->> 'tracking_number'
    )
    where id = p_order_id;
    actor_kind := 'seller';
    reason := 'seller_handed_to_delivery';
  elsif actor_id = marketplace_order.buyer_id
     and marketplace_order.status = 'shipped'
     and p_target_status = 'received' then
    actor_kind := 'buyer';
    reason := 'buyer_confirmed_receipt';
  elsif actor_id = marketplace_order.buyer_id
     and marketplace_order.status = 'received'
     and p_target_status = 'inspection' then
    actor_kind := 'buyer';
    reason := 'buyer_started_inspection';
  elsif actor_id = marketplace_order.buyer_id
     and marketplace_order.status = 'inspection'
     and p_target_status = 'completed' then
    actor_kind := 'buyer';
    reason := 'buyer_accepted_item';
  else
    raise exception 'transition_not_authorized' using errcode = '42501';
  end if;

  return public.apply_order_transition(
    p_order_id,
    p_target_status,
    actor_id,
    actor_kind,
    reason,
    transition_metadata
  );
end;
$$;

revoke all on function public.request_order_transition(text, text, jsonb)
  from public, anon;
grant execute on function public.request_order_transition(text, text, jsonb)
  to authenticated;

-- Provider configuration is deliberately absent by default. Enabling the
-- flag without verified, distinct settlement references still cannot capture.
create table if not exists public.payment_provider_configurations (
  id uuid primary key default gen_random_uuid(),
  provider text not null unique,
  settlement_mode text not null check (settlement_mode in (
    'provider_split', 'nominal_account'
  )),
  seller_funds_account_ref text not null,
  platform_fee_account_ref text not null,
  is_verified boolean not null default false,
  is_active boolean not null default false,
  verified_by uuid references public.users(id) on delete set null,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(provider) <> ''),
  check (btrim(seller_funds_account_ref) <> ''),
  check (btrim(platform_fee_account_ref) <> ''),
  check (seller_funds_account_ref <> platform_fee_account_ref),
  check (not is_active or (is_verified and verified_at is not null))
);

create table if not exists public.provider_webhook_inbox (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  order_id text not null references public.orders(id) on delete restrict,
  provider_transaction_id text not null,
  event_type text not null,
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  payload jsonb not null,
  status text not null default 'received' check (status in (
    'received', 'processed', 'rejected'
  )),
  processed_at timestamptz,
  rejection_reason text not null default '',
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id)
);

create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references public.orders(id) on delete restrict,
  provider text not null,
  provider_event_id text not null,
  provider_transaction_id text not null,
  event_type text not null,
  status text not null check (status in (
    'pending', 'authorized', 'captured', 'cancelled', 'failed', 'refunded'
  )),
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  seller_funds_minor bigint not null default 0 check (seller_funds_minor >= 0),
  platform_fee_minor bigint not null default 0 check (platform_fee_minor >= 0),
  webhook_id uuid not null
    references public.provider_webhook_inbox(id) on delete restrict,
  created_at timestamptz not null default now(),
  unique (provider, provider_event_id),
  check (seller_funds_minor + platform_fee_minor <= amount_minor)
);

create unique index if not exists payment_one_capture_per_order_idx
  on public.payment_transactions (order_id)
  where status = 'captured';
create unique index if not exists payment_one_refund_per_order_idx
  on public.payment_transactions (order_id)
  where status = 'refunded';

create table if not exists public.seller_payouts (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique references public.orders(id) on delete restrict,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  status text not null default 'pending' check (status in (
    'pending', 'frozen', 'eligible', 'processing', 'paid', 'cancelled',
    'failed'
  )),
  provider_payout_id text not null default '',
  release_not_before timestamptz,
  eligible_at timestamptz,
  paid_at timestamptz,
  frozen_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.platform_fees (
  id uuid primary key default gen_random_uuid(),
  order_id text not null unique references public.orders(id) on delete restrict,
  payment_transaction_id uuid not null
    references public.payment_transactions(id) on delete restrict,
  amount_minor bigint not null check (amount_minor >= 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  status text not null default 'accrued' check (status in (
    'accrued', 'settled', 'reversed'
  )),
  created_at timestamptz not null default now(),
  settled_at timestamptz
);

drop trigger if exists payment_transactions_are_immutable
  on public.payment_transactions;
create trigger payment_transactions_are_immutable
before update or delete on public.payment_transactions
for each row execute function public.prevent_immutable_ledger_mutation();

insert into public.app_feature_flags (
  key,
  enabled,
  is_public,
  config,
  reason,
  rollout_percent
)
values
  (
    'payments.live_enabled',
    false,
    true,
    '{"requires_verified_separate_settlement":true}'::jsonb,
    'Disabled until acquiring, fiscal and split-settlement contracts are ready',
    0
  ),
  (
    'payouts.live_enabled',
    false,
    false,
    '{"manual_release_only":true}'::jsonb,
    'Disabled until provider-side seller settlement is legally configured',
    0
  )
on conflict (key) do update
set enabled = false,
    config = excluded.config,
    reason = excluded.reason,
    rollout_percent = 0;

update public.app_feature_flags
set enabled = false,
    rollout_percent = 0,
    reason = case key
      when 'checkout.live_enabled'
        then 'Disabled by C2C payment hardening until provider readiness review'
      when 'payments.yookassa_safe_deal.enabled'
        then 'Disabled until separate seller settlement is contractually ready'
      else reason
    end,
    updated_at = now()
where key in (
  'checkout.live_enabled',
  'payments.yookassa_safe_deal.enabled'
);

drop function if exists public.record_payment_transition(
  text, text, text, text, integer, text, text, jsonb
);

create or replace function public.record_payment_transition(
  p_provider text,
  p_provider_event_id text,
  p_order_id text,
  p_provider_transaction_id text,
  p_amount_minor bigint,
  p_currency text,
  p_event_type text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  inbox_id uuid;
  existing_inbox public.provider_webhook_inbox%rowtype;
  payment_id uuid;
  marketplace_order public.orders%rowtype;
  seller public.seller_accounts%rowtype;
  transaction_status text;
  fee_bps integer := 0;
  fee_minor bigint := 0;
  seller_minor bigint := 0;
  live_enabled boolean;
  payload_hash_value text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_provider, '')), '') is null
     or nullif(btrim(coalesce(p_provider_event_id, '')), '') is null
     or nullif(btrim(coalesce(p_provider_transaction_id, '')), '') is null
     or char_length(p_provider) > 100
     or char_length(p_provider_event_id) > 500
     or char_length(p_provider_transaction_id) > 500
     or p_amount_minor is null
     or p_amount_minor < 0
     or p_currency is distinct from 'RUB'
     or jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object'
     or length(coalesce(p_payload, '{}'::jsonb)::text) > 262144 then
    raise exception 'payment_event_invalid' using errcode = '22023';
  end if;

  payload_hash_value := encode(
    extensions.digest(
      convert_to(coalesce(p_payload, '{}'::jsonb)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );

  perform pg_advisory_xact_lock(
    hashtextextended(
      'payment-event:' || p_provider || ':' || p_provider_event_id,
      0
    )
  );
  select * into existing_inbox
  from public.provider_webhook_inbox existing
  where existing.provider = p_provider
    and existing.provider_event_id = p_provider_event_id;
  if found then
    if existing_inbox.order_id is distinct from p_order_id
       or existing_inbox.provider_transaction_id
         is distinct from p_provider_transaction_id
       or existing_inbox.event_type is distinct from p_event_type
       or existing_inbox.amount_minor is distinct from p_amount_minor
       or existing_inbox.currency is distinct from p_currency
       or existing_inbox.payload_hash is distinct from payload_hash_value then
      raise exception 'payment_event_replay_mismatch'
        using errcode = '23514';
    end if;
    return jsonb_build_object(
      'webhook_id', existing_inbox.id,
      'duplicate', true,
      'processed', existing_inbox.status = 'processed',
      'status', existing_inbox.status
    );
  end if;

  select * into marketplace_order
  from public.orders target_order
  where target_order.id = p_order_id
  for update;
  if not found then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;

  transaction_status := case p_event_type
    when 'payment_pending' then 'pending'
    when 'payment_authorized' then 'authorized'
    when 'payment_captured' then 'captured'
    when 'payment_cancelled' then 'cancelled'
    when 'payment_failed' then 'failed'
    when 'payment_refunded' then 'refunded'
    else null
  end;
  if transaction_status is null then
    raise exception 'payment_event_type_not_allowed' using errcode = '22023';
  end if;

  if transaction_status = 'pending'
     and (
       marketplace_order.status <> 'created'
       or marketplace_order.payment_status not in (
         'not_started', 'pending'
       )
     ) then
    raise exception 'payment_transition_not_allowed' using errcode = '23514';
  elsif transaction_status = 'authorized'
     and (
       marketplace_order.status <> 'created'
       or marketplace_order.payment_status not in (
         'not_started', 'pending', 'authorized'
       )
     ) then
    raise exception 'payment_transition_not_allowed' using errcode = '23514';
  elsif transaction_status = 'captured'
     and (
       marketplace_order.status <> 'created'
       or marketplace_order.payment_status not in (
         'not_started', 'pending', 'authorized'
       )
     ) then
    raise exception 'payment_transition_not_allowed' using errcode = '23514';
  elsif transaction_status in ('cancelled', 'failed')
     and (
       marketplace_order.status not in ('created', 'cancelled')
       or marketplace_order.payment_status in (
         'captured', 'refunding', 'refunded'
       )
     ) then
    raise exception 'payment_transition_not_allowed' using errcode = '23514';
  elsif transaction_status = 'refunded'
     and (
       marketplace_order.status not in (
         'paid', 'seller_confirmed', 'shipped', 'received', 'inspection',
         'completed', 'dispute', 'cancelled'
       )
       or marketplace_order.payment_status not in ('captured', 'refunding')
       or not exists (
         select 1
         from public.payment_transactions captured_payment
         where captured_payment.order_id = p_order_id
           and captured_payment.provider = p_provider
           and captured_payment.status = 'captured'
       )
     ) then
    raise exception 'payment_transition_not_allowed' using errcode = '23514';
  end if;

  if transaction_status in ('authorized', 'captured', 'refunded') then
    if p_amount_minor <> marketplace_order.total_minor then
      raise exception 'payment_amount_mismatch' using errcode = '23514';
    end if;
  end if;
  if transaction_status in ('authorized', 'captured') then
    select enabled into live_enabled
    from public.app_feature_flags
    where key = 'payments.live_enabled';
    if not coalesce(live_enabled, false)
       or not exists (
         select 1
         from public.payment_provider_configurations configuration
         where configuration.provider = p_provider
           and configuration.is_active
           and configuration.is_verified
           and configuration.seller_funds_account_ref
             <> configuration.platform_fee_account_ref
       ) then
      raise exception 'live_payments_not_configured' using errcode = '55000';
    end if;
  end if;

  insert into public.provider_webhook_inbox (
    provider,
    provider_event_id,
    order_id,
    provider_transaction_id,
    event_type,
    amount_minor,
    currency,
    payload_hash,
    payload
  )
  values (
    p_provider,
    p_provider_event_id,
    p_order_id,
    p_provider_transaction_id,
    p_event_type,
    p_amount_minor,
    p_currency,
    payload_hash_value,
    coalesce(p_payload, '{}'::jsonb)
  )
  returning id into inbox_id;

  fee_bps := greatest(0, least(
    coalesce((
      select (flag.config ->> 'platform_fee_bps')::integer
      from public.app_feature_flags flag
      where flag.key = 'payments.live_enabled'
    ), 0),
    10000
  ));
  fee_minor := case when transaction_status = 'captured'
    then (p_amount_minor * fee_bps) / 10000
    else 0 end;
  seller_minor := case when transaction_status = 'captured'
    then p_amount_minor - fee_minor
    else 0 end;

  insert into public.payment_transactions (
    order_id,
    provider,
    provider_event_id,
    provider_transaction_id,
    event_type,
    status,
    amount_minor,
    currency,
    seller_funds_minor,
    platform_fee_minor,
    webhook_id
  )
  values (
    p_order_id,
    p_provider,
    p_provider_event_id,
    p_provider_transaction_id,
    p_event_type,
    transaction_status,
    p_amount_minor,
    p_currency,
    seller_minor,
    fee_minor,
    inbox_id
  )
  returning id into payment_id;

  perform set_config('clothes.payment_transition', 'allowed', true);
  update public.orders
  set payment_status = case transaction_status
    when 'pending' then 'pending'
    when 'authorized' then 'authorized'
    when 'captured' then 'captured'
    when 'cancelled' then 'canceled'
    when 'failed' then 'failed'
    when 'refunded' then 'refunded'
  end
  where id = p_order_id;

  if transaction_status = 'captured' then
    select * into seller
    from public.seller_accounts account
    where account.user_id = marketplace_order.seller_id;

    insert into public.seller_payouts (
      order_id,
      seller_account_id,
      amount_minor,
      currency,
      status
    )
    values (
      p_order_id,
      seller.id,
      seller_minor,
      p_currency,
      'pending'
    )
    on conflict (order_id) do nothing;

    insert into public.platform_fees (
      order_id,
      payment_transaction_id,
      amount_minor,
      currency
    )
    values (
      p_order_id,
      payment_id,
      fee_minor,
      p_currency
    )
    on conflict (order_id) do nothing;

    if marketplace_order.status = 'created' then
      perform public.apply_order_transition(
        p_order_id,
        'paid',
        null,
        'payment_provider',
        'provider_capture_confirmed',
        jsonb_build_object(
          'from_status', 'created',
          'provider', p_provider,
          'provider_event_id', p_provider_event_id
        )
      );
    end if;
  elsif transaction_status in ('cancelled', 'failed')
        and marketplace_order.status = 'created' then
    perform public.apply_order_transition(
      p_order_id,
      'cancelled',
      null,
      'payment_provider',
      'provider_payment_not_completed',
      jsonb_build_object(
        'from_status', 'created',
        'provider', p_provider,
        'provider_event_id', p_provider_event_id,
        'payment_status', transaction_status
      )
    );
  elsif transaction_status = 'refunded' then
    update public.seller_payouts
    set status = 'cancelled',
        frozen_reason = 'provider_refund_confirmed',
        updated_at = now()
    where order_id = p_order_id
      and status in ('pending', 'frozen', 'eligible', 'processing');
    update public.platform_fees
    set status = 'reversed'
    where order_id = p_order_id
      and status = 'accrued';
  end if;

  update public.provider_webhook_inbox
  set status = 'processed',
      processed_at = now()
  where id = inbox_id;

  return jsonb_build_object(
    'webhook_id', inbox_id,
    'payment_transaction_id', payment_id,
    'duplicate', false,
    'processed', true,
    'payment_status', transaction_status
  );
end;
$$;

revoke all on function public.record_payment_transition(
  text, text, text, text, bigint, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.record_payment_transition(
  text, text, text, text, bigint, text, text, jsonb
) to service_role;

create table if not exists public.disputes (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references public.orders(id) on delete restrict,
  created_by uuid not null references public.users(id) on delete restrict,
  reason text not null check (reason in (
    'not_received',
    'wrong_item',
    'fake',
    'hidden_damage',
    'description_mismatch',
    'other'
  )),
  description text not null,
  evidence jsonb not null default '[]'::jsonb,
  status text not null default 'open' check (status in (
    'open',
    'under_review',
    'resolved_buyer',
    'resolved_seller',
    'rejected',
    'cancelled'
  )),
  moderator_id uuid references public.users(id) on delete set null,
  resolution text not null default '',
  payout_action text not null default 'pending' check (payout_action in (
    'pending', 'refund_buyer', 'release_seller', 'no_action'
  )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (char_length(btrim(description)) between 10 and 4000),
  check (jsonb_typeof(evidence) = 'array')
);

create unique index if not exists disputes_one_active_per_order_idx
  on public.disputes (order_id)
  where status in ('open', 'under_review');

create table if not exists public.dispute_evidence (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete restrict,
  submitted_by uuid references public.users(id) on delete set null,
  evidence_type text not null check (evidence_type in (
    'image', 'video', 'document', 'chat_message', 'tracking', 'text'
  )),
  storage_bucket text,
  storage_path text,
  content_hash text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (
    evidence_type in ('chat_message', 'tracking', 'text')
    or (
      btrim(coalesce(storage_bucket, '')) <> ''
      and btrim(coalesce(storage_path, '')) <> ''
    )
  )
);

drop trigger if exists dispute_evidence_is_immutable
  on public.dispute_evidence;
create trigger dispute_evidence_is_immutable
before update or delete on public.dispute_evidence
for each row execute function public.prevent_immutable_ledger_mutation();

drop trigger if exists touch_disputes_updated_at on public.disputes;
create trigger touch_disputes_updated_at
before update on public.disputes
for each row execute function public.c2c_touch_updated_at();

create or replace function public.protect_seller_payout_release()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  marketplace_order public.orders%rowtype;
begin
  if new.status not in ('eligible', 'processing', 'paid') then
    return new;
  end if;

  select * into marketplace_order
  from public.orders target_order
  where target_order.id = new.order_id;

  if not found
     or marketplace_order.status <> 'completed'
     or marketplace_order.payment_status <> 'captured'
     or marketplace_order.completed_at is null
     or new.release_not_before is null
     or new.release_not_before
       < marketplace_order.completed_at + interval '48 hours'
     or now() < new.release_not_before
     or new.eligible_at is null
     or exists (
       select 1
       from public.disputes active_dispute
       where active_dispute.order_id = new.order_id
         and active_dispute.status in ('open', 'under_review')
     ) then
    raise exception 'seller_payout_release_not_allowed'
      using errcode = '42501';
  end if;

  if not exists (
    select 1
    from public.app_feature_flags flag
    where flag.key = 'payouts.live_enabled'
      and flag.enabled
  ) then
    raise exception 'live_payouts_not_configured' using errcode = '55000';
  end if;

  if new.status = 'paid' and (
    nullif(btrim(new.provider_payout_id), '') is null
    or new.paid_at is null
  ) then
    raise exception 'paid_payout_evidence_required' using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_seller_payout_release_before_write
  on public.seller_payouts;
create trigger protect_seller_payout_release_before_write
before insert or update on public.seller_payouts
for each row execute function public.protect_seller_payout_release();

create or replace function public.promote_due_seller_payouts(
  p_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  promoted_count integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_limit is null or p_limit not between 1 and 500 then
    raise exception 'payout_promotion_limit_invalid' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.app_feature_flags flag
    where flag.key = 'payouts.live_enabled'
      and flag.enabled
  ) then
    raise exception 'live_payouts_not_configured' using errcode = '55000';
  end if;

  with due_payouts as (
    select payout.id
    from public.seller_payouts payout
    join public.orders marketplace_order
      on marketplace_order.id = payout.order_id
    where payout.status = 'pending'
      and payout.release_not_before is not null
      and payout.release_not_before <= now()
      and marketplace_order.status = 'completed'
      and marketplace_order.payment_status = 'captured'
      and marketplace_order.completed_at is not null
      and payout.release_not_before
        >= marketplace_order.completed_at + interval '48 hours'
      and not exists (
        select 1
        from public.disputes active_dispute
        where active_dispute.order_id = payout.order_id
          and active_dispute.status in ('open', 'under_review')
      )
    order by payout.release_not_before, payout.id
    for update of payout skip locked
    limit p_limit
  ), promoted as (
    update public.seller_payouts payout
    set status = 'eligible',
        eligible_at = now(),
        frozen_reason = '',
        updated_at = now()
    from due_payouts due
    where payout.id = due.id
    returning payout.id
  )
  select count(*)::integer into promoted_count from promoted;

  return promoted_count;
end;
$$;

revoke all on function public.promote_due_seller_payouts(integer)
  from public, anon, authenticated;
grant execute on function public.promote_due_seller_payouts(integer)
  to service_role;

create or replace function public.open_dispute(
  p_order_id text,
  p_reason text,
  p_description text,
  p_evidence jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  marketplace_order public.orders%rowtype;
  dispute_id uuid;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_reason not in (
    'not_received', 'wrong_item', 'fake', 'hidden_damage',
    'description_mismatch', 'other'
  ) or char_length(btrim(coalesce(p_description, ''))) not between 10 and 4000
     or jsonb_typeof(coalesce(p_evidence, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_evidence, '[]'::jsonb)) > 20
     or length(coalesce(p_evidence, '[]'::jsonb)::text) > 50000 then
    raise exception 'dispute_payload_invalid' using errcode = '22023';
  end if;

  select * into marketplace_order
  from public.orders target_order
  where target_order.id = p_order_id
  for update;
  if not found
     or actor_id not in (
       marketplace_order.buyer_id,
       marketplace_order.seller_id
  ) then
    raise exception 'order_not_found' using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) item
    where jsonb_typeof(item) <> 'object'
  ) then
    raise exception 'dispute_payload_invalid' using errcode = '22023';
  end if;
  if exists (
    select 1
    from jsonb_array_elements(coalesce(p_evidence, '[]'::jsonb)) item
    where coalesce(item ->> 'type', '') not in (
        'text', 'tracking', 'chat_message'
      )
      or char_length(coalesce(item ->> 'reference', '')) > 500
      or char_length(coalesce(item ->> 'note', '')) > 2000
      or exists (
        select 1
        from jsonb_object_keys(item) supplied_key
        where supplied_key not in ('type', 'reference', 'note')
      )
      or (
        item ->> 'type' = 'chat_message'
        and not exists (
          select 1
          from public.chat_messages message
          join public.message_threads thread on thread.id = message.thread_id
          where message.id = item ->> 'reference'
            and actor_id = any(thread.member_ids)
        )
      )
  ) then
    raise exception 'dispute_payload_invalid' using errcode = '22023';
  end if;
  if marketplace_order.status not in (
    'paid', 'seller_confirmed', 'shipped', 'received', 'inspection',
    'completed'
  ) or (
    marketplace_order.status = 'completed'
    and coalesce(
      marketplace_order.completed_at,
      marketplace_order.updated_at,
      marketplace_order.created_at
    ) < now() - interval '48 hours'
  ) then
    raise exception 'dispute_window_closed' using errcode = '55000';
  end if;

  insert into public.disputes (
    order_id,
    created_by,
    reason,
    description,
    evidence
  )
  values (
    p_order_id,
    actor_id,
    p_reason,
    btrim(p_description),
    p_evidence
  )
  returning id into dispute_id;

  update public.seller_payouts
  set status = 'frozen',
      frozen_reason = 'open_dispute',
      eligible_at = null,
      updated_at = now()
  where order_id = p_order_id
    and status in ('pending', 'eligible', 'processing');

  perform public.apply_order_transition(
    p_order_id,
    'dispute',
    actor_id,
    case when actor_id = marketplace_order.buyer_id
      then 'buyer' else 'seller' end,
    'participant_opened_dispute',
    jsonb_build_object(
      'from_status', marketplace_order.status,
      'dispute_id', dispute_id,
      'reason', p_reason
    )
  );
  return dispute_id;
end;
$$;

revoke all on function public.open_dispute(text, text, text, jsonb)
  from public, anon;
grant execute on function public.open_dispute(text, text, text, jsonb)
  to authenticated;

create or replace function public.resolve_dispute(
  p_dispute_id uuid,
  p_outcome text,
  p_resolution text,
  p_moderator_id uuid,
  p_payout_action text
)
returns public.disputes
language plpgsql
security definer
set search_path = ''
as $$
declare
  dispute_row public.disputes%rowtype;
  marketplace_order public.orders%rowtype;
  result public.disputes%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.admin_roles administrator
    where administrator.user_id = p_moderator_id
      and administrator.role in ('moderator', 'ops_admin', 'owner')
  ) then
    raise exception 'moderator_required' using errcode = '42501';
  end if;
  if p_outcome not in ('resolved_buyer', 'resolved_seller', 'rejected')
     or p_payout_action not in (
       'refund_buyer', 'release_seller', 'no_action'
     )
     or char_length(btrim(coalesce(p_resolution, ''))) < 10
     or (
       p_outcome = 'resolved_buyer'
       and p_payout_action <> 'refund_buyer'
     )
     or (
       p_outcome = 'resolved_seller'
       and p_payout_action <> 'release_seller'
     )
     or (
       p_outcome = 'rejected'
       and p_payout_action <> 'release_seller'
     ) then
    raise exception 'dispute_resolution_invalid' using errcode = '22023';
  end if;

  select * into dispute_row
  from public.disputes dispute
  where dispute.id = p_dispute_id
  for update;
  if not found or dispute_row.status not in ('open', 'under_review') then
    raise exception 'dispute_not_resolvable' using errcode = 'P0002';
  end if;
  select * into marketplace_order
  from public.orders target_order
  where target_order.id = dispute_row.order_id
  for update;

  update public.disputes
  set status = p_outcome,
      moderator_id = p_moderator_id,
      resolution = btrim(p_resolution),
      payout_action = p_payout_action,
      resolved_at = now()
  where id = p_dispute_id
  returning * into result;

  if p_payout_action = 'release_seller' then
    update public.seller_payouts
    set status = 'pending',
        frozen_reason = '',
        release_not_before = null,
        eligible_at = null,
        updated_at = now()
    where order_id = dispute_row.order_id
      and status in ('pending', 'frozen');
  elsif p_payout_action = 'refund_buyer' then
    update public.seller_payouts
    set status = 'cancelled',
        frozen_reason = 'refund_buyer_required',
        updated_at = now()
    where order_id = dispute_row.order_id
      and status in ('pending', 'frozen', 'eligible', 'processing');
  end if;

  perform public.apply_order_transition(
    dispute_row.order_id,
    case when p_outcome = 'resolved_buyer'
      then 'cancelled' else 'completed' end,
    p_moderator_id,
    'moderator',
    'dispute_resolved',
    jsonb_build_object(
      'from_status', 'dispute',
      'dispute_id', p_dispute_id,
      'outcome', p_outcome,
      'payout_action', p_payout_action
    )
  );

  insert into public.admin_audit_log (
    actor_id,
    actor_role,
    action,
    target_type,
    target_id,
    reason,
    after_data
  )
  values (
    p_moderator_id,
    'moderator',
    'resolve_dispute',
    'dispute',
    p_dispute_id::text,
    btrim(p_resolution),
    jsonb_build_object(
      'outcome', p_outcome,
      'payout_action', p_payout_action,
      'order_id', dispute_row.order_id
    )
  );
  return result;
end;
$$;

revoke all on function public.resolve_dispute(
  uuid, text, text, uuid, text
) from public, anon, authenticated;
grant execute on function public.resolve_dispute(
  uuid, text, text, uuid, text
) to service_role;

alter table public.payment_provider_configurations enable row level security;
alter table public.provider_webhook_inbox enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.seller_payouts enable row level security;
alter table public.platform_fees enable row level security;
alter table public.disputes enable row level security;
alter table public.dispute_evidence enable row level security;

drop policy if exists "Order participants read disputes" on public.disputes;
create policy "Order participants read disputes"
  on public.disputes for select to authenticated
  using (
    exists (
      select 1
      from public.orders marketplace_order
      where marketplace_order.id = order_id
        and (select auth.uid()) in (
          marketplace_order.buyer_id,
          marketplace_order.seller_id
        )
    )
  );
drop policy if exists "Order participants read dispute evidence"
  on public.dispute_evidence;
create policy "Order participants read dispute evidence"
  on public.dispute_evidence for select to authenticated
  using (
    exists (
      select 1
      from public.disputes dispute
      join public.orders marketplace_order
        on marketplace_order.id = dispute.order_id
      where dispute.id = dispute_id
        and (select auth.uid()) in (
          marketplace_order.buyer_id,
          marketplace_order.seller_id
        )
    )
  );
drop policy if exists "Sellers read own payout ledger"
  on public.seller_payouts;
create policy "Sellers read own payout ledger"
  on public.seller_payouts for select to authenticated
  using (
    exists (
      select 1
      from public.seller_accounts seller
      where seller.id = seller_account_id
        and seller.user_id = (select auth.uid())
    )
  );

revoke all on public.payment_provider_configurations,
  public.provider_webhook_inbox,
  public.payment_transactions,
  public.platform_fees
from anon, authenticated;
revoke all on public.seller_payouts,
  public.disputes,
  public.dispute_evidence
from anon, authenticated;
grant select on public.seller_payouts,
  public.disputes,
  public.dispute_evidence
to authenticated;

-- No mobile role can mutate order, payment, transition or evidence ledgers.
drop policy if exists "Buyers can create orders" on public.orders;
drop policy if exists "Order participants can update orders" on public.orders;
revoke insert, update, delete on public.orders from anon, authenticated;
revoke insert, update, delete on public.order_events from anon, authenticated;

revoke all on function public.protect_order_state()
  from public, anon, authenticated;
revoke all on function public.prevent_immutable_ledger_mutation()
  from public, anon, authenticated;
revoke all on function public.protect_seller_payout_release()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
