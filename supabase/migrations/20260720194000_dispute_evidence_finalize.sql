-- Evidence integrity is established by an Edge command that reads the stored
-- bytes. Mobile clients can upload only into their namespace but cannot attest
-- the checksum or create the durable evidence ledger row directly.

begin;

update storage.buckets
set public = false,
    file_size_limit = 20971520,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp'
    ]::text[]
where id = 'dispute-evidence';

drop policy if exists "Participants upload own dispute evidence"
  on storage.objects;
create policy "Participants upload own dispute evidence"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'dispute-evidence'
    and owner_id = (select auth.uid()::text)
    and split_part(name, '/', 1) = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and (
      select count(*)
      from storage.objects existing
      where existing.bucket_id = 'dispute-evidence'
        and split_part(existing.name, '/', 1) = (select auth.uid()::text)
        and split_part(existing.name, '/', 2) = split_part(name, '/', 2)
    ) < 25
    and exists (
      select 1
      from public.disputes dispute
      join public.orders marketplace_order
        on marketplace_order.id = dispute.order_id
      where dispute.id::text = split_part(name, '/', 2)
        and dispute.status in ('open', 'under_review')
        and public.current_marketplace_user_is_eligible(false)
        and (select auth.uid()) in (
          marketplace_order.buyer_id,
          marketplace_order.seller_id
        )
    )
  );

create unique index if not exists dispute_evidence_storage_object_unique_idx
  on public.dispute_evidence (dispute_id, storage_bucket, storage_path)
  where storage_path is not null;

revoke execute on function public.add_dispute_evidence(
  uuid, text, text, text, jsonb
) from authenticated;

create or replace function public.finalize_dispute_evidence(
  p_actor_id uuid,
  p_dispute_id uuid,
  p_evidence_type text,
  p_storage_path text,
  p_content_hash text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  evidence_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_actor_id is null
     or not public.marketplace_user_is_eligible(p_actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_evidence_type not in ('image', 'video', 'document')
     or p_storage_path !~ (
       '^' || p_actor_id::text || '/' || p_dispute_id::text || '/[^/]+$'
     )
     or p_content_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object'
     or length(coalesce(p_metadata, '{}'::jsonb)::text) > 10000 then
    raise exception 'dispute_evidence_invalid' using errcode = '22023';
  end if;
  if not exists (
    select 1
    from public.disputes dispute
    join public.orders marketplace_order
      on marketplace_order.id = dispute.order_id
    where dispute.id = p_dispute_id
      and dispute.status in ('open', 'under_review')
      and p_actor_id in (
        marketplace_order.buyer_id,
        marketplace_order.seller_id
      )
  ) or not exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = 'dispute-evidence'
      and stored.name = p_storage_path
      and stored.owner_id = p_actor_id::text
  ) then
    raise exception 'dispute_evidence_not_owned' using errcode = '42501';
  end if;
  if not exists (
       select 1
       from public.dispute_evidence evidence
       where evidence.dispute_id = p_dispute_id
         and evidence.storage_bucket = 'dispute-evidence'
         and evidence.storage_path = p_storage_path
     ) and (
       select count(*)
       from public.dispute_evidence evidence
       where evidence.dispute_id = p_dispute_id
     ) >= 20 then
    raise exception 'dispute_evidence_quota_exceeded' using errcode = '54000';
  end if;

  insert into public.dispute_evidence (
    dispute_id,
    submitted_by,
    evidence_type,
    storage_bucket,
    storage_path,
    content_hash,
    metadata
  )
  values (
    p_dispute_id,
    p_actor_id,
    p_evidence_type,
    'dispute-evidence',
    p_storage_path,
    lower(p_content_hash),
    p_metadata
  )
  on conflict (dispute_id, storage_bucket, storage_path)
    where storage_path is not null
  do nothing
  returning id into evidence_id;

  if evidence_id is null then
    select evidence.id into evidence_id
    from public.dispute_evidence evidence
    where evidence.dispute_id = p_dispute_id
      and evidence.storage_bucket = 'dispute-evidence'
      and evidence.storage_path = p_storage_path
      and evidence.content_hash = lower(p_content_hash);
  end if;
  if evidence_id is null then
    raise exception 'dispute_evidence_replay_mismatch' using errcode = '23514';
  end if;
  return evidence_id;
end;
$$;

revoke all on function public.finalize_dispute_evidence(
  uuid, uuid, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.finalize_dispute_evidence(
  uuid, uuid, text, text, text, jsonb
) to service_role;

notify pgrst, 'reload schema';

commit;
