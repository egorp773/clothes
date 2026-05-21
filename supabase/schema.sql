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

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  handle text not null unique,
  avatar_url text not null default '',
  city text not null default 'Москва',
  rating numeric not null default 4.8,
  sales_count integer not null default 0,
  followers_count integer not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

alter table public.profiles
  add column if not exists avatar_url text not null default '',
  add column if not exists followers_count integer not null default 0;

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

create table if not exists public.outfits (
  id uuid primary key,
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
  add column if not exists likes_count integer not null default 0,
  add column if not exists preview_layout jsonb;

alter table public.outfits enable row level security;

drop policy if exists "Public outfits are readable" on public.outfits;
create policy "Public outfits are readable"
  on public.outfits for select
  using (true);

drop policy if exists "Authenticated users can publish outfits" on public.outfits;
create policy "Authenticated users can publish outfits"
  on public.outfits for insert
  to authenticated
  with check (true);

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
