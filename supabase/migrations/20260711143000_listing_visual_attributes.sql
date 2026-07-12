-- Optional category-specific attributes produced by the modular analyzer.
alter table public.products
  add column if not exists fit text,
  add column if not exists sleeve_length text,
  add column if not exists closure text;

notify pgrst, 'reload schema';
