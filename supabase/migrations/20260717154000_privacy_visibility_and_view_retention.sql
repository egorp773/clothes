-- Close privacy gaps that are easy to miss in a marketplace client:
-- exact seller dispatch addresses stay in the owner-only listing_addresses
-- table, blocks affect all public UGC, and view rows follow account deletion.

-- `shipping_address_id` is the private source of truth. Legacy publication
-- functions may still assign the denormalized text column, so a trigger keeps
-- that public product column empty until provider adapters read the private
-- address server-side.
do $$
begin
  if exists (
    select 1
    from public.products product
    left join public.listing_addresses private_address
      on private_address.id = product.shipping_address_id
     and private_address.user_id = product.seller_id
    where (
        (
          product.status = 'published'
          and coalesce(product.delivery_methods, '{}'::text[])
            && array['cdek', 'russian_post', 'yandex_delivery']::text[]
        )
        or btrim(coalesce(product.shipping_address, '')) <> ''
      )
      and (
        private_address.id is null
        or btrim(coalesce(private_address.address, '')) = ''
      )
  ) then
    raise exception using
      errcode = '23514',
      message = 'shipping_address_privacy_preflight_failed';
  end if;
end
$$;

update public.products
set shipping_address = ''
where btrim(coalesce(shipping_address, '')) <> '';

create or replace function public.strip_public_product_shipping_address()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  has_private_address boolean;
begin
  select exists (
    select 1
    from public.listing_addresses private_address
    where private_address.id = new.shipping_address_id
      and private_address.user_id = new.seller_id
      and btrim(coalesce(private_address.address, '')) <> ''
  ) into has_private_address;

  if new.status = 'published'
     and coalesce(new.delivery_methods, '{}'::text[])
       && array['cdek', 'russian_post', 'yandex_delivery']::text[]
     and not has_private_address then
    raise exception using
      errcode = '23514',
      message = 'published_shipping_address_required';
  end if;
  if btrim(coalesce(new.shipping_address, '')) <> ''
     and not has_private_address then
    raise exception using
      errcode = '23514',
      message = 'shipping_address_private_source_required';
  end if;
  new.shipping_address := '';
  return new;
end;
$$;

drop trigger if exists strip_public_product_shipping_address_before_write
  on public.products;
create trigger strip_public_product_shipping_address_before_write
before insert or update of
  shipping_address, shipping_address_id, seller_id, status, delivery_methods
on public.products
for each row execute function public.strip_public_product_shipping_address();

-- Anonymous catalogue browsing remains possible. Signed-in users do not see
-- content or profiles across either side of a block relation.
grant execute on function public.users_are_blocked(uuid, uuid)
  to anon, authenticated;

drop policy if exists "Published products are readable" on public.products;
create policy "Published products are readable"
  on public.products for select
  using (
    auth.uid() = seller_id
    or (
      status = 'published'
      and not coalesce(is_hidden, false)
      and (
        auth.uid() is null
        or seller_id is null
        or not public.users_are_blocked(auth.uid(), seller_id)
      )
    )
  );

drop policy if exists "Public outfits are readable" on public.outfits;
create policy "Public outfits are readable"
  on public.outfits for select
  using (
    auth.uid() is null
    or owner_id is null
    or auth.uid() = owner_id
    or not public.users_are_blocked(auth.uid(), owner_id)
  );

drop policy if exists "Public profiles are readable" on public.profiles;
create policy "Public profiles are readable"
  on public.profiles for select
  using (
    auth.uid() is null
    or auth.uid() = id
    or not public.users_are_blocked(auth.uid(), id)
  );

-- A raw RPC call must not allow a blocked account to create an order even if
-- it already knows a listing UUID.
create or replace function public.reject_blocked_order_participants()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.blocked_users blocked
    where (
      blocked.blocker_id = new.buyer_id
      and blocked.blocked_id = new.seller_id
    ) or (
      blocked.blocker_id = new.seller_id
      and blocked.blocked_id = new.buyer_id
    )
  ) then
    raise exception 'product_unavailable' using errcode = 'P0002';
  end if;
  return new;
end;
$$;

drop trigger if exists reject_blocked_order_participants_before_insert
  on public.orders;
