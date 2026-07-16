create table if not exists public.device_push_tokens (
  token text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  platform text not null default 'unknown',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.device_push_tokens enable row level security;

drop policy if exists "Users can manage their push tokens" on public.device_push_tokens;
create policy "Users can manage their push tokens"
  on public.device_push_tokens for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

create table if not exists public.notification_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  push_enabled boolean not null default true,
  messages_enabled boolean not null default true,
  orders_enabled boolean not null default true,
  favorites_enabled boolean not null default true,
  promotions_enabled boolean not null default false,
  sound_enabled boolean not null default true,
  email_enabled boolean not null default false,
  sms_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table public.notification_settings
  add column if not exists messages_enabled boolean not null default true,
  add column if not exists orders_enabled boolean not null default true,
  add column if not exists favorites_enabled boolean not null default true,
  add column if not exists promotions_enabled boolean not null default false,
  add column if not exists sound_enabled boolean not null default true;

alter table public.notification_settings enable row level security;

drop policy if exists "Users can manage notification settings" on public.notification_settings;
create policy "Users can manage notification settings"
  on public.notification_settings for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create table if not exists public.notifications (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'general',
  target_id text not null default '',
  data jsonb not null default '{}'::jsonb,
  dedupe_key text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists dedupe_key text;

delete from public.notifications where kind = 'message';

alter table public.notifications enable row level security;

drop policy if exists "Users can manage their notifications" on public.notifications;
create policy "Users can manage their notifications"
  on public.notifications for all
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists notifications_user_created_idx
  on public.notifications (user_id, created_at desc);

create unique index if not exists notifications_user_dedupe_idx
  on public.notifications (user_id, dedupe_key);

notify pgrst, 'reload schema';
