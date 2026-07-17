-- Reproducible core schema for clean Supabase projects.
--
-- The project originally kept these tables only in supabase/schema.sql, while
-- versioned migrations started by altering them.  Keep this migration
-- additive: it can be applied to the existing production project as well as
-- to an empty database.  Product enrichment, checkout, chat media and metric
-- columns continue to be owned by their later migrations.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  handle text not null unique,
  avatar_url text not null default '',
  city text not null default '',
  rating numeric not null default 4.8,
  sales_count integer not null default 0,
  followers_count integer not null default 0,
  last_seen_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles
  add column if not exists name text not null default '',
  add column if not exists handle text not null default '',
  add column if not exists avatar_url text not null default '',
  add column if not exists city text not null default '',
  add column if not exists rating numeric not null default 4.8,
  add column if not exists sales_count integer not null default 0,
  add column if not exists followers_count integer not null default 0,
  add column if not exists last_seen_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.profile_private_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '',
  last_name text not null default '',
  middle_name text not null default '',
  gender text not null default 'male'
    check (gender in ('male', 'female')),
  birth_date date,
  phone text not null default '',
  email text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.profile_private_details
  add column if not exists first_name text not null default '',
  add column if not exists last_name text not null default '',
  add column if not exists middle_name text not null default '',
  add column if not exists gender text not null default 'male',
  add column if not exists birth_date date,
  add column if not exists phone text not null default '',
  add column if not exists email text not null default '',
  add column if not exists updated_at timestamptz not null default now();

-- Legacy product columns referenced by the first versioned listing migration.
-- Rich publication/search columns are intentionally added later.
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid references auth.users(id) on delete set null,
  seller_name text not null default 'Продавец',
  seller_handle text not null default '@seller',
  title text not null default '',
  description text default '',
  price numeric not null default 0,
  images text[] not null default '{}',
  original_image text,
  cutout_image text,
  outfit_images text[] not null default '{}',
  category text not null default '',
  brand text not null default '',
  size text not null default '',
  color text not null default '',
  condition text not null default '',
  location text not null default '',
  is_hidden boolean not null default false,
  background_status text not null default 'queued',
  background_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.products
  add column if not exists seller_id uuid references auth.users(id) on delete set null,
  add column if not exists seller_name text not null default 'Продавец',
  add column if not exists seller_handle text not null default '@seller',
  add column if not exists title text not null default '',
  add column if not exists description text default '',
  add column if not exists price numeric not null default 0,
  add column if not exists images text[] not null default '{}',
  add column if not exists original_image text,
  add column if not exists cutout_image text,
  add column if not exists outfit_images text[] not null default '{}',
  add column if not exists category text not null default '',
  add column if not exists brand text not null default '',
  add column if not exists size text not null default '',
  add column if not exists color text not null default '',
  add column if not exists condition text not null default '',
  add column if not exists location text not null default '',
  add column if not exists is_hidden boolean not null default false,
  add column if not exists background_status text not null default 'queued',
  add column if not exists background_error text,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Visual-search functions introduced before the metrics migration already
-- reference this table, so it is part of the baseline despite being repeated
-- idempotently later.
create table if not exists public.product_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists public.outfits (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid references auth.users(id) on delete set null,
  author_name text not null default 'Автор',
  author_handle text not null default '@user',
  photos text[] not null default '{}',
  items jsonb not null default '[]'::jsonb,
  likes_count integer not null default 0,
  preview_layout jsonb,
  created_at timestamptz not null default now()
);

alter table public.outfits
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists author_name text not null default 'Автор',
  add column if not exists author_handle text not null default '@user',
  add column if not exists photos text[] not null default '{}',
  add column if not exists items jsonb not null default '[]'::jsonb,
  add column if not exists likes_count integer not null default 0,
  add column if not exists preview_layout jsonb,
  add column if not exists created_at timestamptz not null default now();

create table if not exists public.outfit_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  outfit_id uuid not null references public.outfits(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, outfit_id)
);

