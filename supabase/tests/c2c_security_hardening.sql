begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(25);

-- Published test documents are transaction-local fixtures. Production
-- migrations deliberately seed no legal text/version.
insert into public.legal_document_versions (
  document_id,
  version,
  status,
  title,
  content_url,
  content_hash,
  effective_at,
  published_at,
  is_active
)
select
  document.id,
  'security-test-v1',
  'published',
  document.title,
  'https://legal.invalid/' || document.code || '/security-test-v1',
  encode(
    extensions.digest(
      convert_to(document.code || ':security-test-v1', 'UTF8'),
      'sha256'
    ),
    'hex'
  ),
  now() - interval '1 minute',
  now() - interval '1 minute',
  true
from public.legal_documents document;

insert into auth.users (
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'seller-a@security.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'seller-b@security.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'minor@security.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000004',
    'authenticated',
    'authenticated',
    'delete@security.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000005',
    'authenticated',
    'authenticated',
    'buyer@security.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

insert into public.profiles (id, name, handle)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'Seller A',
    '@seller_a'
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'Seller B',
    '@seller_b'
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    'Minor',
    '@minor'
  ),
  (
    '10000000-0000-0000-0000-000000000004',
    'Delete Me',
    '@delete_me'
  ),
  (
    '10000000-0000-0000-0000-000000000005',
    'Buyer',
    '@buyer'
  )
on conflict (id) do nothing;

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.throws_ok(
  $test$
    select public.complete_legal_onboarding(
      '10000000-0000-0000-0000-000000000003'::uuid,
      (current_date - interval '17 years')::date,
      '{
        "terms":"security-test-v1",
        "privacy_policy":"security-test-v1",
        "personal_data_consent":"security-test-v1"
      }'::jsonb,
      null,
      '127.0.0.1'::inet,
      'pgTAP security test'
    )
  $test$,
  '23514',
  'age_18_required',
  'a user under 18 cannot complete server age verification'
);

select public.complete_legal_onboarding(
  fixture.user_id,
  (current_date - interval '25 years')::date,
  '{
    "terms":"security-test-v1",
    "privacy_policy":"security-test-v1",
    "personal_data_consent":"security-test-v1"
  }'::jsonb,
  null,
  '127.0.0.1'::inet,
  'pgTAP security test'
)
from (
  values
    ('10000000-0000-0000-0000-000000000001'::uuid),
    ('10000000-0000-0000-0000-000000000002'::uuid),
    ('10000000-0000-0000-0000-000000000004'::uuid),
    ('10000000-0000-0000-0000-000000000005'::uuid)
) fixture(user_id);

select extensions.is(
  (
    select count(*)::integer
    from public.user_consents consent
    where consent.user_id = '10000000-0000-0000-0000-000000000004'
      and consent.document_type in (
        'terms',
        'privacy_policy',
        'personal_data_consent'
      )
      and consent.withdrawn_at is null
  ),
  3,
  'three independent mandatory consents are retained'
);

select extensions.is(
  (
    select count(*)::integer
    from public.user_consents consent
    where consent.user_id = '10000000-0000-0000-0000-000000000004'
      and consent.document_type = 'marketing_consent'
  ),
  0,
  'marketing consent is not inferred from mandatory onboarding'
);

insert into public.seller_accounts (
  user_id,
  seller_type,
  status,
  verification_status,
  moderation_status,
  risk_score
)
values
  (
    '10000000-0000-0000-0000-000000000001',
    'private_individual',
    'verified',
    'verified',
    'clear',
    0
  ),
  (
    '10000000-0000-0000-0000-000000000002',
    'private_individual',
    'blocked',
    'review_required',
    'blocked',
    100
  ),
  (
    '10000000-0000-0000-0000-000000000003',
    'private_individual',
    'verified',
    'verified',
    'clear',
    0
  );

select extensions.is(
  public.marketplace_user_is_eligible(
    '10000000-0000-0000-0000-000000000003',
    true
  ),
  false,
  'an underage account cannot acquire seller entitlement'
);

