-- Make non-listing media owner-scoped and make outfit publication an
-- explicit server command. Uploads happen only after an owned draft row
-- exists; a draft and all of its objects stay private until finalize succeeds.

begin;

alter table public.outfits
  add column if not exists publication_status text not null default 'draft',
  add column if not exists published_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

-- Rows created before the draft command were immediately public.
update public.outfits
set publication_status = 'published',
    published_at = coalesce(published_at, created_at),
    updated_at = greatest(updated_at, created_at)
where publication_status = 'draft';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.outfits'::regclass
      and conname = 'outfits_publication_status_check'
  ) then
    alter table public.outfits
      add constraint outfits_publication_status_check
      check (publication_status in ('draft', 'published', 'archived'));
  end if;
end
$$;

alter table public.outfit_accessories
  add column if not exists media_status text not null default 'ready',
  add column if not exists media_updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.outfit_accessories'::regclass
      and conname = 'outfit_accessories_media_status_check'
  ) then
    alter table public.outfit_accessories
      add constraint outfit_accessories_media_status_check
      check (media_status in ('uploading', 'ready'));
  end if;
end
$$;

create index if not exists outfits_publication_owner_idx
  on public.outfits (publication_status, owner_id, created_at desc);

-- Direct client writes could bypass the draft/finalize checks. Metrics workers
-- and service-role moderation retain their normal server-side access.
drop policy if exists "Authenticated users can publish outfits"
  on public.outfits;
drop policy if exists "Users can publish own outfits"
  on public.outfits;
drop policy if exists "Users can update their outfits"
  on public.outfits;
drop policy if exists "Users can delete their outfits"
  on public.outfits;

revoke insert, update, delete on public.outfits from anon, authenticated;
grant select on public.outfits to anon, authenticated;

drop policy if exists "Public outfits are readable" on public.outfits;
create policy "Published outfits are readable"
  on public.outfits for select
  to anon, authenticated
  using (
    owner_id = (select auth.uid())
    or (
      publication_status = 'published'
      and (
        (select auth.uid()) is null
        or owner_id is null
        or not public.users_are_blocked((select auth.uid()), owner_id)
      )
    )
  );

