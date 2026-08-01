-- Bridge accounts created by the legacy custom OAuth handlers to the
-- server-owned identity map used by the current PKCE flow. User metadata is
-- editable and must not be consulted for ongoing authorization; it is read
-- only once here, with the exact provider marker written by the old handlers.
with legacy_candidates as (
  select
    account.id as user_id,
    account.created_at,
    coalesce(account.last_sign_in_at, account.created_at, now())
      as last_login_at,
    legacy.provider,
    btrim(legacy.provider_subject) as provider_subject,
    jsonb_strip_nulls(
      jsonb_build_object(
        'username', nullif(
          left(btrim(coalesce(
            account.raw_user_meta_data ->> 'username',
            ''
          )), 100),
          ''
        ),
        'full_name', nullif(
          left(btrim(coalesce(
            account.raw_user_meta_data ->> 'full_name',
            ''
          )), 200),
          ''
        ),
        'avatar_url', nullif(
          left(btrim(coalesce(
            account.raw_user_meta_data ->> 'avatar_url',
            ''
          )), 2048),
          ''
        )
      )
    ) as provider_profile
  from auth.users account
  cross join lateral (
    values
      ('yandex'::text, account.raw_user_meta_data ->> 'yandex_id'),
      ('vk'::text, account.raw_user_meta_data ->> 'vk_id'),
      ('telegram'::text, account.raw_user_meta_data ->> 'telegram_id')
  ) as legacy(provider, provider_subject)
  where account.raw_user_meta_data ->> 'provider' = legacy.provider
    and char_length(btrim(coalesce(legacy.provider_subject, '')))
      between 1 and 500
    and btrim(legacy.provider_subject) ~ '^[0-9]+$'
),
unmapped_candidates as (
  select candidate.*
  from legacy_candidates candidate
  where not exists (
    select 1
    from public.oauth_external_identities existing
    where existing.provider = candidate.provider
      and (
        existing.provider_subject = candidate.provider_subject
        or existing.user_id = candidate.user_id
      )
  )
),
ranked_candidates as (
  select
    candidate.*,
    row_number() over (
      partition by candidate.provider, candidate.provider_subject
      order by candidate.created_at asc nulls last, candidate.user_id
    ) as subject_priority,
    row_number() over (
      partition by candidate.provider, candidate.user_id
      order by candidate.provider_subject
    ) as user_priority
  from unmapped_candidates candidate
)
insert into public.oauth_external_identities (
  provider,
  provider_subject,
  user_id,
  provider_profile,
  created_at,
  last_login_at
)
select
  candidate.provider,
  candidate.provider_subject,
  candidate.user_id,
  candidate.provider_profile,
  coalesce(candidate.created_at, now()),
  candidate.last_login_at
from ranked_candidates candidate
where candidate.subject_priority = 1
  and candidate.user_priority = 1
order by
  candidate.provider,
  candidate.provider_subject,
  candidate.created_at asc nulls last,
  candidate.user_id
on conflict do nothing;
