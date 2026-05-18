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
  seller_name text not null,
  product_title text not null,
  last_message text not null,
  unread_count integer not null default 0,
  messages jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.message_threads enable row level security;

drop policy if exists "Authenticated users can manage threads" on public.message_threads;
create policy "Authenticated users can manage threads"
  on public.message_threads for all
  to authenticated
  using (true)
  with check (true);
