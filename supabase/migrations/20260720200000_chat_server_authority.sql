-- Server-authoritative, recoverable chat delivery.
--
-- This migration is deliberately additive. Legacy message_threads columns and
-- chat_thread_member_state remain available during the Flutter rollout.

begin;

-- ---------------------------------------------------------------------------
-- Canonical columns and membership
-- ---------------------------------------------------------------------------

alter table public.message_threads
  add column if not exists kind text,
  add column if not exists created_at timestamptz,
  add column if not exists conversation_key text,
  add column if not exists last_message_id text,
  add column if not exists last_message_preview text;

update public.message_threads
set
  kind = coalesce(
    nullif(kind, ''),
    case
      when is_group then 'group'
      when nullif(product_id, '') is not null then 'product'
      else 'direct'
    end
  ),
  created_at = coalesce(created_at, updated_at, now()),
  last_message_preview = coalesce(last_message_preview, last_message, '');

with keyed as (
  select
    thread.id,
    case
      when thread.is_group then 'group:' || thread.id
      when nullif(thread.product_id, '') is not null
           and thread.buyer_id is not null
           and thread.seller_id is not null then
        'product:' || thread.product_id || ':buyer:' || thread.buyer_id::text ||
          ':seller:' || thread.seller_id::text
      when thread.buyer_id is not null and thread.seller_id is not null then
        'direct:' || least(thread.buyer_id::text, thread.seller_id::text) || ':' ||
          greatest(thread.buyer_id::text, thread.seller_id::text)
      else 'legacy:' || thread.id
    end as base_key
  from public.message_threads thread
), ranked as (
  select
    keyed.*,
    row_number() over (partition by keyed.base_key order by keyed.id) as duplicate_number
  from keyed
)
update public.message_threads thread
set conversation_key = case
  when ranked.duplicate_number = 1 then ranked.base_key
  else ranked.base_key || ':legacy-duplicate:' || thread.id
end
from ranked
where ranked.id = thread.id
  and nullif(thread.conversation_key, '') is null;

alter table public.message_threads
  alter column kind set default 'direct',
  alter column kind set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column conversation_key set not null,
  alter column last_message_preview set default '',
  alter column last_message_preview set not null;

alter table public.message_threads
  drop constraint if exists message_threads_kind_check;
alter table public.message_threads
  add constraint message_threads_kind_check
  check (kind in ('direct', 'product', 'group')) not valid;
alter table public.message_threads
  validate constraint message_threads_kind_check;

create unique index if not exists message_threads_conversation_key_uidx
  on public.message_threads (conversation_key);
create index if not exists message_threads_updated_id_idx
  on public.message_threads (updated_at desc, id desc);

create table if not exists public.chat_thread_members (
  thread_id text not null
    references public.message_threads(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  role text not null default 'member'
    check (role in ('buyer', 'seller', 'member', 'owner', 'moderator')),
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key (thread_id, user_id),
  check (left_at is null or left_at >= joined_at)
);

insert into public.chat_thread_members (
  thread_id,
  user_id,
  role,
  joined_at
)
select
  thread.id,
  member.user_id,
  case
    when thread.is_group and member.user_id = thread.created_by then 'owner'
    when member.user_id = thread.buyer_id then 'buyer'
    when member.user_id = thread.seller_id then 'seller'
    else 'member'
  end,
  coalesce(thread.created_at, thread.updated_at, now())
from public.message_threads thread
cross join lateral (
  select distinct candidate.user_id
  from unnest(
    array_cat(
      coalesce(thread.member_ids, '{}'::uuid[]),
      array_remove(
        array[thread.buyer_id, thread.seller_id, thread.created_by],
        null
      )
    )
  ) candidate(user_id)
) member
join public.users durable_user on durable_user.id = member.user_id
on conflict (thread_id, user_id) do nothing;

create index if not exists chat_thread_members_user_thread_idx
  on public.chat_thread_members (user_id, thread_id)
  where left_at is null;

alter table public.chat_thread_member_state
  add column if not exists unread_count integer not null default 0,
  add column if not exists last_read_message_id text;

alter table public.chat_thread_member_state
  drop constraint if exists chat_thread_member_state_unread_count_check;
alter table public.chat_thread_member_state
  add constraint chat_thread_member_state_unread_count_check
  check (unread_count >= 0) not valid;
alter table public.chat_thread_member_state
  validate constraint chat_thread_member_state_unread_count_check;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_thread_member_state_last_read_message_id_fkey'
      and conrelid = 'public.chat_thread_member_state'::regclass
  ) then
    alter table public.chat_thread_member_state
      add constraint chat_thread_member_state_last_read_message_id_fkey
      foreign key (last_read_message_id)
      references public.chat_messages(id) on delete set null
      not valid;
    alter table public.chat_thread_member_state
      validate constraint chat_thread_member_state_last_read_message_id_fkey;
  end if;
end
$$;

create index if not exists chat_thread_member_state_user_updated_idx
  on public.chat_thread_member_state (user_id, updated_at desc, thread_id);
