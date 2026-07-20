-- C2C identity, age, legal-consent and seller-account boundary.
--
-- This migration intentionally publishes no legal-document version. Until an
-- operator loads and activates the three mandatory documents, onboarding and
-- every buyer/seller entitlement remain fail-closed.

begin;

-- Existing legacy SECURITY DEFINER functions use `public` in search_path.
-- Prevent every API role from creating shadow objects in that schema.
revoke create on schema public from public, anon, authenticated;

do $$
begin
  create type public.seller_type as enum (
    'private_individual',
    'self_employed',
    'individual_entrepreneur',
    'legal_entity'
  );
exception when duplicate_object then null;
end
$$;

do $$
begin
  create type public.seller_account_status as enum (
    'pending',
    'verified',
    'blocked'
  );
exception when duplicate_object then null;
end
$$;

do $$
begin
  create type public.seller_verification_status as enum (
    'not_started',
    'pending',
    'verified',
    'rejected',
    'review_required'
  );
exception when duplicate_object then null;
end
$$;

do $$
begin
  create type public.seller_moderation_status as enum (
    'clear',
    'pending',
    'under_review',
    'restricted',
    'blocked'
  );
exception when duplicate_object then null;
end
$$;

do $$
begin
  create type public.legal_document_type as enum (
    'terms',
    'privacy_policy',
    'personal_data_consent',
    'marketing_consent'
  );
exception when duplicate_object then null;
end
$$;

create table if not exists public.users (
  id uuid primary key,
  -- id is the durable marketplace party id. auth_user_id can be nulled after
  -- anonymisation without destroying orders, disputes or audit evidence.
  auth_user_id uuid unique references auth.users(id) on delete set null,
  account_status text not null default 'active'
    check (account_status in (
      'active', 'blocked', 'deletion_pending', 'anonymized'
    )),
  legal_onboarding_completed_at timestamptz,
  blocked_at timestamptz,
  anonymized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Some legacy projects created public.users before the durable identity
-- boundary existed. CREATE TABLE IF NOT EXISTS does not add missing columns,
-- so normalize that shape additively before the first backfill.
alter table public.users
  add column if not exists auth_user_id uuid,
  add column if not exists account_status text not null default 'active',
  add column if not exists legal_onboarding_completed_at timestamptz,
  add column if not exists blocked_at timestamptz,
  add column if not exists anonymized_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists users_auth_user_id_uidx
  on public.users (auth_user_id) where auth_user_id is not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_auth_user_id_fkey'
  ) then
    alter table public.users
      add constraint users_auth_user_id_fkey
      foreign key (auth_user_id) references auth.users(id)
      on delete set null not valid;
    alter table public.users validate constraint users_auth_user_id_fkey;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.users'::regclass
      and conname = 'users_account_status_check'
  ) then
    alter table public.users
      add constraint users_account_status_check check (
        account_status in ('active', 'blocked', 'deletion_pending', 'anonymized')
      ) not valid;
    alter table public.users validate constraint users_account_status_check;
  end if;
end
$$;

insert into public.users (id, email, auth_user_id, created_at, updated_at)
select account.id, coalesce(account.email, ''), account.id, account.created_at, now()
from auth.users account
on conflict (id) do update
set auth_user_id = excluded.auth_user_id,
    updated_at = now()
where public.users.account_status <> 'anonymized';

create table if not exists public.buyer_profiles (
  user_id uuid primary key references public.users(id) on delete restrict,
  birth_date date,
  age_verified boolean not null default false,
  age_verified_at timestamptz,
  verification_method text,
  verification_evidence jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (not age_verified and age_verified_at is null)
    or (age_verified and age_verified_at is not null
      and nullif(btrim(verification_method), '') is not null)
  )
);

insert into public.buyer_profiles (user_id)
select id from public.users
on conflict (user_id) do nothing;

create table if not exists public.seller_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.users(id) on delete restrict,
  seller_type public.seller_type not null default 'private_individual',
  status public.seller_account_status not null default 'pending',
  verification_status public.seller_verification_status not null
    default 'not_started',
  risk_score numeric(5,2) not null default 0
    check (risk_score between 0 and 100),
  moderation_status public.seller_moderation_status not null default 'pending',
  verification_requested_at timestamptz,
  verified_at timestamptz,
  blocked_at timestamptz,
  status_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    status <> 'verified'
    or (
      seller_type = 'private_individual'
      and verification_status = 'verified'
      and moderation_status = 'clear'
      and risk_score < 40
    )
  )
);

