-- Lock chat mutations down to narrow, membership-aware RPCs and make all
-- conversation preferences private to the current participant.

-- The legacy columns were shared by every participant and could expose a
-- draft written by one user to everyone in the conversation. There is no
-- historical writer id, so migrate the row to one deterministic owner only:
-- the group creator when available, otherwise the direct-chat buyer, then the
-- first valid legacy member. This preserves the state without copying a
-- private draft to every participant. `to_jsonb` keeps this block idempotent
-- after the physical columns have already been dropped.
with legacy_thread_state as (
  select
    thread.id as thread_id,
    coalesce(
      case
        when thread.is_group
          and thread.created_by = any(thread.member_ids)
          then thread.created_by
      end,
      case
        when thread.buyer_id = any(thread.member_ids) then thread.buyer_id
      end,
      case
        when thread.seller_id = any(thread.member_ids) then thread.seller_id
      end,
      thread.member_ids[1]
    ) as user_id,
    coalesce((to_jsonb(thread)->>'is_pinned')::boolean, false) as is_pinned,
    coalesce((to_jsonb(thread)->>'is_muted')::boolean, false) as is_muted,
    coalesce((to_jsonb(thread)->>'is_archived')::boolean, false) as is_archived,
    coalesce(to_jsonb(thread)->>'draft', '') as draft,
    nullif(to_jsonb(thread)->>'last_read_at', '')::timestamptz as last_read_at,
    thread.updated_at
  from public.message_threads thread
), legacy_state_to_migrate as (
  select *
  from legacy_thread_state state
  where state.user_id is not null
    and (
      state.is_pinned
      or state.is_muted
      or state.is_archived
      or state.draft <> ''
      or state.last_read_at is not null
    )
)
insert into public.chat_thread_member_state (
  thread_id,
  user_id,
  is_pinned,
  is_muted,
  is_archived,
  draft,
  last_read_at,
  updated_at
)
select
  state.thread_id,
  state.user_id,
  state.is_pinned,
  state.is_muted,
  state.is_archived,
  state.draft,
  state.last_read_at,
  state.updated_at
from legacy_state_to_migrate state
on conflict (thread_id, user_id) do update
set
  is_pinned = chat_thread_member_state.is_pinned or excluded.is_pinned,
  is_muted = chat_thread_member_state.is_muted or excluded.is_muted,
  is_archived = chat_thread_member_state.is_archived or excluded.is_archived,
  draft = case
    when chat_thread_member_state.draft <> ''
      then chat_thread_member_state.draft
    else excluded.draft
  end,
  last_read_at = greatest(
    chat_thread_member_state.last_read_at,
    excluded.last_read_at
  ),
  updated_at = greatest(chat_thread_member_state.updated_at, excluded.updated_at);

alter table public.message_threads
  drop column if exists is_pinned,
  drop column if exists is_muted,
  drop column if exists is_archived,
  drop column if exists draft,
  drop column if exists last_read_at;

-- Thread identity and membership are immutable after creation. Shared title
-- updates are handled by update_chat_thread_settings below, while last_message
-- and updated_at are maintained by message triggers.
create or replace function public.protect_thread_membership()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.id is distinct from old.id
     or new.buyer_id is distinct from old.buyer_id
     or new.seller_id is distinct from old.seller_id
     or new.product_id is distinct from old.product_id
     or new.is_group is distinct from old.is_group
     or new.created_by is distinct from old.created_by
     or new.member_ids is distinct from old.member_ids
     or new.members is distinct from old.members
     or new.group_avatar is distinct from old.group_avatar
     or new.unread_count is distinct from old.unread_count
     or new.messages is distinct from old.messages then
    raise exception using
      errcode = '42501',
      message = 'chat_thread_identity_is_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_message_thread_before_insert
  on public.message_threads;
create or replace function public.normalize_message_thread_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
begin
  -- Personal state exists only in chat_thread_member_state.
  new.unread_count := 0;
  new.messages := '[]'::jsonb;
  new.last_message := '';
  new.updated_at := now();

  if new.is_group and actor_id is not null then
    new.created_by := actor_id;
  end if;
  return new;
end;
$$;
create trigger normalize_message_thread_before_insert
before insert on public.message_threads
for each row execute function public.normalize_message_thread_insert();

drop policy if exists "Users can create their message threads"
  on public.message_threads;