create index if not exists chat_thread_member_state_user_unread_idx
  on public.chat_thread_member_state (user_id, updated_at desc)
  where unread_count > 0;

insert into public.chat_thread_member_state (thread_id, user_id, updated_at)
select member.thread_id, member.user_id, now()
from public.chat_thread_members member
where member.left_at is null
on conflict (thread_id, user_id) do nothing;

-- ---------------------------------------------------------------------------
-- Message idempotency, delivery receipts and lossless legacy repair
-- ---------------------------------------------------------------------------

alter table public.chat_messages
  add column if not exists client_message_id text,
  add column if not exists delivered_to uuid[] not null default '{}'::uuid[],
  add column if not exists legacy_source_key text;

update public.chat_messages
set
  client_message_id = coalesce(
    nullif(client_message_id, ''),
    case
      when char_length(id) <= 200 then id
      else 'legacy_' || md5(id)
    end
  ),
  delivered_to = case
    when sender_id is not null and not (sender_id = any(delivered_to))
      then array_append(delivered_to, sender_id)
    else delivered_to
  end;

alter table public.chat_messages
  alter column client_message_id set not null;

alter table public.chat_messages
  drop constraint if exists chat_messages_client_message_id_check;
alter table public.chat_messages
  add constraint chat_messages_client_message_id_check
  check (
    char_length(client_message_id) between 1 and 200
    and client_message_id ~ '^[A-Za-z0-9._:-]+$'
  ) not valid;
alter table public.chat_messages
  validate constraint chat_messages_client_message_id_check;

create unique index if not exists chat_messages_sender_client_uidx
  on public.chat_messages (thread_id, sender_id, client_message_id)
  where sender_id is not null;
create unique index if not exists chat_messages_legacy_source_uidx
  on public.chat_messages (legacy_source_key)
  where legacy_source_key is not null;
-- A new name is intentional: the old *_thread_created_idx was originally
-- created without id, so CREATE INDEX IF NOT EXISTS could never repair it.
create index if not exists chat_messages_thread_cursor_idx
  on public.chat_messages (thread_id, created_at desc, id desc);

create table if not exists public.chat_legacy_migration_issues (
  legacy_source_key text primary key,
  thread_id text not null,
  reason text not null,
  legacy_item jsonb not null,
  detected_at timestamptz not null default now()
);
alter table public.chat_legacy_migration_issues enable row level security;
revoke all on public.chat_legacy_migration_issues from anon, authenticated;

-- Preserve maintenance timestamps during a server migration while continuing
-- to make authenticated sender identity and timestamps server-authoritative.
create or replace function public.hydrate_chat_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public
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
    new.created_at := now();
  else
    new.created_at := coalesce(new.created_at, now());
  end if;
  if new.sender_id is null then
    raise exception 'chat_sender_required' using errcode = '23502';
  end if;

  select profile.name, profile.avatar_url
  into profile_name, profile_avatar
  from public.profiles profile
  where profile.id = new.sender_id;

  new.sender_name := coalesce(
    nullif(btrim(profile_name), ''),
    nullif(btrim(new.sender_name), ''),
    'Пользователь'
  );
  new.sender_avatar := coalesce(
    nullif(btrim(profile_avatar), ''),
    nullif(btrim(new.sender_avatar), ''),
    ''
  );
  new.client_message_id := coalesce(
    nullif(btrim(new.client_message_id), ''),
    new.id
  );
  new.read_by := array[new.sender_id];
  new.delivered_to := array[new.sender_id];
  new.reactions := '{}'::jsonb;
  new.edited_at := null;
  new.deleted_at := null;

  if new.type in ('image', 'video') then
    if jsonb_typeof(new.attachment) is distinct from 'object'
       or new.attachment->>'bucket' is distinct from 'chat-media'
       or nullif(new.attachment->>'storage_path', '') is null then
      raise exception 'invalid_chat_attachment' using errcode = '22023';
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
      raise exception 'chat_attachment_owner_mismatch' using errcode = '22023';
    end if;
    attachment_mime := coalesce(new.attachment->>'mime_type', '');
    if (new.type = 'image' and attachment_mime not like 'image/%')
       or (new.type = 'video' and attachment_mime not like 'video/%') then
      raise exception 'chat_attachment_type_mismatch' using errcode = '22023';
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
      raise exception 'invalid_chat_reply' using errcode = '22023';
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

revoke all on function public.hydrate_chat_message_sender()
  from public, anon, authenticated;

create or replace function public.protect_chat_message_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.thread_id is distinct from old.thread_id
     or new.sender_id is distinct from old.sender_id
     or new.client_message_id is distinct from old.client_message_id
     or new.legacy_source_key is distinct from old.legacy_source_key
     or new.created_at is distinct from old.created_at then
    raise exception 'chat_message_identity_is_immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke all on function public.protect_chat_message_identity()
  from public, anon, authenticated;

-- Deterministically associate legacy JSON items with already migrated rows.
-- The identity trigger already exists on upgraded projects. Temporarily
-- suspend it only while attaching the new migration provenance key; the whole
-- operation is transactional and the trigger is restored before inserts.
alter table public.chat_messages
  disable trigger protect_chat_message_identity_before_update;