create index if not exists seller_accounts_queue_idx
  on public.seller_accounts (
    status, verification_status, moderation_status, risk_score desc, created_at
  );

create table if not exists public.business_profiles (
  seller_account_id uuid primary key
    references public.seller_accounts(id) on delete cascade,
  legal_name text not null,
  tax_id text not null,
  registration_number text not null default '',
  registered_address text not null default '',
  representative_name text not null default '',
  verification_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(legal_name) <> ''),
  check (btrim(tax_id) <> '')
);

create table if not exists public.seller_moderation_actions (
  id bigint generated always as identity primary key,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  actor_id uuid references public.users(id) on delete set null,
  action text not null,
  previous_status public.seller_account_status,
  new_status public.seller_account_status,
  previous_verification_status public.seller_verification_status,
  new_verification_status public.seller_verification_status,
  previous_moderation_status public.seller_moderation_status,
  new_moderation_status public.seller_moderation_status,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  check (btrim(action) <> ''),
  check (btrim(reason) <> '')
);

create table if not exists public.legal_documents (
  id uuid primary key default gen_random_uuid(),
  document_type public.legal_document_type not null unique,
  code text not null unique,
  title text not null,
  is_required boolean not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(code) <> ''),
  check (btrim(title) <> ''),
  check (
    (document_type = 'marketing_consent' and not is_required)
    or (document_type <> 'marketing_consent' and is_required)
  )
);

insert into public.legal_documents (
  document_type, code, title, is_required
)
values
  ('terms', 'terms', 'Пользовательское соглашение', true),
  (
    'privacy_policy',
    'privacy-policy',
    'Политика обработки персональных данных',
    true
  ),
  (
    'personal_data_consent',
    'personal-data-consent',
    'Согласие на обработку персональных данных',
    true
  ),
  (
    'marketing_consent',
    'marketing-consent',
    'Согласие на получение маркетинговых сообщений',
    false
  )
on conflict (document_type) do update
set code = excluded.code,
    title = excluded.title,
    is_required = excluded.is_required,
    updated_at = now();

create table if not exists public.legal_document_versions (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null
    references public.legal_documents(id) on delete restrict,
  version text not null,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'retired')),
  title text not null,
  content_url text not null,
  content_hash text not null,
  effective_at timestamptz,
  published_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default false,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (document_id, version),
  check (btrim(version) <> ''),
  check (btrim(title) <> ''),
  check (btrim(content_url) <> ''),
  check (btrim(content_hash) <> ''),
  check (
    not is_active
    or (
      status = 'published'
      and published_at is not null
      and effective_at is not null
    )
  ),
  check (expires_at is null or effective_at is null or expires_at > effective_at)
);

create unique index if not exists legal_document_one_active_version_idx
  on public.legal_document_versions (document_id)
  where is_active;

create or replace function public.protect_published_legal_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('published', 'retired')
     and (
       new.document_id is distinct from old.document_id
       or new.version is distinct from old.version
       or new.title is distinct from old.title
       or new.content_url is distinct from old.content_url
       or new.content_hash is distinct from old.content_hash
       or new.effective_at is distinct from old.effective_at
       or new.published_at is distinct from old.published_at
       or new.expires_at is distinct from old.expires_at
       or new.created_by is distinct from old.created_by
       or new.created_at is distinct from old.created_at
       or new.status not in ('published', 'retired')
       or (old.status = 'retired' and new.status <> 'retired')
     ) then
    raise exception 'published_legal_version_is_immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_published_legal_version_before_update
  on public.legal_document_versions;
create trigger protect_published_legal_version_before_update
before update on public.legal_document_versions
for each row execute function public.protect_published_legal_version();

