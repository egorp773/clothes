-- One verified review per buyer and product, only after a completed order.

begin;

-- Some legacy projects were baselined with `migration repair` before this
-- optional profile feature existed. Keep the hardening migration additive so
-- those projects receive the table instead of failing the whole release push.
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

create index if not exists seller_reviews_seller_created_idx
  on public.seller_reviews (seller_id, created_at desc);

drop policy if exists "Authenticated users can read seller reviews"
  on public.seller_reviews;
create policy "Authenticated users can read seller reviews"
  on public.seller_reviews for select
  to authenticated
  using (true);

grant select, insert, update on public.seller_reviews to authenticated;

alter table public.seller_reviews
  alter column id set default gen_random_uuid();

-- Historical clients could insert the same buyer/product pair repeatedly.
-- Keep the latest row before adding the unique contract.
with ranked_reviews as (
  select
    id,
    row_number() over (
      partition by buyer_id, product_id
      order by created_at desc, id desc
    ) as duplicate_rank
  from public.seller_reviews
)
delete from public.seller_reviews as review
using ranked_reviews as ranked
where review.id = ranked.id
  and ranked.duplicate_rank > 1;

create unique index if not exists seller_reviews_buyer_product_unique_idx
  on public.seller_reviews (buyer_id, product_id);

drop policy if exists "Buyers can create seller reviews"
  on public.seller_reviews;
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
        and completed_order.product_id = seller_reviews.product_id
        and completed_order.status = 'completed'
    )
  );

drop policy if exists "Buyers can update own seller reviews"
  on public.seller_reviews;
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
        and completed_order.product_id = seller_reviews.product_id
        and completed_order.status = 'completed'
    )
  );

notify pgrst, 'reload schema';

commit;
