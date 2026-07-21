-- A block applies to every interactive chat mutation, not only new messages.
-- A sender may still soft-delete their own historical message after a block.

begin;

create or replace function public.edit_chat_message(
  p_thread_id text,
  p_message_id text,
  p_text text
)
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  changed_at timestamptz := now();
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_text is null
     or char_length(btrim(p_text)) < 1
     or char_length(btrim(p_text)) > 8000 then
    raise exception 'invalid_message_text' using errcode = '22023';
  end if;

  update public.chat_messages message
  set text = btrim(p_text), edited_at = changed_at
  where message.id = p_message_id
    and message.thread_id = p_thread_id
    and message.sender_id = actor_id
    and message.deleted_at is null
    and message.type <> 'system'
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = message.thread_id
        and actor_id = any(thread.member_ids)
        and not exists (
          select 1
          from unnest(thread.member_ids) member_id
          where member_id <> actor_id
            and public.users_are_blocked(actor_id, member_id)
        )
    );
  if not found then
    raise exception 'message_edit_not_allowed' using errcode = '42501';
  end if;
  return changed_at;
end;
$$;

create or replace function public.toggle_chat_message_reaction(
  p_thread_id text,
  p_message_id text,
  p_emoji text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  existing jsonb;
  users jsonb;
  updated_users jsonb;
  result jsonb;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_emoji is null or btrim(p_emoji) = '' or char_length(p_emoji) > 16 then
    raise exception 'invalid_reaction' using errcode = '22023';
  end if;

  select message.reactions
  into existing
  from public.chat_messages message
  join public.message_threads thread on thread.id = message.thread_id
  where message.id = p_message_id
    and message.thread_id = p_thread_id
    and message.deleted_at is null
    and actor_id = any(thread.member_ids)
    and not exists (
      select 1
      from unnest(thread.member_ids) member_id
      where member_id <> actor_id
        and public.users_are_blocked(actor_id, member_id)
    )
  for update of message;
  if not found then
    raise exception 'conversation_interaction_not_allowed'
      using errcode = '42501';
  end if;

  existing := coalesce(existing, '{}'::jsonb);
  users := coalesce(existing -> p_emoji, '[]'::jsonb);
  if users @> jsonb_build_array(actor_id::text) then
    select coalesce(jsonb_agg(value), '[]'::jsonb)
    into updated_users
    from jsonb_array_elements_text(users) value
    where value <> actor_id::text;
    result := case
      when updated_users = '[]'::jsonb then existing - p_emoji
      else jsonb_set(existing, array[p_emoji], updated_users, true)
    end;
  else
    result := jsonb_set(
      existing,
      array[p_emoji],
      users || jsonb_build_array(actor_id::text),
      true
    );
  end if;

  update public.chat_messages
  set reactions = result
  where id = p_message_id and thread_id = p_thread_id;
  return result;
end;
$$;

revoke all on function public.edit_chat_message(text, text, text)
  from public, anon;
grant execute on function public.edit_chat_message(text, text, text)
  to authenticated;
revoke all on function public.toggle_chat_message_reaction(text, text, text)
  from public, anon;
grant execute on function public.toggle_chat_message_reaction(text, text, text)
  to authenticated;

notify pgrst, 'reload schema';

commit;
