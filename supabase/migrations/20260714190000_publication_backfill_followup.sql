-- Complete normalization for pre-MVP listings that only stored Russian broad
-- categories and free-form titles. No legacy value is removed or rewritten.

insert into public.product_category_aliases (alias, category_code)
values
  ('верх', 't_shirt'),
  ('низ', 'trousers'),
  ('обувь', 'sneakers'),
  ('аксессуары', 'accessory'),
  ('образ', 'accessory')
on conflict (alias) do update set category_code = excluded.category_code;

update public.products p
set normalized_category = case
  when lower(concat_ws(' ', p.title, p.category)) ~
    '(джинсов.{0,8}(куртк|рубаш)|куртк|пухов|пальто)' then 'jacket'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(рубаш|блуз)' then 'shirt'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(худи|толстов|свитшот|кардиган)' then 'hoodie'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(джинс)' then 'jeans'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(брюк|штан|шорт)' then 'trousers'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(плать|сарафан)' then 'dress'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(юбк)' then 'skirt'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(сапог|ботин)' then 'boots'
  when lower(concat_ws(' ', p.title, p.category)) ~
    '(обув|крос|кед|sneaker|nike af|balenciaga|prada)' then 'sneakers'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(сумк|косметич|рюкзак)' then 'bag'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(кошелек|аксессуар|украшен)' then 'accessory'
  when lower(concat_ws(' ', p.title, p.category)) ~ '(футбол|лонгслив|майк|верх)' then 't_shirt'
  when lower(coalesce(p.category, '')) in ('низ') then 'trousers'
  when lower(coalesce(p.category, '')) in ('обувь') then 'sneakers'
  when lower(coalesce(p.category, '')) in ('аксессуары') then 'accessory'
  else 'accessory'
end
where p.normalized_category is null;

update public.products
set audience = 'unisex'
where status = 'published' and audience is null;

update public.products
set normalized_brand = coalesce(public.normalize_product_brand(brand), 'no_brand')
where status = 'published' and nullif(normalized_brand, '') is null;

update public.products set search_text = search_text;

notify pgrst, 'reload schema';
