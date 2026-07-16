import 'package:flutter/material.dart';

class CatalogOption {
  const CatalogOption(this.id, this.name, {this.color});

  final String id;
  final String name;
  final Color? color;
}

class ListingAttributeDefinition {
  const ListingAttributeDefinition({
    required this.id,
    required this.label,
    required this.options,
  });

  final String id;
  final String label;
  final List<CatalogOption> options;
}

class CatalogOptionGroup {
  const CatalogOptionGroup(this.id, this.name, this.options);

  final String id;
  final String name;
  final List<CatalogOption> options;
}

class ListingCategoryPath {
  const ListingCategoryPath(this.category, this.subcategory, this.itemType);

  final String category;
  final String subcategory;
  final String itemType;
}

abstract final class ListingCatalogs {
  static const sections = <CatalogOption>[
    CatalogOption('women', 'Женское'),
    CatalogOption('men', 'Мужское'),
    CatalogOption('kids', 'Детское'),
    CatalogOption('unisex', 'Унисекс'),
  ];

  static const categories = <CatalogOption>[
    CatalogOption('clothing', 'Одежда'),
    CatalogOption('shoes', 'Обувь'),
    CatalogOption('accessories', 'Аксессуары'),
    CatalogOption('jewelry', 'Украшения'),
  ];

  static const clothingCategories = <CatalogOption>[
    CatalogOption('t_shirt', 'Футболка'),
    CatalogOption('tank_top', 'Майка'),
    CatalogOption('top', 'Топ'),
    CatalogOption('long_sleeve', 'Лонгслив'),
    CatalogOption('polo', 'Поло'),
    CatalogOption('shirt', 'Рубашка'),
    CatalogOption('blouse', 'Блузка'),
    CatalogOption('hoodie', 'Худи'),
    CatalogOption('sweatshirt', 'Свитшот'),
    CatalogOption('sweater', 'Свитер / джемпер'),
    CatalogOption('cardigan', 'Кардиган'),
    CatalogOption('turtleneck', 'Водолазка'),
    CatalogOption('jeans', 'Джинсы'),
    CatalogOption('trousers', 'Брюки'),
    CatalogOption('joggers', 'Джоггеры'),
    CatalogOption('leggings', 'Легинсы'),
    CatalogOption('shorts', 'Шорты'),
    CatalogOption('skirt', 'Юбка'),
    CatalogOption('jacket', 'Куртка'),
    CatalogOption('blazer', 'Пиджак'),
    CatalogOption('puffer', 'Пуховик'),
    CatalogOption('coat', 'Пальто'),
    CatalogOption('trench', 'Тренч / плащ'),
    CatalogOption('vest', 'Жилет'),
    CatalogOption('dress', 'Платье'),
    CatalogOption('jumpsuit', 'Комбинезон'),
    CatalogOption('underwear', 'Нижнее бельё'),
    CatalogOption('swimwear', 'Купальник / плавки'),
    CatalogOption('socks', 'Носки'),
    CatalogOption('tights', 'Колготки'),
  ];

  static const footwearCategories = <CatalogOption>[
    CatalogOption('sneakers', 'Кроссовки'),
    CatalogOption('boots', 'Ботинки'),
    CatalogOption('shoes', 'Туфли'),
    CatalogOption('heels', 'Туфли на каблуке'),
    CatalogOption('loafers', 'Лоферы'),
    CatalogOption('sandals', 'Сандалии'),
    CatalogOption('slippers', 'Домашняя обувь'),
  ];

  static const bagCategories = <CatalogOption>[
    CatalogOption('bag', 'Сумка'),
    CatalogOption('backpack', 'Рюкзак'),
    CatalogOption('wallet', 'Кошелёк'),
  ];

  static const headwearCategories = <CatalogOption>[
    CatalogOption('cap', 'Кепка / бейсболка'),
    CatalogOption('beanie', 'Шапка'),
    CatalogOption('hat', 'Шляпа / панама'),
    CatalogOption('headwear', 'Другой головной убор'),
  ];

  static const accessoryCategories = <CatalogOption>[
    CatalogOption('belt', 'Ремень'),
    CatalogOption('scarf', 'Шарф / платок'),
    CatalogOption('gloves', 'Перчатки'),
    CatalogOption('eyewear', 'Очки'),
    CatalogOption('watch', 'Часы'),
    CatalogOption('tie', 'Галстук / бабочка'),
    CatalogOption('accessory', 'Аксессуар'),
  ];

  static const jewelryCategories = <CatalogOption>[
    CatalogOption('necklace', 'Колье / подвеска'),
    CatalogOption('ring', 'Кольцо'),
    CatalogOption('bracelet', 'Браслет'),
    CatalogOption('earrings', 'Серьги'),
    CatalogOption('brooch', 'Брошь'),
  ];

