-- Restore the simple marketplace contract used by the mobile client:
-- active accounts may use social, profile and chat features, while the 18+
-- and seller checks apply only at the authoritative publication boundary.

begin;

-- These blanket triggers made unrelated profile/chat/favorite writes depend
-- on legal-document and age state. Narrow RPCs keep their own checks.
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
  end loop;
end
$$;

-- Repair durable rows left incomplete by older OAuth/bootstrap paths.
insert into public.users (
  id, email, auth_user_id, account_status, created_at, updated_at
)
select
  account.id,
  coalesce(account.email, ''),
  account.id,
  'active',
  coalesce(account.created_at, now()),
  now()
from auth.users account
on conflict (id) do update
set auth_user_id = excluded.auth_user_id,
    email = case
      when public.users.account_status = 'anonymized'
        then public.users.email
      else excluded.email
    end,
    updated_at = now()
where public.users.account_status <> 'anonymized';

insert into public.profiles (id, name, handle, avatar_url, city)
select
  account.id,
  coalesce(
    nullif(btrim(account.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(account.raw_user_meta_data ->> 'name'), ''),
    'Пользователь'
  ),
  '@user_' || left(replace(account.id::text, '-', ''), 16),
  coalesce(nullif(btrim(account.raw_user_meta_data ->> 'avatar_url'), ''), ''),
  ''
from auth.users account
join public.users durable_user on durable_user.id = account.id
where durable_user.account_status = 'active'
on conflict do nothing;

insert into public.profile_private_details (user_id, email)
select durable_user.id, durable_user.email
from public.users durable_user
where durable_user.account_status = 'active'
on conflict (user_id) do nothing;

insert into public.buyer_profiles (user_id)
select durable_user.id
from public.users durable_user
where durable_user.account_status = 'active'
on conflict (user_id) do nothing;

-- All four supported seller types follow the same publication entitlement.
alter table public.seller_accounts
  drop constraint if exists seller_accounts_check;
alter table public.seller_accounts
  add constraint seller_accounts_check check (
    status <> 'verified'
    or (
      verification_status = 'verified'
      and moderation_status = 'clear'
      and risk_score < 40
    )
  );

-- Existing published sellers predate seller_accounts. Restore a neutral
-- verified account unless a real moderation/risk hold already exists.
insert into public.seller_accounts (
  user_id,
  seller_type,
  status,
  verification_status,
  moderation_status,
  verified_at,
  verification_requested_at
)
select distinct
  product.seller_id,
  'private_individual'::public.seller_type,
  'verified'::public.seller_account_status,
  'verified'::public.seller_verification_status,
  'clear'::public.seller_moderation_status,
  now(),
  now()
from public.products product
join public.users durable_user on durable_user.id = product.seller_id
where product.status = 'published'
  and durable_user.account_status = 'active'
on conflict (user_id) do update
set status = case
      when public.seller_accounts.status <> 'blocked'
        and public.seller_accounts.moderation_status in ('clear', 'pending')
        and public.seller_accounts.verification_status in (
          'not_started', 'pending', 'verified'
        )
        and public.seller_accounts.risk_score < 40
        and btrim(public.seller_accounts.status_reason) = ''
      then 'verified'::public.seller_account_status
      else public.seller_accounts.status
    end,
    verification_status = case
      when public.seller_accounts.status <> 'blocked'
        and public.seller_accounts.moderation_status in ('clear', 'pending')
        and public.seller_accounts.verification_status in (
          'not_started', 'pending', 'verified'
        )
        and public.seller_accounts.risk_score < 40
        and btrim(public.seller_accounts.status_reason) = ''
      then 'verified'::public.seller_verification_status
      else public.seller_accounts.verification_status
    end,
    moderation_status = case
      when public.seller_accounts.status <> 'blocked'
        and public.seller_accounts.moderation_status in ('clear', 'pending')
        and public.seller_accounts.verification_status in (
          'not_started', 'pending', 'verified'
        )
        and public.seller_accounts.risk_score < 40
        and btrim(public.seller_accounts.status_reason) = ''
      then 'clear'::public.seller_moderation_status
      else public.seller_accounts.moderation_status
    end,
    verification_requested_at = coalesce(
      public.seller_accounts.verification_requested_at,
      now()
    ),
    verified_at = case
      when public.seller_accounts.status <> 'blocked'
        and public.seller_accounts.moderation_status in ('clear', 'pending')
        and public.seller_accounts.verification_status in (
          'not_started', 'pending', 'verified'
        )
        and public.seller_accounts.risk_score < 40
        and btrim(public.seller_accounts.status_reason) = ''
      then coalesce(public.seller_accounts.verified_at, now())
      else public.seller_accounts.verified_at
    end;

create or replace function public.marketplace_user_is_active(
  p_user_id uuid
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
    where durable_user.id = p_user_id
      and durable_user.auth_user_id = p_user_id
      and durable_user.account_status = 'active'
  );
$$;

revoke all on function public.marketplace_user_is_active(uuid)
  from public, anon, authenticated;

create or replace function public.marketplace_publish_block_reason(
  p_user_id uuid
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  birth_date_value date;
  seller public.seller_accounts%rowtype;
begin
  if not public.marketplace_user_is_active(p_user_id) then
    return 'blocked';
  end if;

  select * into seller
  from public.seller_accounts account
  where account.user_id = p_user_id;

  if seller.id is not null
     and (
       seller.status = 'blocked'
       or seller.moderation_status in ('restricted', 'blocked')
       or seller.risk_score >= 40
     ) then
    return 'blocked';
  end if;

  select profile.birth_date into birth_date_value
  from public.buyer_profiles profile
  where profile.user_id = p_user_id;

  if birth_date_value is null then
    return 'missing_birth_date';
  end if;
  if birth_date_value > (current_date - interval '18 years')::date then
    return 'underage';
  end if;
  if seller.id is null then
    return 'seller_type_required';
  end if;
  if seller.status <> 'verified'
     or seller.verification_status <> 'verified'
     or seller.moderation_status <> 'clear' then
    return 'review_required';
  end if;
  return null;
end;
$$;

revoke all on function public.marketplace_publish_block_reason(uuid)
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
  select case
    when p_require_seller
      then public.marketplace_publish_block_reason(p_user_id) is null
    else public.marketplace_user_is_active(p_user_id)
  end;
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
    and public.marketplace_user_is_eligible(auth.uid(), p_require_seller);
$$;

revoke all on function public.current_marketplace_user_is_eligible(boolean)
  from public, anon;
grant execute on function public.current_marketplace_user_is_eligible(boolean)
  to authenticated;

create or replace function public.update_my_birth_date(
  p_birth_date date
)
returns public.buyer_profiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  result public.buyer_profiles%rowtype;
  is_adult boolean := p_birth_date is not null
    and p_birth_date <= (current_date - interval '18 years')::date;
begin
  if actor_id is null
     or not public.marketplace_user_is_active(actor_id) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;

  insert into public.buyer_profiles (
    user_id,
    birth_date,
    age_verified,
    age_verified_at,
    verification_method,
    verification_evidence
  ) values (
    actor_id,
    p_birth_date,
    is_adult,
    case when is_adult then now() else null end,
    case when p_birth_date is null then null else 'self_declared' end,
    case
      when p_birth_date is null then '{}'::jsonb
      else jsonb_build_object('source', 'profile_editor')
    end
  )
  on conflict (user_id) do update
  set birth_date = excluded.birth_date,
      age_verified = excluded.age_verified,
      age_verified_at = excluded.age_verified_at,
      verification_method = excluded.verification_method,
      verification_evidence = excluded.verification_evidence
  returning * into result;

  insert into public.profile_private_details (user_id, birth_date)
  values (actor_id, p_birth_date)
  on conflict (user_id) do update
  set birth_date = excluded.birth_date;

  return result;
end;
$$;

revoke all on function public.update_my_birth_date(date)
  from public, anon;
grant execute on function public.update_my_birth_date(date)
  to authenticated;

create or replace function public.set_my_seller_type(
  p_seller_type text
)
returns public.seller_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_id uuid := auth.uid();
  resolved_type public.seller_type;
  result public.seller_accounts%rowtype;
begin
  if actor_id is null
     or not public.marketplace_user_is_active(actor_id) then
    raise exception 'active_account_required' using errcode = '42501';
  end if;
  if p_seller_type not in (
    'private_individual',
    'self_employed',
    'individual_entrepreneur',
    'legal_entity'
  ) then
    raise exception 'seller_type_invalid' using errcode = '22023';
  end if;
  resolved_type := p_seller_type::public.seller_type;

  insert into public.seller_accounts (
    user_id,
    seller_type,
    status,
    verification_status,
    moderation_status,
    verification_requested_at,
    verified_at
  ) values (
    actor_id,
    resolved_type,
    'verified',
    'verified',
    'clear',
    now(),
    now()
  )
  on conflict (user_id) do update
  set seller_type = excluded.seller_type,
      status = case
        when public.seller_accounts.status = 'blocked'
          or public.seller_accounts.moderation_status in (
            'under_review', 'restricted', 'blocked'
          )
          or public.seller_accounts.verification_status in (
            'rejected', 'review_required'
          )
          or public.seller_accounts.risk_score >= 40
          then public.seller_accounts.status
        else 'verified'::public.seller_account_status
      end,
      verification_status = case
        when public.seller_accounts.status = 'blocked'
          or public.seller_accounts.moderation_status in (
            'under_review', 'restricted', 'blocked'
          )
          or public.seller_accounts.verification_status in (
            'rejected', 'review_required'
          )
          or public.seller_accounts.risk_score >= 40
          then public.seller_accounts.verification_status
        else 'verified'::public.seller_verification_status
      end,
      moderation_status = case
        when public.seller_accounts.status = 'blocked'
          or public.seller_accounts.moderation_status in (
            'under_review', 'restricted', 'blocked'
          )
          or public.seller_accounts.verification_status in (
            'rejected', 'review_required'
          )
          or public.seller_accounts.risk_score >= 40
          then public.seller_accounts.moderation_status
        else 'clear'::public.seller_moderation_status
      end,
      verification_requested_at = now(),
      verified_at = case
        when public.seller_accounts.status = 'blocked'
          or public.seller_accounts.moderation_status in (
            'under_review', 'restricted', 'blocked'
          )
          or public.seller_accounts.verification_status in (
            'rejected', 'review_required'
          )
          or public.seller_accounts.risk_score >= 40
          then public.seller_accounts.verified_at
        else coalesce(public.seller_accounts.verified_at, now())
      end,
      blocked_at = case
        when public.seller_accounts.status = 'blocked'
          then public.seller_accounts.blocked_at
        else null
      end
  returning * into result;

  return result;
end;
$$;

revoke all on function public.set_my_seller_type(text)
  from public, anon;
grant execute on function public.set_my_seller_type(text)
  to authenticated;

create or replace function public.request_private_seller_activation()
returns public.seller_accounts
language plpgsql
security definer
set search_path = ''
as $$
declare
  result public.seller_accounts%rowtype;
begin
  select * into result
  from public.set_my_seller_type('private_individual');
  return result;
end;
$$;

revoke all on function public.request_private_seller_activation()
  from public, anon;
grant execute on function public.request_private_seller_activation()
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
  durable_user public.users%rowtype;
  buyer public.buyer_profiles%rowtype;
  seller public.seller_accounts%rowtype;
  account_active boolean;
  age_verified_value boolean;
  block_reason text;
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

  account_active := public.marketplace_user_is_active(actor_id);
  age_verified_value := buyer.birth_date is not null
    and buyer.birth_date <= (current_date - interval '18 years')::date;
  block_reason := public.marketplace_publish_block_reason(actor_id);

  return jsonb_build_object(
    'user_id', actor_id,
    'account_status', coalesce(durable_user.account_status, 'missing'),
    'account_active', account_active,
    'birth_date', buyer.birth_date,
    'age_verified', age_verified_value,
    'verification_method', coalesce(buyer.verification_method, ''),
    'legal_onboarding_complete', account_active,
    'buyer_enabled', account_active,
    'missing_required_documents', '[]'::jsonb,
    'seller_account_id', seller.id,
    'seller_type', seller.seller_type,
    'seller_status', seller.status,
    'seller_verification_status', seller.verification_status,
    'seller_moderation_status', seller.moderation_status,
    'seller_risk_score', coalesce(seller.risk_score, 0),
    'seller_can_publish', block_reason is null,
    'can_publish', block_reason is null,
    'publish_block_reason', block_reason
  );
end;
$$;

revoke all on function public.get_user_entitlements()
  from public, anon;
grant execute on function public.get_user_entitlements()
  to authenticated;

-- save_listing_draft is redefined below with only the obsolete mandatory
-- seller-account gate removed. Its payload validation remains unchanged.
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

-- A public listing is governed by account/moderation state. Seller type and a
-- missing legacy seller row no longer erase an otherwise published listing.
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
    join public.users durable_user
      on durable_user.id = product.seller_id
    left join public.seller_accounts seller
      on seller.user_id = product.seller_id
    where product.id = p_listing_id
      and product.status = 'published'
      and not product.is_hidden
      and durable_user.account_status = 'active'
      and durable_user.auth_user_id = durable_user.id
      and coalesce(seller.status <> 'blocked', true)
      and coalesce(
        seller.moderation_status not in ('restricted', 'blocked'),
        true
      )
      and coalesce(seller.risk_score < 40, true)
  );
$$;

revoke all on function public.listing_is_public(uuid) from public;
grant execute on function public.listing_is_public(uuid)
  to anon, authenticated, service_role;

create or replace function public.hide_ineligible_seller_listings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'blocked'
     or new.moderation_status in ('restricted', 'blocked')
     or new.risk_score >= 40 then
    update public.products product
    set is_hidden = true
    where product.seller_id = new.user_id
      and product.status = 'published'
      and not coalesce(product.is_hidden, false);
  end if;
  return new;
end;
$$;

drop trigger if exists hide_ineligible_seller_listings_after_change
  on public.seller_accounts;
create trigger hide_ineligible_seller_listings_after_change
after insert or update of status, moderation_status, risk_score
on public.seller_accounts
for each row execute function public.hide_ineligible_seller_listings();

revoke all on function public.hide_ineligible_seller_listings()
  from public, anon, authenticated;

-- Keep denormalized listing author labels in sync without granting clients a
-- table-wide products UPDATE privilege.
create or replace function public.sync_profile_to_products()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.products product
  set seller_name = coalesce(nullif(btrim(new.name), ''), 'Продавец'),
      seller_handle = coalesce(nullif(btrim(new.handle), ''), '@seller')
  where product.seller_id = new.id
    and (
      product.seller_name is distinct from
        coalesce(nullif(btrim(new.name), ''), 'Продавец')
      or product.seller_handle is distinct from
        coalesce(nullif(btrim(new.handle), ''), '@seller')
    );
  return new;
end;
$$;

drop trigger if exists sync_profile_to_products_after_update
  on public.profiles;
create trigger sync_profile_to_products_after_update
after update of name, handle on public.profiles
for each row execute function public.sync_profile_to_products();

revoke all on function public.sync_profile_to_products()
  from public, anon, authenticated;

update public.products product
set seller_name = coalesce(nullif(btrim(profile.name), ''), 'Продавец'),
    seller_handle = coalesce(nullif(btrim(profile.handle), ''), '@seller')
from public.profiles profile
where profile.id = product.seller_id
  and (
    product.seller_name is distinct from
      coalesce(nullif(btrim(profile.name), ''), 'Продавец')
    or product.seller_handle is distinct from
      coalesce(nullif(btrim(profile.handle), ''), '@seller')
  );

-- Link every legacy product-images object to the storage locator used by the
-- current read policy. The source URLs remain untouched for compatibility.
with raw_references as (
  select
    product.id as product_id,
    product.seller_id,
    btrim(media.reference) as reference,
    media.ordinality::integer - 1 as position
  from public.products product
  cross join lateral unnest(coalesce(product.images, '{}'::text[]))
    with ordinality as media(reference, ordinality)
  where btrim(media.reference) <> ''
), resolved_references as (
  select
    raw_references.*,
    case
      when reference like 'storage://product-images/%' then
        substring(reference from length('storage://product-images/') + 1)
      when reference ~
        '/storage/v1/object/(public|sign|authenticated)/product-images/' then
        split_part(
          regexp_replace(
            reference,
            '^.*/storage/v1/object/(public|sign|authenticated)/product-images/',
            ''
          ),
          '?',
          1
        )
      else null
    end as storage_path
  from raw_references
)
update public.product_images image
set storage_bucket = 'product-images',
    storage_path = reference.storage_path,
    uploader_id = reference.seller_id,
    mime_type = case
      when lower(reference.storage_path) ~ '\.(jpe?g)$' then 'image/jpeg'
      when lower(reference.storage_path) ~ '\.png$' then 'image/png'
      when lower(reference.storage_path) ~ '\.webp$' then 'image/webp'
      else image.mime_type
    end
from resolved_references reference
where reference.storage_path is not null
  and image.product_id = reference.product_id
  and image.original_url = reference.reference;

with raw_references as (
  select
    product.id as product_id,
    product.seller_id,
    btrim(media.reference) as reference,
    media.ordinality::integer - 1 as position
  from public.products product
  cross join lateral unnest(coalesce(product.images, '{}'::text[]))
    with ordinality as media(reference, ordinality)
  where btrim(media.reference) <> ''
), resolved_references as (
  select
    raw_references.*,
    case
      when reference like 'storage://product-images/%' then
        substring(reference from length('storage://product-images/') + 1)
      when reference ~
        '/storage/v1/object/(public|sign|authenticated)/product-images/' then
        split_part(
          regexp_replace(
            reference,
            '^.*/storage/v1/object/(public|sign|authenticated)/product-images/',
            ''
          ),
          '?',
          1
        )
      else null
    end as storage_path
  from raw_references
)
insert into public.product_images (
  product_id,
  original_url,
  role,
  position,
  is_active,
  storage_bucket,
  storage_path,
  uploader_id,
  mime_type
)
select
  reference.product_id,
  reference.reference,
  case when reference.position = 0 then 'main' else 'gallery' end,
  reference.position,
  true,
  'product-images',
  reference.storage_path,
  reference.seller_id,
  case
    when lower(reference.storage_path) ~ '\.(jpe?g)$' then 'image/jpeg'
    when lower(reference.storage_path) ~ '\.png$' then 'image/png'
    when lower(reference.storage_path) ~ '\.webp$' then 'image/webp'
    else null
  end
from resolved_references reference
where reference.storage_path is not null
on conflict do nothing;

-- Restore every published listing owned by an active, non-restricted user.
-- The custom setting lets this repair cross the authoritative publish guard.
select set_config('clothes.publish_listing', 'allowed', true);
update public.products product
set is_hidden = false
where product.status = 'published'
  and exists (
    select 1
    from public.users durable_user
    where durable_user.id = product.seller_id
      and durable_user.account_status = 'active'
      and durable_user.auth_user_id = durable_user.id
  )
  and not exists (
    select 1
    from public.seller_accounts seller
    where seller.user_id = product.seller_id
      and (
        seller.status = 'blocked'
        or seller.moderation_status in ('restricted', 'blocked')
        or seller.risk_score >= 40
      )
  );

-- Explicit column grants match the mobile upserts. RLS continues to restrict
-- both tables to the authenticated owner.
revoke insert, update on public.profiles from authenticated;
grant insert (id, name, handle, avatar_url, city, last_seen_at)
  on public.profiles to authenticated;
grant update (name, handle, avatar_url, city, last_seen_at)
  on public.profiles to authenticated;

revoke insert, update on public.profile_private_details from authenticated;
grant insert (
  user_id, first_name, last_name, middle_name, gender, phone, email
) on public.profile_private_details to authenticated;
grant update (
  first_name, last_name, middle_name, gender, phone, email
) on public.profile_private_details to authenticated;

notify pgrst, 'reload schema';

commit;