with legacy as (
  select
    thread.id as thread_id,
    item.value as item,
    item.ordinality,
    'legacy:' || md5(
      thread.id || ':' || item.ordinality::text || ':' || item.value::text
    ) as source_key,
    nullif(item.value->>'id', '') as legacy_id
  from public.message_threads thread
  cross join lateral jsonb_array_elements(
    case
      when jsonb_typeof(thread.messages) = 'array' then thread.messages
      else '[]'::jsonb
    end
  ) with ordinality item(value, ordinality)
)
update public.chat_messages message
set legacy_source_key = legacy.source_key
from legacy
where legacy.legacy_id is not null
  and message.id = legacy.legacy_id
  and message.thread_id = legacy.thread_id
  and message.legacy_source_key is null;

with legacy as (
  select
    thread.id as thread_id,
    item.value as item,
    item.ordinality,
    'legacy:' || md5(
      thread.id || ':' || item.ordinality::text || ':' || item.value::text
    ) as source_key,
    case
      when coalesce(item.value->>'sender_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'sender_id')::uuid
    end as sender_id,
    coalesce(item.value->>'text', '') as message_text,
    case
      when item.value->>'type' in ('text', 'product', 'system')
        then item.value->>'type'
      else 'text'
    end as message_type,
    item.value->'product' as product
  from public.message_threads thread
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(thread.messages) = 'array'
      then thread.messages else '[]'::jsonb end
  ) with ordinality item(value, ordinality)
), unmatched_legacy as (
  select
    legacy.*,
    row_number() over (
      partition by legacy.thread_id, legacy.sender_id,
        md5(legacy.message_text || ':' || legacy.message_type || ':' ||
          coalesce(legacy.product::text, 'null'))
      order by legacy.ordinality
    ) as match_number
  from legacy
  where not exists (
    select 1 from public.chat_messages message
    where message.legacy_source_key = legacy.source_key
  )
), unmatched_messages as (
  select
    message.id,
    message.thread_id,
    message.sender_id,
    md5(message.text || ':' || message.type || ':' ||
      coalesce(message.product::text, 'null')) as fingerprint,
    row_number() over (
      partition by message.thread_id, message.sender_id,
        md5(message.text || ':' || message.type || ':' ||
          coalesce(message.product::text, 'null'))
      order by message.created_at, message.id
    ) as match_number
  from public.chat_messages message
  where message.legacy_source_key is null
)
update public.chat_messages message
set legacy_source_key = legacy.source_key
from unmatched_legacy legacy
join unmatched_messages existing
  on existing.thread_id = legacy.thread_id
 and existing.sender_id = legacy.sender_id
 and existing.fingerprint = md5(
   legacy.message_text || ':' || legacy.message_type || ':' ||
   coalesce(legacy.product::text, 'null')
 )
 and existing.match_number = legacy.match_number
where message.id = existing.id;

alter table public.chat_messages
  enable trigger protect_chat_message_identity_before_update;

create or replace function pg_temp.chat_try_parse_legacy_timestamp(
  p_value text
)
returns timestamptz
language plpgsql
stable
set search_path = ''
as $$
begin
  return nullif(p_value, '')::timestamptz;
exception when others then
  return null;
end;
$$;

with legacy as (
  select
    thread.id as thread_id,
    thread.created_at as thread_created_at,
    item.value as item,
    item.ordinality,
    'legacy:' || md5(
      thread.id || ':' || item.ordinality::text || ':' || item.value::text
    ) as source_key,
    case
      when coalesce(item.value->>'sender_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'sender_id')::uuid
    end as sender_id,
    coalesce(
      pg_temp.chat_try_parse_legacy_timestamp(item.value->>'created_at'),
      thread.created_at
    ) as message_created_at
  from public.message_threads thread
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(thread.messages) = 'array'
      then thread.messages else '[]'::jsonb end
  ) with ordinality item(value, ordinality)
)
insert into public.chat_legacy_migration_issues (
  legacy_source_key, thread_id, reason, legacy_item
)
select
  legacy.source_key,
  legacy.thread_id,
  case
    when legacy.sender_id is null then 'invalid_sender_id'
    else 'sender_not_found'
  end,
  legacy.item
from legacy
left join public.users durable_user on durable_user.id = legacy.sender_id
where durable_user.id is null
on conflict (legacy_source_key) do nothing;