  /// Buyer-facing categories are grouped in the picker so the expanded
  /// taxonomy stays scannable without changing the surrounding form design.
  static const finalCategoryGroups = <CatalogOptionGroup>[
    CatalogOptionGroup('clothing', 'Одежда', clothingCategories),
    CatalogOptionGroup('shoes', 'Обувь', footwearCategories),
    CatalogOptionGroup('bags', 'Сумки и рюкзаки', bagCategories),
    CatalogOptionGroup('headwear', 'Головные уборы', headwearCategories),
    CatalogOptionGroup('accessories', 'Аксессуары', accessoryCategories),
    CatalogOptionGroup('jewelry', 'Украшения', jewelryCategories),
  ];

  /// Flat projection retained for normalization, search and compatibility.
  static const finalCategories = <CatalogOption>[
    ...clothingCategories,
    ...footwearCategories,
    ...bagCategories,
    ...headwearCategories,
    ...accessoryCategories,
    ...jewelryCategories,
  ];

  static const subcategoriesByCategory = <String, List<CatalogOption>>{
    'clothing': [
      CatalogOption('tops', 'Верх'),
      CatalogOption('bottoms', 'Низ'),
      CatalogOption('outerwear', 'Верхняя одежда'),
      CatalogOption('dresses', 'Платья и комбинезоны'),
      CatalogOption('basics', 'Бельё, носки и купальники'),
    ],
    'shoes': [CatalogOption('shoes_all', 'Вся обувь')],
    'accessories': [CatalogOption('accessories_all', 'Все аксессуары')],
    'jewelry': [CatalogOption('jewelry_all', 'Все украшения')],
  };

  static const itemTypesBySubcategory = <String, List<CatalogOption>>{
    'tops': [
      CatalogOption('hoodie', 'Худи'),
      CatalogOption('sweatshirt', 'Свитшот'),
      CatalogOption('tshirt', 'Футболка'),
      CatalogOption('tank_top', 'Майка'),
      CatalogOption('long_sleeve', 'Лонгслив'),
      CatalogOption('polo', 'Поло'),
      CatalogOption('shirt', 'Рубашка'),
      CatalogOption('blouse', 'Блузка'),
      CatalogOption('sweater', 'Свитер'),
      CatalogOption('cardigan', 'Кардиган'),
      CatalogOption('turtleneck', 'Водолазка'),
      CatalogOption('top', 'Топ'),
    ],
    'bottoms': [
      CatalogOption('jeans', 'Джинсы'),
      CatalogOption('trousers', 'Брюки'),
      CatalogOption('joggers', 'Джоггеры'),
      CatalogOption('leggings', 'Легинсы'),
      CatalogOption('shorts', 'Шорты'),
      CatalogOption('skirt', 'Юбка'),
    ],
    'outerwear': [
      CatalogOption('jacket', 'Куртка'),
      CatalogOption('blazer', 'Пиджак'),
      CatalogOption('puffer', 'Пуховик'),
      CatalogOption('coat', 'Пальто'),
      CatalogOption('trench', 'Тренч / плащ'),
      CatalogOption('vest', 'Жилет'),
    ],
    'dresses': [
      CatalogOption('dress', 'Платье'),
      CatalogOption('jumpsuit', 'Комбинезон'),
    ],
    'basics': [
      CatalogOption('underwear', 'Нижнее бельё'),
      CatalogOption('swimwear', 'Купальник / плавки'),
      CatalogOption('socks', 'Носки'),
      CatalogOption('tights', 'Колготки'),
    ],
    'shoes_all': [
      CatalogOption('sneakers', 'Кроссовки'),
      CatalogOption('boots', 'Ботинки'),
      CatalogOption('shoes', 'Туфли'),
      CatalogOption('heels', 'Туфли на каблуке'),
      CatalogOption('loafers', 'Лоферы'),
      CatalogOption('sandals', 'Сандалии'),
      CatalogOption('slippers', 'Домашняя обувь'),
    ],
    'accessories_all': [
      CatalogOption('bag', 'Сумка'),
      CatalogOption('backpack', 'Рюкзак'),
      CatalogOption('wallet', 'Кошелёк'),
      CatalogOption('belt', 'Ремень'),
      CatalogOption('scarf', 'Шарф'),
      CatalogOption('gloves', 'Перчатки'),
      CatalogOption('cap', 'Кепка / бейсболка'),
      CatalogOption('beanie', 'Шапка'),
      CatalogOption('hat', 'Шляпа / панама'),
      CatalogOption('headwear', 'Другой головной убор'),
      CatalogOption('eyewear', 'Очки'),
      CatalogOption('watch', 'Часы'),
      CatalogOption('tie', 'Галстук / бабочка'),
      CatalogOption('accessory', 'Другой аксессуар'),
    ],
    'jewelry_all': [
      CatalogOption('necklace', 'Подвеска'),
      CatalogOption('ring', 'Кольцо'),
      CatalogOption('bracelet', 'Браслет'),
      CatalogOption('earrings', 'Серьги'),
      CatalogOption('brooch', 'Брошь'),
    ],
  };

  static const genders = <CatalogOption>[
    CatalogOption('female', 'Женский'),
    CatalogOption('male', 'Мужской'),
    CatalogOption('unisex', 'Унисекс'),
    CatalogOption('kids', 'Детский'),
  ];

