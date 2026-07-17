-- Apply in Supabase SQL Editor if you want outfits and chats persisted remotely.
-- The app already works with the existing public.products table and product-images bucket.

alter table public.products
  add column if not exists original_image text,
  add column if not exists cutout_image text,
  add column if not exists outfit_images text[] not null default '{}',
  add column if not exists is_hidden boolean not null default false,
  add column if not exists seller_id uuid references auth.users(id) on delete set null,
  add column if not exists seller_name text not null default 'Продавец',
  add column if not exists seller_handle text not null default '@seller',
  add column if not exists location text not null default '',
  add column if not exists views_count integer not null default 0,
  add column if not exists likes_count integer not null default 0,
  add column if not exists background_status text not null default 'queued',
  add column if not exists background_error text;

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Public product images are readable" on storage.objects;
create policy "Public product images are readable"
  on storage.objects for select
  using (bucket_id = 'product-images');

drop policy if exists "Authenticated users can upload product images" on storage.objects;
create policy "Authenticated users can upload product images"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'product-images');

drop policy if exists "Authenticated users can update product images" on storage.objects;
create policy "Authenticated users can update product images"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'product-images')
  with check (bucket_id = 'product-images');

notify pgrst, 'reload schema';

-- Durable asynchronous visual-analysis jobs shared by analyzer workers.
alter table public.products
  add column if not exists analysis_job_id text;

create table if not exists public.listing_analysis_jobs (
  id text primary key,
  listing_id uuid not null references public.products(id) on delete cascade,
  image_hash text not null,
  main_image_url text,
  extra_image_urls jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  basic_result jsonb,
  enrichment_result jsonb,
  timings_ms jsonb not null default '{}'::jsonb,
  error text,
  attempt_count integer not null default 0,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index if not exists listing_analysis_jobs_listing_image_idx
  on public.listing_analysis_jobs (listing_id, image_hash);
create index if not exists listing_analysis_jobs_claim_idx
  on public.listing_analysis_jobs (status, lease_until, created_at);

drop trigger if exists touch_listing_analysis_jobs_updated_at
  on public.listing_analysis_jobs;
create trigger touch_listing_analysis_jobs_updated_at
before update on public.listing_analysis_jobs
for each row execute function public.touch_listing_updated_at();

alter table public.listing_analysis_jobs enable row level security;
drop policy if exists "Owners can read listing analysis jobs"
  on public.listing_analysis_jobs;
create policy "Owners can read listing analysis jobs"
  on public.listing_analysis_jobs for select to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = listing_id and p.seller_id = auth.uid()
  ));

notify pgrst, 'reload schema';

-- Optional category-specific attributes produced by the modular analyzer.
alter table public.products
  add column if not exists fit text,
  add column if not exists sleeve_length text,
  add column if not exists closure text;

notify pgrst, 'reload schema';

-- Private profile fields are deliberately kept out of public.profiles.
create table if not exists public.profile_private_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  middle_name text not null default '',
  gender text not null default 'male' check (gender in ('male', 'female')),
  birth_date date,
  phone text not null default '',
  email text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.profile_private_details enable row level security;

drop policy if exists "Users can read their private profile" on public.profile_private_details;
create policy "Users can read their private profile"
  on public.profile_private_details for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their private profile" on public.profile_private_details;
create policy "Users can insert their private profile"
  on public.profile_private_details for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their private profile" on public.profile_private_details;
create policy "Users can update their private profile"
  on public.profile_private_details for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Supabase Auth has no client-side delete-user API. This function deletes only
-- the authenticated caller and lets foreign-key cascades clean related data.
create or replace function public.delete_current_user()
returns void
language sql
security definer
set search_path = public, auth
as $$
  delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_current_user() from public;
revoke execute on function public.delete_current_user() from anon, authenticated;

