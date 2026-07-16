alter table public.outfits
  add column if not exists views_count integer not null default 0;

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

create or replace function public.sync_outfit_views_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    update public.outfits
      set views_count = views_count + 1
      where id = new.outfit_id;
    return new;
  end if;

  if tg_op = 'DELETE' then
    update public.outfits
      set views_count = greatest(views_count - 1, 0)
      where id = old.outfit_id;
    return old;
  end if;

  return null;
end;
$$;

drop trigger if exists sync_outfit_views_count_insert on public.recent_outfits;
create trigger sync_outfit_views_count_insert
after insert on public.recent_outfits
for each row execute function public.sync_outfit_views_count();

-- A historical view must not disappear when history is cleaned up or a viewer
-- removes their account. Only first inserts increase the public counter.
drop trigger if exists sync_outfit_views_count_delete on public.recent_outfits;

update public.outfits
set views_count = greatest(public.outfits.views_count, counts.total)
from (
  select outfit_id, count(*)::integer as total
  from public.recent_outfits
  group by outfit_id
) counts
where public.outfits.id = counts.outfit_id;

create or replace function public.record_outfit_view(p_outfit_id uuid)
returns table(views_count integer, first_view boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_id uuid := auth.uid();
  inserted_rows integer := 0;
  authoritative_count integer := 0;
begin
  if viewer_id is null then
    raise exception 'Authentication is required' using errcode = '42501';
  end if;

  insert into public.recent_outfits (user_id, outfit_id, viewed_at)
  values (viewer_id, p_outfit_id, now())
  on conflict (user_id, outfit_id) do nothing;
  get diagnostics inserted_rows = row_count;

  if inserted_rows = 0 then
    update public.recent_outfits
      set viewed_at = now()
      where user_id = viewer_id and outfit_id = p_outfit_id;
  end if;

  select greatest(coalesce(outfits.views_count, 0), 0)
    into authoritative_count
    from public.outfits
    where outfits.id = p_outfit_id;

  if not found then
    raise exception 'Outfit not found' using errcode = 'P0002';
  end if;

  return query select authoritative_count, inserted_rows > 0;
end;
$$;

revoke all on function public.record_outfit_view(uuid) from public;
grant execute on function public.record_outfit_view(uuid) to authenticated;

notify pgrst, 'reload schema';
