-- Jobs claimed during the rolling deployment may have hit an older product
-- projection before the compatible worker was live. Make only those jobs
-- immediately retryable; their durable attempt history remains intact.

update public.product_enrichment_jobs
set status = 'retry',
    available_at = now(),
    locked_by = null,
    lease_until = null
where status in ('retry', 'failed')
  and last_error like '%column products.collar does not exist%';

update public.products p
set enrichment_status = 'enrichment_pending'
where exists (
  select 1 from public.product_enrichment_jobs j
  where j.product_id = p.id
    and j.status = 'retry'
    and j.last_error like '%column products.collar does not exist%'
);

notify pgrst, 'reload schema';