create or replace function public.create_outfit_media_draft(
  p_outfit_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  requested_id uuid := coalesce(p_outfit_id, gen_random_uuid());
  outfit_row public.outfits%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'marketplace_user_not_eligible' using errcode = '42501';
  end if;

  select * into outfit_row
  from public.outfits outfit
  where outfit.id = requested_id
  for update;

  if found then
    if outfit_row.owner_id is distinct from actor_id then
      raise exception 'outfit_owner_mismatch' using errcode = '42501';
    end if;
    if outfit_row.publication_status <> 'draft' then
      raise exception 'outfit_draft_not_editable' using errcode = '55000';
    end if;
    return to_jsonb(outfit_row);
  end if;

  insert into public.outfits (
    id,
    owner_id,
    photos,
    items,
    preview_layout,
    publication_status,
    likes_count,
    views_count,
    created_at,
    updated_at
  )
  values (
    requested_id,
    actor_id,
    '{}'::text[],
    '[]'::jsonb,
    null,
    'draft',
    0,
    0,
    now(),
    now()
  )
  returning * into outfit_row;

  return to_jsonb(outfit_row);
end;
$$;

create or replace function public.finalize_outfit_media_draft(
  p_outfit_id uuid,
  p_photo_paths text[],
  p_items jsonb,
  p_preview_layout jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  outfit_row public.outfits%rowtype;
  photo_count integer := coalesce(cardinality(p_photo_paths), 0);
  storage_uri_prefix constant text := 'storage://outfit-images/';
  canonical_items jsonb;
  canonical_preview_layout jsonb;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'marketplace_user_not_eligible' using errcode = '42501';
  end if;

  select * into outfit_row
  from public.outfits outfit
  where outfit.id = p_outfit_id
  for update;

  if not found then
    raise exception 'outfit_draft_not_found' using errcode = 'P0002';
  end if;
  if outfit_row.owner_id is distinct from actor_id then
    raise exception 'outfit_owner_mismatch' using errcode = '42501';
  end if;
  -- A response lost after commit can be retried without mutating the already
  -- public row or publishing a second outfit.
  if outfit_row.publication_status = 'published' then
    return to_jsonb(outfit_row);
  end if;
  if outfit_row.publication_status <> 'draft' then
    raise exception 'outfit_draft_not_editable' using errcode = '55000';
  end if;

  if photo_count > 10 then
    raise exception 'outfit_photo_count_invalid' using errcode = '22023';
  end if;
  if p_items is null
     or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) not between 1 and 50
     or octet_length(p_items::text) > 524288 then
    raise exception 'outfit_items_invalid' using errcode = '22023';
  end if;
  if p_preview_layout is not null
     and (
       jsonb_typeof(p_preview_layout) <> 'object'
       or octet_length(p_preview_layout::text) > 524288
     ) then
    raise exception 'outfit_preview_invalid' using errcode = '22023';
  end if;

  if (
    select count(distinct photo_path) <> count(*)
    from unnest(coalesce(p_photo_paths, '{}'::text[])) photo_path
  ) then
    raise exception 'outfit_photo_paths_must_be_unique'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_photo_paths, '{}'::text[])) photo_path
    where photo_path is null
       or not photo_path ~ (
         '^' || actor_id::text || '/' || p_outfit_id::text || '/[^/]+$'
       )
       or photo_path like '%\\%'
       or split_part(photo_path, '/', 3) in ('.', '..')
  ) then
    raise exception 'outfit_photo_path_invalid' using errcode = '22023';
  end if;

  if exists (
    select 1
    from unnest(coalesce(p_photo_paths, '{}'::text[])) photo_path
    left join storage.objects stored
      on stored.bucket_id = 'outfit-images'
     and stored.name = photo_path
    where stored.id is null
       or stored.owner_id is distinct from actor_id::text
  ) then
    raise exception 'outfit_photo_object_missing' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) item
    where jsonb_typeof(item) <> 'object'
       or char_length(btrim(coalesce(item ->> 'id', ''))) not between 1 and 200
       or char_length(coalesce(item ->> 'name', '')) > 500
       or char_length(coalesce(item ->> 'price', '')) > 100
       or char_length(coalesce(item ->> 'image', '')) > 2500
       or (
         coalesce(item ->> 'image', '') !~ (
           '^storage://outfit-images/' || actor_id::text || '/' ||
           p_outfit_id::text || '/[^/]+$'
         )
         and not exists (
           select 1
           from public.products product
           where product.id::text = item ->> 'id'
             and product.seller_id = actor_id
             and public.listing_is_public(product.id)
             and coalesce(
               nullif(product.cutout_image, ''),
               nullif(product.outfit_images[1], ''),
               nullif(product.main_image, ''),
               nullif(product.image, ''),
               nullif(product.images[1], ''),
               nullif(product.original_image, '')
             ) is not null
         )
       )
  ) then
    raise exception 'outfit_item_payload_invalid' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(p_items) item
    left join storage.objects stored
      on stored.bucket_id = 'outfit-images'
     and stored.name = substring(
       item ->> 'image' from char_length(storage_uri_prefix) + 1
     )
    where coalesce(item ->> 'image', '') like storage_uri_prefix || '%'
      and (
        stored.id is null
        or stored.owner_id is distinct from actor_id::text
        or stored.name !~ (
          '^' || actor_id::text || '/' || p_outfit_id::text || '/[^/]+$'
        )
      )
  ) then
    raise exception 'outfit_item_media_invalid' using errcode = '22023';
  end if;

  -- Never persist a caller-provided external URL. For catalogue products the
  -- server derives the media reference from an actor-owned public listing;
  -- outfit-only items already point at this draft's verified Storage object.
  select jsonb_agg(
    case
      when item ->> 'image' ~ (
        '^storage://outfit-images/' || actor_id::text || '/' ||
        p_outfit_id::text || '/[^/]+$'
      ) then item
      else jsonb_set(
        item,
        '{image}',
        to_jsonb((
          select coalesce(
            nullif(product.cutout_image, ''),
            nullif(product.outfit_images[1], ''),
            nullif(product.main_image, ''),
            nullif(product.image, ''),
            nullif(product.images[1], ''),
            nullif(product.original_image, '')
          )
          from public.products product
          where product.id::text = item ->> 'id'
            and product.seller_id = actor_id
            and public.listing_is_public(product.id)
          limit 1
        )),
        true
      )
    end
    order by ordinal
  ) into canonical_items
  from jsonb_array_elements(p_items) with ordinality uploaded(item, ordinal);

  if p_preview_layout is not null
     and jsonb_typeof(coalesce(p_preview_layout -> 'items', '[]'::jsonb))
       <> 'array' then
    raise exception 'outfit_preview_items_invalid' using errcode = '22023';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(
      coalesce(p_preview_layout -> 'items', '[]'::jsonb)
    ) preview_item
    where jsonb_typeof(preview_item) <> 'object'
       or not exists (
         select 1
         from jsonb_array_elements(p_items) item
         where item ->> 'image' = preview_item ->> 'image'
       )
  ) then
    raise exception 'outfit_preview_media_invalid' using errcode = '22023';
  end if;

  if p_preview_layout is null then
    canonical_preview_layout := null;
  else
    select jsonb_set(
      p_preview_layout,
      '{items}',
      coalesce(
        (
          select jsonb_agg(
            jsonb_set(
              preview_item,
              '{image}',
              to_jsonb((
                select canonical_source.value ->> 'image'
                from jsonb_array_elements(p_items)
                  with ordinality original_item(item, ordinal)
                join jsonb_array_elements(canonical_items)
                  with ordinality canonical_source(value, canonical_ordinal)
                  on canonical_source.canonical_ordinal =
                    original_item.ordinal
                where original_item.item ->> 'image' =
                  preview_item ->> 'image'
                limit 1
              )),
              true
            )
            order by preview_ordinal
          )
          from jsonb_array_elements(p_preview_layout -> 'items')
            with ordinality preview(preview_item, preview_ordinal)
        ),
        '[]'::jsonb
      ),
      true
    ) into canonical_preview_layout;
  end if;

  update public.outfits
  set photos = coalesce(
        (
          select array_agg(storage_uri_prefix || photo_path order by ordinal)
          from unnest(coalesce(p_photo_paths, '{}'::text[]))
            with ordinality uploaded(photo_path, ordinal)
        ),
        '{}'::text[]
      ),
      items = canonical_items,
      preview_layout = canonical_preview_layout,
      publication_status = 'published',
      published_at = now(),
      updated_at = now()
  where id = p_outfit_id
  returning * into outfit_row;

  return to_jsonb(outfit_row);
