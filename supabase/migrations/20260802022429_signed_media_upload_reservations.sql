-- Service-signed Storage uploads bypass client INSERT policies by design.
-- Reserve every canonical path first so concurrent requests keep the original
-- per-resource limits and abandoned grants stay bounded.

begin;

create table if not exists public.signed_media_upload_reservations (
  bucket text not null,
  object_path text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  resource_id text not null,
  content_type text not null,
  size_bytes bigint not null check (size_bytes > 0),
  status text not null default 'prepared'
    check (status in ('prepared', 'claimed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  claimed_at timestamptz,
  primary key (bucket, object_path)
);

create index if not exists signed_media_upload_reservations_rate_idx
  on public.signed_media_upload_reservations (
    user_id, bucket, created_at desc
  );
create index if not exists signed_media_upload_reservations_scope_idx
  on public.signed_media_upload_reservations (
    user_id, bucket, resource_id, status, expires_at
  );

alter table public.signed_media_upload_reservations enable row level security;
revoke all on table public.signed_media_upload_reservations
  from public, anon, authenticated;

create or replace function public.reserve_signed_media_upload(
  p_user_id uuid,
  p_bucket text,
  p_storage_path text,
  p_resource_id text,
  p_content_type text,
  p_size_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_grant public.signed_media_upload_reservations%rowtype;
  scope_prefix text;
  rate_limit integer;
  capacity_limit integer;
  used_capacity integer;
  object_exists boolean;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_active(p_user_id) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;
  if p_storage_path is null
     or char_length(p_storage_path) not between 1 and 512
     or p_resource_id is null
     or char_length(p_resource_id) not between 1 and 256
     or p_content_type is null
     or char_length(p_content_type) not between 1 and 64
     or p_size_bytes is null
     or p_size_bytes < 1 then
    raise exception 'upload_reservation_invalid' using errcode = '22023';
  end if;

  case p_bucket
    when 'profile-images' then
      scope_prefix := p_user_id::text || '/avatar/';
      rate_limit := 20;
      capacity_limit := 50;
    when 'listing-drafts' then
      scope_prefix := p_user_id::text || '/' || p_resource_id || '/';
      rate_limit := 64;
      capacity_limit := 8;
    when 'outfit-images' then
      scope_prefix := p_user_id::text || '/' || p_resource_id || '/';
      rate_limit := 120;
      capacity_limit := 30;
    when 'accessory-images' then
      scope_prefix := p_user_id::text || '/' || p_resource_id || '/';
      rate_limit := 30;
      capacity_limit := 1;
    when 'dispute-evidence' then
      scope_prefix := p_user_id::text || '/' || p_resource_id || '/';
      rate_limit := 30;
      capacity_limit := 25;
    when 'chat-media' then
      scope_prefix := 'threads/' || p_resource_id || '/' || p_user_id::text || '/';
      rate_limit := 120;
      capacity_limit := 500;
    else
      raise exception 'upload_bucket_not_allowed' using errcode = '22023';
  end case;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      p_user_id::text || chr(31) || p_bucket || chr(31) || p_resource_id,
      0
    )
  );

  select * into existing_grant
  from public.signed_media_upload_reservations grant_row
  where grant_row.bucket = p_bucket
    and grant_row.object_path = p_storage_path
  for update;

  if found then
    if existing_grant.user_id is distinct from p_user_id
       or existing_grant.resource_id is distinct from p_resource_id
       or existing_grant.content_type is distinct from p_content_type
       or existing_grant.size_bytes is distinct from p_size_bytes then
      raise exception 'upload_reservation_conflict' using errcode = '23505';
    end if;
    if existing_grant.status = 'claimed'
       or existing_grant.expires_at > now() then
      return jsonb_build_object(
        'reserved', true,
        'reused', true,
        'expires_at', existing_grant.expires_at
      );
    end if;
  end if;

  if (
    select count(*)
    from public.signed_media_upload_reservations recent
    where recent.user_id = p_user_id
      and recent.bucket = p_bucket
      and recent.object_path <> p_storage_path
      and recent.created_at > now() - interval '1 hour'
  ) >= rate_limit then
    raise exception 'media_upload_rate_limited' using errcode = '54000';
  end if;

  select exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = p_bucket
      and stored.name = p_storage_path
  ) into object_exists;

  if not object_exists then
    select count(*) into used_capacity
    from (
      select stored.name as object_path
      from storage.objects stored
      where stored.bucket_id = p_bucket
        and stored.name like scope_prefix || '%'
      union
      select pending.object_path
      from public.signed_media_upload_reservations pending
      where pending.user_id = p_user_id
        and pending.bucket = p_bucket
        and pending.resource_id = p_resource_id
        and pending.status = 'prepared'
        and pending.expires_at > now()
    ) occupied;
    if used_capacity >= capacity_limit then
      raise exception 'media_upload_capacity_reached' using errcode = '54000';
    end if;

    if p_bucket = 'chat-media' then
      select count(*) into used_capacity
      from (
        select stored.name as object_path
        from storage.objects stored
        where stored.bucket_id = 'chat-media'
          and split_part(stored.name, '/', 3) = p_user_id::text
        union
        select pending.object_path
        from public.signed_media_upload_reservations pending
        where pending.user_id = p_user_id
          and pending.bucket = 'chat-media'
          and pending.status = 'prepared'
          and pending.expires_at > now()
      ) occupied;
      if used_capacity >= 5000 then
        raise exception 'media_upload_capacity_reached' using errcode = '54000';
      end if;
    end if;
  end if;

  insert into public.signed_media_upload_reservations (
    bucket,
    object_path,
    user_id,
    resource_id,
    content_type,
    size_bytes,
    status,
    created_at,
    expires_at,
    claimed_at
  ) values (
    p_bucket,
    p_storage_path,
    p_user_id,
    p_resource_id,
    p_content_type,
    p_size_bytes,
    'prepared',
    now(),
    now() + interval '2 hours 30 minutes',
    null
  )
  on conflict (bucket, object_path) do update
  set status = 'prepared',
      created_at = excluded.created_at,
      expires_at = excluded.expires_at,
      claimed_at = null;

  return jsonb_build_object(
    'reserved', true,
    'reused', false,
    'expires_at', now() + interval '2 hours 30 minutes'
  );
