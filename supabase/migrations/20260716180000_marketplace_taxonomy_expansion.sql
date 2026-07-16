-- Expand the seller-facing taxonomy without collapsing distinct item types.
-- Canonical codes below are shared by Flutter and product_analyzer.

insert into public.product_categories (code, display_name, sort_order, is_active)
values
  ('t_shirt', 'Футболка', 10, true),
  ('tank_top', 'Майка', 20, true),
  ('top', 'Топ', 30, true),
  ('long_sleeve', 'Лонгслив', 40, true),
  ('polo', 'Поло', 50, true),
  ('shirt', 'Рубашка', 60, true),
  ('blouse', 'Блузка', 70, true),
  ('hoodie', 'Худи', 80, true),
  ('sweatshirt', 'Свитшот', 90, true),
  ('sweater', 'Свитер / джемпер', 100, true),
  ('cardigan', 'Кардиган', 110, true),
  ('turtleneck', 'Водолазка', 120, true),
  ('jeans', 'Джинсы', 130, true),
  ('trousers', 'Брюки', 140, true),
  ('joggers', 'Джоггеры', 150, true),
  ('leggings', 'Легинсы', 160, true),
  ('shorts', 'Шорты', 170, true),
  ('skirt', 'Юбка', 180, true),
  ('jacket', 'Куртка', 190, true),
  ('blazer', 'Пиджак', 200, true),
  ('puffer', 'Пуховик', 210, true),
  ('coat', 'Пальто', 220, true),
  ('trench', 'Тренч / плащ', 230, true),
  ('vest', 'Жилет', 240, true),
  ('dress', 'Платье', 250, true),
  ('jumpsuit', 'Комбинезон', 260, true),
  ('underwear', 'Нижнее бельё', 270, true),
  ('swimwear', 'Купальник / плавки', 280, true),
  ('socks', 'Носки', 290, true),
  ('tights', 'Колготки', 300, true),
  ('sneakers', 'Кроссовки', 310, true),
  ('boots', 'Ботинки', 320, true),
  ('shoes', 'Туфли', 330, true),
  ('heels', 'Туфли на каблуке', 340, true),
  ('loafers', 'Лоферы', 350, true),
  ('sandals', 'Сандалии', 360, true),
  ('slippers', 'Домашняя обувь', 370, true),
  ('bag', 'Сумка', 380, true),
  ('backpack', 'Рюкзак', 390, true),
  ('wallet', 'Кошелёк', 400, true),
  ('cap', 'Кепка / бейсболка', 410, true),
  ('beanie', 'Шапка', 420, true),
  ('hat', 'Шляпа / панама', 430, true),
  ('headwear', 'Другой головной убор', 440, true),
  ('belt', 'Ремень', 450, true),
  ('scarf', 'Шарф / платок', 460, true),
  ('gloves', 'Перчатки', 470, true),
  ('eyewear', 'Очки', 480, true),
  ('watch', 'Часы', 490, true),
  ('tie', 'Галстук / бабочка', 500, true),
  ('accessory', 'Другой аксессуар', 510, true),
  ('necklace', 'Колье / подвеска', 520, true),
  ('ring', 'Кольцо', 530, true),
  ('bracelet', 'Браслет', 540, true),
  ('earrings', 'Серьги', 550, true),
  ('brooch', 'Брошь', 560, true)
on conflict (code) do update
set display_name = excluded.display_name,
    sort_order = excluded.sort_order,
    is_active = true,
    updated_at = now();

