-- Keep outfit author identity complete and renderable everywhere. The server,
-- not the client payload, owns the public author snapshot.

alter table public.outfits
  add column if not exists author_avatar_url text not null default '';

update public.outfits outfit
set
  author_name = coalesce(nullif(profile.name, ''), outfit.author_name),
  author_handle = coalesce(nullif(profile.handle, ''), outfit.author_handle),
  author_avatar_url = coalesce(profile.avatar_url, '')
from public.profiles profile
where profile.id = outfit.owner_id;

-- Legacy rows without a surviving profile must not retain client-provided
-- identity text indefinitely. Keep the UGC but remove spoofable attribution.
update public.outfits outfit
set
  author_name = 'Автор',
  author_handle = '@user',
  author_avatar_url = ''
where not exists (
  select 1
  from public.profiles profile
  where profile.id = outfit.owner_id
);

create or replace function public.hydrate_outfit_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  current_author_id uuid;
  author_profile public.profiles%rowtype;
begin
  if tg_op = 'INSERT' then
    current_author_id := auth.uid();
    if current_author_id is null then
      raise exception 'authentication_required' using errcode = '42501';
    end if;
    if new.owner_id is null then
      new.owner_id := current_author_id;
    end if;
    if new.owner_id <> current_author_id then
      raise exception 'outfit_owner_mismatch' using errcode = '42501';
    end if;
  else
    current_author_id := new.owner_id;
    if current_author_id is null then
      new.author_name := old.author_name;
      new.author_handle := old.author_handle;
      new.author_avatar_url := old.author_avatar_url;
      return new;
    end if;
  end if;

  select * into author_profile
  from public.profiles
  where id = current_author_id;

  if found then
    new.author_name := coalesce(nullif(author_profile.name, ''), 'Автор');
    new.author_handle := coalesce(nullif(author_profile.handle, ''), '@user');
    new.author_avatar_url := coalesce(author_profile.avatar_url, '');
  elsif tg_op = 'INSERT' then
    new.author_name := 'Автор';
    new.author_handle := '@user';
    new.author_avatar_url := '';
  else
    new.author_name := old.author_name;
    new.author_handle := old.author_handle;
    new.author_avatar_url := old.author_avatar_url;
  end if;
  return new;
end;
$$;

drop trigger if exists hydrate_outfit_author_before_write on public.outfits;
create trigger hydrate_outfit_author_before_write
before insert or update of author_name, author_handle, author_avatar_url
on public.outfits
for each row execute function public.hydrate_outfit_author();

drop policy if exists "Authenticated users can publish outfits"
  on public.outfits;
create policy "Users can publish own outfits"
  on public.outfits for insert to authenticated
  with check (auth.uid() = owner_id);

create or replace function public.sync_profile_to_outfits()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.outfits
  set
    author_name = coalesce(nullif(new.name, ''), 'Автор'),
    author_handle = coalesce(nullif(new.handle, ''), '@user'),
    author_avatar_url = coalesce(new.avatar_url, '')
  where owner_id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_profile_to_outfits_after_update
  on public.profiles;
create trigger sync_profile_to_outfits_after_update
after update of name, handle, avatar_url on public.profiles
for each row execute function public.sync_profile_to_outfits();

notify pgrst, 'reload schema';
