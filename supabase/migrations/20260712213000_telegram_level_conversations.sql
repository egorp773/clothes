-- Group conversations and conflict-safe message delivery.
create extension if not exists pg_trgm with schema extensions;

create index if not exists profiles_handle_trgm_idx
  on public.profiles using gin (lower(handle) extensions.gin_trgm_ops);
create index if not exists profiles_name_trgm_idx
  on public.profiles using gin (lower(name) extensions.gin_trgm_ops);

alter table public.message_threads
  add column if not exists is_group boolean not null default false,
  add column if not exists title text not null default '',
  add column if not exists group_avatar text not null default '',
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists member_ids uuid[] not null default '{}',
  add column if not exists members jsonb not null default '[]'::jsonb;

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
  type text not null default 'text'
    check (type in ('text', 'product', 'system')),
  product jsonb,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_thread_created_idx
  on public.chat_messages (thread_id, created_at);

insert into public.chat_messages (
  id, thread_id, sender_id, sender_name, sender_avatar,
  text, type, product, created_at
)
select
  coalesce(item->>'id', gen_random_uuid()::text),
  thread.id,
  (item->>'sender_id')::uuid,
  coalesce(item->>'sender_name', ''),
  coalesce(item->>'sender_avatar', ''),
  coalesce(item->>'text', ''),
  case
    when item->>'type' in ('text', 'product', 'system') then item->>'type'
    else 'text'
  end,
  item->'product',
  coalesce((item->>'created_at')::timestamptz, thread.updated_at)
from public.message_threads thread
cross join lateral jsonb_array_elements(thread.messages) item
where (item->>'sender_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
on conflict (id) do nothing;

alter table public.chat_messages enable row level security;

drop policy if exists "Conversation members can read messages"
  on public.chat_messages;
create policy "Conversation members can read messages"
  on public.chat_messages for select to authenticated
  using (exists (
    select 1 from public.message_threads thread
    where thread.id = thread_id and auth.uid() = any(thread.member_ids)
  ));

drop policy if exists "Conversation members can send messages"
  on public.chat_messages;
create policy "Conversation members can send messages"
  on public.chat_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.message_threads thread
      where thread.id = thread_id and auth.uid() = any(thread.member_ids)
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
      select 1 from public.message_threads thread
      where thread.id = thread_id and auth.uid() = any(thread.member_ids)
    )
  );

drop policy if exists "Users can read their message threads"
  on public.message_threads;
create policy "Users can read their message threads"
  on public.message_threads for select to authenticated
  using (auth.uid() = any(member_ids));

drop policy if exists "Users can create their message threads"
  on public.message_threads;
create policy "Users can create their message threads"
  on public.message_threads for insert to authenticated
  with check (auth.uid() = any(member_ids));

drop policy if exists "Users can update their message threads"
  on public.message_threads;
create policy "Users can update their message threads"
  on public.message_threads for update to authenticated
  using (auth.uid() = any(member_ids))
  with check (auth.uid() = any(member_ids));

create or replace function public.protect_thread_membership()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.member_ids is distinct from old.member_ids
     or new.members is distinct from old.members
     or new.created_by is distinct from old.created_by then
    if old.created_by is null or auth.uid() is distinct from old.created_by then
      raise exception 'Only the conversation creator can change members';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_message_thread_membership
  on public.message_threads;
create trigger protect_message_thread_membership
before update on public.message_threads
for each row execute function public.protect_thread_membership();

create or replace function public.touch_thread_from_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.message_threads
  set
    last_message = case
      when new.type = 'product'
        then 'Объявление: ' || coalesce(new.product->>'title', '')
      else new.text
    end,
    updated_at = greatest(updated_at, new.created_at)
  where id = new.thread_id and new.created_at >= updated_at;
  return new;
end;
$$;

drop trigger if exists touch_thread_after_message on public.chat_messages;
create trigger touch_thread_after_message
after insert on public.chat_messages
for each row execute function public.touch_thread_from_message();

do $$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception
  when duplicate_object then null;
end;
$$;

notify pgrst, 'reload schema';
