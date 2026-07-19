-- Seller rating is a server-owned aggregate. Client profile updates must not
-- be able to invent it or race another review submission.
alter table public.profiles
  alter column rating set default 0,
  add column if not exists review_count integer not null default 0;

create or replace function public.refresh_profile_review_rating(
  p_seller_id uuid
)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.profiles profile
  set
    rating = aggregate.rating,
    review_count = aggregate.review_count,
    updated_at = now()
  from (
    select
      coalesce(avg(review.rating), 0)::numeric as rating,
      count(review.id)::integer as review_count
    from public.seller_reviews review
    where review.seller_id = p_seller_id
  ) aggregate
  where profile.id = p_seller_id;
$$;

revoke all on function public.refresh_profile_review_rating(uuid) from public;

create or replace function public.sync_profile_review_rating()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    perform public.refresh_profile_review_rating(old.seller_id);
  end if;
  if tg_op in ('INSERT', 'UPDATE')
     and (tg_op <> 'UPDATE' or new.seller_id is distinct from old.seller_id
          or new.rating is distinct from old.rating) then
    perform public.refresh_profile_review_rating(new.seller_id);
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.sync_profile_review_rating() from public;

drop trigger if exists sync_profile_review_rating_after_change
  on public.seller_reviews;
create trigger sync_profile_review_rating_after_change
after insert or update of seller_id, rating or delete
on public.seller_reviews
for each row execute function public.sync_profile_review_rating();

update public.profiles profile
set
  rating = aggregate.rating,
  review_count = aggregate.review_count
from (
  select
    profile_row.id,
    coalesce(avg(review.rating), 0)::numeric as rating,
    count(review.id)::integer as review_count
  from public.profiles profile_row
  left join public.seller_reviews review on review.seller_id = profile_row.id
  group by profile_row.id
) aggregate
where profile.id = aggregate.id;

notify pgrst, 'reload schema';