create policy "Users can create their message threads"
  on public.message_threads for insert to authenticated
  with check (
    auth.uid() = any(member_ids)
    and cardinality(member_ids) between 2 and 50
    and cardinality(member_ids) = (
      select count(distinct member_id)::integer
      from unnest(member_ids) member_id
    )
    and buyer_id = any(member_ids)
    and seller_id = any(member_ids)
    and (is_group or cardinality(member_ids) = 2)
    and (not is_group or created_by = auth.uid())
    and not exists (
      select 1
      from unnest(member_ids) member_id
      where public.users_are_blocked(auth.uid(), member_id)
    )
  );

drop policy if exists "Users can update their message threads"
  on public.message_threads;
revoke update on public.message_threads from authenticated;

-- Member state can be read only by that member while they still belong to the
-- conversation. Inserts and updates are intentionally RPC-only.
drop policy if exists "Members can read own chat state"
  on public.chat_thread_member_state;
create policy "Members can read own chat state"
  on public.chat_thread_member_state for select to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = thread_id
        and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Members can insert own chat state"
  on public.chat_thread_member_state;
drop policy if exists "Members can update own chat state"
  on public.chat_thread_member_state;
revoke insert, update on public.chat_thread_member_state from authenticated;
grant select on public.chat_thread_member_state to authenticated;

create or replace function public.protect_chat_thread_state_identity()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.thread_id is distinct from old.thread_id
     or new.user_id is distinct from old.user_id then
    raise exception using
      errcode = '42501',
      message = 'chat_thread_state_identity_is_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_chat_thread_state_identity_before_update
  on public.chat_thread_member_state;
create trigger protect_chat_thread_state_identity_before_update
before update on public.chat_thread_member_state
for each row execute function public.protect_chat_thread_state_identity();

