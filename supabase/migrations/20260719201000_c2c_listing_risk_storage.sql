-- Authoritative listing publication, seller declarations, deterministic risk
-- signals and owner-bound Storage namespaces.

begin;

create table if not exists public.seller_confirmation_versions (
  id uuid primary key default gen_random_uuid(),
  version text not null unique,
  status text not null default 'draft'
    check (status in ('draft', 'active', 'retired')),
  required_confirmations text[] not null,
  schema_hash text not null,
  effective_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (btrim(version) <> ''),
  check (btrim(schema_hash) <> ''),
  check (cardinality(required_confirmations) = 7),
  check (not (status = 'active') or effective_at is not null)
);

create unique index if not exists seller_confirmation_one_active_idx
  on public.seller_confirmation_versions ((status))
  where status = 'active';

-- This is a machine-readable declaration schema, not operator legal content.
insert into public.seller_confirmation_versions (
  version,
  status,
  required_confirmations,
  schema_hash,
  effective_at
)
values (
  'private-individual-v1',
  'active',
  array[
    'owns_item',
    'has_right_to_sell',
    'has_item_in_possession',
    'owns_photos',
    'description_is_accurate',
    'item_is_authentic',
    'item_is_not_prohibited'
  ]::text[],
  'seller-confirmation-schema:private-individual-v1',
  now()
)
on conflict (version) do nothing;

create or replace function public.protect_seller_confirmation_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.status in ('active', 'retired')
     and (
       new.version is distinct from old.version
       or new.required_confirmations
         is distinct from old.required_confirmations
       or new.schema_hash is distinct from old.schema_hash
       or new.effective_at is distinct from old.effective_at
       or new.created_at is distinct from old.created_at
       or new.status not in ('active', 'retired')
       or (old.status = 'retired' and new.status <> 'retired')
     ) then
    raise exception 'seller_confirmation_version_is_immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_seller_confirmation_version_before_update
  on public.seller_confirmation_versions;
create trigger protect_seller_confirmation_version_before_update
before update on public.seller_confirmation_versions
for each row execute function public.protect_seller_confirmation_version();