create table if not exists public.user_consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete restrict,
  document_version_id uuid not null
    references public.legal_document_versions(id) on delete restrict,
  document_type public.legal_document_type not null,
  version text not null,
  accepted_at timestamptz not null default now(),
  ip inet not null,
  user_agent text not null,
  source text not null default 'onboarding',
  withdrawn_at timestamptz,
  withdrawal_ip inet,
  withdrawal_user_agent text,
  evidence jsonb not null default '{}'::jsonb,
  check (btrim(version) <> ''),
  check (char_length(user_agent) between 1 and 1000),
  check (
    (
      withdrawn_at is null
      and withdrawal_ip is null
      and withdrawal_user_agent is null
    )
    or (
      withdrawn_at is not null
      and document_type = 'marketing_consent'
      and withdrawal_ip is not null
      and char_length(btrim(coalesce(withdrawal_user_agent, '')))
        between 1 and 1000
    )
  ),
  check (withdrawn_at is null or withdrawn_at >= accepted_at)
);

create index if not exists user_consents_user_type_idx
  on public.user_consents (user_id, document_type, accepted_at desc);
create unique index if not exists user_consents_one_active_acceptance_idx
  on public.user_consents (user_id, document_version_id)
  where withdrawn_at is null;

create or replace function public.validate_user_consent_reference()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  referenced_type public.legal_document_type;
  referenced_version text;
begin
  select document.document_type, version_row.version
  into referenced_type, referenced_version
  from public.legal_document_versions version_row
  join public.legal_documents document
    on document.id = version_row.document_id
  where version_row.id = new.document_version_id;

  if not found
     or new.document_type is distinct from referenced_type
     or new.version is distinct from referenced_version then
    raise exception 'consent_document_reference_mismatch'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_user_consent_reference_before_write
  on public.user_consents;
create trigger validate_user_consent_reference_before_write
before insert or update on public.user_consents
for each row execute function public.validate_user_consent_reference();

create or replace function public.protect_user_consent_evidence()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'consent_evidence_is_immutable' using errcode = '42501';
  end if;
  if new.id is distinct from old.id
     or new.user_id is distinct from old.user_id
     or new.document_version_id is distinct from old.document_version_id
     or new.document_type is distinct from old.document_type
     or new.version is distinct from old.version
     or new.accepted_at is distinct from old.accepted_at
     or new.ip is distinct from old.ip
     or new.user_agent is distinct from old.user_agent
     or new.source is distinct from old.source
     or new.evidence is distinct from old.evidence
     or old.withdrawn_at is not null
     or (
       new.withdrawn_at is not null
       and new.document_type <> 'marketing_consent'
     ) then
    raise exception 'consent_evidence_is_immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_user_consent_evidence_before_change
  on public.user_consents;
create trigger protect_user_consent_evidence_before_change
before update or delete on public.user_consents
for each row execute function public.protect_user_consent_evidence();

create or replace function public.c2c_touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.bootstrap_public_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.users (
    id, email, auth_user_id, created_at, updated_at
  ) values (
    new.id, coalesce(new.email, ''), new.id, coalesce(new.created_at, now()), now()
  )
  on conflict (id) do update
  set auth_user_id = excluded.auth_user_id,
      updated_at = now()
  where public.users.account_status <> 'anonymized';

  insert into public.buyer_profiles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.bootstrap_public_user() from public;

drop trigger if exists bootstrap_public_user_after_auth_insert on auth.users;
create trigger bootstrap_public_user_after_auth_insert
after insert on auth.users
for each row execute function public.bootstrap_public_user();

drop trigger if exists touch_public_users_updated_at on public.users;
create trigger touch_public_users_updated_at
before update on public.users
for each row execute function public.c2c_touch_updated_at();

drop trigger if exists touch_buyer_profiles_updated_at on public.buyer_profiles;
create trigger touch_buyer_profiles_updated_at
before update on public.buyer_profiles
for each row execute function public.c2c_touch_updated_at();

drop trigger if exists touch_seller_accounts_updated_at on public.seller_accounts;
create trigger touch_seller_accounts_updated_at
before update on public.seller_accounts
for each row execute function public.c2c_touch_updated_at();

drop trigger if exists touch_business_profiles_updated_at on public.business_profiles;
create trigger touch_business_profiles_updated_at
before update on public.business_profiles
for each row execute function public.c2c_touch_updated_at();

drop trigger if exists touch_legal_documents_updated_at on public.legal_documents;
create trigger touch_legal_documents_updated_at
before update on public.legal_documents
for each row execute function public.c2c_touch_updated_at();

drop trigger if exists touch_legal_document_versions_updated_at
  on public.legal_document_versions;
create trigger touch_legal_document_versions_updated_at
before update on public.legal_document_versions
for each row execute function public.c2c_touch_updated_at();

