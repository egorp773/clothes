-- Marketing withdrawal is intentionally easier than acceptance and never
-- affects marketplace entitlement. Network evidence is captured at the Edge
-- boundary, not accepted from a mobile client payload.

begin;

revoke execute on function public.withdraw_marketing_consent(inet, text)
  from authenticated;

create or replace function public.withdraw_marketing_consent_for_user(
  p_user_id uuid,
  p_ip inet,
  p_user_agent text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  affected integer;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_user_id is null
     or not exists (
       select 1 from public.users account where account.id = p_user_id
     ) then
    raise exception 'user_not_found' using errcode = 'P0002';
  end if;
  if p_ip is null
     or char_length(btrim(coalesce(p_user_agent, ''))) not between 1 and 1000
  then
    raise exception 'withdrawal_evidence_required' using errcode = '23514';
  end if;

  update public.user_consents
  set withdrawn_at = now(),
      withdrawal_ip = p_ip,
      withdrawal_user_agent = btrim(p_user_agent),
      evidence = evidence || jsonb_build_object(
        'withdrawal_source', 'edge_consent_center'
      )
  where user_id = p_user_id
    and document_type = 'marketing_consent'
    and withdrawn_at is null;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.withdraw_marketing_consent_for_user(
  uuid, inet, text
) from public, anon, authenticated;
grant execute on function public.withdraw_marketing_consent_for_user(
  uuid, inet, text
) to service_role;

notify pgrst, 'reload schema';

commit;