with legacy as (
  select
    thread.id as thread_id,
    item.value as item,
    item.ordinality,
    'legacy:' || md5(
      thread.id || ':' || item.ordinality::text || ':' || item.value::text
    ) as source_key,
    case
      when coalesce(item.value->>'sender_id', '') ~*
        '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        then (item.value->>'sender_id')::uuid
    end as sender_id,
    coalesce(
      pg_temp.chat_try_parse_legacy_timestamp(item.value->>'created_at'),
      thread.created_at
    ) as message_created_at
  from public.message_threads thread
  cross join lateral jsonb_array_elements(
    case when jsonb_typeof(thread.messages) = 'array'
      then thread.messages else '[]'::jsonb end
  ) with ordinality item(value, ordinality)
)
insert into public.chat_messages (
  id,
  thread_id,
  sender_id,
  client_message_id,
  sender_name,
  sender_avatar,
  text,
  type,
  product,
  created_at,
  legacy_source_key
)
select
  'legacy_' || md5(legacy.source_key),
  legacy.thread_id,
  legacy.sender_id,
  'legacy_' || md5(legacy.source_key),
  coalesce(legacy.item->>'sender_name', ''),
  coalesce(legacy.item->>'sender_avatar', ''),
  coalesce(legacy.item->>'text', ''),
  case
    when legacy.item->>'type' in ('text', 'product', 'system')
      then legacy.item->>'type'
    else 'text'
  end,
  legacy.item->'product',
  coalesce(legacy.message_created_at, now()),
  legacy.source_key
from legacy
join public.users durable_user on durable_user.id = legacy.sender_id
where not exists (
  select 1
  from public.chat_messages message
  where message.legacy_source_key = legacy.source_key
)
on conflict do nothing;

-- Backfill canonical latest-message pointers after legacy repair.
with latest as (
  select distinct on (message.thread_id)
    message.thread_id,
    message.id,
    public.chat_message_preview(message) as preview
  from public.chat_messages message
  order by message.thread_id, message.created_at desc, message.id desc
)
update public.message_threads thread
set
  last_message_id = latest.id,
  last_message_preview = latest.preview,
  last_message = latest.preview
from latest
where latest.thread_id = thread.id
  and thread.last_message_id is null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'message_threads_last_message_id_fkey'
      and conrelid = 'public.message_threads'::regclass
  ) then
    alter table public.message_threads
      add constraint message_threads_last_message_id_fkey
      foreign key (last_message_id) references public.chat_messages(id)
      on delete set null not valid;
    alter table public.message_threads
      validate constraint message_threads_last_message_id_fkey;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Membership-based RLS helpers
-- ---------------------------------------------------------------------------

create or replace function public.current_user_is_chat_thread_member(
  p_thread_id text
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null and exists (
    select 1
    from public.chat_thread_members member
    where member.thread_id = p_thread_id
      and member.user_id = auth.uid()
      and member.left_at is null
  );
$$;

revoke all on function public.current_user_is_chat_thread_member(text)
  from public, anon;
grant execute on function public.current_user_is_chat_thread_member(text)
  to authenticated;

alter table public.chat_thread_members enable row level security;

drop policy if exists "Users can read their message threads"
  on public.message_threads;
create policy "Members read canonical message threads"
  on public.message_threads for select to authenticated
  using (public.current_user_is_chat_thread_member(id));

drop policy if exists "Users can create their message threads"
  on public.message_threads;

drop policy if exists "Conversation members can read messages"
  on public.chat_messages;
create policy "Members read canonical chat messages"
  on public.chat_messages for select to authenticated
  using (public.current_user_is_chat_thread_member(thread_id));

drop policy if exists "Conversation members can send messages"
  on public.chat_messages;

drop policy if exists "Members can read own chat state"
  on public.chat_thread_member_state;
create policy "Members read own canonical chat state"
  on public.chat_thread_member_state for select to authenticated
  using (
    user_id = auth.uid()
    and public.current_user_is_chat_thread_member(thread_id)
  );

create policy "Members read canonical thread membership"
  on public.chat_thread_members for select to authenticated
  using (public.current_user_is_chat_thread_member(thread_id));

revoke insert, update, delete on public.message_threads from anon, authenticated;
revoke insert, update, delete on public.chat_messages from anon, authenticated;
revoke insert, update, delete on public.chat_thread_members from anon, authenticated;
revoke insert, update, delete on public.chat_thread_member_state
  from anon, authenticated;
grant select on public.message_threads, public.chat_messages,
  public.chat_thread_members, public.chat_thread_member_state
  to authenticated;

-- ---------------------------------------------------------------------------
-- Server-authoritative thread commands
-- ---------------------------------------------------------------------------

create or replace function public.chat_legacy_member_snapshot(p_user_ids uuid[])
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', requested.user_id::text,
        'name', coalesce(profile.name, ''),
        'handle', coalesce(profile.handle, ''),
        'avatar_url', coalesce(profile.avatar_url, '')
      ) order by requested.ordinality
    ),
    '[]'::jsonb
  )
  from unnest(p_user_ids) with ordinality requested(user_id, ordinality)
  left join public.profiles profile on profile.id = requested.user_id;
$$;

revoke all on function public.chat_legacy_member_snapshot(uuid[])
  from public, anon, authenticated;