-- Existing profile rows are moved from an auth lifecycle FK to the durable
-- marketplace party. public.users is never client-deletable.
alter table public.profiles
  drop constraint if exists profiles_id_fkey;
alter table public.profiles
  add constraint profiles_id_fkey
  foreign key (id) references public.users(id) on delete restrict;

create table if not exists public.profile_private_details (
  user_id uuid primary key references public.users(id) on delete restrict,
  first_name text not null default '',
  last_name text not null default '',
  middle_name text not null default '',
  gender text not null default 'male'
    check (gender in ('male', 'female')),
  birth_date date,
  phone text not null default '',
  email text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.profile_private_details
  drop constraint if exists profile_private_details_user_id_fkey;
alter table public.profile_private_details
  add constraint profile_private_details_user_id_fkey
  foreign key (user_id) references public.users(id) on delete restrict;

alter table public.products
  drop constraint if exists products_seller_id_fkey;
alter table public.products
  add constraint products_seller_id_fkey
  foreign key (seller_id) references public.users(id) on delete restrict;

alter table public.profiles
  add column if not exists verification_status text not null
    default 'unverified',
  add column if not exists moderation_status text not null
    default 'clear';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_verification_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_verification_status_check
      check (verification_status in (
        'unverified', 'pending', 'verified', 'rejected'
      ));
  end if;
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname = 'profiles_moderation_status_check'
  ) then
    alter table public.profiles
      add constraint profiles_moderation_status_check
      check (moderation_status in (
        'clear', 'pending', 'under_review', 'restricted', 'blocked'
      ));
  end if;
end
$$;

create or replace function public.protect_profile_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('anon', 'authenticated') then
      new.rating := 0;
      new.sales_count := 0;
      new.review_count := 0;
      new.followers_count := 0;
      new.verification_status := 'unverified';
      new.moderation_status := 'clear';
    end if;
    return new;
  end if;

  if current_user in ('anon', 'authenticated')
     and (
       new.rating is distinct from old.rating
       or new.sales_count is distinct from old.sales_count
       or new.review_count is distinct from old.review_count
       or new.followers_count is distinct from old.followers_count
       or new.verification_status is distinct from old.verification_status
       or new.moderation_status is distinct from old.moderation_status
     ) then
    raise exception 'profile_server_fields_are_immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_server_fields_before_write
  on public.profiles;
create trigger protect_profile_server_fields_before_write
before insert or update on public.profiles
for each row execute function public.protect_profile_server_fields();

alter table public.users enable row level security;
alter table public.buyer_profiles enable row level security;
alter table public.seller_accounts enable row level security;
alter table public.business_profiles enable row level security;
alter table public.seller_moderation_actions enable row level security;
alter table public.legal_documents enable row level security;
alter table public.legal_document_versions enable row level security;
alter table public.user_consents enable row level security;

drop policy if exists "Users read own durable account" on public.users;
create policy "Users read own durable account"
  on public.users for select to authenticated
  using (id = (select auth.uid()));

drop policy if exists "Users read own buyer profile" on public.buyer_profiles;
create policy "Users read own buyer profile"
  on public.buyer_profiles for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Users read own seller account" on public.seller_accounts;
create policy "Users read own seller account"
  on public.seller_accounts for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "Sellers read own business profile"
  on public.business_profiles;
create policy "Sellers read own business profile"
  on public.business_profiles for select to authenticated
  using (
    exists (
      select 1
      from public.seller_accounts seller
      where seller.id = seller_account_id
        and seller.user_id = (select auth.uid())
    )
  );

drop policy if exists "Published legal document definitions are readable"
  on public.legal_documents;
create policy "Published legal document definitions are readable"
  on public.legal_documents for select
  using (
    exists (
      select 1
      from public.legal_document_versions version_row
      where version_row.document_id = id
        and version_row.status = 'published'
        and version_row.is_active
        and version_row.effective_at <= now()
        and (
          version_row.expires_at is null
          or version_row.expires_at > now()
        )
    )
  );

drop policy if exists "Active legal document versions are readable"
  on public.legal_document_versions;
create policy "Active legal document versions are readable"
  on public.legal_document_versions for select
  using (
    status = 'published'
    and is_active
    and effective_at <= now()
    and (expires_at is null or expires_at > now())
  );

