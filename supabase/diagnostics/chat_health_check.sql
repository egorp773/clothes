-- READ ONLY. Run in Supabase SQL Editor before and after the chat migration.
-- Every statement only reads catalog/application data.

select
  now() at time zone 'utc' as checked_at_utc,
  current_database() as database_name,
  current_user as database_role,
  current_setting('server_version') as postgres_version;

-- Expected and legacy chat relations.
select
  expected.table_name,
  to_regclass('public.' || expected.table_name) is not null as exists
from unnest(array[
  'message_threads',
  'chat_messages',
  'chat_thread_members',
  'chat_thread_member_state',
  'chat_thread_user_state',
  'chat_message_reactions',
  'notification_settings',
  'device_push_tokens',
  'push_delivery_attempts'
]) expected(table_name)
order by expected.table_name;

select
  columns.table_name,
  columns.ordinal_position,
  columns.column_name,
  columns.data_type,
  columns.udt_name,
  columns.is_nullable,
  columns.column_default
from information_schema.columns columns
where columns.table_schema = 'public'
  and columns.table_name in (
    'message_threads', 'chat_messages', 'chat_thread_members',
    'chat_thread_member_state', 'chat_thread_user_state',
    'chat_message_reactions', 'notification_settings', 'device_push_tokens',
    'push_delivery_attempts'
  )
order by columns.table_name, columns.ordinal_position;

select
  tables.relname as table_name,
  tables.relrowsecurity as rls_enabled,
  tables.relforcerowsecurity as rls_forced,
  tables.relreplident as replica_identity
from pg_class tables
join pg_namespace schemas on schemas.oid = tables.relnamespace
where schemas.nspname = 'public'
  and tables.relname like any (array['chat_%', 'message_threads'])
  and tables.relkind in ('r', 'p')
order by tables.relname;

select
  policies.tablename,
  policies.policyname,
  policies.permissive,
  policies.roles,
  policies.cmd,
  policies.qual,
  policies.with_check
from pg_policies policies
where policies.schemaname = 'public'
  and policies.tablename like any (array['chat_%', 'message_threads'])
order by policies.tablename, policies.policyname;

select
  grants.table_name,
  grants.grantee,
  grants.privilege_type
from information_schema.role_table_grants grants
where grants.table_schema = 'public'
  and grants.table_name like any (array['chat_%', 'message_threads'])
  and grants.grantee in ('anon', 'authenticated', 'service_role')
order by grants.table_name, grants.grantee, grants.privilege_type;

select
  indexes.tablename,
  indexes.indexname,
  indexes.indexdef
from pg_indexes indexes
where indexes.schemaname = 'public'
  and indexes.tablename like any (array['chat_%', 'message_threads'])
order by indexes.tablename, indexes.indexname;

select
  constraints.conrelid::regclass::text as table_name,
  constraints.conname,
  constraints.contype,
  constraints.convalidated,
  pg_get_constraintdef(constraints.oid, true) as definition
from pg_constraint constraints
where constraints.connamespace = 'public'::regnamespace
  and constraints.conrelid::regclass::text like any (
    array['public.chat_%', 'public.message_threads']
  )
order by table_name, constraints.conname;

select
  routines.proname as function_name,
  pg_get_function_identity_arguments(routines.oid) as arguments,
  pg_get_function_result(routines.oid) as result_type,
  routines.prosecdef as security_definer,
  routines.proconfig as function_settings,
  routines.proacl as acl
from pg_proc routines
join pg_namespace schemas on schemas.oid = routines.pronamespace
where schemas.nspname = 'public'
  and routines.proname in (
    'create_or_get_direct_thread',
    'create_or_get_product_thread',
    'create_group_thread',
    'send_chat_message',
    'send_product_chat_message',
    'mark_chat_thread_read',
    'update_chat_thread_settings',
    'toggle_chat_message_reaction',
    'edit_chat_message',
    'delete_chat_message',
    'acknowledge_chat_message_delivery',
    'acknowledge_chat_messages_delivered',
    'get_chat_message_by_client_id',
    'claim_push_delivery'
  )
order by routines.proname, arguments;

select
  published.pubname,
  published.schemaname,
  published.tablename
from pg_publication_tables published
where published.pubname = 'supabase_realtime'
  and published.schemaname = 'public'
  and published.tablename in (
    'message_threads', 'chat_messages', 'chat_thread_members',
    'chat_thread_member_state'
  )
order by published.tablename;

-- Row counts. These statements assume the baseline chat migrations exist.
select 'message_threads' as relation, count(*) as rows
from public.message_threads
union all
select 'chat_messages', count(*) from public.chat_messages
union all
select 'chat_thread_members', count(*) from public.chat_thread_members
union all
select 'chat_thread_member_state', count(*)
from public.chat_thread_member_state
union all
select 'notification_settings', count(*) from public.notification_settings
union all
select 'device_push_tokens', count(*) from public.device_push_tokens;

