begin;

alter table public.profile_private_details enable row level security;

drop policy if exists "Users read own private profile details"
  on public.profile_private_details;
create policy "Users read own private profile details"
  on public.profile_private_details
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users insert own private profile details"
  on public.profile_private_details;
create policy "Users insert own private profile details"
  on public.profile_private_details
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users update own private profile details"
  on public.profile_private_details;
create policy "Users update own private profile details"
  on public.profile_private_details
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

commit;