drop policy if exists "Users read own consent evidence" on public.user_consents;
create policy "Users read own consent evidence"
  on public.user_consents for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.users, public.buyer_profiles, public.seller_accounts,
  public.business_profiles, public.seller_moderation_actions,
  public.user_consents
from anon, authenticated;
grant select on public.users, public.buyer_profiles, public.seller_accounts,
  public.business_profiles, public.user_consents
to authenticated;

revoke all on public.legal_documents, public.legal_document_versions
  from anon, authenticated;
grant select on public.legal_documents, public.legal_document_versions
  to anon, authenticated;

-- Remove table-wide profile writes inherited from the baseline. Clients can
-- edit only display fields; every aggregate and moderation field is protected
-- by both column privileges and the trigger above.
revoke insert, update on public.profiles from authenticated;
grant insert (id, name, handle, avatar_url, city, last_seen_at)
  on public.profiles to authenticated;
grant update (name, handle, avatar_url, city, last_seen_at)
  on public.profiles to authenticated;

-- The private legacy profile is not the source of truth for age. Clients may
-- maintain contact/display data, but birth_date is written only by the
-- server-side onboarding/verification flow.
revoke insert, update on public.profile_private_details from authenticated;
grant insert (
  user_id, first_name, last_name, middle_name, gender, phone, email
) on public.profile_private_details to authenticated;
grant update (
  first_name, last_name, middle_name, gender, phone, email
) on public.profile_private_details to authenticated;