-- Integrity/anomaly summary. Every non-zero count needs investigation.
select 'messages_without_thread' as anomaly, count(*) as affected
from public.chat_messages message
left join public.message_threads thread on thread.id = message.thread_id
where thread.id is null
union all
select 'threads_without_active_members', count(*)
from public.message_threads thread
where not exists (
  select 1 from public.chat_thread_members member
  where member.thread_id = thread.id and member.left_at is null
)
union all
select 'messages_sender_not_active_member', count(*)
from public.chat_messages message
where message.sender_id is not null
  and not exists (
    select 1 from public.chat_thread_members member
    where member.thread_id = message.thread_id
      and member.user_id = message.sender_id
      and member.joined_at <= message.created_at
  )
union all
select 'messages_null_sender', count(*)
from public.chat_messages where sender_id is null
union all
select 'threads_buyer_not_member', count(*)
from public.message_threads thread
where thread.buyer_id is not null and not exists (
  select 1 from public.chat_thread_members member
  where member.thread_id = thread.id and member.user_id = thread.buyer_id
)
union all
select 'threads_seller_not_member', count(*)
from public.message_threads thread
where thread.seller_id is not null and not exists (
  select 1 from public.chat_thread_members member
  where member.thread_id = thread.id and member.user_id = thread.seller_id
)
union all
select 'direct_threads_same_buyer_seller', count(*)
from public.message_threads
where kind = 'direct' and buyer_id = seller_id
union all
select 'product_thread_seller_mismatch', count(*)
from public.message_threads thread
join public.products product on product.id::text = thread.product_id
where thread.kind = 'product'
  and thread.seller_id is distinct from product.seller_id
union all
select 'state_without_active_membership', count(*)
from public.chat_thread_member_state state
where not exists (
  select 1 from public.chat_thread_members member
  where member.thread_id = state.thread_id
    and member.user_id = state.user_id
    and member.left_at is null
)
union all
select 'negative_unread', count(*)
from public.chat_thread_member_state where unread_count < 0
union all
select 'last_message_wrong_thread', count(*)
from public.message_threads thread
join public.chat_messages message on message.id = thread.last_message_id
where message.thread_id <> thread.id
union all
select 'legacy_migration_issues', count(*)
from public.chat_legacy_migration_issues;

select
  message.thread_id,
  message.sender_id,
  message.client_message_id,
  count(*) as duplicate_count,
  array_agg(message.id order by message.created_at, message.id) as message_ids
from public.chat_messages message
group by message.thread_id, message.sender_id, message.client_message_id
having count(*) > 1
order by duplicate_count desc, message.thread_id;

select
  thread.id as thread_id,
  jsonb_array_length(
    case when jsonb_typeof(thread.messages) = 'array'
      then thread.messages else '[]'::jsonb end
  ) as legacy_items,
  count(message.id) filter (where message.legacy_source_key is not null)
    as normalized_legacy_items
from public.message_threads thread
left join public.chat_messages message on message.thread_id = thread.id
where jsonb_array_length(
  case when jsonb_typeof(thread.messages) = 'array'
    then thread.messages else '[]'::jsonb end
) > 0
group by thread.id, thread.messages
order by thread.id;

select
  issue.legacy_source_key,
  issue.thread_id,
  issue.reason,
  issue.detected_at
from public.chat_legacy_migration_issues issue
order by issue.detected_at, issue.thread_id;

-- Security regression checks: expected result is zero rows.
select grants.table_name, grants.grantee, grants.privilege_type
from information_schema.role_table_grants grants
where grants.table_schema = 'public'
  and grants.table_name in (
    'message_threads', 'chat_messages', 'chat_thread_members',
    'chat_thread_member_state'
  )
  and grants.grantee in ('anon', 'authenticated')
  and grants.privilege_type in ('INSERT', 'UPDATE', 'DELETE')
order by grants.table_name, grants.grantee, grants.privilege_type;

select
  bucket.id,
  bucket.public,
  bucket.file_size_limit,
  bucket.allowed_mime_types
from storage.buckets bucket
where bucket.id = 'chat-media';

select
  policies.policyname,
  policies.cmd,
  policies.roles,
  policies.qual,
  policies.with_check
from pg_policies policies
where policies.schemaname = 'storage'
  and policies.tablename = 'objects'
  and (
    coalesce(policies.qual, '') ilike '%chat-media%'
    or coalesce(policies.with_check, '') ilike '%chat-media%'
  )
order by policies.policyname;
