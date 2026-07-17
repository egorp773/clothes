-- Server-only inventory used by the delete-account Edge Function.
-- The caller identity is resolved from the bearer token in the function; this
-- RPC is intentionally unavailable to app roles.
create or replace function public.list_account_deletion_storage_objects(
  p_user_id uuid,
  p_after_bucket text default '',
  p_after_name text default '',
  p_limit integer default 200
)
returns table (bucket_id text, object_name text)
language sql
security definer
set search_path = public, storage, pg_temp
as $$
  with candidates as (
    select stored.bucket_id, stored.name
    from storage.objects stored
    where stored.bucket_id in ('product-images', 'chat-media')
      and (
        stored.owner_id::text = p_user_id::text
        or (
          stored.bucket_id = 'product-images'
          and (
            stored.name like 'users/' || p_user_id::text || '/%'
            or stored.name like 'avatars/' || p_user_id::text || '/%'
            or stored.name like 'accessories/' || p_user_id::text || '/%'
            or exists (
              select 1
              from public.outfit_accessories accessory
              where accessory.owner_id = p_user_id
                and stored.name = 'accessory-cutouts/' || accessory.id::text || '.png'
            )
            or exists (
              select 1
              from public.product_images product_image
              join public.products product on product.id = product_image.product_id
              where product.seller_id = p_user_id
                and stored.name = 'enrichment/' || product.id::text || '/' ||
                  product_image.id::text || '.png'
            )
          )
        )
        or (
          stored.bucket_id = 'chat-media'
          and split_part(stored.name, '/', 1) = 'threads'
          and split_part(stored.name, '/', 3) = p_user_id::text
        )
        -- buyer_id/seller_id use ON DELETE CASCADE, so deleting either anchor
        -- removes the entire thread. Inventory every object in that namespace,
        -- including media uploaded by other participants, before the database
        -- cascade makes the namespace undiscoverable and leaves orphan files.
        or (
          stored.bucket_id = 'chat-media'
          and split_part(stored.name, '/', 1) = 'threads'
          and exists (
            select 1
            from public.message_threads doomed_thread
            where doomed_thread.id = split_part(stored.name, '/', 2)
              and p_user_id in (
                doomed_thread.buyer_id,
                doomed_thread.seller_id
              )
          )
        )
        or (
          stored.bucket_id = 'chat-media'
          and exists (
            select 1
            from public.chat_messages message
            where message.sender_id = p_user_id
              and message.attachment->>'bucket' = 'chat-media'
              and message.attachment->>'storage_path' = stored.name
          )
        )
      )
  )
  select candidate.bucket_id, candidate.name as object_name
  from candidates candidate
  where (candidate.bucket_id, candidate.name) >
    (coalesce(p_after_bucket, ''), coalesce(p_after_name, ''))
  order by candidate.bucket_id, candidate.name
  limit greatest(1, least(coalesce(p_limit, 200), 500));
$$;

revoke all on function public.list_account_deletion_storage_objects(
  uuid, text, text, integer
) from public, anon, authenticated;
grant execute on function public.list_account_deletion_storage_objects(
  uuid, text, text, integer
) to service_role;

-- Account deletion must go through the Edge Function above this RPC layer so
-- owned Storage objects and public UGC are removed before the Auth identity.
-- The legacy direct RPC could delete auth.users first and strand those files.
revoke all on function public.delete_current_user()
  from public, anon, authenticated;

notify pgrst, 'reload schema';
