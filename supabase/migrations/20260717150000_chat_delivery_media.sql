-- Bring the persisted chat contract in line with the Flutter client and add
-- private, membership-scoped media storage. The migration is intentionally
-- additive/idempotent so it can repair projects created from the older
-- schema.sql as well as projects that already ran the conversation migration.

alter table public.message_threads
  add column if not exists is_group boolean not null default false,
  add column if not exists title text not null default '',
  add column if not exists group_avatar text not null default '',
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists member_ids uuid[] not null default '{}',
  add column if not exists members jsonb not null default '[]'::jsonb,
  add column if not exists is_pinned boolean not null default false,
  add column if not exists is_muted boolean not null default false,
  add column if not exists is_archived boolean not null default false,
  add column if not exists draft text not null default '',
  add column if not exists last_read_at timestamptz;

update public.message_threads
set member_ids = array_remove(array[buyer_id, seller_id], null)
where cardinality(member_ids) = 0;

create index if not exists message_threads_member_ids_idx
  on public.message_threads using gin (member_ids);

create table if not exists public.chat_messages (
  id text primary key,
  thread_id text not null references public.message_threads(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  sender_name text not null default '',
  sender_avatar text not null default '',
  text text not null default '',
  type text not null default 'text',
  product jsonb,
  attachment jsonb,
  reply_to_id text,
  reply_snapshot jsonb,
  edited_at timestamptz,
  deleted_at timestamptz,
  read_by uuid[] not null default '{}',
  reactions jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.chat_messages
  add column if not exists attachment jsonb,
  add column if not exists reply_to_id text,
  add column if not exists reply_snapshot jsonb,
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz,
  add column if not exists read_by uuid[] not null default '{}',
  add column if not exists reactions jsonb not null default '{}'::jsonb;

alter table public.chat_messages
  drop constraint if exists chat_messages_type_check;
alter table public.chat_messages
  add constraint chat_messages_type_check
  check (type in ('text', 'product', 'system', 'image', 'video'));

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_messages_reply_to_id_fkey'
      and conrelid = 'public.chat_messages'::regclass
  ) then
    alter table public.chat_messages
      add constraint chat_messages_reply_to_id_fkey
      foreign key (reply_to_id) references public.chat_messages(id)
      on delete set null;
  end if;
end;
$$;

create index if not exists chat_messages_thread_created_idx
  on public.chat_messages (thread_id, created_at, id);
create index if not exists chat_messages_sender_created_idx
  on public.chat_messages (sender_id, created_at desc);

create table if not exists public.chat_thread_member_state (
  thread_id text not null references public.message_threads(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_pinned boolean not null default false,
  is_muted boolean not null default false,
  is_archived boolean not null default false,
  draft text not null default '',
  last_read_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (thread_id, user_id)
);

insert into public.chat_thread_member_state (thread_id, user_id)
select thread.id, member_id
from public.message_threads thread
cross join lateral unnest(thread.member_ids) member_id
on conflict (thread_id, user_id) do nothing;

alter table public.message_threads enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_thread_member_state enable row level security;

drop policy if exists "Users can read their message threads"
  on public.message_threads;
create policy "Users can read their message threads"
  on public.message_threads for select to authenticated
  using (auth.uid() = any(member_ids));

drop policy if exists "Users can create their message threads"
  on public.message_threads;
create policy "Users can create their message threads"
  on public.message_threads for insert to authenticated
  with check (
    auth.uid() = any(member_ids)
    and cardinality(member_ids) between 2 and 50
    and not exists (
      select 1
      from unnest(member_ids) member_id
      where public.users_are_blocked(auth.uid(), member_id)
    )
  );

drop policy if exists "Users can update their message threads"
  on public.message_threads;
create policy "Users can update their message threads"
  on public.message_threads for update to authenticated
  using (auth.uid() = any(member_ids))
  with check (auth.uid() = any(member_ids));

drop policy if exists "Conversation members can read messages"
  on public.chat_messages;
create policy "Conversation members can read messages"
  on public.chat_messages for select to authenticated
  using (exists (
    select 1
    from public.message_threads thread
    where thread.id = thread_id
      and auth.uid() = any(thread.member_ids)
  ));

drop policy if exists "Conversation members can send messages"
  on public.chat_messages;
create policy "Conversation members can send messages"
  on public.chat_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and char_length(text) <= 8000
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
      and nullif(attachment->>'storage_path', '') is not null
    ))
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = thread_id
        and auth.uid() = any(thread.member_ids)
        and not exists (
          select 1
          from unnest(thread.member_ids) member_id
          where public.users_are_blocked(auth.uid(), member_id)
        )
    )
  );

drop policy if exists "Senders can update their messages"
  on public.chat_messages;
create policy "Senders can update their messages"
  on public.chat_messages for update to authenticated
  using (sender_id = auth.uid())
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = thread_id
        and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Members can read own chat state"
  on public.chat_thread_member_state;