create or replace function public.create_or_get_direct_thread(
  p_other_user_id uuid
)
returns public.message_threads
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  pair_ids uuid[];
  canonical_key text;
  thread_row public.message_threads%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_other_user_id is null or p_other_user_id = actor_id then
    raise exception 'invalid_direct_recipient' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.users target
    where target.id = p_other_user_id
      and target.auth_user_id = p_other_user_id
      and target.account_status = 'active'
  ) then
    raise exception 'recipient_not_found' using errcode = 'P0002';
  end if;
  if public.users_are_blocked(actor_id, p_other_user_id) then
    raise exception 'chat_blocked' using errcode = '42501';
  end if;

  pair_ids := case when actor_id::text < p_other_user_id::text
    then array[actor_id, p_other_user_id]
    else array[p_other_user_id, actor_id]
  end;
  canonical_key := 'direct:' || pair_ids[1]::text || ':' || pair_ids[2]::text;
  perform pg_advisory_xact_lock(hashtextextended('chat:' || canonical_key, 0));

  select thread.* into thread_row
  from public.message_threads thread
  where thread.conversation_key = canonical_key;
  if found then
    if not public.current_user_is_chat_thread_member(thread_row.id) then
      raise exception 'conversation_membership_required' using errcode = '42501';
    end if;
    return thread_row;
  end if;

  insert into public.message_threads (
    id, kind, conversation_key, buyer_id, seller_id, created_by,
    member_ids, members, is_group, created_at, updated_at
  ) values (
    gen_random_uuid()::text, 'direct', canonical_key, actor_id,
    p_other_user_id, actor_id, pair_ids,
    public.chat_legacy_member_snapshot(pair_ids), false, now(), now()
  ) returning * into thread_row;

  insert into public.chat_thread_members (thread_id, user_id, role)
  values
    (thread_row.id, actor_id, 'buyer'),
    (thread_row.id, p_other_user_id, 'seller')
  on conflict (thread_id, user_id) do nothing;
  insert into public.chat_thread_member_state (thread_id, user_id)
  values (thread_row.id, actor_id), (thread_row.id, p_other_user_id)
  on conflict (thread_id, user_id) do nothing;
  return thread_row;
end;
$$;

create or replace function public.create_or_get_product_thread(
  p_product_id text
)
returns public.message_threads
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  product_row public.products%rowtype;
  canonical_key text;
  participant_ids uuid[];
  thread_row public.message_threads%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  select product.* into product_row
  from public.products product
  where product.id::text = nullif(btrim(p_product_id), '');
  if not found or product_row.seller_id is null then
    raise exception 'product_or_seller_not_found' using errcode = 'P0002';
  end if;
  if product_row.seller_id = actor_id then
    raise exception 'cannot_message_own_product' using errcode = '22023';
  end if;
  canonical_key := 'product:' || product_row.id::text || ':buyer:' ||
    actor_id::text || ':seller:' || product_row.seller_id::text;
  perform pg_advisory_xact_lock(hashtextextended('chat:' || canonical_key, 0));

  select thread.* into thread_row
  from public.message_threads thread
  where thread.conversation_key = canonical_key;
  if found then
    if not public.current_user_is_chat_thread_member(thread_row.id) then
      raise exception 'conversation_membership_required' using errcode = '42501';
    end if;
    return thread_row;
  end if;
  if product_row.status <> 'published' or coalesce(product_row.is_hidden, false) then
    raise exception 'product_not_available' using errcode = '55000';
  end if;
  if public.users_are_blocked(actor_id, product_row.seller_id) then
    raise exception 'chat_blocked' using errcode = '42501';
  end if;

  participant_ids := array[actor_id, product_row.seller_id];
  insert into public.message_threads (
    id, kind, conversation_key, buyer_id, seller_id, product_id,
    product_title, product_image, created_by, member_ids, members,
    is_group, created_at, updated_at
  ) values (
    gen_random_uuid()::text, 'product', canonical_key, actor_id,
    product_row.seller_id, product_row.id::text, product_row.title,
    coalesce(product_row.images[1], ''), actor_id, participant_ids,
    public.chat_legacy_member_snapshot(participant_ids), false, now(), now()
  ) returning * into thread_row;

  insert into public.chat_thread_members (thread_id, user_id, role)
  values
    (thread_row.id, actor_id, 'buyer'),
    (thread_row.id, product_row.seller_id, 'seller')
  on conflict (thread_id, user_id) do nothing;
  insert into public.chat_thread_member_state (thread_id, user_id)
  values (thread_row.id, actor_id), (thread_row.id, product_row.seller_id)
  on conflict (thread_id, user_id) do nothing;
  return thread_row;