insert into public.listing_addresses (
  id,
  user_id,
  label,
  city,
  address
)
values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Test',
    'Moscow',
    'Private address A'
  ),
  (
    '20000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000002',
    'Test',
    'Moscow',
    'Private address B'
  );

insert into public.products (
  id,
  seller_id,
  seller_name,
  seller_handle,
  title,
  description,
  price,
  category,
  brand,
  size,
  condition,
  primary_color,
  normalized_category,
  audience,
  defects_reviewed,
  shipping_address_id,
  delivery_methods,
  status,
  is_hidden
)
values
  (
    '30000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'Seller A',
    '@seller_a',
    'Test listing A',
    'Description',
    1000,
    'clothes',
    'Brand',
    'M',
    'good',
    'black',
    'clothing',
    'unisex',
    true,
    '20000000-0000-0000-0000-000000000001',
    array['cdek']::text[],
    'draft',
    true
  ),
  (
    '30000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-000000000002',
    'Seller B',
    '@seller_b',
    'Test listing B',
    'Description',
    1000,
    'clothes',
    'Brand',
    'M',
    'good',
    'black',
    'clothing',
    'unisex',
    true,
    '20000000-0000-0000-0000-000000000002',
    array['cdek']::text[],
    'draft',
    true
  );

select extensions.throws_ok(
  $test$
    select public.prepare_listing_publication(
      '10000000-0000-0000-0000-000000000001'::uuid,
      '30000000-0000-0000-0000-000000000001'::uuid,
      'private-individual-v1',
      '{"owns_item":true}'::jsonb,
      '127.0.0.1'::inet,
      'pgTAP security test'
    )
  $test$,
  '23514',
  'all_seller_confirmations_required',
  'publication fails without the exact seven declarations'
);

select extensions.throws_ok(
  $test$
    select public.prepare_listing_publication(
      '10000000-0000-0000-0000-000000000002'::uuid,
      '30000000-0000-0000-0000-000000000002'::uuid,
      'private-individual-v1',
      '{
        "owns_item":true,
        "has_right_to_sell":true,
        "has_item_in_possession":true,
        "owns_photos":true,
        "description_is_accurate":true,
        "item_is_authentic":true,
        "item_is_not_prohibited":true
      }'::jsonb,
      '127.0.0.1'::inet,
      'pgTAP security test'
    )
  $test$,
  '42501',
  'seller_not_eligible',
  'a blocked seller cannot prepare publication'
);

update public.products
set status = 'published', is_hidden = false
where id = '30000000-0000-0000-0000-000000000001';
update public.seller_accounts
set status = 'pending', verification_status = 'review_required'
where user_id = '10000000-0000-0000-0000-000000000001';

select extensions.is(
  (
    select product.is_hidden
    from public.products product
    where product.id = '30000000-0000-0000-0000-000000000001'
  ),
  true,
  'seller eligibility degradation atomically hides published listings'
);

update public.seller_accounts
set status = 'verified', verification_status = 'verified'
where user_id = '10000000-0000-0000-0000-000000000001';
update public.products
set status = 'draft', is_hidden = true
where id = '30000000-0000-0000-0000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.throws_ok(
  $test$
    update public.profiles
    set rating = 5
    where id = '10000000-0000-0000-0000-000000000001'
  $test$,
  '42501',
  'permission denied for table profiles',
  'a user cannot mutate own server-owned rating'
);

select extensions.throws_ok(
  $test$
    update public.products
    set title = 'forged'
    where id = '30000000-0000-0000-0000-000000000002'
  $test$,
  '42501',
  'permission denied for table products',
  'a user cannot update another seller listing'
);

reset role;

insert into storage.objects (
  id,
  bucket_id,
  name,
  owner_id,
  metadata
)
values (
  '40000000-0000-0000-0000-000000000001',
  'product-images',
  '10000000-0000-0000-0000-000000000002/' ||
    '30000000-0000-0000-0000-000000000002/foreign.jpg',
  '10000000-0000-0000-0000-000000000002',
  '{"mimetype":"image/jpeg"}'::jsonb
);