create policy "Members can read own chat state"
  on public.chat_thread_member_state for select to authenticated
  using (user_id = auth.uid());

drop policy if exists "Members can insert own chat state"
  on public.chat_thread_member_state;
create policy "Members can insert own chat state"
  on public.chat_thread_member_state for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.message_threads thread
      where thread.id = thread_id and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Members can update own chat state"
  on public.chat_thread_member_state;
create policy "Members can update own chat state"
  on public.chat_thread_member_state for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create or replace function public.hydrate_chat_message_sender()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_name text;
  profile_avatar text;
begin
  select profile.name, profile.avatar_url
  into profile_name, profile_avatar
  from public.profiles profile
  where profile.id = new.sender_id;

  new.sender_name := coalesce(nullif(btrim(profile_name), ''), new.sender_name, '');
  new.sender_avatar := coalesce(nullif(btrim(profile_avatar), ''), new.sender_avatar, '');
  return new;
end;
$$;

drop trigger if exists hydrate_chat_message_sender_before_insert
  on public.chat_messages;
create trigger hydrate_chat_message_sender_before_insert
before insert on public.chat_messages
for each row execute function public.hydrate_chat_message_sender();

create or replace function public.protect_chat_message_identity()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.id is distinct from old.id
     or new.thread_id is distinct from old.thread_id
     or new.sender_id is distinct from old.sender_id
     or new.created_at is distinct from old.created_at then
    raise exception using errcode = '42501', message = 'chat_message_identity_is_immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_chat_message_identity_before_update
  on public.chat_messages;
create trigger protect_chat_message_identity_before_update
before update on public.chat_messages
for each row execute function public.protect_chat_message_identity();

create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.message_threads
  set
    last_message = case new.type
      when 'product' then 'Объявление: ' || coalesce(new.product->>'title', '')
      when 'image' then coalesce(nullif(btrim(new.text), ''), 'Фотография')
      when 'video' then coalesce(nullif(btrim(new.text), ''), 'Видео')
      else new.text
    end,
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

drop trigger if exists touch_thread_after_message on public.chat_messages;
create trigger touch_thread_after_message
after insert on public.chat_messages
for each row execute function public.touch_thread_from_message();

create or replace function public.mark_chat_thread_read(p_thread_id text)
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
    raise exception using errcode = '42501', message = 'authentication_required';
  end if;
  if not exists (
    select 1 from public.message_threads thread
    where thread.id = p_thread_id and actor_id = any(thread.member_ids)
  ) then
    raise exception using errcode = '42501', message = 'conversation_membership_required';
  end if;

  insert into public.chat_thread_member_state (
    thread_id, user_id, last_read_at, updated_at
  ) values (p_thread_id, actor_id, now(), now())
  on conflict (thread_id, user_id) do update
  set last_read_at = excluded.last_read_at, updated_at = excluded.updated_at;

  update public.chat_messages message
  set read_by = array_append(message.read_by, actor_id)
  where message.thread_id = p_thread_id
    and message.sender_id <> actor_id
    and not (actor_id = any(message.read_by));
  get diagnostics affected = row_count;
  return affected;
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
set search_path = public
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
    and actor_id = any(thread.member_ids)
  for update of message;
  if not found then
    raise exception using errcode = '42501', message = 'conversation_membership_required';
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

revoke all on function public.mark_chat_thread_read(text) from public;
grant execute on function public.mark_chat_thread_read(text) to authenticated;
revoke all on function public.toggle_chat_message_reaction(text, text, text)
  from public;
grant execute on function public.toggle_chat_message_reaction(text, text, text)
  to authenticated;

grant select, insert, update on public.message_threads to authenticated;
grant select, insert, update on public.chat_messages to authenticated;
grant select, insert, update on public.chat_thread_member_state to authenticated;

insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'chat-media',
  'chat-media',
  false,
  104857600,
  array[
    'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
    'video/mp4', 'video/quicktime', 'video/webm'
  ]::text[]
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Conversation members can read chat media"
  on storage.objects;
create policy "Conversation members can read chat media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[1] = 'threads'
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = (storage.foldername(name))[2]
        and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Conversation members can upload own chat media"
  on storage.objects;
create policy "Conversation members can upload own chat media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[1] = 'threads'
    and (storage.foldername(name))[3] = auth.uid()::text
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = (storage.foldername(name))[2]
        and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Uploaders can delete own chat media"
  on storage.objects;
create policy "Uploaders can delete own chat media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and (storage.foldername(name))[1] = 'threads'
    and (storage.foldername(name))[3] = auth.uid()::text
  );

alter table public.message_threads replica identity full;
alter table public.chat_messages replica identity full;

do $$
begin
  alter publication supabase_realtime add table public.message_threads;
exception when duplicate_object then null;
end;
$$;

do $$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception when duplicate_object then null;
end;
$$;

notify pgrst, 'reload schema';