create trigger reject_blocked_order_participants_before_insert
before insert on public.orders
for each row execute function public.reject_blocked_order_participants();

-- Reports are UGC moderation input, not a free-form anonymous write sink.
-- Validate the target and cap accidental/automated floods per account.
create or replace function public.validate_content_report()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  target_exists boolean := false;
begin
  if actor_id is null or new.reporter_id <> actor_id then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if char_length(btrim(new.reason)) not between 2 and 120
     or char_length(new.details) > 2000 then
    raise exception 'invalid_report' using errcode = '22023';
  end if;
  if (
    select count(*) from public.content_reports report
    where report.reporter_id = actor_id
      and report.created_at > now() - interval '24 hours'
  ) >= 20 then
    raise exception 'report_rate_limited' using errcode = '54000';
  end if;

  target_exists := case new.target_type
    when 'product' then exists (
      select 1 from public.products product
      where product.id::text = new.target_id
    )
    when 'outfit' then exists (
      select 1 from public.outfits outfit
      where outfit.id::text = new.target_id
    )
    when 'user' then exists (
      select 1 from auth.users account where account.id::text = new.target_id
    )
    when 'message' then exists (
      select 1
      from public.chat_messages message
      join public.message_threads thread on thread.id = message.thread_id
      where message.id = new.target_id
        and actor_id = any(thread.member_ids)
    )
    else false
  end;
  if not target_exists then
    raise exception 'report_target_not_found' using errcode = 'P0002';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_content_report_before_insert
  on public.content_reports;
create trigger validate_content_report_before_insert
before insert on public.content_reports
for each row execute function public.validate_content_report();

-- View analytics contain a stable user identifier and therefore follow
-- account deletion. Recompute the materialized counters after cascades.
delete from public.product_views view_event
where not exists (
  select 1 from auth.users account where account.id = view_event.viewer_id
);
delete from public.outfit_views view_event
where not exists (
  select 1 from auth.users account where account.id = view_event.viewer_id
);

-- The cleanup above happens before the permanent AFTER DELETE triggers are
-- installed, so rebuild every materialized count from the surviving rows.
update public.products product
set views_count = (
  select count(*)::integer
  from public.product_views remaining
  where remaining.product_id = product.id
);

update public.outfits outfit
set views_count = (
  select count(*)::integer
  from public.outfit_views remaining
  where remaining.outfit_id = outfit.id
);

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.product_views'::regclass
      and conname = 'product_views_viewer_id_fkey'
  ) then
    alter table public.product_views
      add constraint product_views_viewer_id_fkey
      foreign key (viewer_id) references auth.users(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.outfit_views'::regclass
      and conname = 'outfit_views_viewer_id_fkey'
  ) then
    alter table public.outfit_views
      add constraint outfit_views_viewer_id_fkey
      foreign key (viewer_id) references auth.users(id) on delete cascade;
  end if;
end
$$;

create or replace function public.refresh_product_view_count_after_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products product
  set views_count = (
    select count(*)::integer
    from public.product_views remaining
    where remaining.product_id = old.product_id
  )
  where product.id = old.product_id;
  return old;
end;
$$;

create or replace function public.refresh_outfit_view_count_after_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.outfits outfit
  set views_count = (
    select count(*)::integer
    from public.outfit_views remaining
    where remaining.outfit_id = old.outfit_id
  )
  where outfit.id = old.outfit_id;
  return old;
end;
$$;

drop trigger if exists refresh_product_view_count_after_delete
  on public.product_views;
create trigger refresh_product_view_count_after_delete
after delete on public.product_views
for each row execute function public.refresh_product_view_count_after_delete();

drop trigger if exists refresh_outfit_view_count_after_delete
  on public.outfit_views;
create trigger refresh_outfit_view_count_after_delete
after delete on public.outfit_views
for each row execute function public.refresh_outfit_view_count_after_delete();

revoke all on function public.strip_public_product_shipping_address()
  from public;
revoke all on function public.reject_blocked_order_participants()
  from public;
revoke all on function public.validate_content_report()
  from public;
revoke all on function public.refresh_product_view_count_after_delete()
  from public;
revoke all on function public.refresh_outfit_view_count_after_delete()
  from public;

notify pgrst, 'reload schema';
