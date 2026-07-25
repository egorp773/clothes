-- Local Supabase bootstrap only.
-- Storage-owned relations require the migration session to SET ROLE
-- supabase_storage_admin. The managed production role is reserved, so this
-- grant is intentionally applied only by the local CLI roles bootstrap.
grant supabase_storage_admin to postgres;
