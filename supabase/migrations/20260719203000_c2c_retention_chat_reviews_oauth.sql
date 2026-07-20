-- Evidence-preserving chat moderation, order-bound reviews, accountable
-- anonymisation, OAuth one-time exchange primitives and push idempotency.

begin;

-- Retention periods are intentionally not invented in code. The operator must
-- approve them with Russian counsel and record the decision before automated
-- erasure jobs can run.
create table if not exists public.data_retention_policies (
  data_category text primary key,
  purpose text not null,
  legal_basis text not null default 'operator_approval_required',
  retention_interval interval,
  status text not null default 'draft' check (status in (
    'draft', 'approved', 'suspended'
  )),
  approved_by uuid references public.users(id) on delete set null,
  approved_at timestamptz,
  policy_version text not null default '',
  updated_at timestamptz not null default now(),
  check (
    status <> 'approved'
    or (
      retention_interval is not null
      and approved_by is not null
      and approved_at is not null
      and btrim(policy_version) <> ''
    )
  )
);

insert into public.data_retention_policies (data_category, purpose)
values
  ('financial_history', 'Accounting, payment and dispute evidence'),
  ('order_delivery_pii', 'Delivery fulfilment and legal claims'),
  ('legal_consents', 'Proof of consent and document acceptance'),
  ('chat_evidence', 'Fraud, abuse and dispute investigation'),
  ('moderation_audit', 'Accountability of moderation decisions'),
  ('oauth_security_events', 'Authentication security and replay prevention')
on conflict (data_category) do nothing;

create table if not exists public.account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete restrict,
  idempotency_key text not null,
  status text not null default 'requested' check (status in (
    'requested', 'blocked', 'processing', 'completed', 'failed', 'cancelled'
  )),
  reason text not null default '',
  hold_reason text not null default '',
  requested_at timestamptz not null default now(),
  processing_started_at timestamptz,
  completed_at timestamptz,
  processed_by uuid references public.users(id) on delete set null,
  result jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  unique (user_id, idempotency_key),
  check (idempotency_key ~ '^[A-Za-z0-9._:-]{16,128}$')
);

create unique index if not exists account_deletion_one_open_request_idx
  on public.account_deletion_requests (user_id)
  where status in ('requested', 'blocked', 'processing');

drop trigger if exists touch_account_deletion_requests_updated_at
  on public.account_deletion_requests;
create trigger touch_account_deletion_requests_updated_at
before update on public.account_deletion_requests
for each row execute function public.c2c_touch_updated_at();

-- Evidence-bearing identity links no longer cascade with auth.users.
alter table public.message_threads
  drop constraint if exists message_threads_buyer_id_fkey,
  drop constraint if exists message_threads_seller_id_fkey,
  drop constraint if exists message_threads_created_by_fkey;
alter table public.message_threads
  add constraint message_threads_buyer_id_fkey
    foreign key (buyer_id) references public.users(id) on delete set null,
  add constraint message_threads_seller_id_fkey
    foreign key (seller_id) references public.users(id) on delete set null,
  add constraint message_threads_created_by_fkey
    foreign key (created_by) references public.users(id) on delete set null;

alter table public.chat_messages
  alter column sender_id drop not null,
  drop constraint if exists chat_messages_sender_id_fkey,
  drop constraint if exists chat_messages_thread_id_fkey;
alter table public.chat_messages
  add constraint chat_messages_sender_id_fkey
    foreign key (sender_id) references public.users(id) on delete set null,
  add constraint chat_messages_thread_id_fkey
    foreign key (thread_id) references public.message_threads(id)
    on delete restrict;

create table if not exists public.chat_message_evidence (
  message_id text primary key
    references public.chat_messages(id) on delete restrict,
  thread_id text not null
    references public.message_threads(id) on delete restrict,
  sender_id uuid references public.users(id) on delete set null,
  sender_name text not null,
  sender_avatar text not null,
  text text not null,
  message_type text not null,
  product jsonb,
  attachment jsonb,
  reply_to_id text,
  reply_snapshot jsonb,
  message_created_at timestamptz not null,
  captured_at timestamptz not null default now()
);

create table if not exists public.chat_message_edit_history (
  id bigint generated always as identity primary key,
  message_id text not null
    references public.chat_messages(id) on delete restrict,
  text text not null,
  message_type text not null,
  product jsonb,
  attachment jsonb,
  reply_snapshot jsonb,
  edited_at timestamptz,
  deleted_at timestamptz,
  captured_at timestamptz not null default now()
);

insert into public.chat_message_evidence (
  message_id,
  thread_id,
  sender_id,
  sender_name,
  sender_avatar,
  text,
  message_type,
  product,
  attachment,
  reply_to_id,
  reply_snapshot,
  message_created_at,
  captured_at
)
select
  message.id,
  message.thread_id,
  message.sender_id,
  message.sender_name,
  message.sender_avatar,
  message.text,
  message.type,
  message.product,
  message.attachment,
  message.reply_to_id,
  message.reply_snapshot,
  message.created_at,
  now()
from public.chat_messages message
on conflict (message_id) do nothing;

create or replace function public.capture_chat_message_evidence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.chat_message_evidence (
      message_id,
      thread_id,
      sender_id,
      sender_name,
      sender_avatar,
      text,
      message_type,
      product,
      attachment,
      reply_to_id,
      reply_snapshot,
      message_created_at
    )
    values (
      new.id,
      new.thread_id,
      new.sender_id,
      new.sender_name,
      new.sender_avatar,
      new.text,
      new.type,
      new.product,
      new.attachment,
      new.reply_to_id,
      new.reply_snapshot,
      new.created_at
    )
    on conflict (message_id) do nothing;
    return new;
  end if;

  if old.text is distinct from new.text
     or old.type is distinct from new.type
     or old.product is distinct from new.product
     or old.attachment is distinct from new.attachment
     or old.reply_snapshot is distinct from new.reply_snapshot
     or old.deleted_at is distinct from new.deleted_at then
    insert into public.chat_message_edit_history (
      message_id,
      text,
      message_type,
      product,
      attachment,
      reply_snapshot,
      edited_at,
      deleted_at
    )
    values (
      old.id,
      old.text,
      old.type,
      old.product,
      old.attachment,
      old.reply_snapshot,
      old.edited_at,
      old.deleted_at
    );
  end if;
  return new;
end;
$$;

drop trigger if exists capture_chat_message_evidence_after_insert
  on public.chat_messages;
create trigger capture_chat_message_evidence_after_insert
after insert on public.chat_messages
for each row execute function public.capture_chat_message_evidence();

drop trigger if exists capture_chat_message_history_before_update
  on public.chat_messages;
create trigger capture_chat_message_history_before_update
before update on public.chat_messages
for each row execute function public.capture_chat_message_evidence();