create or replace function public.update_chat_thread_settings(
  p_thread_id text,
  p_is_pinned boolean default null,
  p_is_muted boolean default null,
  p_is_archived boolean default null,
  p_draft text default null,
  p_title text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  thread_is_group boolean;
  thread_creator uuid;
  clean_title text;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  select thread.is_group, thread.created_by
  into thread_is_group, thread_creator
  from public.message_threads thread
  where thread.id = p_thread_id
    and actor_id = any(thread.member_ids)
  for update;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'conversation_membership_required';
  end if;

  if p_draft is not null and char_length(p_draft) > 8000 then
    raise exception using errcode = '22023', message = 'draft_too_long';
  end if;

  if p_title is not null then
    clean_title := btrim(p_title);
    if not thread_is_group or thread_creator is distinct from actor_id then
      raise exception using
        errcode = '42501',
        message = 'conversation_creator_required';
    end if;
    if char_length(clean_title) < 1 or char_length(clean_title) > 120 then
      raise exception using errcode = '22023', message = 'invalid_thread_title';
    end if;
    update public.message_threads
    set title = clean_title, updated_at = now()
    where id = p_thread_id;
  end if;

  if p_is_pinned is not null
     or p_is_muted is not null
     or p_is_archived is not null
     or p_draft is not null then
    insert into public.chat_thread_member_state (
      thread_id,
      user_id,
      is_pinned,
      is_muted,
      is_archived,
      draft,
      updated_at
    ) values (
      p_thread_id,
      actor_id,
      coalesce(p_is_pinned, false),
      coalesce(p_is_muted, false),
      coalesce(p_is_archived, false),
      coalesce(p_draft, ''),
      now()
    )
    on conflict (thread_id, user_id) do update
    set
      is_pinned = coalesce(p_is_pinned, chat_thread_member_state.is_pinned),
      is_muted = coalesce(p_is_muted, chat_thread_member_state.is_muted),
      is_archived = coalesce(
        p_is_archived,
        chat_thread_member_state.is_archived
      ),
      draft = coalesce(p_draft, chat_thread_member_state.draft),
      updated_at = now();
  end if;
end;
$$;

revoke all on function public.update_chat_thread_settings(
  text, boolean, boolean, boolean, text, text
) from public;
grant execute on function public.update_chat_thread_settings(
  text, boolean, boolean, boolean, text, text
) to authenticated;

-- Generate the canonical preview in one place so inserts, edits and deletions
-- cannot leave message_threads.last_message stale.
create or replace function public.chat_message_preview(
  p_message public.chat_messages
)
returns text
language sql
stable
set search_path = public, pg_temp
as $$
  select case
    when p_message.deleted_at is not null then 'Сообщение удалено'
    when p_message.type = 'product' then coalesce(
      nullif(btrim(p_message.text), ''),
      'Объявление: ' || coalesce(p_message.product->>'title', '')
    )
    when p_message.type = 'image' then
      coalesce(nullif(btrim(p_message.text), ''), 'Фотография')
    when p_message.type = 'video' then
      coalesce(nullif(btrim(p_message.text), ''), 'Видео')
    else btrim(p_message.text)
  end
$$;

revoke all on function public.chat_message_preview(public.chat_messages)
  from public;

-- Reuse the existing BEFORE INSERT trigger name, but make it authoritative for
-- sender identity, mutation-only fields, replies and attachment ownership.
create or replace function public.hydrate_chat_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  profile_name text;
  profile_avatar text;
  path_parts text[];
  attachment_mime text;
  reply_message public.chat_messages%rowtype;
begin
  if actor_id is not null then
    new.sender_id := actor_id;
  end if;

  select profile.name, profile.avatar_url
  into profile_name, profile_avatar
  from public.profiles profile
  where profile.id = new.sender_id;

  new.sender_name := coalesce(nullif(btrim(profile_name), ''), 'Пользователь');
  new.sender_avatar := coalesce(nullif(btrim(profile_avatar), ''), '');
  new.read_by := array[new.sender_id];
  new.reactions := '{}'::jsonb;
  new.edited_at := null;
  new.deleted_at := null;
  new.created_at := now();

  if new.type in ('image', 'video') then
    if jsonb_typeof(new.attachment) is distinct from 'object'
       or new.attachment->>'bucket' is distinct from 'chat-media'
       or nullif(new.attachment->>'storage_path', '') is null then
      raise exception using errcode = '22023', message = 'invalid_chat_attachment';
    end if;

    path_parts := string_to_array(new.attachment->>'storage_path', '/');
    if cardinality(path_parts) < 4
       or path_parts[1] is distinct from 'threads'
       or path_parts[2] is distinct from new.thread_id
       or path_parts[3] is distinct from new.sender_id::text
       or not exists (
         select 1
         from storage.objects stored_object
         where stored_object.bucket_id = 'chat-media'
           and stored_object.name = new.attachment->>'storage_path'
       ) then
      raise exception using
        errcode = '22023',
        message = 'chat_attachment_owner_mismatch';
    end if;

    attachment_mime := coalesce(new.attachment->>'mime_type', '');
    if (new.type = 'image' and attachment_mime not like 'image/%')
       or (new.type = 'video' and attachment_mime not like 'video/%') then
      raise exception using
        errcode = '22023',
        message = 'chat_attachment_type_mismatch';
    end if;
  else
    new.attachment := null;
  end if;

  if new.reply_to_id is not null then
    select message.*
    into reply_message
    from public.chat_messages message
    where message.id = new.reply_to_id
      and message.thread_id = new.thread_id;
    if not found then
      raise exception using errcode = '22023', message = 'invalid_chat_reply';
    end if;
    new.reply_snapshot := jsonb_build_object(
      'text', public.chat_message_preview(reply_message),
      'sender_name', reply_message.sender_name
    );
  else
    new.reply_snapshot := null;
  end if;
  return new;
end;
$$;

drop policy if exists "Conversation members can send messages"
  on public.chat_messages;
create policy "Conversation members can send messages"
  on public.chat_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and char_length(text) <= 8000
    and (type in ('product', 'system', 'image', 'video')
      or nullif(btrim(text), '') is not null)
    and (type <> 'product' or (
      jsonb_typeof(product) = 'object'
      and nullif(product->>'id', '') is not null
      and exists (
        select 1
        from public.products listed
        where listed.id::text = product->>'id'
          and listed.status = 'published'
          and not coalesce(listed.is_hidden, false)
      )
    ))
    and (type not in ('image', 'video') or (
      jsonb_typeof(attachment) = 'object'
      and attachment->>'bucket' = 'chat-media'
      and (string_to_array(attachment->>'storage_path', '/'))[1] = 'threads'
      and (string_to_array(attachment->>'storage_path', '/'))[2] = thread_id
      and (string_to_array(attachment->>'storage_path', '/'))[3]
        = sender_id::text
    ))
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = thread_id
        and auth.uid() = any(thread.member_ids)
        and (type <> 'system' or (
          thread.is_group
          and thread.created_by = auth.uid()
          and not exists (
            select 1
            from public.chat_messages existing_message
            where existing_message.thread_id = thread.id
          )
          or exists (
            select 1
            from public.chat_messages existing_message
            where existing_message.id = chat_messages.id
              and existing_message.thread_id = thread.id
              and existing_message.sender_id = auth.uid()
              and existing_message.type = 'system'
          )
        ))
        and not exists (
          select 1
          from unnest(thread.member_ids) member_id
          where public.users_are_blocked(auth.uid(), member_id)
        )
    )
  );

drop policy if exists "Senders can update their messages"
  on public.chat_messages;