insert into public.product_category_aliases (alias, category_code)
values
  ('t_shirt', 't_shirt'), ('tshirt', 't_shirt'), ('t-shirt', 't_shirt'),
  ('tee', 't_shirt'), ('футболка', 't_shirt'),
  ('tank_top', 'tank_top'), ('tank top', 'tank_top'), ('майка', 'tank_top'),
  ('top', 'top'), ('топ', 'top'),
  ('long_sleeve', 'long_sleeve'), ('long sleeve', 'long_sleeve'),
  ('лонгслив', 'long_sleeve'),
  ('polo', 'polo'), ('поло', 'polo'),
  ('shirt', 'shirt'), ('рубашка', 'shirt'),
  ('blouse', 'blouse'), ('блузка', 'blouse'),
  ('hoodie', 'hoodie'), ('худи', 'hoodie'),
  ('толстовка с капюшоном', 'hoodie'),
  ('sweatshirt', 'sweatshirt'), ('crewneck', 'sweatshirt'),
  ('свитшот', 'sweatshirt'), ('толстовка', 'sweatshirt'),
  ('sweater', 'sweater'), ('pullover', 'sweater'),
  ('свитер', 'sweater'), ('джемпер', 'sweater'), ('пуловер', 'sweater'),
  ('cardigan', 'cardigan'), ('кардиган', 'cardigan'),
  ('turtleneck', 'turtleneck'), ('водолазка', 'turtleneck'),
  ('jeans', 'jeans'), ('джинсы', 'jeans'),
  ('trousers', 'trousers'), ('pants', 'trousers'),
  ('брюки', 'trousers'), ('штаны', 'trousers'),
  ('joggers', 'joggers'), ('sweatpants', 'joggers'),
  ('джоггеры', 'joggers'), ('спортивные штаны', 'joggers'),
  ('leggings', 'leggings'), ('легинсы', 'leggings'), ('лосины', 'leggings'),
  ('shorts', 'shorts'), ('шорты', 'shorts'),
  ('skirt', 'skirt'), ('юбка', 'skirt'),
  ('jacket', 'jacket'), ('куртка', 'jacket'),
  ('blazer', 'blazer'), ('пиджак', 'blazer'), ('блейзер', 'blazer'),
  ('puffer', 'puffer'), ('puffer jacket', 'puffer'), ('пуховик', 'puffer'),
  ('coat', 'coat'), ('пальто', 'coat'),
  ('trench', 'trench'), ('raincoat', 'trench'),
  ('тренч', 'trench'), ('плащ', 'trench'),
  ('vest', 'vest'), ('жилет', 'vest'), ('безрукавка', 'vest'),
  ('dress', 'dress'), ('платье', 'dress'), ('сарафан', 'dress'),
  ('jumpsuit', 'jumpsuit'), ('комбинезон', 'jumpsuit'),
  ('underwear', 'underwear'), ('нижнее белье', 'underwear'),
  ('нижнее бельё', 'underwear'), ('белье', 'underwear'), ('бельё', 'underwear'),
  ('swimwear', 'swimwear'), ('купальник', 'swimwear'), ('плавки', 'swimwear'),
  ('socks', 'socks'), ('носки', 'socks'), ('гольфы', 'socks'),
  ('tights', 'tights'), ('колготки', 'tights'),
  ('sneakers', 'sneakers'), ('trainers', 'sneakers'),
  ('кроссовки', 'sneakers'), ('кеды', 'sneakers'),
  ('boots', 'boots'), ('ботинки', 'boots'), ('сапоги', 'boots'),
  ('shoes', 'shoes'), ('туфли', 'shoes'),
  ('heels', 'heels'), ('high heels', 'heels'), ('туфли на каблуке', 'heels'),
  ('loafers', 'loafers'), ('лоферы', 'loafers'), ('мокасины', 'loafers'),
  ('sandals', 'sandals'), ('сандалии', 'sandals'), ('босоножки', 'sandals'),
  ('slippers', 'slippers'), ('тапочки', 'slippers'), ('сланцы', 'slippers'),
  ('bag', 'bag'), ('handbag', 'bag'), ('сумка', 'bag'), ('клатч', 'bag'),
  ('backpack', 'backpack'), ('рюкзак', 'backpack'),
  ('wallet', 'wallet'), ('кошелек', 'wallet'), ('кошелёк', 'wallet'),
  ('портмоне', 'wallet'),
  ('cap', 'cap'), ('baseball cap', 'cap'), ('кепка', 'cap'), ('бейсболка', 'cap'),
  ('beanie', 'beanie'), ('шапка', 'beanie'), ('бини', 'beanie'),
  ('hat', 'hat'), ('шляпа', 'hat'), ('панама', 'hat'),
  ('headwear', 'headwear'), ('головной убор', 'headwear'),
  ('belt', 'belt'), ('ремень', 'belt'), ('пояс', 'belt'),
  ('scarf', 'scarf'), ('шарф', 'scarf'), ('платок', 'scarf'),
  ('gloves', 'gloves'), ('перчатки', 'gloves'), ('варежки', 'gloves'),
  ('eyewear', 'eyewear'), ('sunglasses', 'eyewear'),
  ('очки', 'eyewear'), ('солнцезащитные очки', 'eyewear'),
  ('watch', 'watch'), ('wristwatch', 'watch'),
  ('часы', 'watch'), ('наручные часы', 'watch'),
  ('tie', 'tie'), ('necktie', 'tie'), ('bow tie', 'tie'),
  ('галстук', 'tie'), ('бабочка', 'tie'),
  ('accessory', 'accessory'), ('accessories', 'accessory'),
  ('аксессуар', 'accessory'),
  ('necklace', 'necklace'), ('pendant', 'necklace'),
  ('колье', 'necklace'), ('ожерелье', 'necklace'),
  ('подвеска', 'necklace'), ('цепочка', 'necklace'),
  ('ring', 'ring'), ('кольцо', 'ring'), ('перстень', 'ring'),
  ('bracelet', 'bracelet'), ('браслет', 'bracelet'),
  ('earrings', 'earrings'), ('серьги', 'earrings'),
  ('сережки', 'earrings'), ('серёжки', 'earrings'),
  ('brooch', 'brooch'), ('брошь', 'brooch')
