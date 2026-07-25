-- Local Supabase bootstrap only.
-- Storage-owned relations require the migration session to SET ROLE
-- supabase_storage_admin. The managed production role is reserved, so this
-- grant is intentionally issued by the local container's supabase_admin
-- connection and is never included in a normal production db push.
create extension if not exists dblink with schema extensions;
select extensions.dblink_exec(
  'host=supabase_db_clothes port=5432 dbname=postgres user=supabase_admin password=postgres connect_timeout=5',
  'grant supabase_storage_admin to postgres'
);
