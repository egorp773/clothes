-- Local Supabase bootstrap only.
-- Storage-owned relations require the migration session to SET ROLE
-- supabase_storage_admin. The managed production role is reserved, so this
-- grant is intentionally issued by the local container's supabase_admin
-- connection and is never included in a normal production db push.
create extension if not exists dblink with schema extensions;
select extensions.dblink_connect_u(
  'local_admin',
  'host=127.0.0.1 port=5432 dbname=postgres user=supabase_admin password=postgres connect_timeout=5'
);
select extensions.dblink_exec(
  'local_admin',
  'grant supabase_storage_admin to postgres'
);
select extensions.dblink_disconnect('local_admin');