create table if not exists public.listing_publication_attempts (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.products(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  confirmation_version_id uuid not null
    references public.seller_confirmation_versions(id) on delete restrict,
  confirmations jsonb not null,
  ip inet not null,
  user_agent text not null,
  status text not null default 'prepared'
    check (status in ('prepared', 'published', 'held', 'aborted', 'expired')),
  risk_result jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null,
  finalized_at timestamptz,
  aborted_reason text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (jsonb_typeof(confirmations) = 'object'),
  check (char_length(user_agent) between 1 and 1000)
);

create unique index if not exists listing_one_prepared_publication_idx
  on public.listing_publication_attempts (listing_id)
  where status = 'prepared';

create table if not exists public.seller_confirmations (
  id uuid primary key default gen_random_uuid(),
  publication_id uuid not null unique
    references public.listing_publication_attempts(id) on delete restrict,
  listing_id uuid not null references public.products(id) on delete restrict,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  confirmation_version_id uuid not null
    references public.seller_confirmation_versions(id) on delete restrict,
  version text not null,
  confirmations jsonb not null,
  confirmed_at timestamptz not null default now(),
  ip inet not null,
  user_agent text not null,
  check (jsonb_typeof(confirmations) = 'object'),
  check (char_length(user_agent) between 1 and 1000)
);

create index if not exists seller_confirmations_user_created_idx
  on public.seller_confirmations (user_id, confirmed_at desc);

create or replace function public.prevent_seller_confirmation_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'seller_confirmation_evidence_is_immutable'
    using errcode = '42501';
end;
$$;

drop trigger if exists seller_confirmations_are_immutable
  on public.seller_confirmations;
create trigger seller_confirmations_are_immutable
before update or delete on public.seller_confirmations
for each row execute function public.prevent_seller_confirmation_mutation();

create table if not exists public.listing_risk_fingerprints (
  listing_id uuid primary key references public.products(id) on delete restrict,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  product_signature text not null,
  evaluated_at timestamptz not null default now(),
  check (length(product_signature) = 64)
);

create index if not exists listing_risk_signature_idx
  on public.listing_risk_fingerprints (
    seller_account_id, product_signature
  );

create table if not exists public.listing_image_fingerprints (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.products(id) on delete restrict,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  user_id uuid not null references public.users(id) on delete restrict,
  object_path text not null,
  content_hash text not null,
  perceptual_hash text,
  created_at timestamptz not null default now(),
  unique (listing_id, object_path),
  check (content_hash ~ '^[0-9a-f]{64}$')
);

create index if not exists listing_image_exact_hash_idx
  on public.listing_image_fingerprints (
    seller_account_id, content_hash
  );
create index if not exists listing_image_perceptual_hash_idx
  on public.listing_image_fingerprints (
    seller_account_id, perceptual_hash
  )
  where perceptual_hash is not null;

create table if not exists public.seller_risk_events (
  id bigint generated always as identity primary key,
  seller_account_id uuid not null
    references public.seller_accounts(id) on delete restrict,
  listing_id uuid references public.products(id) on delete set null,
  event_type text not null,
  severity text not null check (severity in (
    'low', 'medium', 'high', 'critical'
  )),
  score_delta numeric(5,2) not null check (score_delta between 0 and 100),
  risk_score numeric(5,2) not null check (risk_score between 0 and 100),
  evidence jsonb not null default '{}'::jsonb,
  action text not null default 'none' check (action in (
    'none', 'listing_hidden', 'verification_hold', 'sales_blocked'
  )),
  status text not null default 'open'
    check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  dedupe_key text not null unique,
  resolved_by uuid references public.users(id) on delete set null,
  resolved_at timestamptz,
  resolution text not null default '',
  created_at timestamptz not null default now(),
  check (btrim(event_type) <> ''),
  check (btrim(dedupe_key) <> '')
);

create index if not exists seller_risk_events_queue_idx
  on public.seller_risk_events (
    status, severity, risk_score desc, created_at
  );

alter table public.product_images
  add column if not exists storage_bucket text,
  add column if not exists storage_path text,
  add column if not exists uploader_id uuid references public.users(id)
    on delete set null,
  add column if not exists content_hash text,
  add column if not exists mime_type text;

create unique index if not exists product_images_storage_object_idx
  on public.product_images (storage_bucket, storage_path)
  where storage_bucket is not null and storage_path is not null;

create or replace function public.validate_seller_confirmation_payload(
  p_version_id uuid,
  p_confirmations jsonb
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    jsonb_typeof(p_confirmations) = 'object'
    and (
      select count(*)
      from jsonb_object_keys(p_confirmations)
    ) = cardinality(version_row.required_confirmations)
    and not exists (
      select 1
      from jsonb_object_keys(p_confirmations) supplied_key
      where not (supplied_key = any(version_row.required_confirmations))
    )
    and not exists (
      select 1
      from unnest(version_row.required_confirmations) required_key
      where p_confirmations -> required_key is distinct from 'true'::jsonb
    )
  from public.seller_confirmation_versions version_row
  where version_row.id = p_version_id
    and version_row.status = 'active'
    and version_row.effective_at <= now();
$$;

revoke all on function public.validate_seller_confirmation_payload(uuid, jsonb)
  from public, anon, authenticated;

create or replace function public.marketplace_user_is_eligible(
  p_user_id uuid,
  p_require_seller boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.users durable_user
    join public.buyer_profiles buyer on buyer.user_id = durable_user.id
    where durable_user.id = p_user_id
      and durable_user.auth_user_id = p_user_id
      and durable_user.account_status = 'active'
      and buyer.age_verified
      and buyer.birth_date <= (current_date - interval '18 years')::date
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
          and exists (
            select 1
            from public.user_consents consent
            where consent.user_id = p_user_id
              and consent.document_version_id = active_version.id
              and consent.withdrawn_at is null
          )
      ) = 3
      and (
        not p_require_seller
        or exists (
          select 1
          from public.seller_accounts seller
          where seller.user_id = p_user_id
            and seller.seller_type = 'private_individual'
            and seller.status = 'verified'
            and seller.verification_status = 'verified'
            and seller.moderation_status = 'clear'
            and seller.risk_score < 40
        )
      )
  );
$$;

revoke all on function public.marketplace_user_is_eligible(uuid, boolean)
  from public, anon, authenticated;

create or replace function public.current_marketplace_user_is_eligible(
  p_require_seller boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null
    and public.marketplace_user_is_eligible(
      auth.uid(),
      p_require_seller
    );
$$;

revoke all on function public.current_marketplace_user_is_eligible(boolean)
  from public, anon;
grant execute on function public.current_marketplace_user_is_eligible(boolean)
  to authenticated;

create or replace function public.protect_product_server_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if current_user in ('anon', 'authenticated') then
      new.seller_id := auth.uid();
      new.status := 'draft';
      new.is_hidden := true;
      new.published_at := null;
      new.views_count := 0;
      new.likes_count := 0;
      new.moderation_risk := '{}'::jsonb;
      new.recommendation_tags := '{}'::text[];
      new.enrichment_status := 'enrichment_pending';
      new.enrichment_version := null;
      new.enrichment_completed_at := null;
      new.photo_quality_score := null;
      new.analysis_job_id := null;
    end if;
    return new;
  end if;

  if current_user in ('anon', 'authenticated')
     and (
       new.seller_id is distinct from old.seller_id
       or new.status is distinct from old.status
       or new.is_hidden is distinct from old.is_hidden
       or new.published_at is distinct from old.published_at
       or new.views_count is distinct from old.views_count
       or new.likes_count is distinct from old.likes_count
       or new.moderation_risk is distinct from old.moderation_risk
       or new.recommendation_tags is distinct from old.recommendation_tags
       or new.enrichment_status is distinct from old.enrichment_status
       or new.enrichment_version is distinct from old.enrichment_version
       or new.enrichment_completed_at is distinct from old.enrichment_completed_at
       or new.photo_quality_score is distinct from old.photo_quality_score
       or new.analysis_job_id is distinct from old.analysis_job_id
       or new.background_status is distinct from old.background_status
       or new.background_error is distinct from old.background_error
     ) then
    raise exception 'product_server_fields_are_immutable'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_product_server_fields_before_write
  on public.products;
create trigger protect_product_server_fields_before_write
before insert or update on public.products
for each row execute function public.protect_product_server_fields();

-- Baseline table-wide DML grants allowed sellers to forge counters, seller
-- snapshots and publication state. All draft writes now cross one validated
-- server boundary.
revoke insert, update, delete on public.products from authenticated;

create or replace function public.save_listing_draft(
  p_listing_id uuid default null,
  p_payload jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  resolved_listing_id uuid := coalesce(p_listing_id, gen_random_uuid());
  profile_row public.profiles%rowtype;
  existing_listing public.products%rowtype;
  unknown_keys text[];
  secondary_colors_value text[];
  delivery_methods_value text[];
  shipping_address_value uuid;
  price_value numeric;
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if not public.marketplace_user_is_eligible(actor_id, false) then
    raise exception 'user_not_eligible' using errcode = '42501';
  end if;
  if not exists (
    select 1
    from public.seller_accounts seller
    where seller.user_id = actor_id
      and seller.seller_type = 'private_individual'
      and seller.status <> 'blocked'
      and seller.moderation_status <> 'blocked'
  ) then
    raise exception 'seller_account_required' using errcode = '42501';
  end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'listing_payload_must_be_object' using errcode = '22023';
  end if;

  select array_agg(payload_key order by payload_key)
  into unknown_keys
  from jsonb_object_keys(p_payload) payload_key
  where payload_key <> all(array[
    'title', 'description', 'price', 'category', 'brand', 'size', 'color',
    'condition', 'location', 'section', 'subcategory', 'item_type', 'gender',
    'primary_color', 'secondary_colors', 'material', 'pattern', 'season',
    'style', 'city', 'shipping_address_id', 'delivery_methods', 'draft_step',
    'fit', 'sleeve_length', 'closure', 'audience', 'has_defects',
    'defects_description', 'defects_reviewed'
  ]::text[]);
  if cardinality(unknown_keys) > 0 then
    raise exception 'listing_payload_contains_forbidden_fields'
      using errcode = '22023',
        detail = array_to_string(unknown_keys, ',');
  end if;

  if p_payload ? 'price' then
    begin
      price_value := (p_payload ->> 'price')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'listing_price_invalid' using errcode = '22023';
    end;
    if price_value < 0 or price_value > 100000000 then
      raise exception 'listing_price_invalid' using errcode = '23514';
    end if;
  end if;

  if p_payload ? 'secondary_colors' then
    if jsonb_typeof(p_payload -> 'secondary_colors') <> 'array' then
      raise exception 'secondary_colors_must_be_array'
        using errcode = '22023';
    end if;
    select coalesce(array_agg(left(value, 80)), '{}'::text[])
    into secondary_colors_value
    from jsonb_array_elements_text(p_payload -> 'secondary_colors');
    if cardinality(secondary_colors_value) > 8 then
      raise exception 'too_many_secondary_colors' using errcode = '22023';
    end if;
  end if;

  if p_payload ? 'delivery_methods' then
    if jsonb_typeof(p_payload -> 'delivery_methods') <> 'array' then
      raise exception 'delivery_methods_must_be_array'
        using errcode = '22023';
    end if;
    select coalesce(array_agg(value), '{}'::text[])
    into delivery_methods_value
    from jsonb_array_elements_text(p_payload -> 'delivery_methods');
    if cardinality(delivery_methods_value) > 5
       or exists (
         select 1
         from unnest(delivery_methods_value) method
         where method not in (
           'cdek', 'yandex_delivery', 'russian_post', 'personal_meeting'
         )
       ) then
      raise exception 'delivery_method_not_allowed' using errcode = '22023';
    end if;
  end if;

  if p_payload ? 'shipping_address_id'
     and p_payload -> 'shipping_address_id' <> 'null'::jsonb then
    begin
      shipping_address_value := (p_payload ->> 'shipping_address_id')::uuid;
    exception when invalid_text_representation then
      raise exception 'shipping_address_id_invalid' using errcode = '22023';
    end;
    if not exists (
      select 1
      from public.listing_addresses address
      where address.id = shipping_address_value
        and address.user_id = actor_id
    ) then
      raise exception 'shipping_address_not_owned' using errcode = '42501';
    end if;
  end if;

  select * into profile_row
  from public.profiles profile
  where profile.id = actor_id;

  select * into existing_listing
  from public.products product
  where product.id = resolved_listing_id
  for update;
  if found and (
    existing_listing.seller_id is distinct from actor_id
    or existing_listing.status not in ('draft', 'processing', 'ready')
  ) then
    raise exception 'listing_draft_not_editable' using errcode = '42501';
  end if;

  if existing_listing.id is null then
    insert into public.products (
      id,
      seller_id,
      seller_name,
      seller_handle,
      status,
      is_hidden,
      published_at,
      created_at,
      updated_at,
      last_autosaved_at
    )
    values (
      resolved_listing_id,
      actor_id,
      coalesce(nullif(btrim(profile_row.name), ''), 'Продавец'),
      coalesce(nullif(btrim(profile_row.handle), ''), '@seller'),
      'draft',
      true,
      null,
      now(),
      now(),
      now()
    );
  end if;

  update public.products
  set
    seller_name = coalesce(nullif(btrim(profile_row.name), ''), 'Продавец'),
    seller_handle = coalesce(nullif(btrim(profile_row.handle), ''), '@seller'),
    title = case when p_payload ? 'title'
      then left(btrim(coalesce(p_payload ->> 'title', '')), 80) else title end,
    description = case when p_payload ? 'description'
      then left(coalesce(p_payload ->> 'description', ''), 2000)
      else description end,
    price = case when p_payload ? 'price' then price_value else price end,
    category = case when p_payload ? 'category'
      then left(btrim(coalesce(p_payload ->> 'category', '')), 120)
      else category end,
    brand = case when p_payload ? 'brand'
      then left(btrim(coalesce(p_payload ->> 'brand', '')), 120)
      else brand end,
    size = case when p_payload ? 'size'
      then left(btrim(coalesce(p_payload ->> 'size', '')), 80) else size end,
    color = case when p_payload ? 'color'
      then left(btrim(coalesce(p_payload ->> 'color', '')), 80) else color end,
    condition = case when p_payload ? 'condition'
      then left(btrim(coalesce(p_payload ->> 'condition', '')), 80)
      else condition end,
    location = case when p_payload ? 'location'
      then left(btrim(coalesce(p_payload ->> 'location', '')), 160)
      else location end,
    section = case when p_payload ? 'section'
      then left(btrim(coalesce(p_payload ->> 'section', '')), 80)
      else section end,
    subcategory = case when p_payload ? 'subcategory'
      then left(btrim(coalesce(p_payload ->> 'subcategory', '')), 120)
      else subcategory end,
    item_type = case when p_payload ? 'item_type'
      then left(btrim(coalesce(p_payload ->> 'item_type', '')), 120)
      else item_type end,
    gender = case when p_payload ? 'gender'
      then left(btrim(coalesce(p_payload ->> 'gender', '')), 40)
      else gender end,
    primary_color = case when p_payload ? 'primary_color'
      then left(btrim(coalesce(p_payload ->> 'primary_color', '')), 80)
      else primary_color end,
    secondary_colors = case when p_payload ? 'secondary_colors'
      then secondary_colors_value else secondary_colors end,
    material = case when p_payload ? 'material'
      then left(btrim(coalesce(p_payload ->> 'material', '')), 120)
      else material end,
    pattern = case when p_payload ? 'pattern'
      then left(btrim(coalesce(p_payload ->> 'pattern', '')), 120)
      else pattern end,
    season = case when p_payload ? 'season'
      then left(btrim(coalesce(p_payload ->> 'season', '')), 80)
      else season end,
    style = case when p_payload ? 'style'
      then left(btrim(coalesce(p_payload ->> 'style', '')), 120)
      else style end,
    city = case when p_payload ? 'city'
      then left(btrim(coalesce(p_payload ->> 'city', '')), 160) else city end,
    shipping_address_id = case when p_payload ? 'shipping_address_id'
      then shipping_address_value else shipping_address_id end,
    delivery_methods = case when p_payload ? 'delivery_methods'
      then delivery_methods_value else delivery_methods end,
    draft_step = case when p_payload ? 'draft_step'
      then left(btrim(coalesce(p_payload ->> 'draft_step', '')), 40)
      else draft_step end,
    fit = case when p_payload ? 'fit'
      then left(btrim(coalesce(p_payload ->> 'fit', '')), 80) else fit end,
    sleeve_length = case when p_payload ? 'sleeve_length'
      then left(btrim(coalesce(p_payload ->> 'sleeve_length', '')), 80)
      else sleeve_length end,
    closure = case when p_payload ? 'closure'
      then left(btrim(coalesce(p_payload ->> 'closure', '')), 80)
      else closure end,
    normalized_category = case
      when p_payload ? 'item_type'
        or p_payload ? 'subcategory'
        or p_payload ? 'category'
      then public.normalize_product_category(coalesce(
        nullif(btrim(p_payload ->> 'item_type'), ''),
        nullif(btrim(p_payload ->> 'subcategory'), ''),
        nullif(btrim(p_payload ->> 'category'), ''),
        item_type,
        subcategory,
        category
      ))
      else normalized_category end,
    normalized_brand = case when p_payload ? 'brand'
      then public.normalize_product_brand(p_payload ->> 'brand')
      else normalized_brand end,
    audience = case when p_payload ? 'audience'
      then nullif(btrim(coalesce(p_payload ->> 'audience', '')), '')
      else audience end,
    has_defects = case when p_payload ? 'has_defects'
      then (p_payload ->> 'has_defects')::boolean else has_defects end,
    defects_description = case when p_payload ? 'defects_description'
      then left(coalesce(p_payload ->> 'defects_description', ''), 1000)
      else defects_description end,
    defects_reviewed = case when p_payload ? 'defects_reviewed'
      then (p_payload ->> 'defects_reviewed')::boolean
      else defects_reviewed end,
    status = 'draft',
    is_hidden = true,
    published_at = null,
    updated_at = now(),
    last_autosaved_at = now()
  where id = resolved_listing_id
    and seller_id = actor_id;

  if (
    select product.audience
    from public.products product
    where product.id = resolved_listing_id
  ) is not null and (
    select product.audience
    from public.products product
    where product.id = resolved_listing_id
  ) not in ('male', 'female', 'unisex', 'kids') then
    raise exception 'listing_audience_invalid' using errcode = '23514';
  end if;

  return resolved_listing_id;
end;
$$;

revoke all on function public.save_listing_draft(uuid, jsonb)
  from public, anon;
grant execute on function public.save_listing_draft(uuid, jsonb)
  to authenticated;

revoke execute on function public.publish_listing(uuid)
  from public, anon, authenticated;

create or replace function public.prepare_listing_publication(
  p_user_id uuid,
  p_listing_id uuid,
  p_confirmation_version text,
  p_confirmations jsonb,
  p_ip inet,
  p_user_agent text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing public.products%rowtype;
  seller public.seller_accounts%rowtype;
  confirmation_version public.seller_confirmation_versions%rowtype;
  publication_id uuid;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_ip is null or char_length(btrim(coalesce(p_user_agent, '')))
      not between 1 and 1000 then
    raise exception 'publication_evidence_required' using errcode = '23514';
  end if;
  if not public.marketplace_user_is_eligible(p_user_id, true) then
    raise exception 'seller_not_eligible' using errcode = '42501';
  end if;

  select * into seller
  from public.seller_accounts account
  where account.user_id = p_user_id
  for update;

  select * into listing
  from public.products product
  where product.id = p_listing_id
    and product.seller_id = p_user_id
  for update;
  if not found then
    raise exception 'listing_not_found' using errcode = 'P0002';
  end if;
  if listing.status not in ('draft', 'processing', 'ready') then
    raise exception 'listing_not_preparable' using errcode = '23514';
  end if;
  if btrim(coalesce(listing.title, '')) = ''
     or char_length(listing.title) > 80
     or listing.price is null
     or listing.price <= 0
     or char_length(coalesce(listing.description, '')) > 2000
     or btrim(coalesce(listing.brand, '')) = ''
     or btrim(coalesce(listing.size, '')) = ''
     or btrim(coalesce(listing.condition, '')) = ''
     or btrim(coalesce(listing.primary_color, '')) = ''
     or listing.normalized_category is null
     or listing.audience not in ('male', 'female', 'unisex', 'kids')
     or not listing.defects_reviewed
     or (
       listing.has_defects
       and btrim(coalesce(listing.defects_description, '')) = ''
     )
     or cardinality(coalesce(listing.delivery_methods, '{}'::text[])) < 1
     or listing.shipping_address_id is null then
    raise exception 'listing_publication_fields_incomplete'
      using errcode = '23514';
  end if;
  if not exists (
    select 1
    from public.listing_addresses address
    where address.id = listing.shipping_address_id
      and address.user_id = p_user_id
      and btrim(address.city) <> ''
      and btrim(address.address) <> ''
  ) then
    raise exception 'shipping_address_required' using errcode = '23514';
  end if;

  select * into confirmation_version
  from public.seller_confirmation_versions version_row
  where version_row.version = p_confirmation_version
    and version_row.status = 'active'
    and version_row.effective_at <= now();
  if not found then
    raise exception 'seller_confirmation_version_not_active'
      using errcode = '55000';
  end if;
  if not coalesce(public.validate_seller_confirmation_payload(
    confirmation_version.id, p_confirmations
  ), false) then
    raise exception 'all_seller_confirmations_required'
      using errcode = '23514';
  end if;

  update public.listing_publication_attempts
  set status = 'expired',
      aborted_reason = 'superseded',
      updated_at = now()
  where listing_id = p_listing_id
    and status = 'prepared';

  insert into public.listing_publication_attempts (
    listing_id,
    user_id,
    seller_account_id,
    confirmation_version_id,
    confirmations,
    ip,
    user_agent,
    expires_at
  )
  values (
    p_listing_id,
    p_user_id,
    seller.id,
    confirmation_version.id,
    p_confirmations,
    p_ip,
    btrim(p_user_agent),
    now() + interval '20 minutes'
  )
  returning id into publication_id;

  return jsonb_build_object(
    'publication_id', publication_id,
    'draft_prefix',
      p_user_id::text || '/' || p_listing_id::text || '/',
    'required_final_prefix',
      p_user_id::text || '/' || p_listing_id::text || '/',
    'expires_at', now() + interval '20 minutes'
  );
end;
$$;

revoke all on function public.prepare_listing_publication(
  uuid, uuid, text, jsonb, inet, text
) from public, anon, authenticated;
grant execute on function public.prepare_listing_publication(
  uuid, uuid, text, jsonb, inet, text
) to service_role;

create or replace function public.evaluate_seller_risk(
  p_user_id uuid,
  p_listing_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  seller public.seller_accounts%rowtype;
  listing public.products%rowtype;
  active_count integer;
  sales_count integer;
  new_item_count integer;
  upload_burst_count integer;
  duplicate_image_count integer;
  duplicate_product_count integer;
  brand_size_count integer;
  score numeric := 0;
  signals jsonb := '{}'::jsonb;
  risk_action text := 'none';
  severity text := 'low';
  event_type text := 'seller_risk_evaluated';
  event_status text := 'resolved';
  event_resolution text := 'automated_below_review_threshold';
  event_resolved_at timestamptz := now();
begin
  if auth.role() <> 'service_role'
     and current_setting('clothes.risk_evaluation', true) <> 'allowed' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  select * into seller
  from public.seller_accounts account
  where account.user_id = p_user_id
  for update;
  select * into listing
  from public.products product
  where product.id = p_listing_id
    and product.seller_id = p_user_id;
  if seller.id is null or listing.id is null then
    raise exception 'risk_subject_not_found' using errcode = 'P0002';
  end if;

  select count(*)::integer + case
    when listing.status = 'published' then 0 else 1 end
  into active_count
  from public.products product
  where product.seller_id = p_user_id
    and product.status = 'published'
    and not product.is_hidden;

  select count(*)::integer into sales_count
  from public.orders marketplace_order
  where marketplace_order.seller_id = p_user_id
    and marketplace_order.status = 'completed';

  select count(*)::integer + case
    when lower(listing.condition) in (
      'new', 'new_with_tags', 'new_without_tags',
      'новое', 'новое с биркой', 'новое без бирки'
    ) then 1 else 0 end
  into new_item_count
  from public.products product
  where product.seller_id = p_user_id
    and product.created_at > now() - interval '30 days'
    and product.id <> p_listing_id
    and lower(product.condition) in (
      'new', 'new_with_tags', 'new_without_tags',
      'новое', 'новое с биркой', 'новое без бирки'
    );

  select count(*)::integer + 1 into upload_burst_count
  from public.products product
  where product.seller_id = p_user_id
    and product.id <> p_listing_id
    and product.created_at > now() - interval '24 hours';

  select coalesce(max(hash_count), 0)::integer
  into duplicate_image_count
  from (
    select count(distinct fingerprint.listing_id) as hash_count
    from public.listing_image_fingerprints fingerprint
    where fingerprint.seller_account_id = seller.id
    group by fingerprint.content_hash
  ) duplicate_hashes;

  select count(*)::integer into duplicate_product_count
  from public.listing_risk_fingerprints fingerprint
  where fingerprint.seller_account_id = seller.id
    and fingerprint.product_signature = (
      select own_fingerprint.product_signature
      from public.listing_risk_fingerprints own_fingerprint
      where own_fingerprint.listing_id = p_listing_id
    );

  select count(*)::integer + 1 into brand_size_count
  from public.products product
  where product.seller_id = p_user_id
    and product.id <> p_listing_id
    and product.status = 'published'
    and lower(btrim(product.brand)) = lower(btrim(listing.brand))
    and lower(btrim(product.size)) = lower(btrim(listing.size));

  if active_count >= 50 then score := score + 45;
  elsif active_count >= 20 then score := score + 25;
  elsif active_count >= 10 then score := score + 10;
  end if;
  if sales_count >= 100 then score := score + 45;
  elsif sales_count >= 30 then score := score + 25;
  end if;
  if new_item_count >= 10 then score := score + 40;
  elsif new_item_count >= 5 then score := score + 20;
  end if;
  if upload_burst_count >= 25 then score := score + 60;
  elsif upload_burst_count >= 10 then score := score + 30;
  elsif upload_burst_count >= 6 then score := score + 15;
  end if;
  if duplicate_image_count >= 3 then score := score + 40;
  elsif duplicate_image_count >= 2 then score := score + 25;
  end if;
  if duplicate_product_count >= 3 then score := score + 35;
  elsif duplicate_product_count >= 2 then score := score + 20;
  end if;
  if brand_size_count >= 10 then score := score + 35;
  elsif brand_size_count >= 5 then score := score + 20;
  end if;
  score := least(100, score);

  signals := jsonb_build_object(
    'active_listings', active_count,
    'completed_sales', sales_count,
    'new_items_30d', new_item_count,
    'uploads_24h', upload_burst_count,
    'max_exact_image_reuse', duplicate_image_count,
    'identical_product_count', duplicate_product_count,
    'same_brand_size_count', brand_size_count
  );

  if score >= 80 then
    risk_action := 'sales_blocked';
    severity := 'critical';
    event_type := 'professional_seller_block';
    event_status := 'open';
    event_resolution := '';
    event_resolved_at := null;
    update public.seller_accounts
    set risk_score = greatest(risk_score, score),
        status = 'blocked',
        verification_status = 'review_required',
        moderation_status = 'blocked',
        blocked_at = now(),
        status_reason = 'automatic_professional_selling_risk'
    where id = seller.id;
  elsif score >= 40 then
    risk_action := 'verification_hold';
    severity := case when score >= 60 then 'high' else 'medium' end;
    event_type := 'professional_seller_verification_hold';
    event_status := 'open';
    event_resolution := '';
    event_resolved_at := null;
    update public.seller_accounts
    set risk_score = greatest(risk_score, score),
        status = 'pending',
        verification_status = 'review_required',
        moderation_status = 'under_review',
        status_reason = 'automatic_professional_selling_risk'
    where id = seller.id;
  else
    update public.seller_accounts
    set risk_score = greatest(risk_score, score)
    where id = seller.id;
  end if;

  if score >= 40 then
    update public.products
    set is_hidden = true
    where seller_id = p_user_id
      and status = 'published';
  end if;

  insert into public.seller_risk_events (
    seller_account_id,
    listing_id,
    event_type,
    severity,
    score_delta,
    risk_score,
    evidence,
    action,
    status,
    resolved_at,
    resolution,
    dedupe_key
  )
  values (
    seller.id,
    p_listing_id,
    event_type,
    severity,
    score,
    score,
    signals,
    risk_action,
    event_status,
    event_resolved_at,
    event_resolution,
    seller.id::text || ':' || event_type || ':' ||
      p_listing_id::text || ':' || current_date::text
  )
  on conflict (dedupe_key) do update
  set risk_score = excluded.risk_score,
      evidence = excluded.evidence,
      action = excluded.action,
      status = excluded.status,
      resolved_by = null,
      resolved_at = excluded.resolved_at,
      resolution = excluded.resolution;

  return jsonb_build_object(
    'risk_score', score,
    'action', risk_action,
    'signals', signals,
    'can_publish', score < 40
  );
end;
$$;

revoke all on function public.evaluate_seller_risk(uuid, uuid)
  from public, anon, authenticated;
grant execute on function public.evaluate_seller_risk(uuid, uuid)
  to service_role;

create or replace function public.resolve_seller_risk_event(
  p_event_id bigint,
  p_decision text,
  p_reason text,
  p_new_risk_score numeric,
  p_restore_sales boolean,
  p_actor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  risk_event public.seller_risk_events%rowtype;
  seller public.seller_accounts%rowtype;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_decision not in ('resolved', 'dismissed')
     or nullif(btrim(coalesce(p_reason, '')), '') is null
     or p_new_risk_score is null
     or p_new_risk_score not between 0 and 100
     or (p_restore_sales and p_new_risk_score >= 40) then
    raise exception 'risk_resolution_invalid' using errcode = '22023';
  end if;
  if p_actor_id is null or not exists (
    select 1
    from public.admin_roles administrator
    where administrator.user_id = p_actor_id
      and administrator.role in ('moderator', 'ops_admin', 'owner')
  ) then
    raise exception 'moderator_required' using errcode = '42501';
  end if;

  select * into risk_event
  from public.seller_risk_events event_row
  where event_row.id = p_event_id
  for update;
  if not found or risk_event.status not in ('open', 'reviewing') then
    raise exception 'risk_event_not_resolvable' using errcode = 'P0002';
  end if;
  select * into seller
  from public.seller_accounts account
  where account.id = risk_event.seller_account_id
  for update;
  if p_restore_sales and exists (
    select 1
    from public.seller_risk_events unresolved
    where unresolved.seller_account_id = risk_event.seller_account_id
      and unresolved.id <> p_event_id
      and unresolved.status in ('open', 'reviewing')
  ) then
    raise exception 'other_risk_events_require_resolution'
      using errcode = '55000';
  end if;

  update public.seller_risk_events
  set status = p_decision,
      resolved_by = p_actor_id,
      resolved_at = now(),
      resolution = left(btrim(p_reason), 2000)
  where id = p_event_id;

  update public.seller_accounts
  set risk_score = p_new_risk_score,
      status = case when p_restore_sales then 'verified' else status end,
      verification_status = case
        when p_restore_sales then 'verified'
        else verification_status
      end,
      moderation_status = case
        when p_restore_sales then 'clear'
        else moderation_status
      end,
      blocked_at = case when p_restore_sales then null else blocked_at end,
      status_reason = case
        when p_restore_sales then 'risk_review_cleared'
        else status_reason
      end
  where id = seller.id
    and seller.seller_type = 'private_individual';

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
    reason,
    metadata
  )
  select
    seller.id,
    p_actor_id,
    'risk_event_' || p_decision,
    seller.status,
    updated_seller.status,
    seller.verification_status,
    updated_seller.verification_status,
    seller.moderation_status,
    updated_seller.moderation_status,
    btrim(p_reason),
    jsonb_build_object(
      'risk_event_id', p_event_id,
      'previous_risk_score', seller.risk_score,
      'new_risk_score', updated_seller.risk_score,
      'restore_sales', p_restore_sales
    )
  from public.seller_accounts updated_seller
  where updated_seller.id = seller.id;

  return jsonb_build_object(
    'event_id', p_event_id,
    'status', p_decision,
    'seller_account_id', seller.id,
    'risk_score', p_new_risk_score,
    'sales_restored', p_restore_sales
  );
end;
$$;

revoke all on function public.resolve_seller_risk_event(
  bigint, text, text, numeric, boolean, uuid
) from public, anon, authenticated;
grant execute on function public.resolve_seller_risk_event(
  bigint, text, text, numeric, boolean, uuid
) to service_role;

create or replace function public.publish_listing_authoritatively(
  p_user_id uuid,
  p_listing_id uuid,
  p_publication_id uuid,
  p_final_media jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  attempt public.listing_publication_attempts%rowtype;
  listing public.products%rowtype;
  seller public.seller_accounts%rowtype;
  version_row public.seller_confirmation_versions%rowtype;
  media jsonb;
  draft_path text;
  final_path text;
  content_hash text;
  mime_type text;
  perceptual_hash text;
  media_position integer;
  seen_media_positions integer[] := '{}'::integer[];
  final_references text[] := '{}';
  main_reference text;
  product_signature text;
  computed_risk jsonb;
  publish_allowed boolean;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if jsonb_typeof(p_final_media) <> 'array'
     or jsonb_array_length(p_final_media) not between 1 and 10 then
    raise exception 'final_media_invalid' using errcode = '22023';
  end if;

  select * into attempt
  from public.listing_publication_attempts publication
  where publication.id = p_publication_id
    and publication.listing_id = p_listing_id
    and publication.user_id = p_user_id
  for update;
  if not found then
    raise exception 'publication_attempt_not_found' using errcode = 'P0002';
  end if;
  if attempt.status <> 'prepared' or attempt.expires_at <= now() then
    update public.listing_publication_attempts
    set status = case when status = 'prepared' then 'expired' else status end
    where id = p_publication_id;
    raise exception 'publication_attempt_not_active' using errcode = '55000';
  end if;
  if not public.marketplace_user_is_eligible(p_user_id, true) then
    raise exception 'seller_not_eligible' using errcode = '42501';
  end if;

  select * into listing
  from public.products product
  where product.id = p_listing_id
    and product.seller_id = p_user_id
  for update;
  select * into seller
  from public.seller_accounts account
  where account.id = attempt.seller_account_id
    and account.user_id = p_user_id
  for update;
  select * into version_row
  from public.seller_confirmation_versions confirmation_version
  where confirmation_version.id = attempt.confirmation_version_id;
  if listing.id is null or seller.id is null or version_row.id is null then
    raise exception 'publication_subject_not_found' using errcode = 'P0002';
  end if;

  delete from public.listing_image_fingerprints
  where listing_id = p_listing_id;
  delete from public.product_images
  where product_id = p_listing_id;

  for media in select value from jsonb_array_elements(p_final_media)
  loop
    draft_path := btrim(coalesce(media ->> 'draft_path', ''));
    final_path := btrim(coalesce(media ->> 'final_path', ''));
    content_hash := lower(btrim(coalesce(media ->> 'content_hash', '')));
    mime_type := lower(btrim(coalesce(media ->> 'mime_type', '')));
    perceptual_hash := nullif(lower(btrim(coalesce(
      media ->> 'perceptual_hash', ''
    ))), '');
    begin
      media_position := coalesce((media ->> 'position')::integer, 0);
    exception when invalid_text_representation then
      raise exception 'final_media_position_invalid' using errcode = '22023';
    end;

    if draft_path !~ (
         '^' || p_user_id::text || '/' || p_listing_id::text || '/[^/]+$'
       )
       or final_path !~ (
         '^' || p_user_id::text || '/' || p_listing_id::text || '/[^/]+$'
       )
       or content_hash !~ '^[0-9a-f]{64}$'
       or mime_type not in ('image/jpeg', 'image/png', 'image/webp')
       or media_position not between 0 and 9 then
      raise exception 'final_media_contract_invalid' using errcode = '22023';
    end if;
    if media_position = any(seen_media_positions) then
      raise exception 'final_media_position_duplicate'
        using errcode = '22023';
    end if;
    seen_media_positions := array_append(
      seen_media_positions,
      media_position
    );
    if not exists (
      select 1
      from storage.objects stored
      where stored.bucket_id = 'listing-drafts'
        and stored.name = draft_path
        and stored.owner_id = p_user_id::text
    ) then
      raise exception 'draft_media_not_owned' using errcode = '42501';
    end if;
    if not exists (
      select 1
      from storage.objects stored
      where stored.bucket_id = 'product-images'
        and stored.name = final_path
    ) then
      raise exception 'final_media_not_copied' using errcode = '55000';
    end if;

    insert into public.product_images (
      product_id,
      original_url,
      role,
      position,
      is_active,
      storage_bucket,
      storage_path,
      uploader_id,
      content_hash,
      mime_type
    )
    values (
      p_listing_id,
      'storage://product-images/' || final_path,
      case when media_position = 0 then 'main' else 'gallery' end,
      media_position,
      true,
      'product-images',
      final_path,
      p_user_id,
      content_hash,
      mime_type
    );

    insert into public.listing_image_fingerprints (
      listing_id,
      seller_account_id,
      user_id,
      object_path,
      content_hash,
      perceptual_hash
    )
    values (
      p_listing_id,
      seller.id,
      p_user_id,
      final_path,
      content_hash,
      perceptual_hash
    );
    final_references := array_append(
      final_references,
      'storage://product-images/' || final_path
    );
  end loop;

  if exists (
    select 1
    from generate_series(
      0,
      jsonb_array_length(p_final_media) - 1
    ) required_position
    where not (required_position = any(seen_media_positions))
  ) then
    raise exception 'final_media_positions_not_contiguous'
      using errcode = '22023';
  end if;

  select reference into main_reference
  from unnest(final_references) with ordinality media_ref(reference, ordinality)
  order by ordinality
  limit 1;

  product_signature := encode(
    extensions.digest(
      convert_to(
        lower(concat_ws(
          '|',
          btrim(listing.title),
          btrim(listing.brand),
          btrim(listing.size),
          btrim(listing.condition),
          listing.price::text
        )),
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.listing_risk_fingerprints (
    listing_id,
    seller_account_id,
    user_id,
    product_signature,
    evaluated_at
  )
  values (
    p_listing_id,
    seller.id,
    p_user_id,
    product_signature,
    now()
  )
  on conflict (listing_id) do update
  set product_signature = excluded.product_signature,
      evaluated_at = now();

  computed_risk := public.evaluate_seller_risk(p_user_id, p_listing_id);
  publish_allowed := coalesce(
    (computed_risk ->> 'can_publish')::boolean,
    false
  );

  perform set_config('clothes.publish_listing', 'allowed', true);
  update public.products
  set status = case when publish_allowed then 'published' else 'ready' end,
      images = final_references,
      main_image = main_reference,
      image = main_reference,
      original_image = main_reference,
      is_hidden = not publish_allowed,
      published_at = case
        when publish_allowed then coalesce(published_at, now())
        else null
      end,
      moderation_risk = computed_risk,
      enrichment_status = case
        when publish_allowed then 'enrichment_pending'
        else enrichment_status
      end,
      enrichment_completed_at = case
        when publish_allowed then null
        else enrichment_completed_at
      end,
      last_autosaved_at = now()
  where id = p_listing_id;

  insert into public.seller_confirmations (
    publication_id,
    listing_id,
    seller_account_id,
    user_id,
    confirmation_version_id,
    version,
    confirmations,
    confirmed_at,
    ip,
    user_agent
  )
  values (
    attempt.id,
    p_listing_id,
    seller.id,
    p_user_id,
    version_row.id,
    version_row.version,
    attempt.confirmations,
    now(),
    attempt.ip,
    attempt.user_agent
  );

  update public.listing_publication_attempts
  set status = case when publish_allowed then 'published' else 'held' end,
      risk_result = computed_risk,
      finalized_at = now(),
      updated_at = now()
  where id = attempt.id;

  insert into public.listing_moderation (
    product_id,
    status,
    risk_flags,
    priority,
    submitted_at,
    decided_at,
    decision_reason,
    updated_at
  )
  values (
    p_listing_id,
    case when publish_allowed then 'approved' else 'manual_review' end,
    computed_risk,
    coalesce((computed_risk ->> 'risk_score')::integer, 0),
    now(),
    case when publish_allowed then now() else null end,
    case
      when publish_allowed then 'automatic_risk_checks_passed'
      else 'automatic_professional_selling_risk'
    end,
    now()
  )
  on conflict (product_id) do update
  set status = excluded.status,
      risk_flags = excluded.risk_flags,
      priority = excluded.priority,
      submitted_at = excluded.submitted_at,
      decided_at = excluded.decided_at,
      decision_reason = excluded.decision_reason,
      updated_at = now();

  return jsonb_build_object(
    'listing_id', p_listing_id,
    'publication_id', attempt.id,
    'published', publish_allowed,
    'held_for_review', not publish_allowed,
    'status', case when publish_allowed then 'published' else 'ready' end,
    'risk', computed_risk,
    'media', p_final_media
  );
end;
$$;

revoke all on function public.publish_listing_authoritatively(
  uuid, uuid, uuid, jsonb
) from public, anon, authenticated;
grant execute on function public.publish_listing_authoritatively(
  uuid, uuid, uuid, jsonb
) to service_role;

create or replace function public.abort_listing_publication(
  p_user_id uuid,
  p_listing_id uuid,
  p_publication_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  update public.listing_publication_attempts
  set status = 'aborted',
      aborted_reason = left(btrim(coalesce(p_reason, 'aborted')), 1000),
      finalized_at = now(),
      updated_at = now()
  where id = p_publication_id
    and listing_id = p_listing_id
    and user_id = p_user_id
    and status = 'prepared';
  if not found then
    raise exception 'publication_attempt_not_active' using errcode = 'P0002';
  end if;
  return jsonb_build_object(
    'aborted', true,
    'status', 'aborted',
    'publication_id', p_publication_id,
    'listing_id', p_listing_id
  );
end;
$$;

revoke all on function public.abort_listing_publication(
  uuid, uuid, uuid, text
) from public, anon, authenticated;
grant execute on function public.abort_listing_publication(
  uuid, uuid, uuid, text
) to service_role;

create or replace function public.archive_own_listing(p_listing_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
begin
  if actor_id is null then
    raise exception 'authentication_required' using errcode = '42501';
  end if;
  if exists (
    select 1
    from public.orders marketplace_order
    where marketplace_order.product_id = p_listing_id::text
      and marketplace_order.status not in ('completed', 'canceled', 'cancelled')
  ) then
    raise exception 'listing_has_active_order' using errcode = '55000';
  end if;
  update public.products
  set status = 'archived',
      is_hidden = true
  where id = p_listing_id
    and seller_id = actor_id
    and status in ('draft', 'processing', 'ready', 'published');
  if not found then
    raise exception 'listing_not_archivable' using errcode = 'P0002';
  end if;
  return jsonb_build_object('listing_id', p_listing_id, 'status', 'archived');
end;
$$;

revoke all on function public.archive_own_listing(uuid) from public, anon;
grant execute on function public.archive_own_listing(uuid) to authenticated;

alter table public.seller_confirmation_versions enable row level security;
alter table public.listing_publication_attempts enable row level security;
alter table public.seller_confirmations enable row level security;
alter table public.listing_risk_fingerprints enable row level security;
alter table public.listing_image_fingerprints enable row level security;
alter table public.seller_risk_events enable row level security;

drop policy if exists "Active seller confirmation version readable"
  on public.seller_confirmation_versions;
create policy "Active seller confirmation version readable"
  on public.seller_confirmation_versions for select
  using (status = 'active' and effective_at <= now());

drop policy if exists "Sellers read own confirmations"
  on public.seller_confirmations;
create policy "Sellers read own confirmations"
  on public.seller_confirmations for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.listing_publication_attempts,
  public.listing_risk_fingerprints,
  public.listing_image_fingerprints,
  public.seller_risk_events
from anon, authenticated;
revoke all on public.seller_confirmation_versions
  from anon, authenticated;
grant select on public.seller_confirmation_versions to anon, authenticated;
revoke all on public.seller_confirmations from anon, authenticated;
grant select on public.seller_confirmations to authenticated;

-- Remove legacy owner-managed enrichment/image metadata. Final media linkage,
-- hashes and vector state are server-owned.
drop policy if exists "Owners manage product images"
  on public.product_images;
drop policy if exists "Product images are readable"
  on public.product_images;
drop policy if exists "Owners manage product attributes"
  on public.product_attributes;
revoke insert, update, delete on public.product_images
  from anon, authenticated;
revoke insert, update, delete on public.product_attributes
  from anon, authenticated;

create or replace function public.listing_is_public(
  p_listing_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.products product
    join public.seller_accounts seller
      on seller.user_id = product.seller_id
    where product.id = p_listing_id
      and product.status = 'published'
      and not product.is_hidden
      and seller.status = 'verified'
      and seller.verification_status = 'verified'
      and seller.moderation_status = 'clear'
      and seller.seller_type = 'private_individual'
  );
$$;

revoke all on function public.listing_is_public(uuid) from public;
grant execute on function public.listing_is_public(uuid)
  to anon, authenticated, service_role;

drop policy if exists "Safe product image metadata are readable"
  on public.product_images;
create policy "Safe product image metadata are readable"
  on public.product_images for select
  to anon, authenticated
  using (
    public.listing_is_public(product_id)
    or exists (
      select 1
      from public.products product
      where product.id = product_id
        and product.seller_id = (select auth.uid())
    )
  );

grant select (
  id,
  product_id,
  original_url,
  no_background_url,
  role,
  position,
  is_active,
  storage_bucket,
  storage_path,
  mime_type,
  created_at
) on public.product_images to anon, authenticated;

create or replace function public.product_media_is_public(
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
    from public.product_images image
    where image.storage_bucket = 'product-images'
      and image.storage_path = p_storage_path
      and image.is_active
      and public.listing_is_public(image.product_id)
  );
$$;

revoke all on function public.product_media_is_public(text) from public;
grant execute on function public.product_media_is_public(text)
  to anon, authenticated, service_role;

-- Storage contract.
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'listing-drafts',
  'listing-drafts',
  false,
  15728640,
  array[
    'image/jpeg', 'image/png', 'image/webp'
  ]::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

update storage.buckets
set public = false,
    file_size_limit = 15728640,
    allowed_mime_types = array[
      'image/jpeg', 'image/png', 'image/webp'
    ]::text[]
where id = 'product-images';

drop policy if exists "Public product images are readable" on storage.objects;
drop policy if exists "Authenticated users can upload product images"
  on storage.objects;
drop policy if exists "Authenticated users can update product images"
  on storage.objects;
drop policy if exists "Owners can upload listing images" on storage.objects;
drop policy if exists "Owners can update listing images" on storage.objects;
drop policy if exists "Owners can delete listing images" on storage.objects;
drop policy if exists "Owners can upload product media" on storage.objects;
drop policy if exists "Owners can update product media" on storage.objects;
drop policy if exists "Owners can delete product media" on storage.objects;

drop policy if exists "Owners manage listing draft media" on storage.objects;
create policy "Owners manage listing draft media"
  on storage.objects for all to authenticated
  using (
    bucket_id = 'listing-drafts'
    and owner_id = (select auth.uid()::text)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and exists (
      select 1
      from public.products product
      where product.id::text = split_part(name, '/', 2)
        and product.seller_id = (select auth.uid())
        and product.status in ('draft', 'processing', 'ready')
    )
  )
  with check (
    bucket_id = 'listing-drafts'
    and owner_id = (select auth.uid()::text)
    and public.current_marketplace_user_is_eligible(false)
    and name ~ (
      '^' || (select auth.uid()::text) ||
      '/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/[^/]+$'
    )
    and exists (
      select 1
      from public.products product
      where product.id::text = split_part(name, '/', 2)
        and product.seller_id = (select auth.uid())
        and product.status in ('draft', 'processing', 'ready')
    )
  );

drop policy if exists "Published listing media are readable"
  on storage.objects;
create policy "Published listing media are readable"
  on storage.objects for select
  to anon, authenticated
  using (
    bucket_id = 'product-images'
    and public.product_media_is_public(name)
  );

drop policy if exists "Sellers read own final listing media"
  on storage.objects;
create policy "Sellers read own final listing media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'product-images'
    and split_part(name, '/', 1) = (select auth.uid()::text)
    and exists (
      select 1
      from public.products product
      where product.id::text = split_part(name, '/', 2)
        and product.seller_id = (select auth.uid())
    )
  );

-- Legacy product-images objects remain readable only by the JWT-derived owner.
-- No authenticated write policy remains for this final/public bucket.
drop policy if exists "Owners read legacy product media" on storage.objects;
create policy "Owners read legacy product media"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'product-images'
    and owner_id = (select auth.uid()::text)
  );

-- Tighten the existing private chat bucket while it is still client-uploaded.
drop policy if exists "Conversation members can upload own chat media"
  on storage.objects;
create policy "Conversation members can upload own chat media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid()::text)
    and public.current_marketplace_user_is_eligible(false)
    and split_part(name, '/', 1) = 'threads'
    and split_part(name, '/', 3) = (select auth.uid()::text)
    and name ~ '^threads/[^/]+/[0-9a-f-]{36}/[^/]+$'
    and exists (
      select 1
      from public.message_threads thread
      where thread.id = split_part(name, '/', 2)
        and (select auth.uid()) = any(thread.member_ids)
    )
  );

drop policy if exists "Uploaders can delete own chat media"
  on storage.objects;
create policy "Uploaders can delete own chat media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'chat-media'
    and owner_id = (select auth.uid()::text)
    and split_part(name, '/', 1) = 'threads'
    and split_part(name, '/', 3) = (select auth.uid()::text)
  );

revoke all on function public.prevent_seller_confirmation_mutation()
  from public, anon, authenticated;
revoke all on function public.protect_seller_confirmation_version()
  from public, anon, authenticated;
revoke all on function public.protect_product_server_fields()
  from public, anon, authenticated;

notify pgrst, 'reload schema';

commit;