end;
$$;

create or replace function public.abort_outfit_media_draft(
  p_outfit_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = 'outfit-images'
      and split_part(stored.name, '/', 1) = actor_id::text
      and split_part(stored.name, '/', 2) = p_outfit_id::text
  ) then
    return false;
  end if;
  delete from public.outfits outfit
  where outfit.id = p_outfit_id
    and outfit.owner_id = actor_id
    and outfit.publication_status = 'draft';
  return found;
end;
$$;

-- Private accessories also get a row before Storage sees an upload. The row
-- starts unusable and can only be finalized with an object owned by the JWT
-- actor in the canonical accessory namespace.
drop policy if exists "Authenticated users can create outfit accessories"
  on public.outfit_accessories;
drop policy if exists "Users can update their outfit accessories"
  on public.outfit_accessories;
drop policy if exists "Users can delete their outfit accessories"
  on public.outfit_accessories;
revoke insert, update, delete on public.outfit_accessories
  from anon, authenticated;
grant select on public.outfit_accessories to anon, authenticated;

create or replace function public.create_private_outfit_accessory(
  p_accessory_id uuid default null,
  p_title text default 'Аксессуар'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  requested_id uuid := coalesce(p_accessory_id, gen_random_uuid());
  clean_title text := btrim(coalesce(p_title, ''));
  accessory_row public.outfit_accessories%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'marketplace_user_not_eligible' using errcode = '42501';
  end if;
  if char_length(clean_title) not between 1 and 120 then
    raise exception 'accessory_title_invalid' using errcode = '22023';
  end if;

  select * into accessory_row
  from public.outfit_accessories accessory
  where accessory.id = requested_id
  for update;

  if found then
    if accessory_row.owner_id is distinct from actor_id
       or accessory_row.scope <> 'private' then
      raise exception 'accessory_owner_mismatch' using errcode = '42501';
    end if;
    if accessory_row.media_status <> 'uploading'
       or accessory_row.original_image <> '' then
      raise exception 'accessory_draft_not_editable' using errcode = '55000';
    end if;
    return to_jsonb(accessory_row);
  end if;

  insert into public.outfit_accessories (
    id,
    title,
    scope,
    owner_id,
    original_image,
    cutout_image,
    background_status,
    background_error,
    media_status,
    media_updated_at,
    created_at
  )
  values (
    requested_id,
    clean_title,
    'private',
    actor_id,
    '',
    null,
    'queued',
    null,
    'uploading',
    now(),
    now()
  )
  returning * into accessory_row;
  return to_jsonb(accessory_row);
end;
$$;

create or replace function public.finalize_private_outfit_accessory(
  p_accessory_id uuid,
  p_storage_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  accessory_row public.outfit_accessories%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'marketplace_user_not_eligible' using errcode = '42501';
  end if;

  select * into accessory_row
  from public.outfit_accessories accessory
  where accessory.id = p_accessory_id
  for update;

  if not found then
    raise exception 'accessory_draft_not_found' using errcode = 'P0002';
  end if;
  if accessory_row.owner_id is distinct from actor_id
     or accessory_row.scope <> 'private' then
    raise exception 'accessory_owner_mismatch' using errcode = '42501';
  end if;
  if accessory_row.media_status = 'ready'
     and accessory_row.original_image =
       'storage://accessory-images/' || p_storage_path then
    return to_jsonb(accessory_row);
  end if;
  if accessory_row.media_status <> 'uploading'
     or accessory_row.original_image <> '' then
    raise exception 'accessory_draft_not_editable' using errcode = '55000';
  end if;
  if p_storage_path is null
     or p_storage_path !~ (
       '^' || actor_id::text || '/' || p_accessory_id::text || '/[^/]+$'
     )
     or p_storage_path like '%\\%'
     or split_part(p_storage_path, '/', 3) in ('.', '..') then
    raise exception 'accessory_storage_path_invalid' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = 'accessory-images'
      and stored.name = p_storage_path
      and stored.owner_id = actor_id::text
  ) then
    raise exception 'accessory_storage_object_missing' using errcode = '22023';
  end if;

  update public.outfit_accessories
  set original_image = 'storage://accessory-images/' || p_storage_path,
      media_status = 'ready',
      media_updated_at = now(),
      background_status = 'queued',
      background_error = null
  where id = p_accessory_id
  returning * into accessory_row;
  return to_jsonb(accessory_row);
end;
$$;

create or replace function public.abort_private_outfit_accessory(
  p_accessory_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = 'accessory-images'
      and split_part(stored.name, '/', 1) = actor_id::text
      and split_part(stored.name, '/', 2) = p_accessory_id::text
  ) then
    return false;
  end if;
  delete from public.outfit_accessories accessory
  where accessory.id = p_accessory_id
    and accessory.owner_id = actor_id
    and accessory.scope = 'private'
    and accessory.media_status = 'uploading'
    and accessory.original_image = '';
  return found;
end;
$$;

revoke all on function public.create_outfit_media_draft(uuid)
  from public, anon;
revoke all on function public.finalize_outfit_media_draft(
  uuid, text[], jsonb, jsonb
) from public, anon;
revoke all on function public.abort_outfit_media_draft(uuid)
  from public, anon;
revoke all on function public.create_private_outfit_accessory(uuid, text)
  from public, anon;
revoke all on function public.finalize_private_outfit_accessory(uuid, text)
  from public, anon;
revoke all on function public.abort_private_outfit_accessory(uuid)
  from public, anon;

grant execute on function public.create_outfit_media_draft(uuid)
  to authenticated;
grant execute on function public.finalize_outfit_media_draft(
  uuid, text[], jsonb, jsonb
) to authenticated;
grant execute on function public.abort_outfit_media_draft(uuid)
  to authenticated;
grant execute on function public.create_private_outfit_accessory(uuid, text)
  to authenticated;
grant execute on function public.finalize_private_outfit_accessory(uuid, text)
  to authenticated;
grant execute on function public.abort_private_outfit_accessory(uuid)
  to authenticated;

-- A public bucket bypasses object SELECT RLS. Keep outfit media private and
-- issue signed URLs only when the finalized outfit policy says it is readable.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'outfit-images',
  'outfit-images',
  false,
  15728640,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

create or replace function public.outfit_media_is_readable(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.outfits outfit
    where outfit.id::text = split_part(p_storage_path, '/', 2)
      and split_part(p_storage_path, '/', 1) = outfit.owner_id::text
      and outfit.publication_status = 'published'
      and (
        'storage://outfit-images/' || p_storage_path = any(outfit.photos)
        or exists (
          select 1
          from jsonb_array_elements(
            case
              when jsonb_typeof(outfit.items) = 'array' then outfit.items
              else '[]'::jsonb
            end
          ) item
          where item ->> 'image' =
            'storage://outfit-images/' || p_storage_path
        )
        or exists (
          select 1
          from jsonb_array_elements(
            case
              when jsonb_typeof(outfit.preview_layout -> 'items') = 'array'
                then outfit.preview_layout -> 'items'
              else '[]'::jsonb
            end
          ) preview_item
          where preview_item ->> 'image' =
            'storage://outfit-images/' || p_storage_path
        )
      )
      and (
        auth.uid() is null
        or outfit.owner_id = auth.uid()
        or not public.users_are_blocked(auth.uid(), outfit.owner_id)
      )
  );
$$;

revoke all on function public.outfit_media_is_readable(text) from public;
grant execute on function public.outfit_media_is_readable(text)
  to anon, authenticated, service_role;

drop policy if exists "Owners manage profile images" on storage.objects;
drop policy if exists "Owners upload profile avatars" on storage.objects;
create policy "Owners upload profile avatars"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) || '/avatar/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
  );

