alter table public.products
  add column if not exists views_count integer not null default 0,
  add column if not exists likes_count integer not null default 0;

create table if not exists public.product_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table if not exists public.recent_products (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id text not null,
  viewed_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create unique index if not exists product_favorites_user_product_idx
  on public.product_favorites (user_id, product_id);
create unique index if not exists recent_products_user_product_idx
  on public.recent_products (user_id, product_id);

alter table public.product_favorites enable row level security;
alter table public.recent_products enable row level security;

drop policy if exists "Users can manage product favorites"
  on public.product_favorites;
create policy "Users can manage product favorites"
  on public.product_favorites for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can manage recent products"
  on public.recent_products;
create policy "Users can manage recent products"
  on public.recent_products for all to authenticated
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

notify pgrst, 'reload schema';
