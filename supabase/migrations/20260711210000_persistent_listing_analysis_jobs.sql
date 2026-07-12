-- Durable source of truth for asynchronous visual-analysis work.  It is safe
-- for many API workers because no result is held solely in a worker's memory.
alter table public.products
  add column if not exists analysis_job_id text;

create table if not exists public.listing_analysis_jobs (
  id text primary key,
  listing_id uuid not null references public.products(id) on delete cascade,
  image_hash text not null,
  main_image_url text,
  extra_image_urls jsonb not null default '[]'::jsonb,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'completed', 'failed')),
  basic_result jsonb,
  enrichment_result jsonb,
  timings_ms jsonb not null default '{}'::jsonb,
  error text,
  attempt_count integer not null default 0,
  lease_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create unique index if not exists listing_analysis_jobs_listing_image_idx
  on public.listing_analysis_jobs (listing_id, image_hash);
create index if not exists listing_analysis_jobs_claim_idx
  on public.listing_analysis_jobs (status, lease_until, created_at);

drop trigger if exists touch_listing_analysis_jobs_updated_at on public.listing_analysis_jobs;
create trigger touch_listing_analysis_jobs_updated_at
before update on public.listing_analysis_jobs
for each row execute function public.touch_listing_updated_at();

alter table public.listing_analysis_jobs enable row level security;
drop policy if exists "Owners can read listing analysis jobs" on public.listing_analysis_jobs;
create policy "Owners can read listing analysis jobs"
  on public.listing_analysis_jobs for select to authenticated
  using (exists (
    select 1 from public.products p
    where p.id = listing_id and p.seller_id = auth.uid()
  ));

-- Only the analyzer's service-role client writes job state.  App users retain
-- write access to their editable listing_analysis predictions, not job output.
notify pgrst, 'reload schema';