drop policy if exists "Owners delete profile avatars" on storage.objects;
create policy "Owners delete profile avatars"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'profile-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) || '/avatar/[^/]+$'
    )
  );

-- UUID filenames are immutable: replacing bytes at a published URL is never
-- permitted. Draft owners may upload/remove, and may read their own drafts.
drop policy if exists "Owners manage outfit images" on storage.objects;
drop policy if exists "Outfit owners upload draft images" on storage.objects;
create policy "Outfit owners upload draft images"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'outfit-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
    and exists (
      select 1
      from public.outfits outfit
      where outfit.id::text = split_part(name, '/', 2)
        and outfit.owner_id = (select auth.uid())
        and outfit.publication_status = 'draft'
    )
  );

drop policy if exists "Outfit owners delete draft images" on storage.objects;
create policy "Outfit owners delete draft images"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'outfit-images'
    and owner_id = (select auth.uid()::text)
    and exists (
      select 1
      from public.outfits outfit
      where outfit.id::text = split_part(name, '/', 2)
        and outfit.owner_id = (select auth.uid())
        and outfit.publication_status = 'draft'
    )
  );

drop policy if exists "Outfit owners read own images" on storage.objects;
create policy "Outfit owners read own images"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'outfit-images'
    and owner_id = (select auth.uid()::text)
    and split_part(name, '/', 1) = (select auth.uid()::text)
  );

