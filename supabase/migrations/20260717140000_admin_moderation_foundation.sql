-- Safe foundations for moderation, remote catalog banners and a future
-- separate owner/admin panel. Nothing here silently enables live payments,
-- delivery providers or mandatory pre-moderation.

create table if not exists public.admin_roles (
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in (
    'support_read',
    'moderator',
    'catalog_editor',
    'finance_operator',
    'ops_admin',
    'owner'
  )),
  granted_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

alter table public.admin_roles enable row level security;

create or replace function public.is_app_admin(
  required_roles text[] default '{}'::text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.admin_roles role
    where role.user_id = auth.uid()
      and (
        cardinality(required_roles) = 0
        or role.role = any(required_roles)
        or role.role = 'owner'
      )
  );
$$;

revoke all on function public.is_app_admin(text[]) from public;
grant execute on function public.is_app_admin(text[]) to anon, authenticated;

drop policy if exists "Admins can read admin roles" on public.admin_roles;
create policy "Admins can read admin roles"
  on public.admin_roles for select to authenticated
  using (public.is_app_admin(array['ops_admin', 'owner']));

create table if not exists public.app_feature_flags (
  key text primary key check (key = btrim(key) and key <> ''),
  enabled boolean not null default false,
  is_public boolean not null default false,
  config jsonb not null default '{}'::jsonb,
  reason text not null default '',
  minimum_app_version text not null default '',
  rollout_percent integer not null default 0
    check (rollout_percent between 0 and 100),
  starts_at timestamptz,
  ends_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.app_feature_flags enable row level security;

drop policy if exists "Clients can read public feature flags"
  on public.app_feature_flags;
create policy "Clients can read public feature flags"
  on public.app_feature_flags for select
  using (is_public or public.is_app_admin());

insert into public.app_feature_flags (
  key,
  enabled,
  is_public,
  reason,
  rollout_percent
)
values
  ('checkout.live_enabled', false, true, 'Provider contracts are not active', 0),
  ('payments.yookassa_safe_deal.enabled', false, true, 'Contract and credentials required', 0),
  ('delivery.cdek.enabled', false, true, 'Contract and credentials required', 0),
  ('delivery.russian_post.enabled', false, true, 'Contract and credentials required', 0),
  ('delivery.yandex.enabled', false, true, 'Contract and credentials required', 0),
  ('moderation.require_approval', false, true, 'Enable only with staffed moderation queue', 0),
  ('remote_banners.enabled', false, true, 'Enable after admin panel rollout', 0)
on conflict (key) do nothing;

create table if not exists public.app_banners (
  id uuid primary key default gen_random_uuid(),
  placement text not null check (btrim(placement) <> ''),
  locale text not null default 'ru',
  title text not null default '',
  subtitle text not null default '',
  button_text text not null default '',
  image_url text not null,
  deep_link text not null default '',
  status text not null default 'draft'
    check (status in ('draft', 'published', 'archived')),
  audience jsonb not null default '{}'::jsonb,
  version integer not null default 1 check (version > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists app_banners_active_idx
  on public.app_banners (placement, locale, starts_at, ends_at)
  where status = 'published';

alter table public.app_banners enable row level security;

drop policy if exists "Clients can read active banners" on public.app_banners;
create policy "Clients can read active banners"
  on public.app_banners for select
  using (
    public.is_app_admin(array['catalog_editor', 'ops_admin'])
    or (
      status = 'published'
      and (starts_at is null or starts_at <= now())
      and (ends_at is null or ends_at > now())
    )
  );

create table if not exists public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  target_type text not null
    check (target_type in ('product', 'outfit', 'user', 'message')),
  target_id text not null check (btrim(target_id) <> ''),
  reason text not null check (btrim(reason) <> ''),
  details text not null default '',
  status text not null default 'open'
    check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  assigned_to uuid references auth.users(id) on delete set null,
  resolution text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists content_reports_queue_idx
  on public.content_reports (status, created_at);
create unique index if not exists content_reports_open_dedupe_idx
  on public.content_reports (reporter_id, target_type, target_id)
  where status in ('open', 'reviewing');

alter table public.content_reports enable row level security;

drop policy if exists "Users can submit reports" on public.content_reports;
create policy "Users can submit reports"
  on public.content_reports for insert to authenticated
  with check (auth.uid() = reporter_id);

drop policy if exists "Users and moderators can read reports"
  on public.content_reports;
create policy "Users and moderators can read reports"
  on public.content_reports for select to authenticated
  using (
    auth.uid() = reporter_id
    or public.is_app_admin(array['moderator', 'ops_admin'])
  );

create table if not exists public.blocked_users (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.blocked_users enable row level security;

drop policy if exists "Users can manage own blocks" on public.blocked_users;
create policy "Users can manage own blocks"
  on public.blocked_users for all to authenticated
  using (auth.uid() = blocker_id)
  with check (auth.uid() = blocker_id);

create or replace function public.users_are_blocked(
  first_user_id uuid,
  second_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  -- This RPC is intentionally caller-bound. Without the auth.uid() guard an
  -- authenticated client could probe arbitrary pairs and enumerate private
  -- block relationships despite blocked_users RLS.
  select auth.uid() is not null
    and auth.uid() in (first_user_id, second_user_id)
    and first_user_id is not null
    and second_user_id is not null
    and first_user_id <> second_user_id
    and exists (
      select 1
      from public.blocked_users blocked
      where (
        blocked.blocker_id = first_user_id
        and blocked.blocked_id = second_user_id
      ) or (
        blocked.blocker_id = second_user_id
        and blocked.blocked_id = first_user_id
      )
    );
$$;

revoke all on function public.users_are_blocked(uuid, uuid) from public;
grant execute on function public.users_are_blocked(uuid, uuid)
  to authenticated;

-- Blocking is mutual for communication: either participant can stop future
-- messages. Existing history remains available to the blocker for evidence.
drop policy if exists "Conversation members can send messages"
  on public.chat_messages;
create policy "Conversation members can send messages"
  on public.chat_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
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

drop policy if exists "Users can create their message threads"
  on public.message_threads;
create policy "Users can create their message threads"
  on public.message_threads for insert to authenticated
  with check (
    auth.uid() = any(member_ids)
    and not exists (
      select 1
      from unnest(member_ids) member_id
      where public.users_are_blocked(auth.uid(), member_id)
    )
  );

create table if not exists public.listing_moderation (
  product_id uuid primary key references public.products(id) on delete cascade,
  status text not null default 'pending'
    check (status in (
      'pending',
      'automated_review',
      'manual_review',
      'approved',
      'rejected',
      'needs_changes',
      'restricted',
      'removed'
    )),
  risk_flags jsonb not null default '{}'::jsonb,
  priority integer not null default 0,
  assigned_to uuid references auth.users(id) on delete set null,
  decision_reason text not null default '',
  submitted_at timestamptz not null default now(),
  decided_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists listing_moderation_queue_idx
  on public.listing_moderation (status, priority desc, submitted_at);

alter table public.listing_moderation enable row level security;

drop policy if exists "Sellers and moderators can read listing moderation"
  on public.listing_moderation;
create policy "Sellers and moderators can read listing moderation"
  on public.listing_moderation for select to authenticated
  using (
    exists (
      select 1 from public.products product
      where product.id = product_id and product.seller_id = auth.uid()
    )
    or public.is_app_admin(array['moderator', 'ops_admin'])
  );

create table if not exists public.admin_audit_log (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  actor_role text not null default '',
  action text not null check (btrim(action) <> ''),
  target_type text not null default '',
  target_id text not null default '',
  reason text not null default '',
  before_data jsonb,
  after_data jsonb,
  request_id text not null default '',
  created_at timestamptz not null default now()
);

alter table public.admin_audit_log enable row level security;

drop policy if exists "Ops admins can read audit log"
  on public.admin_audit_log;
create policy "Ops admins can read audit log"
  on public.admin_audit_log for select to authenticated
  using (public.is_app_admin(array['ops_admin', 'owner']));

notify pgrst, 'reload schema';
