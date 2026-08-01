-- Temporary test-only legal document versions.
--
-- These make onboarding usable while the product is in closed testing. Before
-- release, publish lawyer-approved immutable versions, switch the active rows,
-- and retire these test versions. Never silently relabel this content as final.

begin;

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
  'test-2026-07-26',
  'published',
  document.title || ' (тестовая версия)',
  'https://hbwzxtwcjlsfldjcqudt.supabase.co/functions/v1/legal-documents'
    || '?document=' || document.document_type::text
    || '&version=test-2026-07-26',
  md5('TEST ONLY|test-2026-07-26|' || document.document_type::text),
  now(),
  now(),
  true
from public.legal_documents document
where not exists (
  select 1
  from public.legal_document_versions active_version
  where active_version.document_id = document.id
    and active_version.is_active
);

commit;