on conflict (alias) do update
set category_code = excluded.category_code;

with category_schemas(category_code, attribute_keys) as (
  values
    ('t_shirt', array['material','pattern','fit','sleeve_length','collar']),
    ('tank_top', array['material','pattern','fit','sleeve_length','collar']),
    ('top', array['material','pattern','fit','sleeve_length','collar']),
    ('long_sleeve', array['material','pattern','fit','sleeve_length','collar']),
    ('polo', array['material','pattern','fit','sleeve_length','collar']),
    ('shirt', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('blouse', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('hoodie', array['material','pattern','fit','closure']),
    ('sweatshirt', array['material','pattern','fit','sleeve_length']),
    ('sweater', array['material','pattern','fit','sleeve_length','collar']),
    ('cardigan', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('turtleneck', array['material','pattern','fit','sleeve_length','collar']),
    ('jeans', array['material','fit','rise','closure']),
    ('trousers', array['material','pattern','fit','rise','closure']),
    ('joggers', array['material','pattern','fit','rise','closure']),
    ('leggings', array['material','pattern','fit','rise','closure']),
    ('shorts', array['material','pattern','fit','rise','closure']),
    ('skirt', array['material','pattern','fit','rise','closure']),
    ('jacket', array['material','fit','collar','closure','season']),
    ('blazer', array['material','fit','collar','closure','season']),
    ('puffer', array['material','fit','collar','closure','season']),
    ('coat', array['material','fit','collar','closure','season']),
    ('trench', array['material','fit','collar','closure','season']),
    ('vest', array['material','fit','collar','closure','season']),
    ('dress', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('jumpsuit', array['material','pattern','fit','sleeve_length','collar','closure']),
    ('underwear', array['material','pattern','fit']),
    ('swimwear', array['material','pattern','fit']),
    ('socks', array['material','pattern']),
    ('tights', array['material','pattern']),
    ('sneakers', array['material','pattern','closure','style']),
    ('boots', array['material','closure','season','style']),
    ('shoes', array['material','pattern','closure','style']),
    ('heels', array['material','pattern','closure','style']),
    ('loafers', array['material','pattern','closure','style']),
    ('sandals', array['material','pattern','closure','style']),
    ('slippers', array['material','pattern','closure','style']),
    ('bag', array['material','pattern','closure','style']),
    ('backpack', array['material','pattern','closure','style']),
    ('wallet', array['material','pattern','closure','style']),
    ('cap', array['material','pattern','season','style']),
    ('beanie', array['material','pattern','season','style']),
    ('hat', array['material','pattern','season','style']),
    ('headwear', array['material','pattern','season','style']),
    ('belt', array['material','closure','style']),
    ('scarf', array['material','pattern','season','style']),
    ('gloves', array['material','season','style']),
    ('eyewear', array['material','style']),
    ('watch', array['material','style']),
    ('tie', array['material','pattern','style']),
    ('accessory', array['material','pattern','style']),
    ('necklace', array['material','style']),
    ('ring', array['material','style']),
    ('bracelet', array['material','style']),
    ('earrings', array['material','style']),
    ('brooch', array['material','style'])
), expanded as (
  select category_code, attribute_key, ordinality::integer as position
  from category_schemas,
       unnest(attribute_keys) with ordinality as keys(attribute_key, ordinality)
)
insert into public.product_category_attribute_schemas (
  category_code, attribute_key, display_name, position
)
select
  category_code,
  attribute_key,
  case attribute_key
    when 'material' then 'Материал'
    when 'pattern' then 'Рисунок'
    when 'fit' then 'Крой'
    when 'sleeve_length' then 'Длина рукава'
    when 'collar' then 'Воротник'
    when 'rise' then 'Посадка'
    when 'closure' then 'Тип застёжки'
    when 'season' then 'Сезон'
    when 'style' then 'Стиль'
    else attribute_key
  end,
  position
from expanded
on conflict (category_code, attribute_key) do update
set display_name = excluded.display_name,
    position = excluded.position,
    updated_at = now();

update public.product_category_attribute_schemas
set options = case attribute_key
    when 'pattern' then '["solid","logo","striped","checked","floral","graphic","other"]'::jsonb
    when 'fit' then '["slim","regular","relaxed","oversized"]'::jsonb
    when 'sleeve_length' then '["sleeveless","short","three_quarter","long"]'::jsonb
    when 'collar' then '["round","v_neck","polo","shirt","stand","hood","none"]'::jsonb
    when 'rise' then '["low","mid","high"]'::jsonb
    when 'closure' then '["none","zip","buttons","laces","velcro","buckle","snap","magnetic","drawstring","hook"]'::jsonb
    when 'season' then '["all_season","summer","winter","demi"]'::jsonb
    when 'style' then '["casual","sport","classic","streetwear","business","evening","minimalist","vintage","statement","everyday","smart","luxury"]'::jsonb
    else options
  end,
  updated_at = now()
where attribute_key <> 'material';

with option_overrides(category_codes, attribute_key, options) as (
  values
    (array['sneakers','boots','shoes','heels','loafers','sandals','slippers'],
     'closure', '["none","laces","zip","velcro","buckle"]'::jsonb),
    (array['bag','backpack','wallet'],
     'closure', '["none","zip","snap","magnetic","drawstring","buckle"]'::jsonb),
    (array['necklace','ring','bracelet','earrings','brooch'],
     'style', '["minimalist","classic","vintage","statement","everyday","evening"]'::jsonb),
    (array['watch'],
     'style', '["classic","sport","casual","smart","luxury"]'::jsonb)
), expanded_options as (
  select category_code, attribute_key, options
  from option_overrides,
       unnest(category_codes) as category_code
)
update public.product_category_attribute_schemas schema
set options = expanded_options.options, updated_at = now()
from expanded_options
where schema.category_code = expanded_options.category_code
  and schema.attribute_key = expanded_options.attribute_key;

-- Keep the server catalog aware of category-specific material values. The app
-- remains the presentation source, while these IDs make admin/RPC validation
-- and future remote catalog loading deterministic.
update public.product_category_attribute_schemas
set options = to_jsonb(array[
  'cotton','wool','cashmere','linen','silk','viscose','denim','leather',
  'polyester','acrylic','elastane','mixed'
]::text[]), updated_at = now()
where attribute_key = 'material';

with material_groups(category_codes, material_options) as (
  values
    (array['sweater','cardigan','turtleneck'],
     array['cotton','wool','cashmere','viscose','polyester','acrylic','mixed']),
    (array['jacket','blazer','puffer','coat','trench','vest'],
     array['cotton','wool','denim','leather','faux_leather','suede','polyester','nylon','down','fur','mixed']),
    (array['sneakers','boots','shoes','heels','loafers','sandals','slippers'],
     array['leather','faux_leather','suede','textile','canvas','rubber','synthetic','mixed']),
    (array['bag','backpack','wallet'],
     array['leather','faux_leather','suede','textile','canvas','nylon','polyester','plastic','metal','mixed']),
    (array['cap','beanie','hat','headwear','scarf','gloves'],
     array['cotton','wool','cashmere','linen','silk','viscose','polyester','acrylic','leather','fur','mixed']),
    (array['belt'],
     array['leather','faux_leather','suede','textile','metal','plastic','mixed']),
    (array['eyewear'],
     array['metal','steel','titanium','plastic','acetate','mixed']),
    (array['watch'],
     array['steel','metal','titanium','gold','silver','leather','ceramic','plastic','textile','mixed']),
    (array['tie'],
     array['silk','cotton','wool','linen','polyester','mixed']),
    (array['necklace','ring','bracelet','earrings','brooch'],
     array['gold','silver','steel','metal','titanium','platinum','ceramic','leather','textile','plastic','wood','glass','gemstone','pearls','mixed']),
    (array['accessory'],
     array['cotton','wool','cashmere','linen','silk','viscose','denim','leather','faux_leather','suede','polyester','acrylic','elastane','nylon','textile','canvas','rubber','synthetic','down','fur','metal','steel','titanium','gold','silver','platinum','ceramic','plastic','acetate','wood','glass','gemstone','pearls','mixed'])
), expanded as (
  select category_code, material_options
  from material_groups,
       unnest(category_codes) as category_code
)
update public.product_category_attribute_schemas schema
set options = to_jsonb(expanded.material_options), updated_at = now()
from expanded
where schema.category_code = expanded.category_code
  and schema.attribute_key = 'material';

update public.product_category_attribute_schemas
set options = options || '["unknown"]'::jsonb,
    updated_at = now()
where attribute_key = 'material'
  and not options @> '["unknown"]'::jsonb;

-- Recover previously collapsed analyzer output using the retained fine-grained
-- item_type first. Seller-selected canonical values are otherwise preserved.
update public.products p
set normalized_category = a.category_code
from public.product_category_aliases a
where a.alias = lower(btrim(coalesce(p.item_type, '')))
  and p.item_type is not null
  and btrim(p.item_type) <> ''
  and p.normalized_category is distinct from a.category_code;

update public.products
set normalized_category = 'sweater', item_type = 'sweater'
where normalized_category = 'hoodie'
  and lower(concat_ws(' ', title, description)) ~ '(свитер|джемпер|пуловер)';

do $$
declare
  missing_schema text;
begin
  select string_agg(c.code, ', ' order by c.sort_order)
  into missing_schema
  from public.product_categories c
  where c.is_active
    and not exists (
      select 1
      from public.product_category_attribute_schemas s
      where s.category_code = c.code
    );
  if missing_schema is not null then
    raise exception 'Active product categories without schemas: %', missing_schema;
  end if;
  if public.normalize_product_category('свитер') is distinct from 'sweater' then
    raise exception 'Sweater alias is not canonical';
  end if;
  if public.normalize_product_category('браслет') is distinct from 'bracelet' then
    raise exception 'Bracelet alias is not canonical';
  end if;
end;
$$;