end;
$$;

revoke all on function public.reserve_signed_media_upload(
  uuid, text, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.reserve_signed_media_upload(
  uuid, text, text, text, text, bigint
) to service_role;

create or replace function public.claim_signed_media_upload(
  p_user_id uuid,
  p_bucket text,
  p_storage_path text,
  p_content_type text,
  p_size_bytes bigint
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  grant_row public.signed_media_upload_reservations%rowtype;
  result jsonb;
  was_claimed boolean;
  final_owner text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  select * into grant_row
  from public.signed_media_upload_reservations reservation
  where reservation.bucket = p_bucket
    and reservation.object_path = p_storage_path
  for update;

  if not found
     or grant_row.user_id is distinct from p_user_id
     or grant_row.content_type is distinct from p_content_type
     or grant_row.size_bytes is distinct from p_size_bytes
     or (
       grant_row.status <> 'claimed'
       and grant_row.expires_at < now() - interval '15 minutes'
     ) then
    raise exception 'signed_upload_reservation_required'
      using errcode = '42501';
  end if;

  result := public.claim_signed_media_upload_validated(
    p_user_id,
    p_bucket,
    p_storage_path,
    p_content_type,
    p_size_bytes
  );
  was_claimed := coalesce(
    (result ->> 'already_claimed')::boolean,
    false
  );

  if not was_claimed then
    update storage.objects object
    set owner_id = p_user_id::text
    where object.bucket_id = p_bucket
      and object.name = p_storage_path
      and object.owner_id is null;
  end if;

  select object.owner_id into final_owner
  from storage.objects object
  where object.bucket_id = p_bucket
    and object.name = p_storage_path;
  if final_owner is distinct from p_user_id::text then
    raise exception 'uploaded_object_owner_conflict' using errcode = '42501';
  end if;

  update public.signed_media_upload_reservations reservation
  set status = 'claimed',
      claimed_at = coalesce(reservation.claimed_at, now())
  where reservation.bucket = p_bucket
    and reservation.object_path = p_storage_path;

  return jsonb_set(
    result,
    '{already_claimed}',
    to_jsonb(was_claimed),
    true
  );
end;
$$;

revoke all on function public.claim_signed_media_upload(
  uuid, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.claim_signed_media_upload(
  uuid, text, text, text, bigint
) to service_role;

notify pgrst, 'reload schema';

commit;