  static const colors = <CatalogOption>[
    CatalogOption('black', 'Чёрный', color: Color(0xFF111111)),
    CatalogOption('white', 'Белый', color: Color(0xFFFFFFFF)),
    CatalogOption('gray', 'Серый', color: Color(0xFF8B8B90)),
    CatalogOption('beige', 'Бежевый', color: Color(0xFFD8C4A8)),
    CatalogOption('cream', 'Кремовый', color: Color(0xFFF3E8CF)),
    CatalogOption('brown', 'Коричневый', color: Color(0xFF80543C)),
    CatalogOption('blue', 'Синий', color: Color(0xFF3567B7)),
    CatalogOption('dark_blue', 'Тёмно-синий', color: Color(0xFF172A4D)),
    CatalogOption('light_blue', 'Голубой', color: Color(0xFF8BC4E8)),
    CatalogOption('green', 'Зелёный', color: Color(0xFF3A8C5B)),
    CatalogOption('olive', 'Оливковый', color: Color(0xFF74733D)),
    CatalogOption('red', 'Красный', color: Color(0xFFD64545)),
    CatalogOption('burgundy', 'Бордовый', color: Color(0xFF6F263D)),
    CatalogOption('pink', 'Розовый', color: Color(0xFFE794B8)),
    CatalogOption('purple', 'Фиолетовый', color: Color(0xFF845CB2)),
    CatalogOption('yellow', 'Жёлтый', color: Color(0xFFF0C83C)),
    CatalogOption('orange', 'Оранжевый', color: Color(0xFFE9893A)),
    CatalogOption('multicolor', 'Многоцветный'),
  ];

  static const brands = <CatalogOption>[
    CatalogOption('no_brand', 'Без бренда'),
    CatalogOption('nike', 'Nike'),
    CatalogOption('adidas', 'Adidas'),
    CatalogOption('puma', 'Puma'),
    CatalogOption('zara', 'Zara'),
    CatalogOption('hm', 'H&M'),
    CatalogOption('uniqlo', 'Uniqlo'),
    CatalogOption('carhartt', 'Carhartt'),
    CatalogOption('stussy', 'Stüssy'),
    CatalogOption('new_balance', 'New Balance'),
    CatalogOption('the_north_face', 'The North Face'),
    CatalogOption('calvin_klein', 'Calvin Klein'),
    CatalogOption('tommy_hilfiger', 'Tommy Hilfiger'),
    CatalogOption('levis', "Levi's"),
    CatalogOption('other_brand', 'Другой бренд'),
  ];