notify pgrst, 'reload schema';

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text not null unique,
  avatar_url text not null default '',
  city text not null default 'Москва',
  rating numeric not null default 4.8,
  sales_count integer not null default 0,
  followers_count integer not null default 0,
  last_seen_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

alter table public.profiles
  add column if not exists avatar_url text not null default '',
  add column if not exists followers_count integer not null default 0,
  add column if not exists last_seen_at timestamptz;

drop policy if exists "Public profiles are readable" on public.profiles;
create policy "Public profiles are readable"
  on public.profiles for select
  using (true);

drop policy if exists "Users can insert their profile" on public.profiles;
create policy "Users can insert their profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update their profile" on public.profiles;
create policy "Users can update their profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

notify pgrst, 'reload schema';

create table if not exists public.device_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.device_push_tokens enable row level security;

alter table public.device_push_tokens
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists platform text not null default 'unknown',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

drop policy if exists "Users can manage their push tokens" on public.device_push_tokens;
create policy "Users can manage their push tokens"
  on public.device_push_tokens for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

notify pgrst, 'reload schema';

create table if not exists public.outfits (
  id uuid primary key,
  owner_id uuid references auth.users(id) on delete set null,
  author_name text not null default 'Автор',
  author_handle text not null default '@user',
  author_avatar_url text not null default '',
  photos text[] not null default '{}',
  items jsonb not null default '[]'::jsonb,
  likes_count integer not null default 0,
  views_count integer not null default 0,
  preview_layout jsonb,
  created_at timestamptz not null default now()
);

alter table public.outfits
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists author_name text not null default 'Автор',
  add column if not exists author_handle text not null default '@user',
  add column if not exists author_avatar_url text not null default '',
  add column if not exists likes_count integer not null default 0,
  add column if not exists views_count integer not null default 0,
  add column if not exists preview_layout jsonb;

update public.outfits outfit
set
  author_name = 'Автор',
  author_handle = '@user',
  author_avatar_url = ''
where not exists (
  select 1
  from public.profiles profile
  where profile.id = outfit.owner_id
);

alter table public.outfits enable row level security;

create or replace function public.hydrate_outfit_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_author_id uuid;
  author_profile public.profiles%rowtype;
begin
  if tg_op = 'INSERT' then
    current_author_id := auth.uid();
    if current_author_id is null then
      raise exception 'authentication_required' using errcode = '42501';
    end if;
    if new.owner_id is null then
      new.owner_id := current_author_id;
    end if;
    if new.owner_id <> current_author_id then
      raise exception 'outfit_owner_mismatch' using errcode = '42501';
    end if;
  else
    current_author_id := new.owner_id;
    if current_author_id is null then
      new.author_name := old.author_name;
      new.author_handle := old.author_handle;
      new.author_avatar_url := old.author_avatar_url;
      return new;
    end if;
  end if;

  select * into author_profile
  from public.profiles
  where id = current_author_id;

  if found then
    new.author_name := coalesce(nullif(author_profile.name, ''), 'Автор');
    new.author_handle := coalesce(nullif(author_profile.handle, ''), '@user');
    new.author_avatar_url := coalesce(author_profile.avatar_url, '');
  elsif tg_op = 'INSERT' then
    new.author_name := 'Автор';
    new.author_handle := '@user';
    new.author_avatar_url := '';
  else
    new.author_name := old.author_name;
    new.author_handle := old.author_handle;
    new.author_avatar_url := old.author_avatar_url;
  end if;
  return new;
end;
$$;

drop trigger if exists hydrate_outfit_author_before_write on public.outfits;
create trigger hydrate_outfit_author_before_write
before insert or update of author_name, author_handle, author_avatar_url
on public.outfits
for each row execute function public.hydrate_outfit_author();

drop policy if exists "Public outfits are readable" on public.outfits;
create policy "Public outfits are readable"
  on public.outfits for select
  using (true);

drop policy if exists "Authenticated users can publish outfits" on public.outfits;
create policy "Users can publish own outfits"
  on public.outfits for insert
  to authenticated
  with check (auth.uid() = owner_id);

