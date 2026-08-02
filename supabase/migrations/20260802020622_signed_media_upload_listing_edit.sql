-- Listing edits use a deterministic idempotency-key filename rather than a
-- bare UUID. Keep the service-only claim contract strict while accepting that
-- canonical filename.

begin;

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
  stored storage.objects%rowtype;
  normalized_content_type text := lower(btrim(coalesce(p_content_type, '')));
  max_size bigint;
  allowed_path boolean := false;
  already_claimed boolean;
  stored_mime text;
  stored_size bigint;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_active(p_user_id) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  case p_bucket
    when 'profile-images' then
      max_size := 10485760;
      allowed_path := p_storage_path ~ (
        '^' || p_user_id::text ||
        '/avatar/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
      );
    when 'listing-drafts' then
      max_size := 15728640;
      allowed_path := p_storage_path ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f-]{36}/[A-Za-z0-9][A-Za-z0-9._-]{0,179}\.(jpg|jpeg|png|webp)$'
      );
    when 'outfit-images' then
      max_size := 15728640;
      allowed_path := p_storage_path ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
      );
    when 'accessory-images' then
      max_size := 15728640;
      allowed_path := p_storage_path ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|jpeg|png|webp)$'
      );
    when 'dispute-evidence' then
      max_size := 20971520;
      allowed_path := p_storage_path ~ (
        '^' || p_user_id::text ||
        '/[0-9a-f-]{36}/[0-9a-f]{64}\.(jpg|jpeg|png|webp)$'
      );
    when 'chat-media' then
      max_size := 20971520;
      allowed_path := p_storage_path ~ (
        '^threads/[^/]+/' || p_user_id::text ||
        '/[0-9a-f-]{36}\.(jpg|jpeg|png|webp|gif)$'
      );
    else
      raise exception 'upload_bucket_not_allowed' using errcode = '22023';
  end case;

  if not allowed_path then
    raise exception 'upload_path_invalid' using errcode = '22023';
  end if;
  if normalized_content_type not in (
    'image/jpeg', 'image/png', 'image/webp', 'image/gif'
  ) or (
    p_bucket <> 'chat-media' and normalized_content_type = 'image/gif'
  ) then
    raise exception 'upload_content_type_invalid' using errcode = '22023';
  end if;
  if p_size_bytes is null
     or p_size_bytes < 1
     or p_size_bytes > max_size then
    raise exception 'upload_size_invalid' using errcode = '22023';
  end if;

  select * into stored
  from storage.objects object
  where object.bucket_id = p_bucket
    and object.name = p_storage_path
  for update;
  if not found then
    raise exception 'uploaded_object_not_found' using errcode = 'P0002';
  end if;
  if stored.owner_id is not null
     and stored.owner_id <> p_user_id::text then
    raise exception 'uploaded_object_owner_conflict' using errcode = '42501';
  end if;

  stored_mime := lower(btrim(coalesce(stored.metadata ->> 'mimetype', '')));
  if stored_mime <> '' and stored_mime <> normalized_content_type then
    raise exception 'uploaded_object_mime_mismatch' using errcode = '23514';
  end if;
  begin
    stored_size := nullif(stored.metadata ->> 'size', '')::bigint;
  exception when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'uploaded_object_size_invalid' using errcode = '23514';
  end;
  if stored_size is not null and stored_size <> p_size_bytes then
    raise exception 'uploaded_object_size_mismatch' using errcode = '23514';
  end if;

  already_claimed := stored.owner_id = p_user_id::text;
  if not already_claimed then
    update storage.objects object
    set owner_id = p_user_id::text
    where object.id = stored.id;
  end if;

  return jsonb_build_object(
    'claimed', true,
    'already_claimed', already_claimed,
    'bucket', p_bucket,
    'storage_path', p_storage_path
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