create or replace function public.sync_outfit_likes_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.outfits outfit
  set likes_count = (
    select count(*)::integer
    from public.outfit_favorites favorite
    where favorite.outfit_id = case
      when tg_op = 'DELETE' then old.outfit_id else new.outfit_id
    end
  )
  where outfit.id = case
    when tg_op = 'DELETE' then old.outfit_id else new.outfit_id
  end;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists sync_outfit_likes_count_insert
  on public.outfit_favorites;
create trigger sync_outfit_likes_count_insert
after insert on public.outfit_favorites
for each row execute function public.sync_outfit_likes_count();

drop trigger if exists sync_outfit_likes_count_delete
  on public.outfit_favorites;
create trigger sync_outfit_likes_count_delete
after delete on public.outfit_favorites
for each row execute function public.sync_outfit_likes_count();

revoke all on function public.sync_outfit_likes_count() from public;

-- The first conversation migration normalizes embedded `messages` into a
-- separate table, therefore the legacy thread projection must exist first.
create table if not exists public.message_threads (
  id text primary key,
  buyer_id uuid references auth.users(id) on delete cascade,
  seller_id uuid references auth.users(id) on delete cascade,
  product_id text,
  seller_name text not null default 'Продавец',
  buyer_name text not null default 'Покупатель',
  product_title text not null default '',
  product_image text not null default '',
  buyer_handle text not null default '',
  seller_handle text not null default '',
  buyer_avatar text not null default '',
  seller_avatar text not null default '',
  last_message text not null default '',
  unread_count integer not null default 0,
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.message_threads
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

create table if not exists public.delivery_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  full_name text not null default '',
  phone text not null default '',
  email text not null default '',
  city text not null default '',
  address text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.delivery_profiles
  add column if not exists full_name text not null default '',
  add column if not exists phone text not null default '',
  add column if not exists email text not null default '',
  add column if not exists city text not null default '',
  add column if not exists address text not null default '',
  add column if not exists updated_at timestamptz not null default now();

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

alter table public.seller_reviews
  add column if not exists seller_id uuid references public.profiles(id) on delete cascade,
  add column if not exists buyer_id uuid references auth.users(id) on delete cascade,
  add column if not exists buyer_name text not null default '',
  add column if not exists buyer_avatar text not null default '',
  add column if not exists product_id text not null default '',
  add column if not exists product_title text not null default '',
  add column if not exists product_image text not null default '',
  add column if not exists rating integer,
  add column if not exists text text not null default '',
  add column if not exists has_photo boolean not null default false,
  add column if not exists deal_completed boolean not null default true,
  add column if not exists created_at timestamptz not null default now();

create index if not exists seller_reviews_seller_created_idx
  on public.seller_reviews (seller_id, created_at desc);

create table if not exists public.outfit_accessories (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'Аксессуар',
  scope text not null default 'private'
    check (scope in ('default', 'private')),
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

-- Supabase Auth deliberately has no client-side delete-user endpoint.  The
-- authenticated caller can delete only its own auth row; foreign keys above
-- perform the related cleanup.
create or replace function public.delete_current_user()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_current_user()
  from public, anon, authenticated;

insert into storage.buckets (id, name, public)
values ('product-images', 'product-images', true)
on conflict (id) do update set public = true;

drop policy if exists "Public product images are readable"
  on storage.objects;
create policy "Public product images are readable"
  on storage.objects for select
  using (bucket_id = 'product-images');

alter table public.profiles enable row level security;
alter table public.profile_private_details enable row level security;
alter table public.products enable row level security;
alter table public.product_favorites enable row level security;
alter table public.outfits enable row level security;
alter table public.outfit_favorites enable row level security;
alter table public.message_threads enable row level security;
alter table public.delivery_profiles enable row level security;
alter table public.seller_reviews enable row level security;
alter table public.outfit_accessories enable row level security;

-- Only bootstrap policies for a table that has none.  This is important when
-- the additive baseline is deployed to a project where later, stricter
-- policies (blocking, moderation, chat invariants) are already live.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profiles'
  ) then
    create policy "Public profiles are readable"
      on public.profiles for select using (true);
    create policy "Users can insert their profile"
      on public.profiles for insert to authenticated
      with check ((select auth.uid()) = id);
    create policy "Users can update their profile"
      on public.profiles for update to authenticated
      using ((select auth.uid()) = id)
      with check ((select auth.uid()) = id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'profile_private_details'
  ) then
    create policy "Users can read their private profile"
      on public.profile_private_details for select to authenticated
      using ((select auth.uid()) = user_id);
    create policy "Users can insert their private profile"
      on public.profile_private_details for insert to authenticated
      with check ((select auth.uid()) = user_id);
    create policy "Users can update their private profile"
      on public.profile_private_details for update to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'product_favorites'
  ) then
    create policy "Users can manage product favorites"
      on public.product_favorites for all to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'outfits'
  ) then
    create policy "Public outfits are readable"
      on public.outfits for select using (true);
    create policy "Authenticated users can publish outfits"
      on public.outfits for insert to authenticated
      with check ((select auth.uid()) = owner_id);
    create policy "Users can update their outfits"
      on public.outfits for update to authenticated
      using ((select auth.uid()) = owner_id)
      with check ((select auth.uid()) = owner_id);
    create policy "Users can delete their outfits"
      on public.outfits for delete to authenticated
      using ((select auth.uid()) = owner_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'outfit_favorites'
  ) then
    create policy "Users can manage outfit favorites"
      on public.outfit_favorites for all to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'message_threads'
  ) then
    create policy "Users can read their message threads"
      on public.message_threads for select to authenticated
      using (
        (select auth.uid()) = buyer_id or (select auth.uid()) = seller_id
      );
    create policy "Users can create their message threads"
      on public.message_threads for insert to authenticated
      with check (
        (select auth.uid()) = buyer_id or (select auth.uid()) = seller_id
      );
    create policy "Users can update their message threads"
      on public.message_threads for update to authenticated
      using (
        (select auth.uid()) = buyer_id or (select auth.uid()) = seller_id
      )
      with check (
        (select auth.uid()) = buyer_id or (select auth.uid()) = seller_id
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'delivery_profiles'
  ) then
    create policy "Users can read own delivery profile"
      on public.delivery_profiles for select to authenticated
      using ((select auth.uid()) = user_id);
    create policy "Users can insert own delivery profile"
      on public.delivery_profiles for insert to authenticated
      with check ((select auth.uid()) = user_id);
    create policy "Users can update own delivery profile"
      on public.delivery_profiles for update to authenticated
      using ((select auth.uid()) = user_id)
      with check ((select auth.uid()) = user_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'seller_reviews'
  ) then
    create policy "Authenticated users can read seller reviews"
      on public.seller_reviews for select to authenticated using (true);
    create policy "Buyers can create seller reviews"
      on public.seller_reviews for insert to authenticated
      with check (
        (select auth.uid()) = buyer_id and buyer_id <> seller_id
      );
    create policy "Buyers can update own seller reviews"
      on public.seller_reviews for update to authenticated
      using ((select auth.uid()) = buyer_id)
      with check ((select auth.uid()) = buyer_id);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'outfit_accessories'
  ) then
    create policy "Readable outfit accessories"
      on public.outfit_accessories for select
      using (scope = 'default' or (select auth.uid()) = owner_id);
    create policy "Authenticated users can create outfit accessories"
      on public.outfit_accessories for insert to authenticated
      with check (scope = 'private' and (select auth.uid()) = owner_id);
    create policy "Users can update their outfit accessories"
      on public.outfit_accessories for update to authenticated
      using ((select auth.uid()) = owner_id)
      with check (scope = 'private' and (select auth.uid()) = owner_id);
    create policy "Users can delete their outfit accessories"
      on public.outfit_accessories for delete to authenticated
      using (scope = 'private' and (select auth.uid()) = owner_id);
  end if;
end
$$;

grant select on public.profiles, public.outfits, public.outfit_accessories
  to anon, authenticated;
grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;
grant insert, update, delete on public.outfits to authenticated;
grant insert, update on public.profiles, public.profile_private_details,
  public.delivery_profiles, public.seller_reviews to authenticated;
grant select on public.profile_private_details, public.delivery_profiles,
  public.seller_reviews to authenticated;
grant select, insert, update, delete on public.product_favorites,
  public.outfit_favorites, public.outfit_accessories to authenticated;
grant select, insert, update on public.message_threads to authenticated;

notify pgrst, 'reload schema';
