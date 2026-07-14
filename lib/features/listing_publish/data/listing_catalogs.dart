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

  /// Final buyer-facing categories. New listings select exactly one of these
  /// instead of exposing the legacy section/category/subcategory hierarchy.
  static const finalCategories = <CatalogOption>[
    CatalogOption('t_shirt', 'Футболка'),
    CatalogOption('hoodie', 'Худи'),
    CatalogOption('shirt', 'Рубашка'),
    CatalogOption('jacket', 'Куртка'),
    CatalogOption('jeans', 'Джинсы'),
    CatalogOption('trousers', 'Брюки'),
    CatalogOption('dress', 'Платье'),
    CatalogOption('skirt', 'Юбка'),
    CatalogOption('sneakers', 'Кроссовки'),
    CatalogOption('boots', 'Ботинки'),
    CatalogOption('bag', 'Сумка'),
    CatalogOption('accessory', 'Аксессуар'),
  ];

  static const subcategoriesByCategory = <String, List<CatalogOption>>{
    'clothing': [
      CatalogOption('tops', 'Верх'),
      CatalogOption('bottoms', 'Низ'),
      CatalogOption('outerwear', 'Верхняя одежда'),
      CatalogOption('dresses', 'Платья и комбинезоны'),
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
      CatalogOption('shirt', 'Рубашка'),
      CatalogOption('sweater', 'Свитер'),
      CatalogOption('top', 'Топ'),
    ],
    'bottoms': [
      CatalogOption('jeans', 'Джинсы'),
      CatalogOption('trousers', 'Брюки'),
      CatalogOption('shorts', 'Шорты'),
      CatalogOption('skirt', 'Юбка'),
    ],
    'outerwear': [
      CatalogOption('jacket', 'Куртка'),
      CatalogOption('coat', 'Пальто'),
      CatalogOption('vest', 'Жилет'),
    ],
    'dresses': [
      CatalogOption('dress', 'Платье'),
      CatalogOption('jumpsuit', 'Комбинезон'),
    ],
    'shoes_all': [
      CatalogOption('sneakers', 'Кроссовки'),
      CatalogOption('boots', 'Ботинки'),
      CatalogOption('shoes', 'Туфли'),
      CatalogOption('sandals', 'Сандалии'),
    ],
    'accessories_all': [
      CatalogOption('bag', 'Сумка'),
      CatalogOption('backpack', 'Рюкзак'),
      CatalogOption('belt', 'Ремень'),
      CatalogOption('scarf', 'Шарф'),
      CatalogOption('headwear', 'Головной убор'),
    ],
    'jewelry_all': [
      CatalogOption('necklace', 'Подвеска'),
      CatalogOption('ring', 'Кольцо'),
      CatalogOption('bracelet', 'Браслет'),
      CatalogOption('earrings', 'Серьги'),
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
    CatalogOption('linen', 'Лён'),
    CatalogOption('denim', 'Деним'),
    CatalogOption('leather', 'Кожа'),
    CatalogOption('polyester', 'Полиэстер'),
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
      };

  static const categoryAliases = <String, String>{
    'tshirt': 't_shirt',
    't-shirt': 't_shirt',
    'tee': 't_shirt',
    'футболка': 't_shirt',
    'толстовка': 'hoodie',
    'худи': 'hoodie',
    'рубашка': 'shirt',
    'куртка': 'jacket',
    'джинсы': 'jeans',
    'брюки': 'trousers',
    'штаны': 'trousers',
    'платье': 'dress',
    'юбка': 'skirt',
    'кроссовки': 'sneakers',
    'ботинки': 'boots',
    'сумка': 'bag',
    'аксессуар': 'accessory',
  };

  static String normalizeCategory(String raw) {
    final value = raw.trim().toLowerCase().replaceAll('ё', 'е');
    if (finalCategories.any((option) => option.id == value)) return value;
    return categoryAliases[value] ?? '';
  }

  static List<ListingAttributeDefinition> attributesFor(String category) =>
      categoryAttributeSchemas[normalizeCategory(category)] ?? const [];

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

  static String nameOf(String id, {String fallback = 'Не указано'}) =>
      find(id)?.name ?? (id.isEmpty ? fallback : id);
}