drop policy if exists "Published outfit images are readable"
  on storage.objects;
create policy "Published outfit images are readable"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'outfit-images'
    and public.outfit_media_is_readable(name)
  );

drop policy if exists "Owners manage private accessory images"
  on storage.objects;
drop policy if exists "Owners read private accessory images"
  on storage.objects;
drop policy if exists "Accessory media are readable" on storage.objects;
create policy "Accessory media are readable"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'accessory-images'
    and exists (
      select 1
      from public.outfit_accessories accessory
      where accessory.id::text = split_part(name, '/', 2)
        and split_part(name, '/', 1) = accessory.owner_id::text
        and (
          accessory.owner_id = (select auth.uid())
          or (
            accessory.scope = 'default'
            and accessory.media_status = 'ready'
            and (
              accessory.original_image =
                'storage://accessory-images/' || name
              or accessory.cutout_image = name
              or accessory.cutout_image =
                'storage://accessory-images/' || name
            )
          )
        )
    )
  );

drop policy if exists "Owners upload private accessory drafts"
  on storage.objects;
create policy "Owners upload private accessory drafts"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'accessory-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
    and exists (
      select 1
      from public.outfit_accessories accessory
      where accessory.id::text = split_part(name, '/', 2)
        and accessory.owner_id = (select auth.uid())
        and accessory.scope = 'private'
        and accessory.media_status = 'uploading'
        and accessory.original_image = ''
    )
  );

drop policy if exists "Owners delete private accessory drafts"
  on storage.objects;
create policy "Owners delete private accessory drafts"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'accessory-images'
    and owner_id = (select auth.uid()::text)
    and exists (
      select 1
      from public.outfit_accessories accessory
      where accessory.id::text = split_part(name, '/', 2)
        and accessory.owner_id = (select auth.uid())
        and accessory.scope = 'private'
        and accessory.media_status = 'uploading'
        and accessory.original_image = ''
    )
  );

-- Final/public listing media are written only by the authoritative listing
-- command. Re-drop all legacy generic product-images writers defensively.
drop policy if exists "Authenticated users can upload product images"
  on storage.objects;
drop policy if exists "Authenticated users can update product images"
  on storage.objects;
drop policy if exists "Owners can upload product media" on storage.objects;
drop policy if exists "Owners can update product media" on storage.objects;
drop policy if exists "Owners can delete product media" on storage.objects;
drop policy if exists "Owners can upload listing images" on storage.objects;
drop policy if exists "Owners can update listing images" on storage.objects;
drop policy if exists "Owners can delete listing images" on storage.objects;

notify pgrst, 'reload schema';

commit;