end;
$$;

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
  thread_id text := btrim(coalesce(p_client_thread_id, ''));
  thread_row public.message_threads%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_title, ''))) not between 1 and 120 then
    raise exception 'invalid_group_metadata' using errcode = '22023';
  end if;
  if thread_id !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    raise exception 'invalid_client_thread_id' using errcode = '22023';
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

  perform pg_advisory_xact_lock(
    hashtextextended('chat:group:' || thread_id, 0)
  );
  select thread.* into thread_row
  from public.message_threads thread
  where thread.conversation_key = 'group:' || thread_id;
  if found then
    if thread_row.created_by is distinct from actor_id
       or not public.current_user_is_chat_thread_member(thread_row.id) then
      raise exception 'conversation_membership_required' using errcode = '42501';
    end if;
    return thread_row;
  end if;

  insert into public.message_threads (
    id, kind, conversation_key, buyer_id, seller_id, is_group, title,
    group_avatar, created_by, member_ids, members, created_at, updated_at
  ) values (
    thread_id, 'group', 'group:' || thread_id, normalized_members[1],
    normalized_members[2], true, btrim(p_title), '',
    actor_id, normalized_members,
    public.chat_legacy_member_snapshot(normalized_members), now(), now()
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

-- ---------------------------------------------------------------------------
-- Atomic message commands
-- ---------------------------------------------------------------------------

create or replace function public.send_chat_message(
  p_thread_id text,
  p_client_message_id text,
  p_type text default 'text',
  p_text text default '',
  p_product jsonb default null,
  p_attachment jsonb default null,
  p_reply_to_id text default null
)
returns public.chat_messages
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  thread_row public.message_threads%rowtype;
  message_row public.chat_messages%rowtype;
  clean_type text := lower(btrim(coalesce(p_type, 'text')));
  clean_text text := btrim(coalesce(p_text, ''));
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_client_message_id is null
     or char_length(p_client_message_id) not between 1 and 200
     or p_client_message_id !~ '^[A-Za-z0-9._:-]+$' then
    raise exception 'invalid_client_message_id' using errcode = '22023';
  end if;
  if clean_type not in ('text', 'product', 'image', 'video')
     or char_length(clean_text) > 8000
     or (clean_type = 'text' and clean_text = '') then
    raise exception 'invalid_chat_message' using errcode = '22023';
  end if;

  select thread.* into thread_row
  from public.message_threads thread
  where thread.id = p_thread_id
  for update;
  if not found then
    raise exception 'thread_not_found' using errcode = 'P0002';
  end if;
  if not exists (
    select 1 from public.chat_thread_members member
    where member.thread_id = thread_row.id
      and member.user_id = actor_id
      and member.left_at is null
  ) then
    raise exception 'conversation_membership_required' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.chat_thread_members member
    where member.thread_id = thread_row.id
      and member.left_at is null
      and member.user_id <> actor_id
      and public.users_are_blocked(actor_id, member.user_id)
  ) then
    raise exception 'chat_blocked' using errcode = '42501';
  end if;

  select message.* into message_row
  from public.chat_messages message
  where message.thread_id = thread_row.id
    and message.sender_id = actor_id
    and message.client_message_id = p_client_message_id;
  if found then
    return message_row;
  end if;

  if clean_type = 'product' and (
    jsonb_typeof(p_product) is distinct from 'object'
    or nullif(p_product->>'id', '') is null
    or not exists (
      select 1 from public.products product
      where product.id::text = p_product->>'id'
        and product.status = 'published'
        and not coalesce(product.is_hidden, false)
    )
  ) then
    raise exception 'invalid_shared_product' using errcode = '22023';
  end if;
  if clean_type in ('image', 'video') and p_attachment is null then
    raise exception 'invalid_chat_attachment' using errcode = '22023';
  end if;
  if p_reply_to_id is not null and not exists (
    select 1 from public.chat_messages reply
    where reply.id = p_reply_to_id and reply.thread_id = thread_row.id
  ) then
    raise exception 'invalid_chat_reply' using errcode = '22023';
  end if;

  insert into public.chat_messages (
    id, thread_id, sender_id, client_message_id, text, type, product,
    attachment, reply_to_id, created_at
  ) values (
    gen_random_uuid()::text, thread_row.id, actor_id, p_client_message_id,
    clean_text, clean_type,
    case when clean_type = 'product' then p_product end,
    case when clean_type in ('image', 'video') then p_attachment end,
    p_reply_to_id, now()
  ) returning * into message_row;

  update public.message_threads
  set
    last_message_id = message_row.id,
    last_message_preview = public.chat_message_preview(message_row),
    last_message = public.chat_message_preview(message_row),
    updated_at = message_row.created_at
  where id = thread_row.id;

  insert into public.chat_thread_member_state (
    thread_id, user_id, unread_count, updated_at
  )
  select
    member.thread_id,
    member.user_id,
    case when member.user_id = actor_id then 0 else 1 end,
    now()
  from public.chat_thread_members member
  where member.thread_id = thread_row.id and member.left_at is null
  on conflict (thread_id, user_id) do update
  set
    unread_count = case
      when excluded.user_id = actor_id
        then public.chat_thread_member_state.unread_count
      else public.chat_thread_member_state.unread_count + 1
    end,
    updated_at = now();
  return message_row;
exception
  when unique_violation then
    select message.* into message_row
    from public.chat_messages message
    where message.thread_id = p_thread_id
      and message.sender_id = actor_id
      and message.client_message_id = p_client_message_id;
    if found then return message_row; end if;
    raise;
end;
$$;

