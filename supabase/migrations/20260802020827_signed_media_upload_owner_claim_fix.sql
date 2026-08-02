-- SQL three-valued boolean logic made a NULL owner look neither claimed nor
-- unclaimed in the original command. Wrap the validated command and make the
-- first owner assignment explicit and retry-safe.

begin;

alter function public.claim_signed_media_upload(
  uuid, text, text, text, bigint
) rename to claim_signed_media_upload_validated;

create function public.claim_signed_media_upload(
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
  result jsonb;
  was_claimed boolean;
  final_owner text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;

  result := public.claim_signed_media_upload_validated(
    p_user_id,
    p_bucket,
    p_storage_path,
    p_content_type,
    p_size_bytes
  );
  was_claimed := coalesce((result ->> 'already_claimed')::boolean, false);

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

  return jsonb_set(
    result,
    '{already_claimed}',
    to_jsonb(was_claimed),
    true
  );
end;
$$;

revoke all on function public.claim_signed_media_upload_validated(
  uuid, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.claim_signed_media_upload_validated(
  uuid, text, text, text, bigint
) to service_role;

revoke all on function public.claim_signed_media_upload(
  uuid, text, text, text, bigint
) from public, anon, authenticated;
grant execute on function public.claim_signed_media_upload(
  uuid, text, text, text, bigint
) to service_role;

notify pgrst, 'reload schema';

commit;