create or replace function pg_temp.try_foreign_storage_update()
returns integer
language plpgsql
set search_path = ''
as $$
declare
  affected integer := 0;
begin
  update storage.objects
  set name = name || '.forged'
  where id = '40000000-0000-0000-0000-000000000001';
  get diagnostics affected = row_count;
  return affected;
exception when insufficient_privilege then
  return 0;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.is(
  pg_temp.try_foreign_storage_update(),
  0,
  'a user cannot update another user final media'
);

reset role;

insert into public.orders (
  id,
  product_id,
  product_title,
  product_image,
  product_price,
  product_price_value,
  seller_id,
  buyer_id,
  status,
  subtotal_minor,
  delivery_minor,
  total_minor
)
values (
  'order_security_test',
  '30000000-0000-0000-0000-000000000001',
  'Test listing A',
  '',
  '1000',
  1000,
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000005',
  'created',
  100000,
  0,
  100000
);

insert into public.seller_payouts (
  order_id,
  seller_account_id,
  amount_minor,
  status
)
select
  'order_security_test',
  seller.id,
  100000,
  'pending'
from public.seller_accounts seller
where seller.user_id = '10000000-0000-0000-0000-000000000001';

select extensions.throws_ok(
  $test$
    update public.seller_payouts
    set status = 'eligible',
        release_not_before = now(),
        eligible_at = now()
    where order_id = 'order_security_test'
  $test$,
  '42501',
  'seller_payout_release_not_allowed',
  'payout cannot become eligible before completion and the dispute hold'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000005',
  true
);

select extensions.throws_ok(
  $test$
    update public.orders
    set status = 'completed'
    where id = 'order_security_test'
  $test$,
  '42501',
  'permission denied for table orders',
  'a mobile client cannot forge order status'
);

reset role;

select set_config('request.jwt.claim.role', 'service_role', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

update public.products
set status = 'published',
    is_hidden = false,
    published_at = now() - interval '10 days',
    images = array['storage://product-images/existing.jpg'],
    main_image = 'storage://product-images/existing.jpg'
where id = '30000000-0000-0000-0000-000000000001';

select extensions.throws_ok(
  $test$
    select public.submit_listing_edit_authoritatively(
      '10000000-0000-0000-0000-000000000001'::uuid,
      '30000000-0000-0000-0000-000000000001'::uuid,
      '50000000-0000-0000-0000-000000000001'::uuid,
      '{"title":"Edited while ordered"}'::jsonb,
      'private-individual-v1',
      '{
        "owns_item":true,
        "has_right_to_sell":true,
        "has_item_in_possession":true,
        "owns_photos":true,
        "description_is_accurate":true,
        "item_is_authentic":true,
        "item_is_not_prohibited":true
      }'::jsonb,
      null,
      '127.0.0.1'::inet,
      'pgTAP listing edit test'
    )
  $test$,
  '55000',
  'listing_has_order_history',
  'a listing with non-cancelled order history cannot be edited'
);

update public.orders set status = 'cancelled'
where id = 'order_security_test';

select extensions.is(
  (
    public.submit_listing_edit_authoritatively(
      '10000000-0000-0000-0000-000000000001'::uuid,
      '30000000-0000-0000-0000-000000000001'::uuid,
      '50000000-0000-0000-0000-000000000002'::uuid,
      '{"title":"Edited safely","price":1250}'::jsonb,
      'private-individual-v1',
      '{
        "owns_item":true,
        "has_right_to_sell":true,
        "has_item_in_possession":true,
        "owns_photos":true,
        "description_is_accurate":true,
        "item_is_authentic":true,
        "item_is_not_prohibited":true
      }'::jsonb,
      null,
      '127.0.0.1'::inet,
      'pgTAP listing edit test'
    ) ->> 'edited'
  )::boolean,
  true,
  'an eligible owner can submit an allowlisted material edit'
);

