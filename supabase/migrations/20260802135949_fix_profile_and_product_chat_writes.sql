begin;

-- The canonical chat RPCs intentionally write only authoritative ids and
-- snapshots. Legacy presentation columns are still NOT NULL, though, and the
-- original table predates defaults for three of them. As a result every new
-- direct/product/group thread could fail before member rows were created.
alter table public.message_threads
  alter column seller_name set default 'Продавец',
  alter column product_title set default '',
  alter column last_message set default '';

-- Existing functions keep their least-privilege, server-authoritative flow;
-- These defaults only complete the omitted legacy display fields.
notify pgrst, 'reload schema';

commit;
