-- Durable order workflow for buyer checkout and participant order history.

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
  delivery_service text not null default 'Почта России',
  delivery_address text not null default '',
  recipient_name text not null default '',
  recipient_phone text not null default '',
  recipient_email text not null default '',
  delivery_price integer not null default 0,
  status text not null default 'pendingConfirmation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Keep the migration safe for installations where an early orders table
-- already exists with only part of the checkout payload.
alter table public.orders
  add column if not exists product_id text not null default '',
  add column if not exists product_title text not null default '',
  add column if not exists product_image text not null default '',
  add column if not exists product_price text not null default '',
  add column if not exists product_price_value integer not null default 0,
  add column if not exists seller_id uuid,
  add column if not exists buyer_id uuid,
  add column if not exists tracking_number text not null default '',
  add column if not exists delivery_service text not null default 'Почта России',
  add column if not exists delivery_address text not null default '',
  add column if not exists recipient_name text not null default '',
  add column if not exists recipient_phone text not null default '',
  add column if not exists recipient_email text not null default '',
  add column if not exists delivery_price integer not null default 0,
  add column if not exists status text not null default 'pendingConfirmation',
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.orders
  alter column product_id set not null,
  alter column product_title set not null,
  alter column buyer_id set not null,
  alter column seller_id drop not null,
  drop constraint if exists orders_buyer_id_fkey,
  drop constraint if exists orders_seller_id_fkey;

alter table public.orders
  add constraint orders_buyer_id_fkey
    foreign key (buyer_id) references auth.users(id) on delete cascade,
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

notify pgrst, 'reload schema';