  static const materials = <CatalogOption>[
    CatalogOption('cotton', 'Хлопок'),
    CatalogOption('wool', 'Шерсть'),
    CatalogOption('cashmere', 'Кашемир'),
    CatalogOption('linen', 'Лён'),
    CatalogOption('silk', 'Шёлк'),
    CatalogOption('viscose', 'Вискоза'),
    CatalogOption('denim', 'Деним'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('faux_leather', 'Экокожа'),
    CatalogOption('suede', 'Замша'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('acrylic', 'Акрил'),
    CatalogOption('elastane', 'Эластан'),
    CatalogOption('nylon', 'Нейлон'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('canvas', 'Канвас'),
    CatalogOption('rubber', 'Резина'),
    CatalogOption('synthetic', 'Синтетика'),
    CatalogOption('down', 'Пух'),
    CatalogOption('fur', 'Мех'),
    CatalogOption('metal', 'Металл'),
    CatalogOption('steel', 'Нержавеющая сталь'),
    CatalogOption('titanium', 'Титан'),
    CatalogOption('gold', 'Золото'),
    CatalogOption('silver', 'Серебро'),
    CatalogOption('platinum', 'Платина'),
    CatalogOption('ceramic', 'Керамика'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('acetate', 'Ацетат'),
    CatalogOption('wood', 'Дерево'),
    CatalogOption('glass', 'Стекло'),
    CatalogOption('gemstone', 'Натуральный камень'),
    CatalogOption('pearls', 'Жемчуг'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const apparelMaterials = <CatalogOption>[
    CatalogOption('cotton', 'Хлопок'),
    CatalogOption('wool', 'Шерсть'),
    CatalogOption('cashmere', 'Кашемир'),
    CatalogOption('linen', 'Лён'),
    CatalogOption('silk', 'Шёлк'),
    CatalogOption('viscose', 'Вискоза'),
    CatalogOption('denim', 'Деним'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('acrylic', 'Акрил'),
    CatalogOption('elastane', 'Эластан'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const knitwearMaterials = <CatalogOption>[
    CatalogOption('cotton', 'Хлопок'),
    CatalogOption('wool', 'Шерсть'),
    CatalogOption('cashmere', 'Кашемир'),
    CatalogOption('viscose', 'Вискоза'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('acrylic', 'Акрил'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const outerwearMaterials = <CatalogOption>[
    CatalogOption('cotton', 'Хлопок'),
    CatalogOption('wool', 'Шерсть'),
    CatalogOption('denim', 'Деним'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('faux_leather', 'Экокожа'),
    CatalogOption('suede', 'Замша'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('nylon', 'Нейлон'),
    CatalogOption('down', 'Пух'),
    CatalogOption('fur', 'Мех'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const footwearMaterials = <CatalogOption>[
    CatalogOption('leather', 'Кожа'),
    CatalogOption('faux_leather', 'Экокожа'),
    CatalogOption('suede', 'Замша'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('canvas', 'Канвас'),
    CatalogOption('rubber', 'Резина'),
    CatalogOption('synthetic', 'Синтетика'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const bagMaterials = <CatalogOption>[
    CatalogOption('leather', 'Кожа'),
    CatalogOption('faux_leather', 'Экокожа'),
    CatalogOption('suede', 'Замша'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('canvas', 'Канвас'),
    CatalogOption('nylon', 'Нейлон'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('metal', 'Металл'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const textileAccessoryMaterials = <CatalogOption>[
    CatalogOption('cotton', 'Хлопок'),
    CatalogOption('wool', 'Шерсть'),
    CatalogOption('cashmere', 'Кашемир'),
    CatalogOption('linen', 'Лён'),
    CatalogOption('silk', 'Шёлк'),
    CatalogOption('viscose', 'Вискоза'),
    CatalogOption('polyester', 'Полиэстер'),
    CatalogOption('acrylic', 'Акрил'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('fur', 'Мех'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const beltMaterials = <CatalogOption>[
    CatalogOption('leather', 'Кожа'),
    CatalogOption('faux_leather', 'Экокожа'),
    CatalogOption('suede', 'Замша'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('metal', 'Металл'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const eyewearMaterials = <CatalogOption>[
    CatalogOption('metal', 'Металл'),
    CatalogOption('steel', 'Нержавеющая сталь'),
    CatalogOption('titanium', 'Титан'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('acetate', 'Ацетат'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const watchMaterials = <CatalogOption>[
    CatalogOption('steel', 'Нержавеющая сталь'),
    CatalogOption('metal', 'Металл'),
    CatalogOption('titanium', 'Титан'),
    CatalogOption('gold', 'Золото'),
    CatalogOption('silver', 'Серебро'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('ceramic', 'Керамика'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const jewelryMaterials = <CatalogOption>[
    CatalogOption('gold', 'Золото'),
    CatalogOption('silver', 'Серебро'),
    CatalogOption('steel', 'Нержавеющая сталь'),
    CatalogOption('metal', 'Металл'),
    CatalogOption('titanium', 'Титан'),
    CatalogOption('platinum', 'Платина'),
    CatalogOption('ceramic', 'Керамика'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('textile', 'Текстиль'),
    CatalogOption('plastic', 'Пластик'),
    CatalogOption('wood', 'Дерево'),
    CatalogOption('glass', 'Стекло'),
    CatalogOption('gemstone', 'Натуральный камень'),
    CatalogOption('pearls', 'Жемчуг'),
    CatalogOption('mixed', 'Смешанный состав'),
    CatalogOption('unknown', 'Не знаю'),
  ];

  static const patterns = <CatalogOption>[
    CatalogOption('solid', 'Однотонный'),
    CatalogOption('logo', 'Логотип'),
    CatalogOption('striped', 'Полоска'),
    CatalogOption('checked', 'Клетка'),
    CatalogOption('floral', 'Цветочный'),
    CatalogOption('graphic', 'Рисунок'),
    CatalogOption('other', 'Другой'),
  ];

  static const seasons = <CatalogOption>[
    CatalogOption('all_season', 'Всесезон'),
    CatalogOption('summer', 'Лето'),
    CatalogOption('winter', 'Зима'),
    CatalogOption('demi', 'Демисезон'),
  ];

  static const styles = <CatalogOption>[
    CatalogOption('casual', 'Повседневный'),
    CatalogOption('sport', 'Спортивный'),
    CatalogOption('classic', 'Классический'),
    CatalogOption('streetwear', 'Стритвир'),
    CatalogOption('business', 'Деловой'),
    CatalogOption('evening', 'Вечерний'),
    CatalogOption('minimalist', 'Минимализм'),
    CatalogOption('vintage', 'Винтажный'),
    CatalogOption('statement', 'Акцентный'),
    CatalogOption('everyday', 'На каждый день'),
    CatalogOption('smart', 'Смарт-часы'),
    CatalogOption('luxury', 'Премиальный'),
  ];

  static const jewelryStyles = <CatalogOption>[
    CatalogOption('minimalist', 'Минимализм'),
    CatalogOption('classic', 'Классический'),
    CatalogOption('vintage', 'Винтажный'),
    CatalogOption('statement', 'Акцентный'),
    CatalogOption('everyday', 'На каждый день'),
    CatalogOption('evening', 'Вечерний'),
  ];

  static const watchStyles = <CatalogOption>[
    CatalogOption('classic', 'Классические'),
    CatalogOption('sport', 'Спортивные'),
    CatalogOption('casual', 'Повседневные'),
    CatalogOption('smart', 'Смарт-часы'),
    CatalogOption('luxury', 'Премиальные'),
  ];

  static const fits = <CatalogOption>[
    CatalogOption('slim', 'Облегающий'),
    CatalogOption('regular', 'Прямой'),
    CatalogOption('relaxed', 'Свободный'),
    CatalogOption('oversized', 'Оверсайз'),
  ];

  static const sleeveLengths = <CatalogOption>[
    CatalogOption('sleeveless', 'Без рукавов'),
    CatalogOption('short', 'Короткий рукав'),
    CatalogOption('three_quarter', 'Рукав 3/4'),
    CatalogOption('long', 'Длинный рукав'),
  ];

  static const closures = <CatalogOption>[
    CatalogOption('none', 'Без застёжки'),
    CatalogOption('zip', 'Молния'),
    CatalogOption('buttons', 'Пуговицы'),
    CatalogOption('laces', 'Шнуровка'),
    CatalogOption('velcro', 'Липучка'),
    CatalogOption('buckle', 'Пряжка'),
    CatalogOption('snap', 'Кнопка'),
    CatalogOption('magnetic', 'Магнитная'),
    CatalogOption('drawstring', 'Кулиска'),
    CatalogOption('hook', 'Крючок'),
  ];

  static const footwearClosures = <CatalogOption>[
    CatalogOption('none', 'Без застёжки'),
    CatalogOption('laces', 'Шнуровка'),
    CatalogOption('zip', 'Молния'),
    CatalogOption('velcro', 'Липучка'),
    CatalogOption('buckle', 'Пряжка'),
  ];

  static const bagClosures = <CatalogOption>[
    CatalogOption('none', 'Без застёжки'),
    CatalogOption('zip', 'Молния'),
    CatalogOption('snap', 'Кнопка'),
    CatalogOption('magnetic', 'Магнитная'),
    CatalogOption('drawstring', 'Кулиска'),
    CatalogOption('buckle', 'Пряжка'),
  ];

  static const collars = <CatalogOption>[
    CatalogOption('round', 'Круглый'),
    CatalogOption('v_neck', 'V-образный'),
    CatalogOption('polo', 'Поло'),
    CatalogOption('shirt', 'Рубашечный'),
    CatalogOption('stand', 'Стойка'),
    CatalogOption('hood', 'Капюшон'),
    CatalogOption('none', 'Без воротника'),
  ];

  static const rises = <CatalogOption>[
    CatalogOption('low', 'Низкая'),
    CatalogOption('mid', 'Средняя'),
    CatalogOption('high', 'Высокая'),
  ];

  static const categoryAttributeSchemas =
      <String, List<ListingAttributeDefinition>>{
        't_shirt': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'sleeve_length',
            label: 'Длина рукава',
            options: sleeveLengths,
          ),
          ListingAttributeDefinition(
            id: 'collar',
            label: 'Воротник',
            options: collars,
          ),
        ],
        'hoodie': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'shirt': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'sleeve_length',
            label: 'Длина рукава',
            options: sleeveLengths,
          ),
          ListingAttributeDefinition(
            id: 'collar',
            label: 'Воротник',
            options: collars,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'jacket': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'collar',
            label: 'Воротник',
            options: collars,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
          ListingAttributeDefinition(
            id: 'season',
            label: 'Сезон',
            options: seasons,
          ),
        ],
        'jeans': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'rise',
            label: 'Посадка',
            options: rises,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'trousers': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'rise',
            label: 'Посадка',
            options: rises,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'dress': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'sleeve_length',
            label: 'Длина рукава',
            options: sleeveLengths,
          ),
          ListingAttributeDefinition(
            id: 'collar',
            label: 'Воротник',
            options: collars,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'skirt': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'rise',
            label: 'Посадка',
            options: rises,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
        ],
        'sneakers': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'boots': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
          ListingAttributeDefinition(
            id: 'season',
            label: 'Сезон',
            options: seasons,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'bag': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'accessory': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'sweatshirt': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(id: 'fit', label: 'Крой', options: fits),
          ListingAttributeDefinition(
            id: 'sleeve_length',
            label: 'Длина рукава',
            options: sleeveLengths,
          ),
        ],
        'underwear': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'fit',
            label: 'Посадка',
            options: fits,
          ),
        ],
        'socks': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
        ],
        'headwear': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'season',
            label: 'Сезон',
            options: seasons,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'belt': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'closure',
            label: 'Тип застёжки',
            options: closures,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'scarf': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'season',
            label: 'Сезон',
            options: seasons,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'gloves': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'season',
            label: 'Сезон',
            options: seasons,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'eyewear': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал оправы',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'watch': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал корпуса / ремешка',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'tie': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'pattern',
            label: 'Рисунок',
            options: patterns,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: styles,
          ),
        ],
        'bracelet': [
          ListingAttributeDefinition(
            id: 'material',
            label: 'Материал',
            options: materials,
          ),
          ListingAttributeDefinition(
            id: 'style',
            label: 'Стиль',
            options: jewelryStyles,
          ),
        ],
      };

  static const categoryAliases = <String, String>{
    't_shirt': 't_shirt',
    'tshirt': 't_shirt',
    't-shirt': 't_shirt',
    'tee': 't_shirt',
    'футболка': 't_shirt',
    'майка': 'tank_top',
    'танк топ': 'tank_top',
    'топ': 'top',
    'лонгслив': 'long_sleeve',
    'поло': 'polo',
    'блузка': 'blouse',
    'blouse': 'blouse',
    'худи': 'hoodie',
    'толстовка с капюшоном': 'hoodie',
    'толстовка': 'sweatshirt',
    'свитшот': 'sweatshirt',
    'crewneck': 'sweatshirt',
    'свитер': 'sweater',
    'джемпер': 'sweater',
    'пуловер': 'sweater',
    'pullover': 'sweater',
    'кардиган': 'cardigan',
    'водолазка': 'turtleneck',
    'рубашка': 'shirt',
    'куртка': 'jacket',
    'пиджак': 'blazer',
    'блейзер': 'blazer',
    'пуховик': 'puffer',
    'пальто': 'coat',
    'тренч': 'trench',
    'плащ': 'trench',
    'жилет': 'vest',
    'безрукавка': 'vest',
    'джинсы': 'jeans',
    'брюки': 'trousers',
    'штаны': 'trousers',
    'джоггеры': 'joggers',
    'спортивные штаны': 'joggers',
    'легинсы': 'leggings',
    'лосины': 'leggings',
    'шорты': 'shorts',
    'платье': 'dress',
    'сарафан': 'dress',
    'комбинезон': 'jumpsuit',
    'нижнее белье': 'underwear',
    'белье': 'underwear',
    'купальник': 'swimwear',
    'плавки': 'swimwear',
    'носки': 'socks',
    'гольфы': 'socks',
    'колготки': 'tights',
    'юбка': 'skirt',
    'кроссовки': 'sneakers',
    'кеды': 'sneakers',
    'ботинки': 'boots',
    'сапоги': 'boots',
    'туфли': 'shoes',
    'каблуки': 'heels',
    'туфли на каблуке': 'heels',
    'лоферы': 'loafers',
    'мокасины': 'loafers',
    'сандалии': 'sandals',
    'босоножки': 'sandals',
    'тапочки': 'slippers',
    'сланцы': 'slippers',
    'сумка': 'bag',
    'клатч': 'bag',
    'рюкзак': 'backpack',
    'кошелек': 'wallet',
    'кошелёк': 'wallet',
    'портмоне': 'wallet',
    'головной убор': 'headwear',
    'шапка': 'beanie',
    'бини': 'beanie',
    'кепка': 'cap',
    'бейсболка': 'cap',
    'панама': 'hat',
    'шляпа': 'hat',
    'ремень': 'belt',
    'пояс': 'belt',
    'шарф': 'scarf',
    'платок': 'scarf',
    'перчатки': 'gloves',
    'варежки': 'gloves',
    'очки': 'eyewear',
    'солнцезащитные очки': 'eyewear',
    'часы': 'watch',
    'наручные часы': 'watch',
    'галстук': 'tie',
    'бабочка': 'tie',
    'колье': 'necklace',
    'ожерелье': 'necklace',
    'подвеска': 'necklace',
    'цепочка': 'necklace',
    'кольцо': 'ring',
    'перстень': 'ring',
    'браслет': 'bracelet',
    'серьги': 'earrings',
    'сережки': 'earrings',
    'серёжки': 'earrings',
    'брошь': 'brooch',
    'аксессуар': 'accessory',
    'украшение': 'accessory',
  };

  static const categorySchemaAliases = <String, String>{
    'tank_top': 't_shirt',
    'top': 't_shirt',
    'long_sleeve': 't_shirt',
    'polo': 't_shirt',
    'blouse': 'shirt',
    'sweater': 't_shirt',
    'cardigan': 'shirt',
    'turtleneck': 't_shirt',
    'blazer': 'jacket',
    'puffer': 'jacket',
    'coat': 'jacket',
    'trench': 'jacket',
    'vest': 'jacket',
    'joggers': 'trousers',
    'leggings': 'trousers',
    'shorts': 'trousers',
    'jumpsuit': 'dress',
    'swimwear': 'underwear',
    'tights': 'socks',
    'shoes': 'sneakers',
    'heels': 'sneakers',
    'loafers': 'sneakers',
    'sandals': 'sneakers',
    'slippers': 'sneakers',
    'backpack': 'bag',
    'wallet': 'bag',
    'cap': 'headwear',
    'beanie': 'headwear',
    'hat': 'headwear',
    'necklace': 'bracelet',
    'ring': 'bracelet',
    'earrings': 'bracelet',
    'brooch': 'bracelet',
  };

  static String normalizeCategory(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('ё', 'е');
    if (finalCategories.any((option) => option.id == value)) return value;
    return categoryAliases[value] ?? '';
  }

  static List<ListingAttributeDefinition> attributesFor(String category) {
    final normalized = normalizeCategory(category);
    final schemaKey = categorySchemaAliases[normalized] ?? normalized;
    final definitions = categoryAttributeSchemas[schemaKey] ?? const [];
    return definitions
        .map(
          (definition) => ListingAttributeDefinition(
            id: definition.id,
            label: definition.label,
            options: _optionsFor(normalized, definition),
          ),
        )
        .toList(growable: false);
  }

  static List<CatalogOption> _optionsFor(
    String category,
    ListingAttributeDefinition definition,
  ) {
    return switch (definition.id) {
      'material' => materialsFor(category),
      'closure' when isShoeCategory(category) => footwearClosures,
      'closure' when const {'bag', 'backpack', 'wallet'}.contains(category) =>
        bagClosures,
      'style' when isJewelryCategory(category) => jewelryStyles,
      'style' when category == 'watch' => watchStyles,
      _ => definition.options,
    };
  }

  static List<CatalogOption> materialsFor(String category) {
    final normalized = normalizeCategory(category);
    if (const {'sweater', 'cardigan', 'turtleneck'}.contains(normalized)) {
      return knitwearMaterials;
    }
    if (const {
      'jacket',
      'blazer',
      'puffer',
      'coat',
      'trench',
      'vest',
    }.contains(normalized)) {
      return outerwearMaterials;
    }
    if (isShoeCategory(normalized)) return footwearMaterials;
    if (const {'bag', 'backpack', 'wallet'}.contains(normalized)) {
      return bagMaterials;
    }
    if (const {
      'cap',
      'beanie',
      'hat',
      'headwear',
      'scarf',
      'gloves',
    }.contains(normalized)) {
      return textileAccessoryMaterials;
    }
    if (normalized == 'belt') return beltMaterials;
    if (normalized == 'eyewear') return eyewearMaterials;
    if (normalized == 'watch') return watchMaterials;
    if (isJewelryCategory(normalized)) return jewelryMaterials;
    if (normalized == 'accessory') return materials;
    if (normalized == 'tie') {
      return const [
        CatalogOption('silk', 'Шёлк'),
        CatalogOption('cotton', 'Хлопок'),
        CatalogOption('wool', 'Шерсть'),
        CatalogOption('linen', 'Лён'),
        CatalogOption('polyester', 'Полиэстер'),
        CatalogOption('mixed', 'Смешанный состав'),
        CatalogOption('unknown', 'Не знаю'),
      ];
    }
    return apparelMaterials;
  }

  static bool isShoeCategory(String category) => const {
    'sneakers',
    'boots',
    'shoes',
    'heels',
    'loafers',
    'sandals',
    'slippers',
  }.contains(normalizeCategory(category));

  static bool isJewelryCategory(String category) => const {
    'necklace',
    'ring',
    'bracelet',
    'earrings',
    'brooch',
  }.contains(normalizeCategory(category));

  static bool isTopCategory(String category) =>
      legacyPathFor(category).subcategory == 'tops';

  static bool isBottomCategory(String category) =>
      legacyPathFor(category).subcategory == 'bottoms';

  static bool usesOneSize(String category) {
    final normalized = normalizeCategory(category);
    return const {
      'bag',
      'backpack',
      'wallet',
      'cap',
      'beanie',
      'hat',
      'headwear',
      'belt',
      'scarf',
      'gloves',
      'eyewear',
      'watch',
      'tie',
      'accessory',
      'necklace',
      'ring',
      'bracelet',
      'earrings',
      'brooch',
    }.contains(normalized);
  }

  static List<CatalogOption> sizeOptionsFor(String category) {
    if (isShoeCategory(category)) return shoeSizes;
    if (usesOneSize(category)) return oneSizeOptions;
    return universalSizes;
  }

  static ListingCategoryPath legacyPathFor(String category) {
    final normalized = normalizeCategory(category);
    final itemType = normalized == 't_shirt' ? 'tshirt' : normalized;
    if (const {
      't_shirt',
      'tank_top',
      'top',
      'long_sleeve',
      'polo',
      'shirt',
      'blouse',
      'hoodie',
      'sweatshirt',
      'sweater',
      'cardigan',
      'turtleneck',
    }.contains(normalized)) {
      return ListingCategoryPath('clothing', 'tops', itemType);
    }
    if (const {
      'jeans',
      'trousers',
      'joggers',
      'leggings',
      'shorts',
      'skirt',
    }.contains(normalized)) {
      return ListingCategoryPath('clothing', 'bottoms', itemType);
    }
    if (const {
      'jacket',
      'blazer',
      'puffer',
      'coat',
      'trench',
      'vest',
    }.contains(normalized)) {
      return ListingCategoryPath('clothing', 'outerwear', itemType);
    }
    if (const {'dress', 'jumpsuit'}.contains(normalized)) {
      return ListingCategoryPath('clothing', 'dresses', itemType);
    }
    if (const {
      'underwear',
      'swimwear',
      'socks',
      'tights',
    }.contains(normalized)) {
      return ListingCategoryPath('clothing', 'basics', itemType);
    }
    if (isShoeCategory(normalized)) {
      return ListingCategoryPath('shoes', 'shoes_all', itemType);
    }
    if (const {'bag', 'backpack', 'wallet'}.contains(normalized)) {
      return ListingCategoryPath('accessories', 'accessories_all', itemType);
    }
    if (isJewelryCategory(normalized)) {
      return ListingCategoryPath('jewelry', 'jewelry_all', itemType);
    }
    if (normalized.isNotEmpty) {
      return ListingCategoryPath('accessories', 'accessories_all', itemType);
    }
    return const ListingCategoryPath('', '', '');
  }

  static const universalSizes = <CatalogOption>[
    CatalogOption('xxs', 'XXS'),
    CatalogOption('xs', 'XS'),
    CatalogOption('s', 'S'),
    CatalogOption('m', 'M'),
    CatalogOption('l', 'L'),
    CatalogOption('xl', 'XL'),
    CatalogOption('xxl', 'XXL'),
    CatalogOption('one_size', 'One Size'),
    CatalogOption('kids', 'Детский размер'),
    CatalogOption('custom', 'Другой размер'),
  ];

  static const oneSizeOptions = <CatalogOption>[
    CatalogOption('one_size', 'One Size'),
    CatalogOption('custom', 'Другой размер'),
  ];

  static final shoeSizes = List<CatalogOption>.generate(
    19,
    (index) => CatalogOption('${27 + index}', '${27 + index}'),
    growable: false,
  );

  static const conditions = <CatalogOption>[
    CatalogOption('new_with_tags', 'Новое с биркой'),
    CatalogOption('new_without_tags', 'Новое без бирки'),
    CatalogOption('excellent', 'Отличное'),
    CatalogOption('good', 'Хорошее'),
    CatalogOption('fair', 'Удовлетворительное'),
  ];

  static const deliveryMethods = <CatalogOption>[
    CatalogOption('cdek', 'СДЭК'),
    CatalogOption('yandex_delivery', 'Яндекс Доставка'),
    CatalogOption('russian_post', 'Почта России'),
    CatalogOption('meetup', 'Личная встреча'),
  ];

  static CatalogOption? find(String id) {
    final all = <CatalogOption>[
      ...sections,
      ...categories,
      ...finalCategories,
      ...subcategoriesByCategory.values.expand((items) => items),
      ...itemTypesBySubcategory.values.expand((items) => items),
      ...genders,
      ...colors,
      ...brands,
      ...materials,
      ...patterns,
      ...seasons,
      ...styles,
      ...fits,
      ...sleeveLengths,
      ...closures,
      ...collars,
      ...rises,
      ...universalSizes,
      ...shoeSizes,
      ...conditions,
      ...deliveryMethods,
    ];
    for (final option in all) {
      if (option.id == id) return option;
    }
    return null;
  }

  static String _nameIn(
    Iterable<CatalogOption> options,
    String id, {
    required String fallback,
  }) {
    for (final option in options) {
      if (option.id == id) return option.name;
    }
    return fallback;
  }

  static String _idIn(Iterable<CatalogOption> options, String value) {
    final normalized = value.trim().toLowerCase();
    for (final option in options) {
      if (option.id.toLowerCase() == normalized ||
          option.name.toLowerCase() == normalized) {
        return option.id;
      }
    }
    return value;
  }

  static String categoryName(String id, {String fallback = 'Не указано'}) {
    final normalized = normalizeCategory(id);
    final value = normalized.isEmpty ? id : normalized;
    for (final option in finalCategories) {
      if (option.id == value) return option.name;
    }
    for (final option in categories) {
      if (option.id == value) return option.name;
    }
    return fallback;
  }

  static String genderName(String id, {String fallback = 'Не указано'}) =>
      _nameIn(genders, id, fallback: fallback);

  static String brandName(String id, {String fallback = 'Не указано'}) =>
      _nameIn(brands, id, fallback: fallback);

  static String colorName(String id, {String fallback = 'Не указано'}) =>
      _nameIn(colors, id, fallback: fallback);

  static String sizeName(String id, {String fallback = 'Не указано'}) =>
      _nameIn([...universalSizes, ...shoeSizes], id, fallback: fallback);

  static String conditionName(String id, {String fallback = 'Не указано'}) =>
      _nameIn(conditions, id, fallback: fallback);

  static String sizeIdOf(String value) =>
      _idIn([...universalSizes, ...shoeSizes], value);

  static String conditionIdOf(String value) => _idIn(conditions, value);

  static String attributeValueName(
    String attribute,
    String value, {
    String category = '',
    String fallback = 'Не указано',
  }) {
    if (category.isNotEmpty) {
      for (final definition in attributesFor(category)) {
        if (definition.id == attribute) {
          return _nameIn(definition.options, value, fallback: fallback);
        }
      }
    }
    final options = switch (attribute) {
      'material' => materials,
      'pattern' => patterns,
      'season' => seasons,
      'style' => styles,
      'fit' => fits,
      'sleeve_length' => sleeveLengths,
      'closure' => closures,
      'collar' => collars,
      'rise' => rises,
      _ => const <CatalogOption>[],
    };
    return _nameIn(options, value, fallback: fallback);
  }

  /// Compatibility lookup for contexts without a semantic field. UI code
  /// should use the typed display helpers above so duplicate IDs stay safe.
  static String nameOf(String id, {String fallback = 'Не указано'}) =>
      find(id)?.name ?? (id.isEmpty ? fallback : id);
}