create table if not exists public.product_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

alter table public.product_favorites enable row level security;

drop policy if exists "Users can manage product favorites" on public.product_favorites;
create policy "Users can manage product favorites"
  on public.product_favorites for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.outfit_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, outfit_id)
);

alter table public.outfit_favorites enable row level security;

drop policy if exists "Users can manage outfit favorites" on public.outfit_favorites;
create policy "Users can manage outfit favorites"
  on public.outfit_favorites for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.sync_outfit_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.outfits
      set likes_count = likes_count + 1
      where id = new.outfit_id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.outfits
      set likes_count = greatest(likes_count - 1, 0)
      where id = old.outfit_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists sync_outfit_likes_count_insert on public.outfit_favorites;
create trigger sync_outfit_likes_count_insert
after insert on public.outfit_favorites
for each row execute function public.sync_outfit_likes_count();

drop trigger if exists sync_outfit_likes_count_delete on public.outfit_favorites;
create trigger sync_outfit_likes_count_delete
after delete on public.outfit_favorites
for each row execute function public.sync_outfit_likes_count();

update public.outfits
set likes_count = 0;

update public.outfits
set likes_count = counts.total
from (
  select outfit_id, count(*)::integer as total
  from public.outfit_favorites
  group by outfit_id
) counts
where public.outfits.id = counts.outfit_id;

