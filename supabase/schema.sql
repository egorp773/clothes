-- Apply in Supabase SQL Editor if you want outfits and chats persisted remotely.
-- The app already works with the existing public.products table and product-images bucket.

alter table public.products
  add column if not exists original_image text,
  add column if not exists cutout_image text,
  add column if not exists outfit_images text[] not null default '{}',
  add column if not exists is_hidden boolean not null default false,
  add column if not exists seller_id uuid references auth.users(id) on delete set null,
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

create table if not exists public.outfits (
  id uuid primary key,
  owner_id uuid references auth.users(id) on delete set null,
  author_name text not null default 'Автор',
  author_handle text not null default '@user',
  photos text[] not null default '{}',
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.outfits
  add column if not exists owner_id uuid references auth.users(id) on delete set null,
  add column if not exists author_name text not null default 'Автор',
  add column if not exists author_handle text not null default '@user';

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

create table if not exists public.message_threads (
  id text primary key,
  buyer_id uuid references auth.users(id) on delete cascade,
  seller_id uuid references auth.users(id) on delete cascade,
  product_id text,
  seller_name text not null,
  buyer_name text not null default 'Покупатель',
  product_title text not null,
  product_image text not null default '',
  last_message text not null,
  unread_count integer not null default 0,
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.message_threads
  add column if not exists buyer_id uuid references auth.users(id) on delete cascade,
  add column if not exists seller_id uuid references auth.users(id) on delete cascade,
  add column if not exists product_id text,
  add column if not exists buyer_name text not null default 'Покупатель',
  add column if not exists product_image text not null default '';

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
