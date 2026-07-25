-- Owner listing edits are commands, never table-wide client updates.
-- Any material change withdraws the listing from the catalogue and creates an
-- append-only revision which must be decided by a moderator/server workflow.

begin;

alter table public.products
  drop constraint if exists products_status_check;
alter table public.products
  add constraint products_status_check
  check (status in (
    'draft', 'processing', 'ready', 'pending_moderation',
    'published', 'archived', 'sold'
  ));

alter table public.products
  add column if not exists content_revision integer not null default 0
    check (content_revision >= 0),
  add column if not exists first_published_at timestamptz;

update public.products
set first_published_at = coalesce(published_at, created_at)
where status in ('published', 'sold')
  and first_published_at is null;

create or replace function public.preserve_product_first_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.first_published_at is not null then
    new.first_published_at := old.first_published_at;
  elsif new.status = 'published' then
    new.first_published_at := coalesce(
      old.published_at, new.published_at, old.created_at, now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists preserve_product_first_publication_before_update
  on public.products;
create trigger preserve_product_first_publication_before_update
before update on public.products
for each row execute function public.preserve_product_first_publication();

create table if not exists public.listing_edit_revisions (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.products(id) on delete restrict,
  revision_number integer not null check (revision_number > 0),
  editor_id uuid references public.users(id) on delete restrict,
  editor_role text not null default 'owner'
    check (editor_role in ('owner', 'moderator', 'system')),
  request_id uuid not null unique,
  request_hash text not null check (request_hash ~ '^[0-9a-f]{64}$'),
  before_snapshot jsonb not null,
  after_snapshot jsonb not null,
  changed_fields text[] not null check (cardinality(changed_fields) > 0),
  confirmation_version_id uuid not null
    references public.seller_confirmation_versions(id) on delete restrict,
  confirmation_version text not null,
  confirmations jsonb not null check (jsonb_typeof(confirmations) = 'object'),
  ip inet not null,
  user_agent text not null check (char_length(user_agent) between 1 and 1000),
  created_at timestamptz not null default now(),
  unique (listing_id, revision_number),
  check (jsonb_typeof(before_snapshot) = 'object'),
  check (jsonb_typeof(after_snapshot) = 'object')
);

create index if not exists listing_edit_revisions_listing_created_idx
  on public.listing_edit_revisions (listing_id, created_at desc);

create table if not exists public.listing_edit_decisions (
  id bigint generated always as identity primary key,
  revision_id uuid not null
    references public.listing_edit_revisions(id) on delete restrict,
  decision text not null check (decision in (
    'approved', 'rejected', 'needs_changes', 'superseded', 'risk_hold'
  )),
  moderator_id uuid references public.users(id) on delete restrict,
  reason text not null default '',
  risk_result jsonb not null default '{}'::jsonb,
  ip inet,
  user_agent text not null default '',
  created_at timestamptz not null default now(),
  check (jsonb_typeof(risk_result) = 'object')
);

create index if not exists listing_edit_decisions_revision_created_idx
  on public.listing_edit_decisions (revision_id, created_at desc);

create or replace function public.prevent_listing_edit_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'listing_edit_audit_is_append_only' using errcode = '42501';
end;
$$;

drop trigger if exists listing_edit_revisions_append_only
  on public.listing_edit_revisions;
create trigger listing_edit_revisions_append_only
before update or delete on public.listing_edit_revisions
for each row execute function public.prevent_listing_edit_audit_mutation();

drop trigger if exists listing_edit_decisions_append_only
  on public.listing_edit_decisions;
create trigger listing_edit_decisions_append_only
before update or delete on public.listing_edit_decisions
for each row execute function public.prevent_listing_edit_audit_mutation();

create or replace function public.listing_editable_snapshot(
  p_listing public.products
)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select jsonb_build_object(
    'title', p_listing.title,
    'description', coalesce(p_listing.description, ''),
    'price', p_listing.price,
    'category', p_listing.category,
    'brand', p_listing.brand,
    'size', p_listing.size,
    'color', p_listing.color,
    'condition', p_listing.condition,
    'location', p_listing.location,
    'section', p_listing.section,
    'subcategory', p_listing.subcategory,
    'item_type', p_listing.item_type,
    'gender', p_listing.gender,
    'primary_color', p_listing.primary_color,
    'secondary_colors', coalesce(p_listing.secondary_colors, '{}'::text[]),
    'material', p_listing.material,
    'pattern', p_listing.pattern,
    'season', p_listing.season,
    'style', p_listing.style,
    'fit', p_listing.fit,
    'sleeve_length', p_listing.sleeve_length,
    'closure', p_listing.closure,
    'audience', p_listing.audience,
    'has_defects', p_listing.has_defects,
    'defects_description', p_listing.defects_description,
    'defects_reviewed', p_listing.defects_reviewed,
    'city', p_listing.city,
    'shipping_address_id', p_listing.shipping_address_id,
    'delivery_methods', coalesce(p_listing.delivery_methods, '{}'::text[]),
    'images', coalesce(p_listing.images, '{}'::text[]),
    'main_image', p_listing.main_image
  );
$$;

create or replace function public.submit_listing_edit_authoritatively(
  p_user_id uuid,
  p_listing_id uuid,
  p_request_id uuid,
  p_payload jsonb,
  p_confirmation_version text,
  p_confirmations jsonb,
  p_final_media jsonb,
  p_ip inet,
  p_user_agent text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  listing_before public.products%rowtype;
  listing_after public.products%rowtype;
  seller public.seller_accounts%rowtype;
  version_row public.seller_confirmation_versions%rowtype;
  existing_revision public.listing_edit_revisions%rowtype;
  revision_id uuid;
  next_revision integer;
  request_hash text;
  unknown_keys text[];
  changed_fields text[];
  before_snapshot jsonb;
  after_snapshot jsonb;
  secondary_colors_value text[];
  delivery_methods_value text[];
  shipping_address_value uuid;
  price_value numeric;
  replace_media boolean := p_final_media is not null
    and p_final_media <> 'null'::jsonb;
  media jsonb;
  draft_path text;
  final_path text;
  content_hash text;
  mime_type text;
  perceptual_hash text;
  media_position integer;
  seen_media_positions integer[] := '{}'::integer[];
  final_references text[] := '{}'::text[];
  main_reference text;
  product_signature text;
  current_status text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_user_id is null or p_listing_id is null or p_request_id is null then
    raise exception 'listing_edit_identity_required' using errcode = '22023';
  end if;
  if p_ip is null or char_length(btrim(coalesce(p_user_agent, '')))
      not between 1 and 1000 then
    raise exception 'listing_edit_evidence_required' using errcode = '23514';
  end if;
  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'listing_payload_must_be_object' using errcode = '22023';
  end if;

  request_hash := encode(
    extensions.digest(
      convert_to(
        jsonb_build_object(
          'listing_id', p_listing_id,
          'payload', coalesce(p_payload, '{}'::jsonb),
          'confirmation_version', p_confirmation_version,
          'confirmations', p_confirmations,
          'final_media', p_final_media
        )::text,
        'UTF8'
      ),
      'sha256'
    ),
    'hex'
  );

  select * into existing_revision
  from public.listing_edit_revisions revision
  where revision.request_id = p_request_id;
  if found then
    if existing_revision.listing_id <> p_listing_id
       or existing_revision.editor_id is distinct from p_user_id
       or existing_revision.request_hash <> request_hash then
      raise exception 'listing_edit_idempotency_mismatch'
        using errcode = '23505';
    end if;
    select product.status into current_status
    from public.products product
    where product.id = p_listing_id;
    return jsonb_build_object(
      'edited', true,
      'replayed', true,
      'listing_id', p_listing_id,
      'revision_id', existing_revision.id,
      'revision_number', existing_revision.revision_number,
      'status', coalesce(current_status, 'unknown')
    );
  end if;

  if not public.marketplace_user_is_eligible(p_user_id, true) then
    raise exception 'seller_not_eligible' using errcode = '42501';
  end if;

  select * into seller
  from public.seller_accounts account
  where account.user_id = p_user_id
  for update;

  select * into listing_before
  from public.products product
  where product.id = p_listing_id
    and product.seller_id = p_user_id
  for update;
  if not found then
    raise exception 'listing_not_found' using errcode = 'P0002';
  end if;
  if listing_before.status not in (
    'published', 'ready', 'pending_moderation'
  ) then
    raise exception 'listing_not_editable' using errcode = '23514';
  end if;
  if exists (
    select 1
    from public.orders marketplace_order
    where marketplace_order.product_id = p_listing_id::text
      and marketplace_order.status <> 'cancelled'
  ) then
    raise exception 'listing_has_order_history' using errcode = '55000';
  end if;

  select array_agg(payload_key order by payload_key)
  into unknown_keys
  from jsonb_object_keys(p_payload) payload_key
  where payload_key <> all(array[
    'title', 'description', 'price', 'category', 'brand', 'size', 'color',
    'condition', 'location', 'section', 'subcategory', 'item_type', 'gender',
    'primary_color', 'secondary_colors', 'material', 'pattern', 'season',
    'style', 'city', 'shipping_address_id', 'delivery_methods', 'fit',
    'sleeve_length', 'closure', 'audience', 'has_defects',
    'defects_description', 'defects_reviewed'
  ]::text[]);
  if cardinality(unknown_keys) > 0 then
    raise exception 'listing_payload_contains_forbidden_fields'
      using errcode = '22023', detail = array_to_string(unknown_keys, ',');
  end if;

  select * into version_row
  from public.seller_confirmation_versions confirmation_version
  where confirmation_version.version = p_confirmation_version
    and confirmation_version.status = 'active'
    and confirmation_version.effective_at <= now();
  if not found then
    raise exception 'seller_confirmation_version_not_active'
      using errcode = '55000';
  end if;
  if not coalesce(public.validate_seller_confirmation_payload(
    version_row.id, p_confirmations
  ), false) then
    raise exception 'all_seller_confirmations_required'
      using errcode = '23514';
  end if;

  if p_payload ? 'price' then
    begin
      price_value := (p_payload ->> 'price')::numeric;
    exception when invalid_text_representation or numeric_value_out_of_range then
      raise exception 'listing_price_invalid' using errcode = '22023';
    end;
    if price_value <= 0 or price_value > 100000000 then
      raise exception 'listing_price_invalid' using errcode = '23514';
    end if;
  end if;
  if p_payload ? 'has_defects'
     and jsonb_typeof(p_payload -> 'has_defects') <> 'boolean' then
    raise exception 'has_defects_must_be_boolean' using errcode = '22023';
  end if;
  if p_payload ? 'defects_reviewed'
     and jsonb_typeof(p_payload -> 'defects_reviewed') <> 'boolean' then
    raise exception 'defects_reviewed_must_be_boolean' using errcode = '22023';
  end if;

  if p_payload ? 'secondary_colors' then
    if jsonb_typeof(p_payload -> 'secondary_colors') <> 'array' then
      raise exception 'secondary_colors_must_be_array' using errcode = '22023';
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
      raise exception 'delivery_methods_must_be_array' using errcode = '22023';
    end if;
    select coalesce(array_agg(value), '{}'::text[])
    into delivery_methods_value
    from jsonb_array_elements_text(p_payload -> 'delivery_methods');
    if cardinality(delivery_methods_value) > 5
       or exists (
         select 1 from unnest(delivery_methods_value) method
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
      select 1 from public.listing_addresses address
      where address.id = shipping_address_value
        and address.user_id = p_user_id
    ) then
      raise exception 'shipping_address_not_owned' using errcode = '42501';
    end if;
  end if;

  before_snapshot := public.listing_editable_snapshot(listing_before);

  update public.products
  set
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
      then left(btrim(coalesce(p_payload ->> 'brand', '')), 120) else brand end,
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
      then left(btrim(coalesce(p_payload ->> 'gender', '')), 40) else gender end,
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
      then left(btrim(coalesce(p_payload ->> 'style', '')), 120) else style end,
    fit = case when p_payload ? 'fit'
      then left(btrim(coalesce(p_payload ->> 'fit', '')), 80) else fit end,
    sleeve_length = case when p_payload ? 'sleeve_length'
      then left(btrim(coalesce(p_payload ->> 'sleeve_length', '')), 80)
      else sleeve_length end,
    closure = case when p_payload ? 'closure'
      then left(btrim(coalesce(p_payload ->> 'closure', '')), 80)
      else closure end,
    audience = case when p_payload ? 'audience'
      then nullif(btrim(coalesce(p_payload ->> 'audience', '')), '')
      else audience end,
    has_defects = case when p_payload ? 'has_defects'
      then (p_payload ->> 'has_defects')::boolean else has_defects end,
    defects_description = case when p_payload ? 'defects_description'
      then left(coalesce(p_payload ->> 'defects_description', ''), 1000)
      else defects_description end,
    defects_reviewed = case when p_payload ? 'defects_reviewed'
      then (p_payload ->> 'defects_reviewed')::boolean else defects_reviewed end,
    city = case when p_payload ? 'city'
      then left(btrim(coalesce(p_payload ->> 'city', '')), 160) else city end,
    shipping_address_id = case when p_payload ? 'shipping_address_id'
      then shipping_address_value else shipping_address_id end,
    delivery_methods = case when p_payload ? 'delivery_methods'
      then delivery_methods_value else delivery_methods end,
    normalized_category = case
      when p_payload ? 'item_type'
        or p_payload ? 'subcategory'
        or p_payload ? 'category'
      then public.normalize_product_category(coalesce(
        nullif(btrim(p_payload ->> 'item_type'), ''),
        nullif(btrim(p_payload ->> 'subcategory'), ''),
        nullif(btrim(p_payload ->> 'category'), ''),
        item_type, subcategory, category
      ))
      else normalized_category end,
    normalized_brand = case when p_payload ? 'brand'
      then public.normalize_product_brand(p_payload ->> 'brand')
      else normalized_brand end
  where id = p_listing_id
  returning * into listing_after;

  if replace_media then
    if jsonb_typeof(p_final_media) <> 'array'
       or jsonb_array_length(p_final_media) not between 1 and 8 then
      raise exception 'final_media_invalid' using errcode = '22023';
    end if;
    delete from public.listing_image_fingerprints where listing_id = p_listing_id;
    delete from public.product_images where product_id = p_listing_id;

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
        media_position := coalesce((media ->> 'position')::integer, -1);
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
         or media_position not between 0 and 7
         or media_position = any(seen_media_positions) then
        raise exception 'final_media_contract_invalid' using errcode = '22023';
      end if;
      if not exists (
        select 1 from storage.objects stored
        where stored.bucket_id = 'listing-drafts'
          and stored.name = draft_path
          and stored.owner_id = p_user_id::text
      ) then
        raise exception 'draft_media_not_owned' using errcode = '42501';
      end if;
      if not exists (
        select 1 from storage.objects stored
        where stored.bucket_id = 'product-images' and stored.name = final_path
      ) then
        raise exception 'final_media_not_copied' using errcode = '55000';
      end if;
      seen_media_positions := array_append(seen_media_positions, media_position);
      insert into public.product_images (
        product_id, original_url, role, position, is_active, storage_bucket,
        storage_path, uploader_id, content_hash, mime_type
      ) values (
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
        listing_id, seller_account_id, user_id, object_path,
        content_hash, perceptual_hash
      ) values (
        p_listing_id, seller.id, p_user_id, final_path,
        content_hash, perceptual_hash
      );
      final_references := array_append(
        final_references, 'storage://product-images/' || final_path
      );
    end loop;
    if exists (
      select 1
      from generate_series(0, jsonb_array_length(p_final_media) - 1) required
      where not (required = any(seen_media_positions))
    ) then
      raise exception 'final_media_positions_not_contiguous'
        using errcode = '22023';
    end if;
    main_reference := final_references[1];
    update public.products
    set images = final_references,
        main_image = main_reference,
        image = main_reference,
        original_image = main_reference,
        cutout_image = null,
        background_status = 'queued',
        background_error = null
    where id = p_listing_id
    returning * into listing_after;
  end if;

  if btrim(coalesce(listing_after.title, '')) = ''
     or char_length(listing_after.title) > 80
     or listing_after.price is null or listing_after.price <= 0
     or char_length(coalesce(listing_after.description, '')) > 2000
     or btrim(coalesce(listing_after.brand, '')) = ''
     or btrim(coalesce(listing_after.size, '')) = ''
     or btrim(coalesce(listing_after.condition, '')) = ''
     or btrim(coalesce(listing_after.primary_color, '')) = ''
     or listing_after.normalized_category is null
     or listing_after.audience not in ('male', 'female', 'unisex', 'kids')
     or not listing_after.defects_reviewed
     or (listing_after.has_defects and
       btrim(coalesce(listing_after.defects_description, '')) = '')
     or cardinality(coalesce(listing_after.delivery_methods, '{}'::text[])) < 1
     or listing_after.shipping_address_id is null
     or cardinality(coalesce(listing_after.images, '{}'::text[])) < 1 then
    raise exception 'listing_publication_fields_incomplete'
      using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.listing_addresses address
    where address.id = listing_after.shipping_address_id
      and address.user_id = p_user_id
      and btrim(address.city) <> '' and btrim(address.address) <> ''
  ) then
    raise exception 'shipping_address_required' using errcode = '23514';
  end if;

  after_snapshot := public.listing_editable_snapshot(listing_after);
  select coalesce(array_agg(key order by key), '{}'::text[])
  into changed_fields
  from jsonb_object_keys(before_snapshot || after_snapshot) key
  where before_snapshot -> key is distinct from after_snapshot -> key;
  if cardinality(changed_fields) = 0 then
    return jsonb_build_object(
      'edited', false,
      'listing_id', p_listing_id,
      'status', listing_before.status
    );
  end if;

  next_revision := listing_before.content_revision + 1;
  update public.products
  set content_revision = next_revision,
      status = 'pending_moderation',
      is_hidden = true,
      analysis_status = 'pending',
      analysis_completed_at = null,
      enrichment_status = 'enrichment_pending',
      enrichment_completed_at = null,
      recommendation_tags = '{}'::text[],
      last_autosaved_at = now(),
      updated_at = now()
  where id = p_listing_id
  returning * into listing_after;

  insert into public.listing_edit_decisions (
    revision_id, decision, reason, risk_result
  )
  select prior.id, 'superseded', 'superseded_by_new_owner_edit', '{}'::jsonb
  from public.listing_edit_revisions prior
  where prior.listing_id = p_listing_id
    and not exists (
      select 1 from public.listing_edit_decisions decision
      where decision.revision_id = prior.id
        and decision.decision in (
          'approved', 'rejected', 'needs_changes', 'superseded'
        )
    );

  insert into public.listing_edit_revisions (
    listing_id, revision_number, editor_id, editor_role, request_id,
    request_hash, before_snapshot, after_snapshot, changed_fields,
    confirmation_version_id, confirmation_version, confirmations,
    ip, user_agent
  ) values (
    p_listing_id, next_revision, p_user_id, 'owner', p_request_id,
    request_hash, before_snapshot, after_snapshot, changed_fields,
    version_row.id, version_row.version, p_confirmations,
    p_ip, btrim(p_user_agent)
  ) returning id into revision_id;

  product_signature := encode(
    extensions.digest(
      convert_to(lower(concat_ws(
        '|', btrim(listing_after.title), btrim(listing_after.brand),
        btrim(listing_after.size), btrim(listing_after.condition),
        listing_after.price::text
      )), 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  insert into public.listing_risk_fingerprints (
    listing_id, seller_account_id, user_id, product_signature, evaluated_at
  ) values (
    p_listing_id, seller.id, p_user_id, product_signature, now()
  ) on conflict (listing_id) do update
    set product_signature = excluded.product_signature,
        evaluated_at = excluded.evaluated_at;

  insert into public.listing_moderation (
    product_id, status, risk_flags, priority, submitted_at,
    decided_at, decision_reason, updated_at
  ) values (
    p_listing_id, 'manual_review', '{}'::jsonb, 0, now(),
    null, 'seller_material_edit', now()
  ) on conflict (product_id) do update
    set status = 'manual_review',
        risk_flags = '{}'::jsonb,
        submitted_at = now(),
        decided_at = null,
        decision_reason = 'seller_material_edit',
        updated_at = now();

  return jsonb_build_object(
    'edited', true,
    'listing_id', p_listing_id,
    'revision_id', revision_id,
    'revision_number', next_revision,
    'changed_fields', changed_fields,
    'status', 'pending_moderation'
  );
end;
$$;

create or replace function public.moderate_listing_edit_authoritatively(
  p_moderator_id uuid,
  p_revision_id uuid,
  p_decision text,
  p_reason text,
  p_ip inet,
  p_user_agent text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  revision public.listing_edit_revisions%rowtype;
  listing public.products%rowtype;
  risk jsonb := '{}'::jsonb;
  publish_allowed boolean := false;
  stored_decision text;
begin
  if auth.role() <> 'service_role' then
    raise exception 'service_role_required' using errcode = '42501';
  end if;
  if p_moderator_id is null or not exists (
    select 1 from public.admin_roles role
    where role.user_id = p_moderator_id
      and role.role in ('moderator', 'ops_admin', 'owner')
  ) then
    raise exception 'listing_moderator_required' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'needs_changes', 'reject') then
    raise exception 'listing_edit_decision_invalid' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 3 and 2000
     or p_ip is null
     or char_length(btrim(coalesce(p_user_agent, ''))) not between 1 and 1000 then
    raise exception 'moderation_evidence_required' using errcode = '23514';
  end if;

  select * into revision
  from public.listing_edit_revisions edit_revision
  where edit_revision.id = p_revision_id;
  if not found then
    raise exception 'listing_edit_revision_not_found' using errcode = 'P0002';
  end if;
  select * into listing
  from public.products product
  where product.id = revision.listing_id
  for update;
  if listing.status <> 'pending_moderation'
     or listing.content_revision <> revision.revision_number
     or exists (
       select 1 from public.listing_edit_decisions decision
       where decision.revision_id = revision.id
         and decision.decision in (
           'approved', 'rejected', 'needs_changes', 'superseded'
         )
     ) then
    raise exception 'listing_edit_revision_not_pending' using errcode = '55000';
  end if;

  if p_decision = 'approve' then
    if exists (
      select 1 from public.orders marketplace_order
      where marketplace_order.product_id = listing.id::text
        and marketplace_order.status <> 'cancelled'
    ) then
      raise exception 'listing_has_order_history' using errcode = '55000';
    end if;
    if not public.marketplace_user_is_eligible(listing.seller_id, true) then
      raise exception 'seller_not_eligible' using errcode = '42501';
    end if;
    risk := public.evaluate_seller_risk(listing.seller_id, listing.id);
    publish_allowed := coalesce((risk ->> 'can_publish')::boolean, false);
    if publish_allowed then
      perform set_config('clothes.publish_listing', 'allowed', true);
      update public.products
      set status = 'published',
          is_hidden = false,
          published_at = coalesce(
            listing.first_published_at,
            listing.published_at,
            listing.created_at
          ),
          moderation_risk = risk,
          updated_at = now()
      where id = listing.id;
      stored_decision := 'approved';
      update public.listing_moderation
      set status = 'approved', risk_flags = risk,
          priority = coalesce((risk ->> 'risk_score')::integer, 0),
          assigned_to = p_moderator_id, decision_reason = btrim(p_reason),
          decided_at = now(), updated_at = now()
      where product_id = listing.id;
    else
      update public.products
      set is_hidden = true, moderation_risk = risk, updated_at = now()
      where id = listing.id;
      stored_decision := 'risk_hold';
      update public.listing_moderation
      set status = 'manual_review', risk_flags = risk,
          priority = coalesce((risk ->> 'risk_score')::integer, 0),
          assigned_to = p_moderator_id,
          decision_reason = 'automatic_professional_selling_risk',
          decided_at = null, updated_at = now()
      where product_id = listing.id;
    end if;
  elsif p_decision = 'needs_changes' then
    update public.products
    set status = 'ready', is_hidden = true, published_at = null,
        updated_at = now()
    where id = listing.id;
    stored_decision := 'needs_changes';
    update public.listing_moderation
    set status = 'needs_changes', assigned_to = p_moderator_id,
        decision_reason = btrim(p_reason), decided_at = now(), updated_at = now()
    where product_id = listing.id;
  else
    update public.products
    set status = 'archived', is_hidden = true, published_at = null,
        updated_at = now()
    where id = listing.id;
    stored_decision := 'rejected';
    update public.listing_moderation
    set status = 'rejected', assigned_to = p_moderator_id,
        decision_reason = btrim(p_reason), decided_at = now(), updated_at = now()
    where product_id = listing.id;
  end if;

  insert into public.listing_edit_decisions (
    revision_id, decision, moderator_id, reason, risk_result, ip, user_agent
  ) values (
    revision.id, stored_decision, p_moderator_id, btrim(p_reason), risk,
    p_ip, btrim(p_user_agent)
  );
  insert into public.admin_audit_log (
    actor_id, actor_role, action, target_type, target_id, reason,
    before_data, after_data
  ) values (
    p_moderator_id, 'moderator', 'moderate_listing_edit', 'product',
    listing.id::text, btrim(p_reason),
    jsonb_build_object(
      'status', listing.status, 'revision_id', revision.id,
      'revision_number', revision.revision_number
    ),
    jsonb_build_object(
      'decision', stored_decision,
      'published', publish_allowed,
      'risk', risk
    )
  );

  return jsonb_build_object(
    'listing_id', listing.id,
    'revision_id', revision.id,
    'decision', stored_decision,
    'published', publish_allowed,
    'status', case
      when stored_decision = 'approved' then 'published'
      when stored_decision = 'needs_changes' then 'ready'
      when stored_decision = 'rejected' then 'archived'
      else 'pending_moderation'
    end,
    'risk', risk
  );
end;
$$;

-- Pending edits can be archived by their owner, subject to the existing order
-- guard. This remains a command; no direct DELETE/UPDATE privilege is restored.
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
    select 1 from public.orders marketplace_order
    where marketplace_order.product_id = p_listing_id::text
      and marketplace_order.status not in ('completed', 'cancelled')
  ) then
    raise exception 'listing_has_active_order' using errcode = '55000';
  end if;
  update public.products
  set status = 'archived', is_hidden = true, updated_at = now()
  where id = p_listing_id
    and seller_id = actor_id
    and status in (
      'draft', 'processing', 'ready', 'pending_moderation', 'published'
    );
  if not found then
    raise exception 'listing_not_archivable' using errcode = 'P0002';
  end if;
  return jsonb_build_object('listing_id', p_listing_id, 'status', 'archived');
end;
$$;

alter table public.listing_edit_revisions enable row level security;
alter table public.listing_edit_decisions enable row level security;
revoke all on public.listing_edit_revisions, public.listing_edit_decisions
  from anon, authenticated;
revoke insert, update, delete on public.products from authenticated;
revoke all on function public.submit_listing_edit_authoritatively(
  uuid, uuid, uuid, jsonb, text, jsonb, jsonb, inet, text
) from public, anon, authenticated;
grant execute on function public.submit_listing_edit_authoritatively(
  uuid, uuid, uuid, jsonb, text, jsonb, jsonb, inet, text
) to service_role;
revoke all on function public.moderate_listing_edit_authoritatively(
  uuid, uuid, text, text, inet, text
) from public, anon, authenticated;
grant execute on function public.moderate_listing_edit_authoritatively(
  uuid, uuid, text, text, inet, text
) to service_role;
revoke all on function public.prevent_listing_edit_audit_mutation()
  from public, anon, authenticated;
revoke all on function public.preserve_product_first_publication()
  from public, anon, authenticated;
revoke all on function public.listing_editable_snapshot(public.products)
  from public, anon, authenticated;
revoke all on function public.archive_own_listing(uuid) from public, anon;
grant execute on function public.archive_own_listing(uuid) to authenticated;

-- Reuse the private canonical listing-draft namespace for replacement photos.
-- A per-listing cap prevents an authenticated owner from turning edit staging
-- into unbounded object storage.
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
      select 1 from public.products product
      where product.id::text = split_part(name, '/', 2)
        and product.seller_id = (select auth.uid())
        and product.status in (
          'draft', 'processing', 'ready', 'published', 'pending_moderation'
        )
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
      select 1 from public.products product
      where product.id::text = split_part(name, '/', 2)
        and product.seller_id = (select auth.uid())
        and product.status in (
          'draft', 'processing', 'ready', 'published', 'pending_moderation'
        )
    )
    and (
      select count(*)
      from storage.objects sibling
      where sibling.bucket_id = 'listing-drafts'
        and split_part(sibling.name, '/', 1) = (select auth.uid()::text)
        and split_part(sibling.name, '/', 2) = split_part(name, '/', 2)
    ) < 8
  );

notify pgrst, 'reload schema';

commit;
