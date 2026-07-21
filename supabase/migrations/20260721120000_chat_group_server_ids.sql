begin;

-- Keep the legacy parameter name so released clients retain the same RPC
-- signature. Its value is only an idempotency token; Postgres generates and
-- returns the canonical thread id.
create or replace function public.create_group_thread(
  p_member_ids uuid[],
  p_title text,
  p_client_thread_id text
)
returns public.message_threads
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  normalized_members uuid[];
  request_id text := btrim(coalesce(p_client_thread_id, ''));
  request_key text;
  thread_row public.message_threads%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if request_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_group_request_id' using errcode = '22023';
  end if;

  request_key := 'group-request:v2:' || actor_id::text || ':' || request_id;
  -- Share the previous implementation's lock during a rolling replacement,
  -- then take the actor-scoped v2 lock used by all new calls.
  perform pg_advisory_xact_lock(
    hashtextextended('chat:group:' || request_id, 0)
  );
  perform pg_advisory_xact_lock(hashtextextended('chat:' || request_key, 0));

  -- Recover a committed request whose response was lost.
  select thread.* into thread_row
  from public.message_threads thread
  where thread.conversation_key = request_key;
  if found then
    if thread_row.created_by is distinct from actor_id
       or not public.current_user_is_chat_thread_member(thread_row.id) then
      raise exception 'conversation_membership_required' using errcode = '42501';
    end if;
    return thread_row;
  end if;

  -- During a rolling deployment the previous RPC may already have used the
  -- request UUID as the thread id. Return that row instead of duplicating it;
  -- newly created groups never enter this legacy namespace.
  select thread.* into thread_row
  from public.message_threads thread
  where thread.conversation_key = 'group:' || request_id
    and thread.created_by = actor_id;
  if found then
    if not public.current_user_is_chat_thread_member(thread_row.id) then
      raise exception 'conversation_membership_required' using errcode = '42501';
    end if;
    return thread_row;
  end if;

  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'invalid_group_metadata' using errcode = '22023';
  end if;
  select array_agg(member_id order by member_id::text)
  into normalized_members
  from (
    select distinct unnest(coalesce(p_member_ids, '{}'::uuid[]) || actor_id)
      as member_id
  ) members;
  if cardinality(normalized_members) not between 2 and 50 then
    raise exception 'invalid_group_members' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(normalized_members) member_id
    left join public.users durable_user on durable_user.id = member_id
    where durable_user.id is null
       or durable_user.auth_user_id is distinct from durable_user.id
       or durable_user.account_status <> 'active'
  ) then
    raise exception 'group_member_not_found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from unnest(normalized_members) member_id
    where member_id <> actor_id
      and public.users_are_blocked(actor_id, member_id)
  ) then
    raise exception 'chat_blocked' using errcode = '42501';
  end if;

  insert into public.message_threads (
    id, kind, conversation_key, buyer_id, seller_id, is_group, title,
    group_avatar, created_by, member_ids, members, created_at, updated_at
  ) values (
    gen_random_uuid()::text, 'group', request_key, normalized_members[1],
    normalized_members[2], true, btrim(p_title), '', actor_id,
    normalized_members, public.chat_legacy_member_snapshot(normalized_members),
    now(), now()
  ) returning * into thread_row;

  insert into public.chat_thread_members (thread_id, user_id, role)
  select thread_row.id, member_id,
    case when member_id = actor_id then 'owner' else 'member' end
  from unnest(normalized_members) member_id;
  insert into public.chat_thread_member_state (thread_id, user_id)
  select thread_row.id, member_id from unnest(normalized_members) member_id
  on conflict (thread_id, user_id) do nothing;
  return thread_row;
end;
$$;

revoke all on function public.create_group_thread(uuid[], text, text)
  from public, anon;
grant execute on function public.create_group_thread(uuid[], text, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