revoke update on public.chat_messages from authenticated;

create or replace function public.edit_chat_message(
  p_thread_id text,
  p_message_id text,
  p_text text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  changed_at timestamptz := now();
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_text is null
     or char_length(btrim(p_text)) < 1
     or char_length(btrim(p_text)) > 8000 then
    raise exception using errcode = '22023', message = 'invalid_message_text';
  end if;

  update public.chat_messages message
  set text = btrim(p_text), edited_at = changed_at
  where message.id = p_message_id
    and message.thread_id = p_thread_id
    and message.sender_id = actor_id
    and message.deleted_at is null
    and message.type <> 'system';
  if not found then
    raise exception using errcode = '42501', message = 'message_edit_not_allowed';
  end if;
  return changed_at;
end;
$$;

create or replace function public.delete_chat_message(
  p_thread_id text,
  p_message_id text
)
returns timestamptz
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  changed_at timestamptz := now();
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;

  update public.chat_messages message
  set
    text = '',
    type = 'text',
    product = null,
    attachment = null,
    edited_at = null,
    deleted_at = changed_at,
    reactions = '{}'::jsonb
  where message.id = p_message_id
    and message.thread_id = p_thread_id
    and message.sender_id = actor_id
    and message.deleted_at is null
    and message.type <> 'system';
  if not found then
    raise exception using errcode = '42501', message = 'message_delete_not_allowed';
  end if;
  return changed_at;
end;
$$;

revoke all on function public.edit_chat_message(text, text, text) from public;
grant execute on function public.edit_chat_message(text, text, text)
  to authenticated;
revoke all on function public.delete_chat_message(text, text) from public;
grant execute on function public.delete_chat_message(text, text)
  to authenticated;

create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.message_threads
  set
    last_message = public.chat_message_preview(new),
    updated_at = greatest(updated_at, new.created_at)
  where id = new.thread_id and new.created_at >= updated_at;

  insert into public.chat_thread_member_state (thread_id, user_id)
  select new.thread_id, member_id
  from public.message_threads thread
  cross join lateral unnest(thread.member_ids) member_id
  where thread.id = new.thread_id
  on conflict (thread_id, user_id) do nothing;
  return new;
end;
$$;

create or replace function public.refresh_thread_preview_from_message_update()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  latest public.chat_messages%rowtype;
begin
  select message.*
  into latest
  from public.chat_messages message
  where message.thread_id = new.thread_id
  order by message.created_at desc, message.id desc
  limit 1;

  if found then
    update public.message_threads
    set
      last_message = public.chat_message_preview(latest),
      updated_at = greatest(updated_at, now())
    where id = new.thread_id;
  end if;
  return new;
end;
$$;

drop trigger if exists refresh_thread_preview_after_message_update
  on public.chat_messages;
create trigger refresh_thread_preview_after_message_update
after update of text, type, product, attachment, deleted_at
on public.chat_messages
for each row
when (
  old.text is distinct from new.text
  or old.type is distinct from new.type
  or old.product is distinct from new.product
  or old.attachment is distinct from new.attachment
  or old.deleted_at is distinct from new.deleted_at
)
execute function public.refresh_thread_preview_from_message_update();

-- Only the reaction RPC can mutate reactions. Deleted messages are excluded.
create or replace function public.toggle_chat_message_reaction(
  p_thread_id text,
  p_message_id text,
  p_emoji text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  existing jsonb;
  users jsonb;
  updated_users jsonb;
  result jsonb;
begin
  if actor_id is null then
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if p_emoji is null or btrim(p_emoji) = '' or char_length(p_emoji) > 16 then
    raise exception using errcode = '22023', message = 'invalid_reaction';
  end if;

  select message.reactions
  into existing
  from public.chat_messages message
  join public.message_threads thread on thread.id = message.thread_id
  where message.id = p_message_id
    and message.thread_id = p_thread_id
    and message.deleted_at is null
    and actor_id = any(thread.member_ids)
  for update of message;
  if not found then
    raise exception using
      errcode = '42501',
      message = 'conversation_membership_required';
  end if;

  existing := coalesce(existing, '{}'::jsonb);
  users := coalesce(existing->p_emoji, '[]'::jsonb);
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

revoke all on function public.toggle_chat_message_reaction(text, text, text)
  from public;
grant execute on function public.toggle_chat_message_reaction(text, text, text)
  to authenticated;

alter table public.chat_thread_member_state replica identity full;
do $$
begin
  alter publication supabase_realtime
    add table public.chat_thread_member_state;
exception when duplicate_object then null;
end;
$$;

notify pgrst, 'reload schema';