create or replace function public.prevent_chat_message_physical_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if coalesce(
    current_setting('clothes.chat_retention_purge', true),
    ''
  ) <> 'allowed' then
    raise exception 'chat_messages_require_retention_purge'
      using errcode = '42501';
  end if;
  return old;
end;
$$;

drop trigger if exists prevent_chat_message_physical_delete
  on public.chat_messages;
create trigger prevent_chat_message_physical_delete
before delete on public.chat_messages
for each row execute function public.prevent_chat_message_physical_delete();

drop trigger if exists chat_message_evidence_is_immutable
  on public.chat_message_evidence;
create trigger chat_message_evidence_is_immutable
before update or delete on public.chat_message_evidence
for each row execute function public.prevent_immutable_ledger_mutation();

drop trigger if exists chat_message_edit_history_is_immutable
  on public.chat_message_edit_history;
create trigger chat_message_edit_history_is_immutable
before update or delete on public.chat_message_edit_history
for each row execute function public.prevent_immutable_ledger_mutation();

create table if not exists public.message_reports (
  id uuid primary key default gen_random_uuid(),
  message_id text not null
    references public.chat_messages(id) on delete restrict,
  thread_id text not null
    references public.message_threads(id) on delete restrict,
  reporter_id uuid not null references public.users(id) on delete restrict,
  reason text not null check (reason in (
    'spam', 'harassment', 'fraud', 'prohibited_content', 'personal_data',
    'other'
  )),
  description text not null default '',
  status text not null default 'open' check (status in (
    'open', 'under_review', 'resolved', 'dismissed'
  )),
  moderator_id uuid references public.users(id) on delete set null,
  resolution text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,
  check (char_length(description) <= 2000)
);

create unique index if not exists message_reports_open_dedupe_idx
  on public.message_reports (message_id, reporter_id)
  where status in ('open', 'under_review');

