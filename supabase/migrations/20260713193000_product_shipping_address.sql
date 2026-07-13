alter table public.products
  add column if not exists shipping_address text not null default '';

update public.products p
set shipping_address = concat_ws(
  ', ',
  nullif(btrim(a.city), ''),
  nullif(btrim(a.address), '')
)
from public.listing_addresses a
where p.shipping_address_id = a.id
  and btrim(coalesce(p.shipping_address, '')) = '';