create table if not exists public.recent_products (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  viewed_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

alter table public.recent_products enable row level security;

drop policy if exists "Users can manage recent products" on public.recent_products;
create policy "Users can manage recent products"
  on public.recent_products for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.sync_product_views_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_product_id text;
begin
  affected_product_id := case when tg_op = 'DELETE'
    then old.product_id else new.product_id end;
  update public.products product
  set views_count = (
    select count(*)::integer
    from public.recent_products recent
    where recent.product_id = affected_product_id
  )
  where product.id::text = affected_product_id;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.sync_product_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_product_id text;
begin
  affected_product_id := case when tg_op = 'DELETE'
    then old.product_id else new.product_id end;
  update public.products product
  set likes_count = (
    select count(*)::integer
    from public.product_favorites favorite
    where favorite.product_id = affected_product_id
  )
  where product.id::text = affected_product_id;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists sync_product_views_count_change
  on public.recent_products;
create trigger sync_product_views_count_change
after insert or delete on public.recent_products
for each row execute function public.sync_product_views_count();

drop trigger if exists sync_product_likes_count_change
  on public.product_favorites;
create trigger sync_product_likes_count_change
after insert or delete on public.product_favorites
for each row execute function public.sync_product_likes_count();

update public.products product
set views_count = (
  select count(*)::integer
  from public.recent_products recent
  where recent.product_id = product.id::text
),
likes_count = (
  select count(*)::integer
  from public.product_favorites favorite
  where favorite.product_id = product.id::text
);

create table if not exists public.recent_outfits (
  user_id uuid not null references auth.users(id) on delete cascade,
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (user_id, outfit_id)
);

alter table public.recent_outfits enable row level security;

drop policy if exists "Users can manage recent outfits" on public.recent_outfits;
create policy "Users can manage recent outfits"
  on public.recent_outfits for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.sync_outfit_views_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.outfits
      set views_count = views_count + 1
      where id = new.outfit_id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.outfits
      set views_count = greatest(views_count - 1, 0)
      where id = old.outfit_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists sync_outfit_views_count_insert on public.recent_outfits;
create trigger sync_outfit_views_count_insert
after insert on public.recent_outfits
for each row execute function public.sync_outfit_views_count();

drop trigger if exists sync_outfit_views_count_delete on public.recent_outfits;

update public.outfits
set views_count = greatest(public.outfits.views_count, counts.total)
from (
  select outfit_id, count(*)::integer as total
  from public.recent_outfits
  group by outfit_id
) counts
where public.outfits.id = counts.outfit_id;

create or replace function public.record_outfit_view(p_outfit_id uuid)
returns table(views_count integer, first_view boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_id uuid := auth.uid();
  inserted_rows integer := 0;
  authoritative_count integer := 0;
begin
  if viewer_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  insert into public.recent_outfits (user_id, outfit_id, viewed_at)
  values (viewer_id, p_outfit_id, now())
  on conflict (user_id, outfit_id) do nothing;
  get diagnostics inserted_rows = row_count;

  if inserted_rows = 0 then
    update public.recent_outfits
      set viewed_at = now()
      where user_id = viewer_id and outfit_id = p_outfit_id;
  end if;

  select greatest(coalesce(outfits.views_count, 0), 0)
    into authoritative_count
    from public.outfits
    where outfits.id = p_outfit_id;

  if not found then
    raise exception 'Outfit not found' using errcode = 'P0002';
  end if;

  return query select authoritative_count, inserted_rows > 0;
end;
$$;

revoke all on function public.record_outfit_view(uuid) from public;
grant execute on function public.record_outfit_view(uuid) to authenticated;

notify pgrst, 'reload schema';

create table if not exists public.message_threads (
  id text primary key,
  buyer_id uuid references auth.users(id) on delete cascade,
  seller_id uuid references auth.users(id) on delete cascade,
  product_id text,
  seller_name text not null,
  buyer_name text not null default 'Покупатель',
  product_title text not null,
  product_image text not null default '',
  buyer_handle text not null default '',
  seller_handle text not null default '',
  buyer_avatar text not null default '',
  seller_avatar text not null default '',
  last_message text not null,
  unread_count integer not null default 0,
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.message_threads
  alter column id type text using id::text,
  add column if not exists buyer_id uuid references auth.users(id) on delete cascade,
  add column if not exists seller_id uuid references auth.users(id) on delete cascade,
  add column if not exists product_id text,
  add column if not exists seller_name text not null default 'Продавец',
  add column if not exists buyer_name text not null default 'Покупатель',
  add column if not exists product_title text not null default '',
  add column if not exists product_image text not null default '',
  add column if not exists buyer_handle text not null default '',
  add column if not exists seller_handle text not null default '',
  add column if not exists buyer_avatar text not null default '',
  add column if not exists seller_avatar text not null default '',
  add column if not exists last_message text not null default '',
  add column if not exists unread_count integer not null default 0,
  add column if not exists messages jsonb not null default '[]'::jsonb,
  add column if not exists updated_at timestamptz not null default now();

alter table public.message_threads enable row level security;

drop policy if exists "Authenticated users can manage threads" on public.message_threads;
drop policy if exists "Users can read their message threads" on public.message_threads;
create policy "Users can read their message threads"
  on public.message_threads for select
  to authenticated
  using (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists "Users can create their message threads" on public.message_threads;
create policy "Users can create their message threads"
  on public.message_threads for insert
  to authenticated
  with check (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists "Users can update their message threads" on public.message_threads;
create policy "Users can update their message threads"
  on public.message_threads for update
  to authenticated
  using (auth.uid() = buyer_id or auth.uid() = seller_id)
  with check (auth.uid() = buyer_id or auth.uid() = seller_id);

create table if not exists public.notification_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  messages_enabled boolean not null default true,
  orders_enabled boolean not null default true,
  favorites_enabled boolean not null default true,
  promotions_enabled boolean not null default false,
  sound_enabled boolean not null default true,
  email_enabled boolean not null default false,
  sms_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_settings
  add column if not exists messages_enabled boolean not null default true,
  add column if not exists orders_enabled boolean not null default true,
  add column if not exists favorites_enabled boolean not null default true,
  add column if not exists promotions_enabled boolean not null default false,
  add column if not exists sound_enabled boolean not null default true;

alter table public.notification_settings enable row level security;

drop policy if exists "Users can manage notification settings" on public.notification_settings;
create policy "Users can manage notification settings"
  on public.notification_settings for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.notifications (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  target_id text not null default '',
  data jsonb not null default '{}'::jsonb,
  dedupe_key text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists dedupe_key text;

delete from public.notifications where kind = 'message';

alter table public.notifications enable row level security;

drop policy if exists "Users can manage their notifications" on public.notifications;
create policy "Users can manage their notifications"
  on public.notifications for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create unique index if not exists notifications_user_dedupe_idx
  on public.notifications (user_id, dedupe_key);

create table if not exists public.orders (
  id text primary key,
  product_id text not null,
  product_title text not null,
  product_image text not null default '',
  product_price text not null default '',
  product_price_value integer not null default 0,
  seller_id uuid references auth.users(id) on delete set null,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  tracking_number text not null default '',
  delivery_service text not null default 'Яндекс Доставка',
  delivery_address text not null default '',
  recipient_name text not null default '',
  recipient_phone text not null default '',
  recipient_email text not null default '',
  delivery_price integer not null default 0,
  status text not null default 'pendingConfirmation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.orders
  add column if not exists delivery_address text not null default '',
  add column if not exists recipient_name text not null default '',
  add column if not exists recipient_phone text not null default '',
  add column if not exists recipient_email text not null default '',
  add column if not exists delivery_price integer not null default 0;

alter table public.orders
  alter column seller_id drop not null,
  drop constraint if exists orders_seller_id_fkey;

alter table public.orders
  add constraint orders_seller_id_fkey
  foreign key (seller_id) references auth.users(id) on delete set null;

create or replace function public.touch_order_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists touch_orders_updated_at on public.orders;
create trigger touch_orders_updated_at
before update on public.orders
for each row execute function public.touch_order_updated_at();

alter table public.orders enable row level security;

drop policy if exists "Order participants can read orders" on public.orders;
create policy "Order participants can read orders"
  on public.orders for select
  to authenticated
  using (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists "Buyers can create orders" on public.orders;
create policy "Buyers can create orders"
  on public.orders for insert
  to authenticated
  with check (auth.uid() = buyer_id);

drop policy if exists "Order participants can update orders" on public.orders;
create policy "Order participants can update orders"
  on public.orders for update
  to authenticated
  using (auth.uid() = buyer_id or auth.uid() = seller_id)
  with check (auth.uid() = buyer_id or auth.uid() = seller_id);

create index if not exists orders_buyer_updated_idx
  on public.orders (buyer_id, updated_at desc);

create index if not exists orders_seller_updated_idx
  on public.orders (seller_id, updated_at desc);

create table if not exists public.seller_reviews (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public.profiles(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  buyer_name text not null default '',
  buyer_avatar text not null default '',
  product_id text not null default '',
  product_title text not null default '',
  product_image text not null default '',
  rating integer not null check (rating between 1 and 5),
  text text not null default '',
  has_photo boolean not null default false,
  deal_completed boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.seller_reviews enable row level security;

drop policy if exists "Authenticated users can read seller reviews" on public.seller_reviews;
create policy "Authenticated users can read seller reviews"
  on public.seller_reviews for select
  to authenticated
  using (true);

drop policy if exists "Buyers can create seller reviews" on public.seller_reviews;
create policy "Buyers can create seller reviews"
  on public.seller_reviews for insert
  to authenticated
  with check (
    (select auth.uid()) = buyer_id
    and buyer_id <> seller_id
    and nullif(btrim(product_id), '') is not null
    and exists (
      select 1
      from public.orders as completed_order
      where completed_order.buyer_id = seller_reviews.buyer_id
        and completed_order.seller_id = seller_reviews.seller_id
        and completed_order.product_id::text = seller_reviews.product_id
        and completed_order.status = 'completed'
    )
  );

drop policy if exists "Buyers can update own seller reviews" on public.seller_reviews;
create policy "Buyers can update own seller reviews"
  on public.seller_reviews for update
  to authenticated
  using ((select auth.uid()) = buyer_id)
  with check (
    (select auth.uid()) = buyer_id
    and buyer_id <> seller_id
    and nullif(btrim(product_id), '') is not null
    and exists (
      select 1
      from public.orders as completed_order
      where completed_order.buyer_id = seller_reviews.buyer_id
        and completed_order.seller_id = seller_reviews.seller_id
        and completed_order.product_id::text = seller_reviews.product_id
        and completed_order.status = 'completed'
    )
  );

create index if not exists seller_reviews_seller_created_idx
  on public.seller_reviews (seller_id, created_at desc);

create unique index if not exists seller_reviews_buyer_product_unique_idx
  on public.seller_reviews (buyer_id, product_id);

create table if not exists public.delivery_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  full_name text not null default '',
  phone text not null default '',
  email text not null default '',
  city text not null default '',
  address text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.delivery_profiles enable row level security;

drop policy if exists "Users can read own delivery profile" on public.delivery_profiles;
create policy "Users can read own delivery profile"
  on public.delivery_profiles for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own delivery profile" on public.delivery_profiles;
create policy "Users can insert own delivery profile"
  on public.delivery_profiles for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own delivery profile" on public.delivery_profiles;
create policy "Users can update own delivery profile"
  on public.delivery_profiles for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

notify pgrst, 'reload schema';

create table if not exists public.outfit_accessories (
  id uuid primary key,
  title text not null default 'Аксессуар',
  scope text not null default 'private' check (scope in ('default', 'private')),
  owner_id uuid references auth.users(id) on delete cascade,
  original_image text not null default '',
  cutout_image text,
  background_status text not null default 'queued',
  background_error text,
  created_at timestamptz not null default now()
);

alter table public.outfit_accessories
  add column if not exists title text not null default 'Аксессуар',
  add column if not exists scope text not null default 'private',
  add column if not exists owner_id uuid references auth.users(id) on delete cascade,
  add column if not exists original_image text not null default '',
  add column if not exists cutout_image text,
  add column if not exists background_status text not null default 'queued',
  add column if not exists background_error text,
  add column if not exists created_at timestamptz not null default now();

alter table public.outfit_accessories enable row level security;

drop policy if exists "Readable outfit accessories" on public.outfit_accessories;
create policy "Readable outfit accessories"
  on public.outfit_accessories for select
  using (scope = 'default' or auth.uid() = owner_id);

drop policy if exists "Authenticated users can create outfit accessories" on public.outfit_accessories;
create policy "Authenticated users can create outfit accessories"
  on public.outfit_accessories for insert
  to authenticated
  with check (scope = 'default' or auth.uid() = owner_id);

drop policy if exists "Users can update their outfit accessories" on public.outfit_accessories;
create policy "Users can update their outfit accessories"
  on public.outfit_accessories for update
  to authenticated
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

notify pgrst, 'reload schema';

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
  add column if not exists shipping_address text not null default '',
  add column if not exists delivery_methods text[],
  add column if not exists image text,
  add column if not exists main_image text,
  add column if not exists published_at timestamptz,
  add column if not exists analysis_status text,
  add column if not exists analysis_completed_at timestamptz,
  add column if not exists draft_step text,
  add column if not exists last_autosaved_at timestamptz;

update public.products p
set shipping_address = concat_ws(
  ', ',
  nullif(btrim(a.city), ''),
  nullif(btrim(a.address), '')
)
from public.listing_addresses a
where p.shipping_address_id = a.id
  and btrim(coalesce(p.shipping_address, '')) = '';

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

revoke all on function public.strip_public_product_shipping_address()
  from public;

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
  using (
    auth.uid() = seller_id
    or (status = 'published' and not coalesce(is_hidden, false))
  );

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
