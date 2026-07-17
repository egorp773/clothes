-- Remove the legacy product-images policies that allowed every authenticated
-- account to write any non-users/* object.  New uploads are owner-scoped by
-- both namespace and Storage's JWT-derived owner_id.

-- Global/default accessories are catalogue content and must be created by a
-- trusted service/admin workflow (service_role bypasses RLS), not by a mobile
-- client toggling `scope = default`.
drop policy if exists "Authenticated users can create outfit accessories"
  on public.outfit_accessories;
create policy "Authenticated users can create outfit accessories"
  on public.outfit_accessories for insert to authenticated
  with check (
    scope = 'private' and owner_id = (select auth.uid())
  );

drop policy if exists "Users can update their outfit accessories"
  on public.outfit_accessories;
create policy "Users can update their outfit accessories"
  on public.outfit_accessories for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (
    scope = 'private' and owner_id = (select auth.uid())
  );

drop policy if exists "Users can delete their outfit accessories"
  on public.outfit_accessories;
create policy "Users can delete their outfit accessories"
  on public.outfit_accessories for delete to authenticated
  using (
    scope = 'private' and owner_id = (select auth.uid())
  );

drop policy if exists "Authenticated users can upload product images"
  on storage.objects;
drop policy if exists "Authenticated users can update product images"
  on storage.objects;
drop policy if exists "Owners can upload listing images"
  on storage.objects;
drop policy if exists "Owners can update listing images"
  on storage.objects;
drop policy if exists "Owners can delete listing images"
  on storage.objects;
drop policy if exists "Owners can upload product media"
  on storage.objects;
drop policy if exists "Owners can update product media"
  on storage.objects;
drop policy if exists "Owners can delete product media"
  on storage.objects;

-- Canonical namespaces:
--   users/<uid>/listings/<listing-id>/<file>
--   avatars/<uid>/<file>
--   accessories/<uid>/<file>
--
-- The current client also has legacy random-name paths under items/* and
-- outfits/{items,photos}/*.  They cannot encode a UID without a client
-- migration, so compatibility is limited to objects whose owner_id is set by
-- Storage from the uploader's JWT.  Existing objects owned by another account
-- can never be updated or deleted through these policies.
create policy "Owners can upload product media"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'product-images'
    and owner_id = (select auth.uid()::text)
    and (
      (
        (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
        and (storage.foldername(name))[3] = 'listings'
      )
      or (
        (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (
        (storage.foldername(name))[1] = 'accessories'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (storage.foldername(name))[1] = 'items'
      or (storage.foldername(name))[1] = 'outfits'
    )
  );

create policy "Owners can update product media"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'product-images'
    and owner_id = (select auth.uid()::text)
    and (
      (
        (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
        and (storage.foldername(name))[3] = 'listings'
      )
      or (
        (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (
        (storage.foldername(name))[1] = 'accessories'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (storage.foldername(name))[1] = 'items'
      or (storage.foldername(name))[1] = 'outfits'
    )
  )
  with check (
    bucket_id = 'product-images'
    and owner_id = (select auth.uid()::text)
    and (
      (
        (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
        and (storage.foldername(name))[3] = 'listings'
      )
      or (
        (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (
        (storage.foldername(name))[1] = 'accessories'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (storage.foldername(name))[1] = 'items'
      or (storage.foldername(name))[1] = 'outfits'
    )
  );

create policy "Owners can delete product media"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'product-images'
    and owner_id = (select auth.uid()::text)
    and (
      (
        (storage.foldername(name))[1] = 'users'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
        and (storage.foldername(name))[3] = 'listings'
      )
      or (
        (storage.foldername(name))[1] = 'avatars'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (
        (storage.foldername(name))[1] = 'accessories'
        and (storage.foldername(name))[2] = (select auth.uid()::text)
      )
      or (storage.foldername(name))[1] = 'items'
      or (storage.foldername(name))[1] = 'outfits'
    )
  );

notify pgrst, 'reload schema';