create or replace function public.get_active_legal_documents()
returns table (
  document_type text,
  document_code text,
  version text,
  title text,
  content_url text,
  content_hash text,
  published_at timestamptz,
  is_required boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    document.document_type::text,
    document.code,
    version_row.version,
    version_row.title,
    version_row.content_url,
    version_row.content_hash,
    version_row.published_at,
    document.is_required
  from public.legal_documents document
  join public.legal_document_versions version_row
    on version_row.document_id = document.id
  where version_row.status = 'published'
    and version_row.is_active
    and version_row.effective_at <= now()
    and (
      version_row.expires_at is null
      or version_row.expires_at > now()
    )
  order by document.is_required desc, document.document_type;
$$;

revoke all on function public.get_active_legal_documents() from public;
grant execute on function public.get_active_legal_documents()
  to anon, authenticated, service_role;

create or replace function public.complete_legal_onboarding(
  p_user_id uuid,
  p_birth_date date,
  p_required_versions jsonb,
  p_marketing_version text default null,
  p_ip inet default null,
  p_user_agent text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  required_type public.legal_document_type;
  supplied_version text;
  active_version public.legal_document_versions%rowtype;
  active_document public.legal_documents%rowtype;
  required_types constant public.legal_document_type[] := array[
    'terms'::public.legal_document_type,
    'privacy_policy'::public.legal_document_type,
    'personal_data_consent'::public.legal_document_type
  ];
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_user_id is null
     or not exists (select 1 from auth.users account where account.id = p_user_id) then
    raise exception 'auth_user_not_found' using errcode = 'P0002';
  end if;
  if p_birth_date is null
     or p_birth_date > (current_date - interval '18 years')::date
     or p_birth_date < (current_date - interval '120 years')::date then
    raise exception 'age_18_required' using errcode = '23514';
  end if;
  if p_ip is null then
    raise exception 'consent_ip_required' using errcode = '23514';
  end if;
  if char_length(btrim(coalesce(p_user_agent, ''))) not between 1 and 1000 then
    raise exception 'consent_user_agent_required' using errcode = '23514';
  end if;
  if jsonb_typeof(coalesce(p_required_versions, '{}'::jsonb)) <> 'object' then
    raise exception 'required_document_versions_invalid' using errcode = '22023';
  end if;
  if (
    select count(*) from jsonb_object_keys(p_required_versions)
  ) <> 3 or exists (
    select 1
    from jsonb_object_keys(p_required_versions) supplied_key
    where supplied_key not in (
      'terms', 'privacy_policy', 'personal_data_consent'
    )
  ) then
    raise exception 'required_document_versions_invalid'
      using errcode = '22023';
  end if;

  insert into public.users (id, email, auth_user_id)
  select account.id, coalesce(account.email, ''), account.id
  from auth.users account
  where account.id = p_user_id
  on conflict (id) do nothing;

  if not exists (
    select 1
    from public.users durable_user
    where durable_user.id = p_user_id
      and durable_user.auth_user_id = p_user_id
      and durable_user.account_status = 'active'
  ) then
    raise exception 'account_not_active' using errcode = '42501';
  end if;

  foreach required_type in array required_types loop
    supplied_version := nullif(
      btrim(coalesce(p_required_versions ->> required_type::text, '')),
      ''
    );
    if supplied_version is null then
      raise exception 'mandatory_document_acceptance_missing'
        using errcode = '23514',
          detail = required_type::text;
    end if;

    select version_row.*
    into active_version
    from public.legal_documents document
    join public.legal_document_versions version_row
      on version_row.document_id = document.id
    where document.document_type = required_type
      and document.is_required
      and version_row.version = supplied_version
      and version_row.status = 'published'
      and version_row.is_active
      and version_row.effective_at <= now()
      and (
        version_row.expires_at is null
        or version_row.expires_at > now()
      );

    if not found then
      raise exception 'mandatory_document_version_not_active'
        using errcode = '55000',
          detail = required_type::text;
    end if;
    select document.* into active_document
    from public.legal_documents document
    where document.id = active_version.document_id;

    insert into public.user_consents (
      user_id,
      document_version_id,
      document_type,
      version,
      accepted_at,
      ip,
      user_agent,
      source,
      evidence
    )
    values (
      p_user_id,
      active_version.id,
      required_type,
      active_version.version,
      now(),
      p_ip,
      btrim(p_user_agent),
      'onboarding',
      jsonb_build_object('content_hash', active_version.content_hash)
    )
    on conflict (user_id, document_version_id)
      where withdrawn_at is null
    do nothing;
  end loop;

  if nullif(btrim(coalesce(p_marketing_version, '')), '') is not null then
    select version_row.*
    into active_version
    from public.legal_documents document
    join public.legal_document_versions version_row
      on version_row.document_id = document.id
    where document.document_type = 'marketing_consent'
      and not document.is_required
      and version_row.version = btrim(p_marketing_version)
      and version_row.status = 'published'
      and version_row.is_active
      and version_row.effective_at <= now()
      and (
        version_row.expires_at is null
        or version_row.expires_at > now()
      );
    if not found then
      raise exception 'marketing_document_version_not_active'
        using errcode = '55000';
    end if;
    select document.* into active_document
    from public.legal_documents document
    where document.id = active_version.document_id;

    insert into public.user_consents (
      user_id,
      document_version_id,
      document_type,
      version,
      accepted_at,
      ip,
      user_agent,
      source,
      evidence
    )
    values (
      p_user_id,
      active_version.id,
      'marketing_consent',
      active_version.version,
      now(),
      p_ip,
      btrim(p_user_agent),
      'onboarding_optional',
      jsonb_build_object('content_hash', active_version.content_hash)
    )
    on conflict (user_id, document_version_id)
      where withdrawn_at is null
    do nothing;
  end if;

  insert into public.buyer_profiles (
    user_id,
    birth_date,
    age_verified,
    age_verified_at,
    verification_method,
    verification_evidence,
    updated_at
  )
  values (
    p_user_id,
    p_birth_date,
    true,
    now(),
    'server_validated_birth_date_declaration',
    jsonb_build_object('minimum_age', 18),
    now()
  )
  on conflict (user_id) do update
  set birth_date = excluded.birth_date,
      age_verified = true,
      age_verified_at = excluded.age_verified_at,
      verification_method = excluded.verification_method,
      verification_evidence = excluded.verification_evidence,
      updated_at = now();

  update public.profile_private_details
  set birth_date = p_birth_date,
      updated_at = now()
  where user_id = p_user_id;

  update public.users
  set legal_onboarding_completed_at = now(),
      updated_at = now()
  where id = p_user_id
    and account_status = 'active';

  return jsonb_build_object(
    'user_id', p_user_id,
    'age_verified', true,
    'legal_onboarding_complete', true,
    'marketing_accepted',
      nullif(btrim(coalesce(p_marketing_version, '')), '') is not null
  );
end;
$$;

revoke all on function public.complete_legal_onboarding(
  uuid, date, jsonb, text, inet, text
) from public, anon, authenticated;
grant execute on function public.complete_legal_onboarding(
  uuid, date, jsonb, text, inet, text
) to service_role;

create or replace function public.withdraw_marketing_consent(
  p_ip inet,
  p_user_agent text
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  affected integer;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if p_ip is null
     or char_length(btrim(coalesce(p_user_agent, ''))) not between 1 and 1000 then
    raise exception 'withdrawal_evidence_required' using errcode = '23514';
  end if;

  update public.user_consents
  set withdrawn_at = now(),
      withdrawal_ip = p_ip,
      withdrawal_user_agent = btrim(p_user_agent)
  where user_id = actor_id
    and document_type = 'marketing_consent'
    and withdrawn_at is null;
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.withdraw_marketing_consent(inet, text)
  from public, anon;
grant execute on function public.withdraw_marketing_consent(inet, text)
  to authenticated;

create or replace function public.get_user_entitlements()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  buyer public.buyer_profiles%rowtype;
  durable_user public.users%rowtype;
  seller public.seller_accounts%rowtype;
  missing_documents text[];
  legal_complete boolean;
  buyer_enabled boolean;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;

  select * into durable_user
  from public.users account
  where account.id = actor_id;
  select * into buyer
  from public.buyer_profiles profile
  where profile.user_id = actor_id;
  select * into seller
  from public.seller_accounts account
  where account.user_id = actor_id;

  select coalesce(array_agg(missing.document_type order by missing.document_type), '{}')
  into missing_documents
  from (
    select document.document_type::text as document_type
    from public.legal_documents document
    join public.legal_document_versions active_version
      on active_version.document_id = document.id
     and active_version.status = 'published'
     and active_version.is_active
     and active_version.effective_at <= now()
     and (
       active_version.expires_at is null
       or active_version.expires_at > now()
     )
    where document.is_required
      and not exists (
        select 1
        from public.user_consents consent
        where consent.user_id = actor_id
          and consent.document_version_id = active_version.id
          and consent.withdrawn_at is null
      )
  ) missing;

  legal_complete := durable_user.id is not null
    and durable_user.account_status = 'active'
    and cardinality(missing_documents) = 0
    and (
      select count(*)
      from public.legal_documents required_document
      join public.legal_document_versions active_version
        on active_version.document_id = required_document.id
       and active_version.status = 'published'
       and active_version.is_active
       and active_version.effective_at <= now()
       and (
         active_version.expires_at is null
         or active_version.expires_at > now()
       )
      where required_document.is_required
    ) = 3;

  buyer_enabled := legal_complete
    and coalesce(buyer.age_verified, false)
    and buyer.birth_date <= (current_date - interval '18 years')::date;

  return jsonb_build_object(
    'user_id', actor_id,
    'account_status', coalesce(durable_user.account_status, 'missing'),
    'age_verified', coalesce(buyer.age_verified, false),
    'legal_onboarding_complete', legal_complete,
    'buyer_enabled', buyer_enabled,
    'missing_required_documents', to_jsonb(missing_documents),
    'seller_account_id', seller.id,
    'seller_type', seller.seller_type,
    'seller_status', seller.status,
    'seller_verification_status', seller.verification_status,
    'seller_moderation_status', seller.moderation_status,
    'seller_risk_score', seller.risk_score,
    'seller_can_publish',
      buyer_enabled
      and seller.seller_type = 'private_individual'
      and seller.status = 'verified'
      and seller.verification_status = 'verified'
      and seller.moderation_status = 'clear'
      and seller.risk_score < 40
  );
end;
$$;

revoke all on function public.get_user_entitlements() from public, anon;
grant execute on function public.get_user_entitlements() to authenticated;

create or replace function public.request_private_seller_activation()
returns public.seller_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  entitlements jsonb;
  result public.seller_accounts%rowtype;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  entitlements := public.get_user_entitlements();
  if not coalesce((entitlements ->> 'buyer_enabled')::boolean, false) then
    raise exception 'legal_and_age_onboarding_required' using errcode = '55000';
  end if;

  insert into public.seller_accounts (
    user_id,
    seller_type,
    status,
    verification_status,
    moderation_status,
    verification_requested_at
  )
  values (
    actor_id,
    'private_individual',
    'pending',
    'pending',
    'pending',
    now()
  )
  on conflict (user_id) do update
  set verification_requested_at = now(),
      verification_status = case
        when seller_accounts.status = 'blocked'
          then seller_accounts.verification_status
        else 'pending'::public.seller_verification_status
      end,
      moderation_status = case
        when seller_accounts.status = 'blocked'
          then seller_accounts.moderation_status
        else 'pending'::public.seller_moderation_status
      end,
      updated_at = now()
  returning * into result;

  if result.seller_type <> 'private_individual' then
    raise exception 'seller_type_not_available_in_mvp' using errcode = '55000';
  end if;
  if result.status = 'blocked' then
    raise exception 'seller_blocked' using errcode = '42501';
  end if;
  return result;
end;
$$;

revoke all on function public.request_private_seller_activation()
  from public, anon;
grant execute on function public.request_private_seller_activation()
  to authenticated;

create or replace function public.moderate_seller_account(
  p_user_id uuid,
  p_status text,
  p_verification_status text,
  p_moderation_status text,
  p_reason text,
  p_actor_id uuid
)
returns public.seller_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  previous public.seller_accounts%rowtype;
  result public.seller_accounts%rowtype;
  new_status public.seller_account_status;
  new_verification public.seller_verification_status;
  new_moderation public.seller_moderation_status;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_actor_id is null or not exists (
    select 1
    from public.admin_roles role
    where role.user_id = p_actor_id
      and role.role in ('moderator', 'ops_admin', 'owner')
  ) then
    raise exception 'authorized_moderator_required' using errcode = '42501';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then
    raise exception 'moderation_reason_required' using errcode = '23514';
  end if;

  begin
    new_status := p_status::public.seller_account_status;
    new_verification :=
      p_verification_status::public.seller_verification_status;
    new_moderation :=
      p_moderation_status::public.seller_moderation_status;
  exception when invalid_text_representation then
    raise exception 'invalid_seller_moderation_state' using errcode = '22023';
  end;

  select * into previous
  from public.seller_accounts account
  where account.user_id = p_user_id
  for update;
  if not found then
    raise exception 'seller_account_not_found' using errcode = 'P0002';
  end if;
  if new_status = 'verified' and (
    previous.seller_type <> 'private_individual'
    or new_verification <> 'verified'
    or new_moderation <> 'clear'
    or previous.risk_score >= 40
  ) then
    raise exception 'seller_not_eligible_for_verification'
      using errcode = '23514';
  end if;

  update public.seller_accounts
  set status = new_status,
      verification_status = new_verification,
      moderation_status = new_moderation,
      verified_at = case when new_status = 'verified' then now() else verified_at end,
      blocked_at = case when new_status = 'blocked' then now() else null end,
      status_reason = btrim(p_reason),
      updated_at = now()
  where user_id = p_user_id
  returning * into result;

  update public.profiles
  set verification_status = case result.verification_status
        when 'verified' then 'verified'
        when 'pending' then 'pending'
        when 'rejected' then 'rejected'
        else 'unverified'
      end,
      moderation_status = case result.moderation_status
        when 'clear' then 'clear'
        when 'pending' then 'pending'
        when 'under_review' then 'under_review'
        when 'restricted' then 'restricted'
        else 'blocked'
      end,
      updated_at = now()
  where id = p_user_id;

  insert into public.seller_moderation_actions (
    seller_account_id,
    actor_id,
    action,
    previous_status,
    new_status,
    previous_verification_status,
    new_verification_status,
    previous_moderation_status,
    new_moderation_status,
    reason
  )
  values (
    result.id,
    p_actor_id,
    'moderate_seller_account',
    previous.status,
    result.status,
    previous.verification_status,
    result.verification_status,
    previous.moderation_status,
    result.moderation_status,
    btrim(p_reason)
  );
  return result;
end;
$$;

revoke all on function public.moderate_seller_account(
  uuid, text, text, text, text, uuid
) from public, anon, authenticated;
grant execute on function public.moderate_seller_account(
  uuid, text, text, text, text, uuid
) to service_role;

revoke all on function public.protect_published_legal_version()
  from public, anon, authenticated;
revoke all on function public.validate_user_consent_reference()
  from public, anon, authenticated;
revoke all on function public.protect_user_consent_evidence()
  from public, anon, authenticated;
revoke all on function public.c2c_touch_updated_at()
  from public, anon, authenticated;
revoke all on function public.protect_profile_server_fields()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