create table if not exists public.moderation_actions (
  id bigint generated always as identity primary key,
  actor_id uuid references public.users(id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text not null,
  reason text not null,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now(),
  check (btrim(action) <> ''),
  check (btrim(target_type) <> ''),
  check (btrim(target_id) <> ''),
  check (btrim(reason) <> '')
);

drop trigger if exists moderation_actions_are_immutable
  on public.moderation_actions;
create trigger moderation_actions_are_immutable
before update or delete on public.moderation_actions
for each row execute function public.prevent_immutable_ledger_mutation();

create or replace function public.report_chat_message(
  p_message_id text,
  p_reason text,
  p_description text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  message_row public.chat_messages%rowtype;
  report_id uuid;
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_reason not in (
    'spam', 'harassment', 'fraud', 'prohibited_content', 'personal_data',
    'other'
  ) or char_length(coalesce(p_description, '')) > 2000 then
    raise exception 'message_report_invalid' using errcode = '22023';
  end if;
  if (
    select count(*)
    from public.message_reports report
    where report.reporter_id = actor_id
      and report.created_at > now() - interval '24 hours'
  ) >= 20 then
    raise exception 'report_rate_limited' using errcode = '54000';
  end if;

  select message.* into message_row
  from public.chat_messages message
  join public.message_threads thread on thread.id = message.thread_id
  where message.id = p_message_id
    and actor_id = any(thread.member_ids);
  if not found then
    raise exception 'message_not_found' using errcode = 'P0002';
  end if;

  insert into public.message_reports (
    message_id,
    thread_id,
    reporter_id,
    reason,
    description
  )
  values (
    message_row.id,
    message_row.thread_id,
    actor_id,
    p_reason,
    btrim(coalesce(p_description, ''))
  )
  returning id into report_id;
  return report_id;
end;
$$;

revoke all on function public.report_chat_message(text, text, text)
  from public, anon;
grant execute on function public.report_chat_message(text, text, text)
  to authenticated;

create or replace function public.block_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_blocked_user_id is null
     or p_blocked_user_id = actor_id
     or not exists (
       select 1
       from public.users durable_user
       where durable_user.id = p_blocked_user_id
         and durable_user.account_status <> 'anonymized'
     ) then
    raise exception 'block_target_invalid' using errcode = '22023';
  end if;
  insert into public.blocked_users (blocker_id, blocked_id)
  values (actor_id, p_blocked_user_id)
  on conflict do nothing;
end;
$$;

create or replace function public.unblock_user(p_blocked_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  delete from public.blocked_users
  where blocker_id = actor_id
    and blocked_id = p_blocked_user_id;
end;
$$;

revoke all on function public.block_user(uuid) from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;

create or replace function public.moderate_message_report(
  p_report_id uuid,
  p_status text,
  p_resolution text,
  p_moderator_id uuid
)
returns public.message_reports
language plpgsql
security definer
set search_path = ''
as $$
declare
  report_before public.message_reports%rowtype;
  report_after public.message_reports%rowtype;
begin
  if auth.role() <> 'service_role'
     or not exists (
       select 1
       from public.admin_roles administrator
       where administrator.user_id = p_moderator_id
         and administrator.role in ('moderator', 'ops_admin', 'owner')
     ) then
    raise exception 'moderator_required' using errcode = '42501';
  end if;
  if p_status not in ('under_review', 'resolved', 'dismissed')
     or char_length(btrim(coalesce(p_resolution, ''))) < 3 then
    raise exception 'moderation_decision_invalid' using errcode = '22023';
  end if;
  select * into report_before
  from public.message_reports report
  where report.id = p_report_id
  for update;
  if not found or report_before.status not in ('open', 'under_review') then
    raise exception 'message_report_not_actionable' using errcode = 'P0002';
  end if;

  update public.message_reports
  set status = p_status,
      moderator_id = p_moderator_id,
      resolution = btrim(p_resolution),
      resolved_at = case
        when p_status in ('resolved', 'dismissed') then now()
        else null
      end,
      updated_at = now()
  where id = p_report_id
  returning * into report_after;

  insert into public.moderation_actions (
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    before_data,
    after_data
  )
  values (
    p_moderator_id,
    'moderate_message_report',
    'message_report',
    p_report_id::text,
    btrim(p_resolution),
    to_jsonb(report_before),
    to_jsonb(report_after)
  );
  return report_after;
end;
$$;

revoke all on function public.moderate_message_report(
  uuid, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.moderate_message_report(
  uuid, text, text, uuid
) to service_role;

-- Direct block/message mutation and physical attachment deletion are replaced
-- with narrow RPCs/soft deletion.
revoke insert, update, delete on public.blocked_users
  from anon, authenticated;
revoke delete on public.chat_messages from anon, authenticated;
drop policy if exists "Users can manage own blocks" on public.blocked_users;
drop policy if exists "Uploaders can delete own chat media"
  on storage.objects;

alter table public.chat_message_evidence enable row level security;
alter table public.chat_message_edit_history enable row level security;
alter table public.message_reports enable row level security;
alter table public.moderation_actions enable row level security;
alter table public.account_deletion_requests enable row level security;
alter table public.data_retention_policies enable row level security;

drop policy if exists "Reporters read own message reports"
  on public.message_reports;
create policy "Reporters read own message reports"
  on public.message_reports for select to authenticated
  using (reporter_id = (select auth.uid()));
drop policy if exists "Users read own deletion requests"
  on public.account_deletion_requests;
create policy "Users read own deletion requests"
  on public.account_deletion_requests for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.chat_message_evidence,
  public.chat_message_edit_history,
  public.moderation_actions,
  public.data_retention_policies
from anon, authenticated;
revoke all on public.message_reports,
  public.account_deletion_requests
from anon, authenticated;
grant select on public.message_reports,
  public.account_deletion_requests
to authenticated;

-- Reviews are bound to a concrete completed order and are server-snapshotted.
alter table public.seller_reviews
  add column if not exists order_id text
    references public.orders(id) on delete restrict,
  add column if not exists evidence jsonb not null default '{}'::jsonb,
  add column if not exists updated_at timestamptz not null default now(),
  drop constraint if exists seller_reviews_buyer_id_fkey;
alter table public.seller_reviews
  add constraint seller_reviews_buyer_id_fkey
    foreign key (buyer_id) references public.users(id) on delete restrict;

create unique index if not exists seller_reviews_order_unique_idx
  on public.seller_reviews (order_id)
  where order_id is not null;

drop policy if exists "Buyers can create seller reviews"
  on public.seller_reviews;
drop policy if exists "Buyers can update own seller reviews"
  on public.seller_reviews;
revoke insert, update, delete on public.seller_reviews
  from anon, authenticated;

create or replace function public.submit_order_review(
  p_order_id text,
  p_rating integer,
  p_text text,
  p_evidence jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  marketplace_order public.orders%rowtype;
  buyer_profile public.profiles%rowtype;
  review_id uuid;
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_rating not between 1 and 5
     or char_length(coalesce(p_text, '')) > 4000
     or jsonb_typeof(coalesce(p_evidence, '{}'::jsonb)) <> 'object' then
    raise exception 'review_payload_invalid' using errcode = '22023';
  end if;
  select * into marketplace_order
  from public.orders target_order
  where target_order.id = p_order_id
    and target_order.buyer_id = actor_id
    and target_order.status = 'completed';
  if not found or marketplace_order.seller_id is null then
    raise exception 'completed_order_required' using errcode = '42501';
  end if;
  select * into buyer_profile
  from public.profiles profile
  where profile.id = actor_id;

  insert into public.seller_reviews (
    order_id,
    seller_id,
    buyer_id,
    buyer_name,
    buyer_avatar,
    product_id,
    product_title,
    product_image,
    rating,
    text,
    has_photo,
    deal_completed,
    evidence,
    created_at,
    updated_at
  )
  values (
    p_order_id,
    marketplace_order.seller_id,
    actor_id,
    coalesce(nullif(btrim(buyer_profile.name), ''), 'Покупатель'),
    coalesce(buyer_profile.avatar_url, ''),
    marketplace_order.product_id,
    marketplace_order.product_title,
    marketplace_order.product_image,
    p_rating,
    btrim(coalesce(p_text, '')),
    coalesce(p_evidence ->> 'has_photo', 'false') = 'true',
    true,
    p_evidence,
    now(),
    now()
  )
  on conflict (order_id) where order_id is not null do update
  set rating = excluded.rating,
      text = excluded.text,
      has_photo = excluded.has_photo,
      evidence = excluded.evidence,
      updated_at = now()
  returning id into review_id;
  return review_id;
end;
$$;

revoke all on function public.submit_order_review(
  text, integer, text, jsonb
) from public, anon;
grant execute on function public.submit_order_review(
  text, integer, text, jsonb
) to authenticated;

create or replace function public.request_account_deletion(
  p_idempotency_key text,
  p_reason text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  request_id uuid;
  hold_reasons text[] := '{}'::text[];
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.users durable_user
    where durable_user.id = actor_id
      and durable_user.auth_user_id = actor_id
      and durable_user.account_status in ('active', 'blocked')
  ) then
    raise exception 'account_not_deletable' using errcode = '42501';
  end if;
  if char_length(coalesce(p_reason, '')) > 1000 then
    raise exception 'deletion_reason_too_long' using errcode = '22023';
  end if;
  if p_idempotency_key !~ '^[A-Za-z0-9._:-]{16,128}$' then
    raise exception 'deletion_idempotency_key_invalid'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.orders marketplace_order
    where actor_id in (
      marketplace_order.buyer_id,
      marketplace_order.seller_id
    )
      and marketplace_order.status not in ('completed', 'cancelled')
  ) then
    hold_reasons := array_append(hold_reasons, 'active_order');
  end if;
  if exists (
    select 1
    from public.disputes dispute
    join public.orders marketplace_order
      on marketplace_order.id = dispute.order_id
    where actor_id in (
      marketplace_order.buyer_id,
      marketplace_order.seller_id
    )
      and dispute.status in ('open', 'under_review')
  ) then
    hold_reasons := array_append(hold_reasons, 'active_dispute');
  end if;
  if exists (
    select 1
    from public.seller_payouts payout
    join public.seller_accounts seller
      on seller.id = payout.seller_account_id
    where seller.user_id = actor_id
      and payout.status in ('pending', 'frozen', 'eligible', 'processing')
  ) then
    hold_reasons := array_append(hold_reasons, 'unsettled_payout');
  end if;

  insert into public.account_deletion_requests (
    user_id,
    idempotency_key,
    status,
    reason,
    hold_reason,
    result
  )
  values (
    actor_id,
    p_idempotency_key,
    case when cardinality(hold_reasons) > 0
      then 'blocked' else 'requested' end,
    btrim(coalesce(p_reason, '')),
    array_to_string(hold_reasons, ','),
    jsonb_build_object(
      'full_erasure_promised', false,
      'retained_categories', jsonb_build_array(
        'financial_history',
        'legal_consents',
        'order_and_dispute_evidence',
        'moderation_audit'
      )
    )
  )
  on conflict (user_id) where status in ('requested', 'blocked', 'processing')
  do update
  set status = excluded.status,
      reason = excluded.reason,
      hold_reason = excluded.hold_reason,
      result = excluded.result,
      updated_at = now()
  returning id into request_id;

  if cardinality(hold_reasons) = 0 then
    update public.users
    set account_status = 'deletion_pending',
        updated_at = now()
    where id = actor_id
      and account_status in ('active', 'blocked');
  end if;

  return jsonb_build_object(
    'request_id', request_id,
    'accepted', cardinality(hold_reasons) = 0,
    'status', case when cardinality(hold_reasons) > 0
      then 'blocked' else 'requested' end,
    'hold_reasons', to_jsonb(hold_reasons),
    'full_erasure_promised', false
  );
end;
$$;

revoke all on function public.request_account_deletion(text, text)
  from public, anon;
grant execute on function public.request_account_deletion(text, text)
  to authenticated;

create or replace function public.anonymize_user_account(
  p_request_id uuid,
  p_user_id uuid,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  deletion_request public.account_deletion_requests%rowtype;
  original_auth_user_id uuid;
  retained_order_count integer;
  retained_consent_count integer;
  retained_chat_count integer;
  resolved_actor_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if nullif(btrim(coalesce(p_actor, '')), '') is null then
    raise exception 'anonymization_actor_required' using errcode = '23514';
  end if;
  begin
    resolved_actor_id := p_actor::uuid;
  exception when invalid_text_representation then
    resolved_actor_id := null;
  end;
  if resolved_actor_id is not null
     and not exists (
       select 1
       from public.admin_roles administrator
       where administrator.user_id = resolved_actor_id
         and administrator.role in ('ops_admin', 'owner')
     ) then
    raise exception 'authorized_operator_required' using errcode = '42501';
  end if;
  if resolved_actor_id is null and p_actor !~ '^edge:[a-z0-9._-]{1,100}$' then
    raise exception 'authorized_operator_required' using errcode = '42501';
  end if;

  select durable_user.auth_user_id into original_auth_user_id
  from public.users durable_user
  where durable_user.id = p_user_id
    and durable_user.account_status = 'deletion_pending'
  for update;
  if not found then
    raise exception 'deletion_pending_account_required'
      using errcode = '42501';
  end if;
  if exists (
    select 1
    from public.orders marketplace_order
    where p_user_id in (
      marketplace_order.buyer_id,
      marketplace_order.seller_id
    )
      and marketplace_order.status not in ('completed', 'cancelled')
  ) or exists (
    select 1
    from public.disputes dispute
    join public.orders marketplace_order
      on marketplace_order.id = dispute.order_id
    where p_user_id in (
      marketplace_order.buyer_id,
      marketplace_order.seller_id
    )
      and dispute.status in ('open', 'under_review')
  ) or exists (
    select 1
    from public.seller_payouts payout
    join public.seller_accounts seller
      on seller.id = payout.seller_account_id
    where seller.user_id = p_user_id
      and payout.status in ('pending', 'frozen', 'eligible', 'processing')
  ) then
    raise exception 'deletion_legal_hold_active' using errcode = '55000';
  end if;

  select * into deletion_request
  from public.account_deletion_requests request_row
  where request_row.id = p_request_id
    and request_row.user_id = p_user_id
    and request_row.status in ('requested', 'processing')
  order by request_row.requested_at desc
  limit 1
  for update;
  if not found then
    raise exception 'deletion_request_not_found' using errcode = 'P0002';
  end if;
  update public.account_deletion_requests
  set status = 'processing',
      processing_started_at = coalesce(processing_started_at, now()),
      processed_by = resolved_actor_id
  where id = deletion_request.id;

  update public.products
  set status = case when status = 'sold' then 'sold' else 'archived' end,
      is_hidden = true,
      seller_name = 'Удалённый пользователь',
      seller_handle = '@deleted'
  where seller_id = p_user_id;

  update public.profiles
  set name = 'Удалённый пользователь',
      handle = '@deleted_' || left(replace(id::text, '-', ''), 12),
      avatar_url = '',
      city = '',
      verification_status = 'unverified',
      moderation_status = 'blocked'
  where id = p_user_id;

  update public.seller_accounts
  set status = 'blocked',
      verification_status = 'rejected',
      moderation_status = 'blocked',
      blocked_at = coalesce(blocked_at, now()),
      status_reason = 'account_anonymized'
  where user_id = p_user_id;

  update public.buyer_profiles
  set birth_date = null,
      age_verified = false,
      age_verified_at = null,
      verification_method = null,
      verification_evidence = '{}'::jsonb,
      updated_at = now()
  where user_id = p_user_id;

  update public.chat_messages
  set sender_name = 'Удалённый пользователь',
      sender_avatar = ''
  where sender_id = p_user_id;

  update public.message_threads
  set buyer_name = case when buyer_id = p_user_id
        then 'Удалённый пользователь' else buyer_name end,
      buyer_handle = case when buyer_id = p_user_id
        then '@deleted' else buyer_handle end,
      buyer_avatar = case when buyer_id = p_user_id
        then '' else buyer_avatar end,
      seller_name = case when seller_id = p_user_id
        then 'Удалённый пользователь' else seller_name end,
      seller_handle = case when seller_id = p_user_id
        then '@deleted' else seller_handle end,
      seller_avatar = case when seller_id = p_user_id
        then '' else seller_avatar end
  where p_user_id in (buyer_id, seller_id);

  update public.seller_reviews
  set buyer_name = 'Удалённый пользователь',
      buyer_avatar = ''
  where buyer_id = p_user_id;

  update public.outfits
  set author_name = 'Удалённый пользователь',
      author_handle = '@deleted',
      author_avatar_url = ''
  where owner_id = original_auth_user_id;

  -- OAuth attempts are short-lived authentication material, not durable
  -- financial evidence. Remove their provider profile/subject together with
  -- the linked external identity instead of retaining a second identifier for
  -- an anonymized account.
  delete from public.oauth_login_attempts
  where auth_user_id = original_auth_user_id;
  delete from public.oauth_external_identities
  where user_id = original_auth_user_id;

  delete from public.product_favorites where user_id = p_user_id;
  delete from public.outfit_favorites where user_id = p_user_id;
  delete from public.profile_follows
    where follower_id = p_user_id or seller_id = p_user_id;
  delete from public.blocked_users
    where blocker_id = p_user_id or blocked_id = p_user_id;
  delete from public.recent_products where user_id = p_user_id;
  delete from public.recent_outfits where user_id = p_user_id;
  delete from public.product_views where viewer_id = p_user_id;
  delete from public.outfit_views where viewer_id = p_user_id;
  delete from public.delivery_profiles where user_id = p_user_id;
  delete from public.profile_private_details where user_id = p_user_id;

  select count(*)::integer into retained_order_count
  from public.orders marketplace_order
  where p_user_id in (
    marketplace_order.buyer_id,
    marketplace_order.seller_id
  );
  select count(*)::integer into retained_consent_count
  from public.user_consents consent
  where consent.user_id = p_user_id;
  select count(*)::integer into retained_chat_count
  from public.chat_message_evidence evidence
  where evidence.sender_id = p_user_id;

  update public.users
  set auth_user_id = null,
      account_status = 'anonymized',
      anonymized_at = now(),
      updated_at = now()
  where id = p_user_id;

  update public.account_deletion_requests
  set status = 'completed',
      completed_at = now(),
      result = jsonb_build_object(
        'anonymized', true,
        'retained_orders', retained_order_count,
        'retained_consents', retained_consent_count,
        'retained_chat_evidence', retained_chat_count,
        'retention_policy_approval_required', true
      )
  where id = deletion_request.id;

  insert into public.moderation_actions (
    actor_id,
    action,
    target_type,
    target_id,
    reason,
    after_data
  )
  values (
    resolved_actor_id,
    'anonymize_account',
    'user',
    p_user_id::text,
    btrim(p_actor),
    jsonb_build_object(
      'retained_orders', retained_order_count,
      'retained_consents', retained_consent_count,
      'retained_chat_evidence', retained_chat_count
    )
  );

  delete from auth.users
  where id = original_auth_user_id;

  return jsonb_build_object(
    'user_id', p_user_id,
    'anonymized', true,
    'status', 'anonymized',
    'retained_categories', jsonb_build_array(
      'financial_history',
      'legal_consents',
      'order_and_dispute_evidence',
      'moderation_audit',
      'chat_evidence_pending_retention_policy'
    ),
    'removed_categories', jsonb_build_array(
      'auth_identity',
      'profile_contact_data',
      'age_data',
      'favorites_and_recent_history'
    ),
    'retained_orders', retained_order_count,
    'retained_consents', retained_consent_count,
    'retained_chat_evidence', retained_chat_count
  );
end;
$$;

revoke all on function public.anonymize_user_account(uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.anonymize_user_account(uuid, uuid, text)
  to service_role;

-- Preserve financial/legal/chat evidence while restricting the Edge deletion
-- inventory to media that can actually be erased.
create or replace function public.list_account_deletion_storage_objects(
  p_user_id uuid,
  p_after_bucket text default '',
  p_after_name text default '',
  p_limit integer default 200
)
returns table (bucket_id text, object_name text)
language sql
security definer
set search_path = ''
as $$
  with candidates as (
    select stored.bucket_id, stored.name
    from storage.objects stored
    where (
      stored.bucket_id = 'listing-drafts'
      and stored.owner_id = p_user_id::text
    ) or (
      stored.bucket_id = 'product-images'
      and (
        stored.owner_id = p_user_id::text
        or stored.name like 'avatars/' || p_user_id::text || '/%'
        or stored.name like 'outfits/' || p_user_id::text || '/%'
        or stored.name like 'accessories/' || p_user_id::text || '/%'
        or exists (
          select 1
          from public.product_images owned_image
          join public.products owned_product
            on owned_product.id = owned_image.product_id
          where owned_product.seller_id = p_user_id
            and owned_image.storage_bucket = 'product-images'
            and owned_image.storage_path = stored.name
        )
      )
      and not exists (
        select 1
        from public.product_images image
        join public.orders marketplace_order
          on marketplace_order.product_id = image.product_id::text
        where image.storage_bucket = 'product-images'
          and image.storage_path = stored.name
          and (
            marketplace_order.status = 'completed'
            or exists (
              select 1
              from public.disputes retained_dispute
              where retained_dispute.order_id = marketplace_order.id
            )
          )
      )
    ) or (
      stored.bucket_id = 'profile-images'
      and (
        stored.owner_id = p_user_id::text
        or split_part(stored.name, '/', 1) = p_user_id::text
      )
    ) or (
      stored.bucket_id = 'outfit-images'
      and (
        stored.owner_id = p_user_id::text
        or split_part(stored.name, '/', 1) = p_user_id::text
      )
    ) or (
      stored.bucket_id = 'accessory-images'
      and (
        stored.owner_id = p_user_id::text
        or split_part(stored.name, '/', 1) = p_user_id::text
      )
    )
  )
  select candidate.bucket_id, candidate.name
  from candidates candidate
  where (candidate.bucket_id, candidate.name) >
    (coalesce(p_after_bucket, ''), coalesce(p_after_name, ''))
  order by candidate.bucket_id, candidate.name
  limit greatest(1, least(coalesce(p_limit, 200), 500));
$$;

revoke all on function public.list_account_deletion_storage_objects(
  uuid, text, text, integer
) from public, anon, authenticated;
grant execute on function public.list_account_deletion_storage_objects(
  uuid, text, text, integer
) to service_role;

-- Provisional OAuth identities may read legal onboarding resources only.
-- This trigger closes legacy direct-write policies and SECURITY DEFINER RPC
-- paths that predate the entitlement model.
create or replace function public.require_onboarded_user_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is not null
     and auth.role() = 'authenticated'
     and not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'legal_onboarding_required' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

create or replace function public.protect_outfit_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('anon', 'authenticated') then
      new.likes_count := 0;
      new.views_count := 0;
    end if;
    return new;
  end if;
  if current_user in ('anon', 'authenticated')
     and (
       new.owner_id is distinct from old.owner_id
       or new.author_name is distinct from old.author_name
       or new.author_handle is distinct from old.author_handle
       or new.author_avatar_url is distinct from old.author_avatar_url
       or new.likes_count is distinct from old.likes_count
       or new.views_count is distinct from old.views_count
     ) then
    raise exception 'outfit_server_fields_are_immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_outfit_server_fields_before_write
  on public.outfits;
create trigger protect_outfit_server_fields_before_write
before insert or update on public.outfits
for each row execute function public.protect_outfit_server_fields();

do $$
declare
  protected_table regclass;
  trigger_name text;
begin
  foreach protected_table in array array[
    'public.profiles'::regclass,
    'public.profile_private_details'::regclass,
    'public.delivery_profiles'::regclass,
    'public.listing_addresses'::regclass,
    'public.listing_publish_preferences'::regclass,
    'public.outfits'::regclass,
    'public.outfit_accessories'::regclass,
    'public.product_favorites'::regclass,
    'public.outfit_favorites'::regclass,
    'public.profile_follows'::regclass,
    'public.blocked_users'::regclass,
    'public.content_reports'::regclass,
    'public.message_threads'::regclass,
    'public.chat_messages'::regclass,
    'public.chat_thread_member_state'::regclass,
    'public.recent_products'::regclass,
    'public.recent_outfits'::regclass,
    'public.product_views'::regclass,
    'public.outfit_views'::regclass,
    'public.device_push_tokens'::regclass,
    'public.notification_settings'::regclass
  ]
  loop
    trigger_name := 'require_onboarding_' ||
      replace(protected_table::text, '.', '_');
    execute format(
      'drop trigger if exists %I on %s',
      trigger_name,
      protected_table
    );
    execute format(
      'create trigger %I before insert or update or delete on %s ' ||
      'for each row execute function public.require_onboarded_user_mutation()',
      trigger_name,
      protected_table
    );
  end loop;
end
$$;

-- Notification rows are server-originated. Clients can only read their rows
-- and acknowledge them through a narrow RPC.
drop policy if exists "Users can manage their notifications"
  on public.notifications;
drop policy if exists "Users read own notifications"
  on public.notifications;
create policy "Users read own notifications"
  on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
revoke insert, update, delete on public.notifications
  from anon, authenticated;
grant select on public.notifications to authenticated;

create or replace function public.mark_notification_read(
  p_notification_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  update public.notifications notification
  set is_read = true
  where notification.id = p_notification_id
    and notification.user_id = actor_id;
  return found;
end;
$$;

create or replace function public.mark_all_notifications_read()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  affected integer;
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  update public.notifications
  set is_read = true
  where user_id = actor_id
    and not is_read;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.mark_notification_read(uuid)
  from public, anon;
grant execute on function public.mark_notification_read(uuid)
  to authenticated;
revoke all on function public.mark_all_notifications_read()
  from public, anon;
grant execute on function public.mark_all_notifications_read()
  to authenticated;

-- One-time, PKCE-bound OAuth exchanges. Only Edge Functions holding the
-- service role can access these tables or RPCs.
create table if not exists public.oauth_login_attempts (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('vk', 'yandex', 'telegram')),
  state_hash text not null unique,
  redirect_uri text not null,
  app_code_challenge text not null,
  provider_code_verifier text,
  status text not null default 'pending' check (status in (
    'pending',
    'callback_processing',
    'callback_complete',
    'exchanged',
    'failed'
  )),
  expires_at timestamptz not null,
  exchange_code_hash text unique,
  exchange_expires_at timestamptz,
  provider_subject text,
  provider_profile jsonb not null default '{}'::jsonb,
  auth_user_id uuid references auth.users(id) on delete set null,
  consumed_at timestamptz,
  failure_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (state_hash ~ '^[0-9a-f]{64}$'),
  check (char_length(redirect_uri) between 1 and 2000),
  check (char_length(app_code_challenge) between 43 and 128),
  check (
    (
      provider = 'telegram'
      and provider_code_verifier is null
    )
    or (
      provider in ('vk', 'yandex')
      and char_length(provider_code_verifier) between 43 and 128
    )
  ),
  check (
    exchange_code_hash is null
    or exchange_code_hash ~ '^[0-9a-f]{64}$'
  ),
  check (
    status not in ('callback_complete', 'exchanged')
    or (
      provider_subject is not null
      and auth_user_id is not null
    )
  )
);

create index if not exists oauth_login_attempts_expiry_idx
  on public.oauth_login_attempts (status, expires_at);

create table if not exists public.oauth_external_identities (
  provider text not null check (provider in ('vk', 'yandex', 'telegram')),
  provider_subject text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_profile jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  last_login_at timestamptz not null default now(),
  primary key (provider, provider_subject),
  unique (provider, user_id),
  check (btrim(provider_subject) <> '')
);

create or replace function public.oauth_pkce_s256(p_verifier text)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select rtrim(
    translate(
      replace(
        encode(
          extensions.digest(convert_to(p_verifier, 'UTF8'), 'sha256'),
          'base64'
        ),
        E'\n',
        ''
      ),
      '+/',
      '-_'
    ),
    '='
  );
$$;

revoke all on function public.oauth_pkce_s256(text) from public;

create or replace function public.create_oauth_login_attempt(
  p_provider text,
  p_state_hash text,
  p_redirect_uri text,
  p_app_code_challenge text,
  p_provider_code_verifier text,
  p_expires_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_provider not in ('vk', 'yandex', 'telegram')
     or p_state_hash !~ '^[0-9a-f]{64}$'
     or char_length(coalesce(p_redirect_uri, '')) not between 1 and 2000
     or char_length(coalesce(p_app_code_challenge, '')) not between 43 and 128
     or (
       p_provider = 'telegram'
       and p_provider_code_verifier is not null
     )
     or (
       p_provider in ('vk', 'yandex')
       and char_length(coalesce(p_provider_code_verifier, ''))
         not between 43 and 128
     )
     or p_expires_at <= now()
     or p_expires_at > now() + interval '15 minutes' then
    raise exception 'oauth_attempt_invalid' using errcode = '22023';
  end if;

  insert into public.oauth_login_attempts (
    provider,
    state_hash,
    redirect_uri,
    app_code_challenge,
    provider_code_verifier,
    expires_at
  )
  values (
    p_provider,
    lower(p_state_hash),
    p_redirect_uri,
    p_app_code_challenge,
    p_provider_code_verifier,
    p_expires_at
  )
  returning id into attempt_id;
  return attempt_id;
end;
$$;

revoke all on function public.create_oauth_login_attempt(
  text, text, text, text, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.create_oauth_login_attempt(
  text, text, text, text, text, timestamptz
) to service_role;

create or replace function public.claim_oauth_callback(
  p_provider text,
  p_state_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.oauth_login_attempts%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  update public.oauth_login_attempts
  set status = 'callback_processing',
      updated_at = now()
  where provider = p_provider
    and state_hash = lower(p_state_hash)
    and status = 'pending'
    and expires_at > now()
  returning * into attempt;
  if not found then
    raise exception 'oauth_state_expired_or_consumed' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'id', attempt.id,
    'provider', attempt.provider,
    'redirect_uri', attempt.redirect_uri,
    'app_code_challenge', attempt.app_code_challenge,
    'provider_code_verifier', attempt.provider_code_verifier,
    'expires_at', attempt.expires_at
  );
end;
$$;

revoke all on function public.claim_oauth_callback(text, text)
  from public, anon, authenticated;
grant execute on function public.claim_oauth_callback(text, text)
  to service_role;

create or replace function public.fail_oauth_attempt(
  p_attempt_id uuid,
  p_reason text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 1 and 1000 then
    raise exception 'oauth_failure_reason_invalid' using errcode = '22023';
  end if;
  update public.oauth_login_attempts
  set status = 'failed',
      failure_reason = btrim(p_reason),
      provider_code_verifier = null,
      exchange_code_hash = null,
      updated_at = now()
  where id = p_attempt_id
    and status in ('pending', 'callback_processing');
end;
$$;

revoke all on function public.fail_oauth_attempt(uuid, text)
  from public, anon, authenticated;
grant execute on function public.fail_oauth_attempt(uuid, text)
  to service_role;

create or replace function public.resolve_oauth_identity(
  p_provider text,
  p_provider_subject text,
  p_profile jsonb,
  p_candidate_user_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolved_user_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_provider not in ('vk', 'yandex', 'telegram')
     or char_length(btrim(coalesce(p_provider_subject, '')))
       not between 1 and 500
     or jsonb_typeof(coalesce(p_profile, '{}'::jsonb)) <> 'object'
     or length(coalesce(p_profile, '{}'::jsonb)::text) > 20000 then
    raise exception 'oauth_identity_invalid' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_provider || ':' || p_provider_subject, 0)
  );
  select identity_row.user_id into resolved_user_id
  from public.oauth_external_identities identity_row
  where identity_row.provider = p_provider
    and identity_row.provider_subject = p_provider_subject
  for update;
  if found then
    update public.oauth_external_identities
    set provider_profile = p_profile,
        last_login_at = now()
    where provider = p_provider
      and provider_subject = p_provider_subject;
    return resolved_user_id;
  end if;

  if p_candidate_user_id is null then
    return null;
  end if;
  if not exists (
    select 1 from auth.users account where account.id = p_candidate_user_id
  ) then
    raise exception 'oauth_candidate_auth_user_not_found'
      using errcode = 'P0002';
  end if;

  insert into public.oauth_external_identities (
    provider,
    provider_subject,
    user_id,
    provider_profile
  )
  values (
    p_provider,
    p_provider_subject,
    p_candidate_user_id,
    p_profile
  )
  returning user_id into resolved_user_id;
  return resolved_user_id;
end;
$$;

revoke all on function public.resolve_oauth_identity(
  text, text, jsonb, uuid
) from public, anon, authenticated;
grant execute on function public.resolve_oauth_identity(
  text, text, jsonb, uuid
) to service_role;

create or replace function public.complete_oauth_callback(
  p_attempt_id uuid,
  p_provider_subject text,
  p_profile jsonb,
  p_auth_user_id uuid,
  p_exchange_code_hash text,
  p_exchange_expires_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.oauth_login_attempts%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_exchange_code_hash !~ '^[0-9a-f]{64}$'
     or p_exchange_expires_at <= now()
     or p_exchange_expires_at > now() + interval '5 minutes'
     or jsonb_typeof(coalesce(p_profile, '{}'::jsonb)) <> 'object' then
    raise exception 'oauth_callback_completion_invalid'
      using errcode = '22023';
  end if;
  select * into attempt
  from public.oauth_login_attempts attempt_row
  where attempt_row.id = p_attempt_id
    and attempt_row.status = 'callback_processing'
    and attempt_row.expires_at > now()
  for update;
  if not found then
    raise exception 'oauth_callback_not_claimed' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.oauth_external_identities identity_row
    where identity_row.provider = attempt.provider
      and identity_row.provider_subject = p_provider_subject
      and identity_row.user_id = p_auth_user_id
  ) then
    raise exception 'oauth_identity_not_linked' using errcode = '42501';
  end if;

  update public.oauth_login_attempts
  set status = 'callback_complete',
      provider_subject = p_provider_subject,
      provider_profile = p_profile,
      auth_user_id = p_auth_user_id,
      exchange_code_hash = lower(p_exchange_code_hash),
      exchange_expires_at = p_exchange_expires_at,
      provider_code_verifier = null,
      updated_at = now()
  where id = p_attempt_id;
end;
$$;

revoke all on function public.complete_oauth_callback(
  uuid, text, jsonb, uuid, text, timestamptz
) from public, anon, authenticated;
grant execute on function public.complete_oauth_callback(
  uuid, text, jsonb, uuid, text, timestamptz
) to service_role;

create or replace function public.consume_oauth_exchange(
  p_exchange_code_hash text,
  p_app_code_verifier text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.oauth_login_attempts%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_exchange_code_hash !~ '^[0-9a-f]{64}$'
     or char_length(coalesce(p_app_code_verifier, '')) not between 43 and 128 then
    raise exception 'oauth_exchange_invalid' using errcode = '22023';
  end if;

  update public.oauth_login_attempts
  set status = 'exchanged',
      consumed_at = now(),
      exchange_code_hash = null,
      updated_at = now()
  where exchange_code_hash = lower(p_exchange_code_hash)
    and status = 'callback_complete'
    and exchange_expires_at > now()
    and app_code_challenge = public.oauth_pkce_s256(p_app_code_verifier)
  returning * into attempt;
  if not found then
    raise exception 'oauth_exchange_expired_or_consumed'
      using errcode = '42501';
  end if;

  return jsonb_build_object(
    'auth_user_id', attempt.auth_user_id,
    'provider', attempt.provider,
    'provider_subject', attempt.provider_subject,
    'provider_profile', attempt.provider_profile
  );
end;
$$;

revoke all on function public.consume_oauth_exchange(text, text)
  from public, anon, authenticated;
grant execute on function public.consume_oauth_exchange(text, text)
  to service_role;

alter table public.oauth_login_attempts enable row level security;
alter table public.oauth_external_identities enable row level security;
revoke all on public.oauth_login_attempts,
  public.oauth_external_identities
from anon, authenticated;

create table if not exists public.push_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  message_id text not null unique
    references public.chat_messages(id) on delete restrict,
  sender_id uuid references public.users(id) on delete set null,
  thread_id text not null
    references public.message_threads(id) on delete restrict,
  status text not null default 'processing' check (status in (
    'processing', 'sent', 'skipped', 'failed'
  )),
  error text not null default '',
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists push_delivery_attempts_sender_claimed_idx
  on public.push_delivery_attempts (sender_id, claimed_at desc);

create or replace function public.claim_push_delivery(
  p_message_id text,
  p_sender_id uuid,
  p_thread_id text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.chat_messages message
    where message.id = p_message_id
      and message.thread_id = p_thread_id
      and message.sender_id = p_sender_id
  ) then
    raise exception 'push_message_contract_mismatch' using errcode = 'P0002';
  end if;

  -- Serialize each sender's claims so concurrent messages cannot race past
  -- the abuse limit. A replay of an already claimed message remains a
  -- harmless idempotent no-op and does not consume rate-limit capacity.
  perform pg_advisory_xact_lock(
    hashtextextended('push-delivery:' || p_sender_id::text, 0)
  );
  if exists (
    select 1
    from public.push_delivery_attempts attempt
    where attempt.message_id = p_message_id
  ) then
    return null;
  end if;
  if (
    select count(*)
    from public.push_delivery_attempts attempt
    where attempt.sender_id = p_sender_id
      and attempt.claimed_at >= now() - interval '1 minute'
  ) >= 20 then
    raise exception 'push_rate_limited' using errcode = '55000';
  end if;

  insert into public.push_delivery_attempts (
    message_id,
    sender_id,
    thread_id
  )
  values (
    p_message_id,
    p_sender_id,
    p_thread_id
  )
  on conflict (message_id) do nothing
  returning id into attempt_id;
  return attempt_id;
end;
$$;

create or replace function public.complete_push_delivery(
  p_attempt_id uuid,
  p_status text,
  p_error text default ''
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_status not in ('sent', 'skipped', 'failed')
     or char_length(coalesce(p_error, '')) > 4000 then
    raise exception 'push_result_invalid' using errcode = '22023';
  end if;
  update public.push_delivery_attempts
  set status = p_status,
      error = left(coalesce(p_error, ''), 4000),
      completed_at = now()
  where id = p_attempt_id
    and status = 'processing';
  if not found then
    raise exception 'push_attempt_not_processing' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.claim_push_delivery(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.claim_push_delivery(text, uuid, text)
  to service_role;
revoke all on function public.complete_push_delivery(uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.complete_push_delivery(uuid, text, text)
  to service_role;

alter table public.push_delivery_attempts enable row level security;
revoke all on public.push_delivery_attempts from anon, authenticated;

-- Durable moderation reports survive Auth identity removal.
alter table public.content_reports
  drop constraint if exists content_reports_reporter_id_fkey,
  drop constraint if exists content_reports_assigned_to_fkey;
alter table public.content_reports
  add constraint content_reports_reporter_id_fkey
    foreign key (reporter_id) references public.users(id) on delete restrict,
  add constraint content_reports_assigned_to_fkey
    foreign key (assigned_to) references public.users(id) on delete set null;

-- Dispute evidence uses a private owner-bound namespace and is linked through
-- an RPC after a dispute exists: {uid}/{dispute_uuid}/{file}.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'dispute-evidence',
  'dispute-evidence',
  false,
  20971520,
  array[
    'image/jpeg',
    'image/png',
    'image/webp'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

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

create or replace function public.add_dispute_evidence(
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
  actor_id uuid := auth.uid();
  evidence_id uuid;
begin
  if actor_id is null
     or not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'eligible_user_required' using errcode = '42501';
  end if;
  if p_evidence_type not in ('image', 'video', 'document')
     or p_storage_path !~ (
       '^' || actor_id::text || '/' || p_dispute_id::text || '/[^/]+$'
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
      and actor_id in (
        marketplace_order.buyer_id,
        marketplace_order.seller_id
      )
  ) or not exists (
    select 1
    from storage.objects stored
    where stored.bucket_id = 'dispute-evidence'
      and stored.name = p_storage_path
      and stored.owner_id = actor_id::text
  ) then
    raise exception 'dispute_evidence_not_owned' using errcode = '42501';
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
    actor_id,
    p_evidence_type,
    'dispute-evidence',
    p_storage_path,
    lower(p_content_hash),
    p_metadata
  )
  returning id into evidence_id;
  return evidence_id;
end;
$$;

revoke all on function public.add_dispute_evidence(
  uuid, text, text, text, jsonb
) from public, anon;
grant execute on function public.add_dispute_evidence(
  uuid, text, text, text, jsonb
) to authenticated;

create or replace function public.dispute_evidence_is_readable(
  p_storage_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.dispute_evidence evidence
    join public.disputes dispute on dispute.id = evidence.dispute_id
    join public.orders marketplace_order
      on marketplace_order.id = dispute.order_id
    where evidence.storage_bucket = 'dispute-evidence'
      and evidence.storage_path = p_storage_path
      and (select auth.uid()) in (
        marketplace_order.buyer_id,
        marketplace_order.seller_id
      )
  );
$$;

revoke all on function public.dispute_evidence_is_readable(text)
  from public;
grant execute on function public.dispute_evidence_is_readable(text)
  to authenticated, service_role;

drop policy if exists "Participants read dispute evidence objects"
  on storage.objects;
create policy "Participants read dispute evidence objects"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'dispute-evidence'
    and public.dispute_evidence_is_readable(name)
  );

-- No participant can overwrite or physically remove submitted evidence.
drop policy if exists "Participants update dispute evidence"
  on storage.objects;
drop policy if exists "Participants delete dispute evidence"
  on storage.objects;

-- Non-listing media no longer shares product-images. These narrow buckets are
-- the migration targets for legacy avatar/outfit/accessory paths.
insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values
  (
    'profile-images',
    'profile-images',
    true,
    10485760,
    array['image/jpeg', 'image/png', 'image/webp']::text[]
  ),
  (
    'outfit-images',
    'outfit-images',
    true,
    15728640,
    array['image/jpeg', 'image/png', 'image/webp']::text[]
  ),
  (
    'accessory-images',
    'accessory-images',
    false,
    15728640,
    array['image/jpeg', 'image/png', 'image/webp']::text[]
  )
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Owners manage profile images" on storage.objects;
create policy "Owners manage profile images"
  on storage.objects for all to authenticated
  using (
    bucket_id = 'profile-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) || '/avatar/[^/]+$'
    )
  )
  with check (
    bucket_id = 'profile-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) || '/avatar/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
  );

drop policy if exists "Owners manage outfit images" on storage.objects;
create policy "Owners manage outfit images"
  on storage.objects for all to authenticated
  using (
    bucket_id = 'outfit-images'
    and owner_id = (select auth.uid()::text)
    and split_part(name, '/', 1) = (select auth.uid()::text)
    and exists (
      select 1
      from public.outfits outfit
      where outfit.id::text = split_part(name, '/', 2)
        and outfit.owner_id = (select auth.uid())
    )
  )
  with check (
    bucket_id = 'outfit-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
    and exists (
      select 1
      from public.outfits outfit
      where outfit.id::text = split_part(name, '/', 2)
        and outfit.owner_id = (select auth.uid())
    )
  );

drop policy if exists "Owners manage private accessory images"
  on storage.objects;
create policy "Owners manage private accessory images"
  on storage.objects for all to authenticated
  using (
    bucket_id = 'accessory-images'
    and owner_id = (select auth.uid()::text)
    and split_part(name, '/', 1) = (select auth.uid()::text)
    and exists (
      select 1
      from public.outfit_accessories accessory
      where accessory.id::text = split_part(name, '/', 2)
        and accessory.owner_id = (select auth.uid())
        and accessory.scope = 'private'
    )
  )
  with check (
    bucket_id = 'accessory-images'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and public.current_marketplace_user_is_eligible(false)
    and exists (
      select 1
      from public.outfit_accessories accessory
      where accessory.id::text = split_part(name, '/', 2)
        and accessory.owner_id = (select auth.uid())
        and accessory.scope = 'private'
    )
  );

drop policy if exists "Owners read private accessory images"
  on storage.objects;
create policy "Owners read private accessory images"
  on storage.objects for select to anon, authenticated
  using (
    bucket_id = 'accessory-images'
    and (
      owner_id = (select auth.uid()::text)
      or exists (
        select 1
        from public.outfit_accessories accessory
        where accessory.id::text = split_part(name, '/', 2)
          and accessory.scope = 'default'
      )
    )
  );

revoke all on function public.capture_chat_message_evidence()
  from public, anon, authenticated;
revoke all on function public.prevent_chat_message_physical_delete()
  from public, anon, authenticated;
revoke all on function public.require_onboarded_user_mutation()
  from public, anon, authenticated;
revoke all on function public.protect_outfit_server_fields()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