create or replace function public.send_product_chat_message(
  p_product_id text,
  p_client_message_id text,
  p_text text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  seller_id uuid;
  canonical_key text;
  thread_existed boolean;
  thread_has_messages boolean;
  thread_row public.message_threads%rowtype;
  message_row public.chat_messages%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  select product.seller_id into seller_id
  from public.products product
  where product.id::text = nullif(btrim(p_product_id), '');
  if not found or seller_id is null then
    raise exception 'product_or_seller_not_found' using errcode = 'P0002';
  end if;
  canonical_key := 'product:' || btrim(p_product_id) || ':buyer:' ||
    actor_id::text || ':seller:' || seller_id::text;
  -- Acquire the same transaction lock before deciding whether the thread is
  -- new. This prevents two first-message calls from both sending a canned
  -- opener.
  perform pg_advisory_xact_lock(hashtextextended('chat:' || canonical_key, 0));
  thread_existed := exists (
    select 1 from public.message_threads thread
    where thread.conversation_key = canonical_key
  );
  thread_row := public.create_or_get_product_thread(p_product_id);

  thread_has_messages := exists (
    select 1 from public.chat_messages existing_message
    where existing_message.thread_id = thread_row.id
  );

  select message.* into message_row
  from public.chat_messages message
  where message.thread_id = thread_row.id
    and message.sender_id = actor_id
    and message.client_message_id = p_client_message_id;
  if found then
    return jsonb_build_object(
      'thread', to_jsonb(thread_row),
      'message', to_jsonb(message_row),
      'created_thread', false,
      'created_message', false
    );
  end if;

  -- Old clients could commit an empty product thread before their separate
  -- first-message insert failed. Repair that partial state exactly once.
  if not thread_has_messages then
    message_row := public.send_chat_message(
      thread_row.id,
      p_client_message_id,
      'text',
      p_text,
      null,
      null,
      null
    );
  end if;
  return jsonb_build_object(
    'thread', to_jsonb(thread_row),
    'message', case
      when message_row.id is null then null
      else to_jsonb(message_row)
    end,
    'created_thread', not thread_existed,
    'created_message', message_row.id is not null
  );
end;
$$;

create or replace function public.get_chat_message_by_client_id(
  p_thread_id text,
  p_client_message_id text
)
returns public.chat_messages
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  message_row public.chat_messages%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.current_user_is_chat_thread_member(p_thread_id) then
    raise exception 'conversation_membership_required' using errcode = '42501';
  end if;
  select message.* into message_row
  from public.chat_messages message
  where message.thread_id = p_thread_id
    and message.sender_id = actor_id
    and message.client_message_id = p_client_message_id;
  return message_row;
end;
$$;

create or replace function public.acknowledge_chat_messages_delivered(
  p_thread_id text,
  p_message_ids text[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  affected integer := 0;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.current_user_is_chat_thread_member(p_thread_id) then
    raise exception 'conversation_membership_required' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_message_ids), 0) = 0
     or cardinality(p_message_ids) > 200
     or array_position(p_message_ids, null) is not null then
    raise exception 'invalid_delivery_batch' using errcode = '22023';
  end if;
  update public.chat_messages message
  set delivered_to = array_append(message.delivered_to, actor_id)
  where message.thread_id = p_thread_id
    and message.id = any(p_message_ids)
    and message.sender_id is distinct from actor_id
    and not (actor_id = any(message.delivered_to));
  get diagnostics affected = row_count;
  return affected;
end;
$$;

create or replace function public.acknowledge_chat_message_delivery(
  p_thread_id text,
  p_message_id text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
begin
  return public.acknowledge_chat_messages_delivered(
    p_thread_id,
    array[p_message_id]
  ) > 0;
end;
$$;

create or replace function public.mark_chat_thread_read(p_thread_id text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_id uuid := auth.uid();
  latest public.chat_messages%rowtype;
  affected integer := 0;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.current_user_is_chat_thread_member(p_thread_id) then
    raise exception 'conversation_membership_required' using errcode = '42501';
  end if;
  select message.* into latest
  from public.chat_messages message
  where message.thread_id = p_thread_id
  order by message.created_at desc, message.id desc
  limit 1;

  insert into public.chat_thread_member_state (
    thread_id, user_id, last_read_at, last_read_message_id,
    unread_count, updated_at
  ) values (
    p_thread_id, actor_id, now(), latest.id, 0, now()
  )
  on conflict (thread_id, user_id) do update
  set
    last_read_at = excluded.last_read_at,
    last_read_message_id = excluded.last_read_message_id,
    unread_count = 0,
    updated_at = excluded.updated_at;

  if latest.id is not null then
    update public.chat_messages message
    set read_by = array_append(message.read_by, actor_id)
    where message.thread_id = p_thread_id
      and message.sender_id is distinct from actor_id
      and not (actor_id = any(message.read_by))
      and (message.created_at, message.id) <= (latest.created_at, latest.id);
    get diagnostics affected = row_count;
  end if;
  return affected;
end;
$$;

-- Keep both canonical and legacy previews coherent for current clients.
create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.message_threads
  set
    last_message_id = new.id,
    last_message_preview = public.chat_message_preview(new),
    last_message = public.chat_message_preview(new),
    updated_at = greatest(updated_at, new.created_at)
  where id = new.thread_id
    and new.created_at >= updated_at;
  return new;
end;
$$;

create or replace function public.refresh_thread_preview_from_message_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  latest public.chat_messages%rowtype;
begin
  select message.* into latest
  from public.chat_messages message
  where message.thread_id = new.thread_id
  order by message.created_at desc, message.id desc
  limit 1;
  if found then
    update public.message_threads
    set
      last_message_id = latest.id,
      last_message_preview = public.chat_message_preview(latest),
      last_message = public.chat_message_preview(latest),
      updated_at = greatest(updated_at, now())
    where id = new.thread_id;
  end if;
  return new;
end;
$$;

revoke all on function public.touch_thread_from_message()
  from public, anon, authenticated;
revoke all on function public.refresh_thread_preview_from_message_update()
  from public, anon, authenticated;

-- Public command grants are explicit. PostgreSQL otherwise grants new
-- functions to PUBLIC by default.
revoke all on function public.create_or_get_direct_thread(uuid)
  from public, anon;
grant execute on function public.create_or_get_direct_thread(uuid)
  to authenticated;
revoke all on function public.create_or_get_product_thread(text)
  from public, anon;
grant execute on function public.create_or_get_product_thread(text)
  to authenticated;
revoke all on function public.create_group_thread(uuid[], text, text)
  from public, anon;
grant execute on function public.create_group_thread(uuid[], text, text)
  to authenticated;
revoke all on function public.send_chat_message(
  text, text, text, text, jsonb, jsonb, text
) from public, anon;
grant execute on function public.send_chat_message(
  text, text, text, text, jsonb, jsonb, text
) to authenticated;
revoke all on function public.send_product_chat_message(text, text, text)
  from public, anon;
grant execute on function public.send_product_chat_message(text, text, text)
  to authenticated;
revoke all on function public.get_chat_message_by_client_id(text, text)
  from public, anon;
grant execute on function public.get_chat_message_by_client_id(text, text)
  to authenticated;
revoke all on function public.acknowledge_chat_message_delivery(text, text)
  from public, anon;
grant execute on function public.acknowledge_chat_message_delivery(text, text)
  to authenticated;
revoke all on function public.acknowledge_chat_messages_delivered(text, text[])
  from public, anon;
grant execute on function public.acknowledge_chat_messages_delivered(text, text[])
  to authenticated;
revoke all on function public.mark_chat_thread_read(text)
  from public, anon;
grant execute on function public.mark_chat_thread_read(text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Push retry claim: preserve the UUID/null contract used by the deployed Edge
-- function. Only the transaction that atomically owns the claim receives UUID.
-- ---------------------------------------------------------------------------

create or replace function public.claim_push_delivery(
  p_message_id text,
  p_sender_id uuid,
  p_thread_id text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  attempt public.push_delivery_attempts%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.chat_messages message
    where message.id = p_message_id
      and message.thread_id = p_thread_id
      and message.sender_id = p_sender_id
  ) then
    raise exception 'push_message_contract_mismatch' using errcode = 'P0002';
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended('push-delivery:' || p_message_id, 0)
  );
  select delivery.* into attempt
  from public.push_delivery_attempts delivery
  where delivery.message_id = p_message_id
  for update;

  if found then
    if attempt.status in ('sent', 'skipped') then return null; end if;
    if attempt.status = 'processing'
       and attempt.claimed_at > now() - interval '2 minutes' then
      return null;
    end if;
    if attempt.status = 'failed'
       and coalesce(attempt.completed_at, attempt.claimed_at)
         > now() - interval '30 seconds' then
      return null;
    end if;
    update public.push_delivery_attempts
    set status = 'processing', error = '', claimed_at = now(), completed_at = null
    where id = attempt.id;
    return attempt.id;
  end if;

  if (
    select count(*) from public.push_delivery_attempts delivery
    where delivery.sender_id = p_sender_id
      and delivery.claimed_at >= now() - interval '1 minute'
  ) >= 20 then
    raise exception 'push_rate_limited' using errcode = '55000';
  end if;
  insert into public.push_delivery_attempts (
    message_id, sender_id, thread_id
  ) values (p_message_id, p_sender_id, p_thread_id)
  returning * into attempt;
  return attempt.id;
end;
$$;

revoke all on function public.claim_push_delivery(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_push_delivery(text, uuid, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------

alter table public.message_threads replica identity full;
alter table public.chat_messages replica identity full;
alter table public.chat_thread_members replica identity full;
alter table public.chat_thread_member_state replica identity full;

do $$
declare
  relation_name text;
begin
  foreach relation_name in array array[
    'message_threads',
    'chat_messages',
    'chat_thread_members',
    'chat_thread_member_state'
  ] loop
    if not exists (
      select 1
      from pg_publication_tables published
      where published.pubname = 'supabase_realtime'
        and published.schemaname = 'public'
        and published.tablename = relation_name
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        relation_name
      );
    end if;
  end loop;
end
$$;

notify pgrst, 'reload schema';

commit;
