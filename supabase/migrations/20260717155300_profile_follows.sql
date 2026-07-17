-- Durable seller subscriptions shared by product cards and seller profiles.

begin;

create table if not exists public.profile_follows (
  follower_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, seller_id),
  constraint profile_follows_not_self check (follower_id <> seller_id)
);

create index if not exists profile_follows_seller_created_idx
  on public.profile_follows (seller_id, created_at desc);

alter table public.profile_follows enable row level security;

drop policy if exists "Participants can read profile follows"
  on public.profile_follows;
create policy "Participants can read profile follows"
  on public.profile_follows for select
  to authenticated
  using ((select auth.uid()) in (follower_id, seller_id));

drop policy if exists "Users can follow sellers"
  on public.profile_follows;
create policy "Users can follow sellers"
  on public.profile_follows for insert
  to authenticated
  with check (
    (select auth.uid()) = follower_id
    and follower_id <> seller_id
  );

drop policy if exists "Users can unfollow sellers"
  on public.profile_follows;
create policy "Users can unfollow sellers"
  on public.profile_follows for delete
  to authenticated
  using ((select auth.uid()) = follower_id);

grant select, insert, delete on public.profile_follows to authenticated;

create or replace function public.refresh_profile_followers_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  affected_seller_id uuid;
begin
  affected_seller_id := case
    when tg_op = 'DELETE' then old.seller_id
    else new.seller_id
  end;
  update public.profiles profile
  set followers_count = (
    select count(*)::integer
    from public.profile_follows follow
    where follow.seller_id = affected_seller_id
  )
  where profile.id = affected_seller_id;
  return null;
end;
$$;

revoke all on function public.refresh_profile_followers_count() from public;

drop trigger if exists refresh_profile_followers_count
  on public.profile_follows;
create trigger refresh_profile_followers_count
after insert or delete on public.profile_follows
for each row execute function public.refresh_profile_followers_count();

update public.profiles profile
set followers_count = (
  select count(*)::integer
  from public.profile_follows follow
  where follow.seller_id = profile.id
);

notify pgrst, 'reload schema';

commit;