select extensions.ok(
  (
    select product.status = 'pending_moderation' and product.is_hidden
    from public.products product
    where product.id = '30000000-0000-0000-0000-000000000001'
  ),
  'a material edit atomically hides the listing for moderation'
);

select extensions.ok(
  (
    select revision.changed_fields @> array['price', 'title']::text[]
      and revision.before_snapshot ->> 'title' = 'Test listing A'
      and revision.after_snapshot ->> 'title' = 'Edited safely'
    from public.listing_edit_revisions revision
    where revision.request_id =
      '50000000-0000-0000-0000-000000000002'::uuid
  ),
  'the immutable revision contains before/after content and changed fields'
);

select extensions.throws_ok(
  $test$
    update public.listing_edit_revisions
    set after_snapshot = '{}'::jsonb
    where request_id = '50000000-0000-0000-0000-000000000002'::uuid
  $test$,
  '42501',
  'listing_edit_audit_is_append_only',
  'listing revision evidence cannot be rewritten'
);

insert into public.admin_roles (user_id, role, granted_by)
values (
  '10000000-0000-0000-0000-000000000005',
  'moderator',
  '10000000-0000-0000-0000-000000000001'
);

select public.moderate_listing_edit_authoritatively(
  '10000000-0000-0000-0000-000000000005'::uuid,
  (
    select revision.id from public.listing_edit_revisions revision
    where revision.request_id =
      '50000000-0000-0000-0000-000000000002'::uuid
  ),
  'approve',
  'reviewed and approved',
  '127.0.0.1'::inet,
  'pgTAP listing moderation test'
);

select extensions.ok(
  (
    select product.status = 'published'
      and not product.is_hidden
      and product.published_at = product.first_published_at
      and product.published_at < now() - interval '9 days'
    from public.products product
    where product.id = '30000000-0000-0000-0000-000000000001'
  ),
  'moderator approval rechecks risk and republishes without free bumping'
);

select extensions.is(
  (
    with statuses(status) as (
      values
        ('created'),
        ('paid'),
        ('seller_confirmed'),
        ('shipped'),
        ('received'),
        ('inspection'),
        ('completed'),
        ('dispute'),
        ('cancelled')
    )
    select count(*)::integer
    from statuses source
    cross join statuses target
    where public.order_transition_is_allowed(source.status, target.status)
  ),
  17,
  'the state machine contains exactly the reviewed transition edges'
);

select extensions.is(
  public.order_transition_is_allowed('created', 'completed'),
  false,
  'created cannot jump directly to completed'
);

select extensions.is(
  public.order_transition_is_allowed('inspection', 'completed'),
  true,
  'inspection can complete through the reviewed edge'
);

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000004',
  true
);

select extensions.is(
  (
    public.request_account_deletion(
      'delete-test-000000000004',
      'pgTAP security test'
    )
      ->> 'accepted'
  )::boolean,
  true,
  'deletion request is accepted when no legal hold exists'
);

reset role;
select set_config('request.jwt.claim.role', 'service_role', true);
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.is(
  (
    public.anonymize_user_account(
      (
        select request_row.id
        from public.account_deletion_requests request_row
        where request_row.user_id =
          '10000000-0000-0000-0000-000000000004'
          and request_row.idempotency_key = 'delete-test-000000000004'
      ),
      '10000000-0000-0000-0000-000000000004',
      'edge:pg-tap'
    ) ->> 'anonymized'
  )::boolean,
  true,
  'eligible deletion is anonymized by the server workflow'
);

select extensions.is(
  (
    select durable_user.account_status
    from public.users durable_user
    where durable_user.id = '10000000-0000-0000-0000-000000000004'
  ),
  'anonymized',
  'durable financial identity remains with anonymized status'
);

select extensions.is(
  (
    select buyer.birth_date is null and not buyer.age_verified
    from public.buyer_profiles buyer
    where buyer.user_id = '10000000-0000-0000-0000-000000000004'
  ),
  true,
  'deletion removes age PII while retaining the durable party record'
);

select * from extensions.finish();

rollback;
