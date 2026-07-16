from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class CategoryDefinition:
    item_type: str
    subcategory: str
    category: str
    prompts: tuple[str, ...]


CATEGORIES: tuple[CategoryDefinition, ...] = (
    CategoryDefinition("hoodie", "tops", "clothing", ("a hoodie", "a hooded sweatshirt", "худи", "толстовка с капюшоном")),
    CategoryDefinition("sweatshirt", "tops", "clothing", ("a sweatshirt", "a crewneck sweatshirt", "свитшот", "толстовка без капюшона")),
    CategoryDefinition("tshirt", "tops", "clothing", ("a t-shirt", "a short sleeve tee", "футболка", "футболка с коротким рукавом")),
    CategoryDefinition("tank_top", "tops", "clothing", ("a tank top", "a sleeveless undershirt", "майка", "топ на бретелях")),
    CategoryDefinition("long_sleeve", "tops", "clothing", ("a long sleeve t-shirt", "a long-sleeve jersey top", "лонгслив", "футболка с длинным рукавом")),
    CategoryDefinition("polo", "tops", "clothing", ("a polo shirt", "a short sleeve polo", "поло", "футболка поло")),
    CategoryDefinition("shirt", "tops", "clothing", ("a button-up shirt", "a collared shirt", "рубашка", "рубашка на пуговицах")),
    CategoryDefinition("blouse", "tops", "clothing", ("a blouse", "a women's blouse", "блузка", "женская блузка")),
    CategoryDefinition("sweater", "tops", "clothing", ("a knitted sweater", "a pullover", "свитер", "вязаный джемпер")),
    CategoryDefinition("cardigan", "tops", "clothing", ("a knitted cardigan", "an open front cardigan", "кардиган", "вязаный кардиган")),
    CategoryDefinition("turtleneck", "tops", "clothing", ("a turtleneck sweater", "a roll-neck top", "водолазка", "свитер с высоким горлом")),
    CategoryDefinition("top", "tops", "clothing", ("a fashion top", "a sleeveless top", "топ", "женский топ")),
    CategoryDefinition("jeans", "bottoms", "clothing", ("denim jeans", "a pair of jeans", "джинсы", "джинсовые брюки")),
    CategoryDefinition("trousers", "bottoms", "clothing", ("a pair of trousers", "formal pants", "брюки", "классические брюки")),
    CategoryDefinition("joggers", "bottoms", "clothing", ("a pair of jogger pants", "sweatpants", "джоггеры", "спортивные штаны")),
    CategoryDefinition("leggings", "bottoms", "clothing", ("a pair of leggings", "stretch leggings", "легинсы", "лосины")),
    CategoryDefinition("shorts", "bottoms", "clothing", ("a pair of shorts", "short pants", "шорты", "короткие шорты")),
    CategoryDefinition("skirt", "bottoms", "clothing", ("a skirt", "a fashion skirt", "юбка", "женская юбка")),
    CategoryDefinition("jacket", "outerwear", "clothing", ("a jacket", "an outerwear jacket", "куртка", "верхняя куртка")),
    CategoryDefinition("blazer", "outerwear", "clothing", ("a tailored blazer", "a suit jacket", "пиджак", "блейзер")),
    CategoryDefinition("puffer", "outerwear", "clothing", ("a puffer jacket", "a quilted down jacket", "пуховик", "дутая куртка")),
    CategoryDefinition("coat", "outerwear", "clothing", ("a long coat", "an overcoat", "пальто", "длинное пальто")),
    CategoryDefinition("trench", "outerwear", "clothing", ("a trench coat", "a raincoat", "тренч", "плащ")),
    CategoryDefinition("vest", "outerwear", "clothing", ("a vest", "a sleeveless outerwear vest", "жилет", "безрукавка")),
    CategoryDefinition("dress", "dresses", "clothing", ("a dress", "a one-piece dress", "платье", "женское платье")),
    CategoryDefinition("jumpsuit", "dresses", "clothing", ("a jumpsuit", "a one-piece jumpsuit", "комбинезон", "цельный комбинезон")),
    CategoryDefinition("underwear", "basics", "clothing", ("underwear", "lingerie", "нижнее белье", "комплект белья")),
    CategoryDefinition("swimwear", "basics", "clothing", ("swimwear", "a swimsuit", "купальник", "плавки")),
    CategoryDefinition("socks", "basics", "clothing", ("a pair of socks", "hosiery socks", "носки", "гольфы")),
    CategoryDefinition("tights", "basics", "clothing", ("a pair of tights", "pantyhose", "колготки", "капроновые колготки")),
    CategoryDefinition("sneakers", "shoes_all", "shoes", ("a pair of sneakers", "athletic shoes", "кроссовки", "спортивная обувь")),
    CategoryDefinition("boots", "shoes_all", "shoes", ("a pair of boots", "ankle boots", "ботинки", "сапоги")),
    CategoryDefinition("shoes", "shoes_all", "shoes", ("a pair of formal shoes", "dress shoes", "туфли", "классическая обувь")),
    CategoryDefinition("heels", "shoes_all", "shoes", ("a pair of high heels", "heeled pumps", "туфли на каблуке", "лодочки на каблуке")),
    CategoryDefinition("loafers", "shoes_all", "shoes", ("a pair of loafers", "slip-on loafers", "лоферы", "мокасины")),
    CategoryDefinition("sandals", "shoes_all", "shoes", ("a pair of sandals", "open toe shoes", "сандалии", "открытая обувь")),
    CategoryDefinition("slippers", "shoes_all", "shoes", ("a pair of slippers", "house shoes", "тапочки", "домашняя обувь")),
    CategoryDefinition("bag", "accessories_all", "accessories", ("a handbag", "a shoulder bag", "сумка", "женская сумка")),
    CategoryDefinition("backpack", "accessories_all", "accessories", ("a backpack", "a rucksack", "рюкзак", "городской рюкзак")),
    CategoryDefinition("wallet", "accessories_all", "accessories", ("a wallet", "a card holder wallet", "кошелек", "портмоне")),
    CategoryDefinition("belt", "accessories_all", "accessories", ("a belt", "a leather belt", "ремень", "поясной ремень")),
    CategoryDefinition("scarf", "accessories_all", "accessories", ("a scarf", "a neck scarf", "шарф", "шейный платок")),
    CategoryDefinition("gloves", "accessories_all", "accessories", ("a pair of gloves", "winter gloves", "перчатки", "варежки")),
    CategoryDefinition("cap", "accessories_all", "accessories", ("a baseball cap", "a peaked cap", "кепка", "бейсболка")),
    CategoryDefinition("beanie", "accessories_all", "accessories", ("a knitted beanie", "a winter knit hat", "шапка", "шапка бини")),
    CategoryDefinition("hat", "accessories_all", "accessories", ("a brimmed hat", "a bucket hat", "шляпа", "панама")),
    CategoryDefinition("headwear", "accessories_all", "accessories", ("fashion headwear", "a head covering", "головной убор", "другой головной убор")),
    CategoryDefinition("eyewear", "accessories_all", "accessories", ("a pair of sunglasses", "fashion eyeglasses", "очки", "солнцезащитные очки")),
    CategoryDefinition("watch", "accessories_all", "accessories", ("a wristwatch", "a fashion watch", "наручные часы", "часы на руку")),
    CategoryDefinition("tie", "accessories_all", "accessories", ("a necktie", "a bow tie", "галстук", "галстук-бабочка")),
    CategoryDefinition("accessory", "accessories_all", "accessories", ("a fashion accessory", "a wearable accessory", "аксессуар", "модный аксессуар")),
    CategoryDefinition("necklace", "jewelry_all", "jewelry", ("a necklace", "a pendant necklace", "подвеска", "ожерелье")),
    CategoryDefinition("ring", "jewelry_all", "jewelry", ("a ring", "a jewelry ring", "кольцо", "ювелирное кольцо")),
    CategoryDefinition("bracelet", "jewelry_all", "jewelry", ("a bracelet", "a wrist bracelet", "браслет", "украшение на руку")),
    CategoryDefinition("earrings", "jewelry_all", "jewelry", ("a pair of earrings", "ear jewelry", "серьги", "украшение для ушей")),
    CategoryDefinition("brooch", "jewelry_all", "jewelry", ("a brooch", "a decorative pin", "брошь", "декоративная брошь")),
)

BRANDS: dict[str, str] = {
    "no_brand": "Без бренда",
    "nike": "Nike",
    "adidas": "Adidas",
    "puma": "Puma",
    "zara": "Zara",
    "hm": "H&M",
    "uniqlo": "Uniqlo",
    "carhartt": "Carhartt",
    "stussy": "Stüssy",
    "new_balance": "New Balance",
    "the_north_face": "The North Face",
    "calvin_klein": "Calvin Klein",
    "tommy_hilfiger": "Tommy Hilfiger",
    "levis": "Levi's",
}

ITEM_TYPE_TITLES: dict[str, str] = {
    "hoodie": "Худи",
    "sweatshirt": "Свитшот",
    "tshirt": "Футболка",
    "tank_top": "Майка",
    "long_sleeve": "Лонгслив",
    "polo": "Поло",
    "shirt": "Рубашка",
    "blouse": "Блузка",
    "sweater": "Свитер",
    "cardigan": "Кардиган",
    "turtleneck": "Водолазка",
    "top": "Топ",
    "jeans": "Джинсы",
    "trousers": "Брюки",
    "joggers": "Джоггеры",
    "leggings": "Легинсы",
    "shorts": "Шорты",
    "skirt": "Юбка",
    "jacket": "Куртка",
    "blazer": "Пиджак",
    "puffer": "Пуховик",
    "coat": "Пальто",
    "trench": "Тренч",
    "vest": "Жилет",
    "dress": "Платье",
    "jumpsuit": "Комбинезон",
    "underwear": "Нижнее бельё",
    "swimwear": "Купальник",
    "socks": "Носки",
    "tights": "Колготки",
    "sneakers": "Кроссовки",
    "boots": "Ботинки",
    "shoes": "Туфли",
    "heels": "Туфли на каблуке",
    "loafers": "Лоферы",
    "sandals": "Сандалии",
    "slippers": "Домашняя обувь",
    "bag": "Сумка",
    "backpack": "Рюкзак",
    "wallet": "Кошелёк",
    "belt": "Ремень",
    "scarf": "Шарф",
    "gloves": "Перчатки",
    "cap": "Кепка",
    "beanie": "Шапка",
    "hat": "Шляпа",
    "headwear": "Головной убор",
    "eyewear": "Очки",
    "watch": "Часы",
    "tie": "Галстук",
    "accessory": "Аксессуар",
    "necklace": "Ожерелье",
    "ring": "Кольцо",
    "bracelet": "Браслет",
    "earrings": "Серьги",
    "brooch": "Брошь",
}

COLORS: dict[str, tuple[int, int, int]] = {
    "black": (17, 17, 17),
    "white": (255, 255, 255),
    "gray": (139, 139, 144),
    "beige": (216, 196, 168),
    "cream": (243, 232, 207),
    "brown": (128, 84, 60),
    "blue": (53, 103, 183),
    "dark_blue": (23, 42, 77),
    "light_blue": (139, 196, 232),
    "green": (58, 140, 91),
    "olive": (116, 115, 61),
    "red": (214, 69, 69),
    "burgundy": (111, 38, 61),
    "pink": (231, 148, 184),
    "purple": (132, 92, 178),
    "yellow": (240, 200, 60),
    "orange": (233, 137, 58),
}

ALLOWED_ATTRIBUTES: dict[str, tuple[str, ...]] = {
    "gender": ("female", "male", "unisex", "kids"),
    "material": (
        "cotton", "wool", "cashmere", "linen", "silk", "viscose", "denim",
        "leather", "faux_leather", "suede", "polyester", "acrylic", "elastane",
        "nylon", "textile", "canvas", "rubber", "synthetic", "down", "fur",
        "metal", "steel", "titanium", "gold", "silver", "platinum", "ceramic",
        "plastic", "acetate", "wood", "glass", "gemstone", "pearls", "mixed",
        "unknown",
    ),
    "pattern": ("solid", "logo", "striped", "checked", "floral", "graphic", "other"),
    "season": ("all_season", "summer", "winter", "demi"),
    "style": (
        "casual", "sport", "classic", "streetwear", "business", "evening",
        "minimalist", "vintage", "statement", "everyday", "smart", "luxury",
    ),
    "fit": ("slim", "regular", "relaxed", "oversized"),
    "sleeve_length": ("sleeveless", "short", "three_quarter", "long"),
    "closure": (
        "none", "zip", "buttons", "laces", "velcro", "buckle", "snap",
        "magnetic", "drawstring", "hook",
    ),
    "collar": ("round", "v_neck", "polo", "shirt", "stand", "hood", "none"),
    "rise": ("low", "mid", "high"),
}


NORMALIZED_CATEGORIES: dict[str, str] = {
    "tshirt": "t_shirt",
    "tank_top": "tank_top",
    "top": "top",
    "long_sleeve": "long_sleeve",
    "polo": "polo",
    "hoodie": "hoodie",
    "sweatshirt": "sweatshirt",
    "sweater": "sweater",
    "cardigan": "cardigan",
    "turtleneck": "turtleneck",
    "shirt": "shirt",
    "blouse": "blouse",
    "jacket": "jacket",
    "blazer": "blazer",
    "puffer": "puffer",
    "coat": "coat",
    "trench": "trench",
    "vest": "vest",
    "jeans": "jeans",
    "trousers": "trousers",
    "joggers": "joggers",
    "leggings": "leggings",
    "shorts": "shorts",
    "dress": "dress",
    "jumpsuit": "jumpsuit",
    "skirt": "skirt",
    "underwear": "underwear",
    "swimwear": "swimwear",
    "socks": "socks",
    "tights": "tights",
    "sneakers": "sneakers",
    "boots": "boots",
    "shoes": "shoes",
    "heels": "heels",
    "loafers": "loafers",
    "sandals": "sandals",
    "slippers": "slippers",
    "bag": "bag",
    "backpack": "backpack",
    "wallet": "wallet",
    "belt": "belt",
    "scarf": "scarf",
    "gloves": "gloves",
    "cap": "cap",
    "beanie": "beanie",
    "hat": "hat",
    "headwear": "headwear",
    "eyewear": "eyewear",
    "watch": "watch",
    "tie": "tie",
    "accessory": "accessory",
    "necklace": "necklace",
    "ring": "ring",
    "bracelet": "bracelet",
    "earrings": "earrings",
    "brooch": "brooch",
}


CATEGORY_ALIASES: dict[str, str] = {
    **NORMALIZED_CATEGORIES,
    **{value: value for value in NORMALIZED_CATEGORIES.values()},
    "t-shirt": "t_shirt", "tee": "t_shirt", "футболка": "t_shirt",
    "tank top": "tank_top", "long sleeve": "long_sleeve",
    "pullover": "sweater", "jumper": "sweater", "crewneck": "sweatshirt",
    "pants": "trousers", "sweatpants": "joggers", "trainers": "sneakers",
    "handbag": "bag", "rucksack": "backpack", "purse": "wallet",
    "майка": "tank_top", "топ": "top", "лонгслив": "long_sleeve",
    "поло": "polo", "рубашка": "shirt", "блузка": "blouse",
    "худи": "hoodie", "толстовка с капюшоном": "hoodie",
    "толстовка": "sweatshirt", "свитшот": "sweatshirt",
    "свитер": "sweater", "джемпер": "sweater", "пуловер": "sweater",
    "кардиган": "cardigan", "водолазка": "turtleneck",
    "куртка": "jacket", "пиджак": "blazer", "пуховик": "puffer",
    "пальто": "coat", "тренч": "trench", "плащ": "trench",
    "жилет": "vest", "джинсы": "jeans", "брюки": "trousers",
    "джоггеры": "joggers", "легинсы": "leggings", "шорты": "shorts",
    "юбка": "skirt", "платье": "dress", "комбинезон": "jumpsuit",
    "нижнее белье": "underwear", "купальник": "swimwear",
    "носки": "socks", "колготки": "tights", "кроссовки": "sneakers",
    "ботинки": "boots", "туфли": "shoes", "туфли на каблуке": "heels",
    "лоферы": "loafers", "сандалии": "sandals", "тапочки": "slippers",
    "сумка": "bag", "рюкзак": "backpack", "кошелек": "wallet",
    "ремень": "belt", "шарф": "scarf", "перчатки": "gloves",
    "кепка": "cap", "шапка": "beanie", "шляпа": "hat",
    "головной убор": "headwear", "очки": "eyewear", "часы": "watch",
    "галстук": "tie", "аксессуар": "accessory", "подвеска": "necklace",
    "колье": "necklace", "кольцо": "ring", "браслет": "bracelet",
    "серьги": "earrings", "брошь": "brooch",
}


def normalize_category(raw_value: str | None) -> str | None:
    cleaned = (raw_value or "").strip().casefold().replace("ё", "е")
    return CATEGORY_ALIASES.get(cleaned)


_CATEGORY_ATTRIBUTE_GROUPS: tuple[tuple[tuple[str, ...], tuple[str, ...]], ...] = (
    (("t_shirt", "tank_top", "top", "long_sleeve", "polo", "sweater", "turtleneck"),
     ("material", "pattern", "fit", "sleeve_length", "collar")),
    (("shirt", "blouse", "cardigan"),
     ("material", "pattern", "fit", "sleeve_length", "collar", "closure")),
    (("hoodie",), ("material", "pattern", "fit", "closure")),
    (("sweatshirt",), ("material", "pattern", "fit", "sleeve_length")),
    (("jacket", "blazer", "puffer", "coat", "trench", "vest"),
     ("material", "fit", "collar", "closure", "season")),
    (("jeans",), ("material", "fit", "rise", "closure")),
    (("trousers", "joggers", "leggings", "shorts", "skirt"),
     ("material", "pattern", "fit", "rise", "closure")),
    (("dress", "jumpsuit"),
     ("material", "pattern", "fit", "sleeve_length", "collar", "closure")),
    (("underwear", "swimwear"), ("material", "pattern", "fit")),
    (("socks", "tights"), ("material", "pattern")),
    (("sneakers", "shoes", "heels", "loafers", "sandals", "slippers"),
     ("material", "pattern", "closure", "style")),
    (("boots",), ("material", "closure", "season", "style")),
    (("bag", "backpack", "wallet"), ("material", "pattern", "closure", "style")),
    (("cap", "beanie", "hat", "headwear"), ("material", "pattern", "season", "style")),
    (("belt",), ("material", "closure", "style")),
    (("scarf",), ("material", "pattern", "season", "style")),
    (("gloves",), ("material", "season", "style")),
    (("eyewear", "watch"), ("material", "style")),
    (("tie",), ("material", "pattern", "style")),
    (("accessory",), ("material", "pattern", "style")),
    (("necklace", "ring", "bracelet", "earrings", "brooch"), ("material", "style")),
)

CATEGORY_ATTRIBUTES: dict[str, tuple[str, ...]] = {
    category: attributes
    for categories, attributes in _CATEGORY_ATTRIBUTE_GROUPS
    for category in categories
}

_APPAREL_MATERIALS = (
    "cotton", "wool", "cashmere", "linen", "silk", "viscose", "denim",
    "leather", "polyester", "acrylic", "elastane", "mixed",
)
_KNITWEAR_MATERIALS = (
    "cotton", "wool", "cashmere", "viscose", "polyester", "acrylic", "mixed",
)
_OUTERWEAR_MATERIALS = (
    "cotton", "wool", "denim", "leather", "faux_leather", "suede",
    "polyester", "nylon", "down", "fur", "mixed",
)
_FOOTWEAR_MATERIALS = (
    "leather", "faux_leather", "suede", "textile", "canvas", "rubber",
    "synthetic", "mixed",
)
_BAG_MATERIALS = (
    "leather", "faux_leather", "suede", "textile", "canvas", "nylon",
    "polyester", "plastic", "metal", "mixed",
)
_TEXTILE_ACCESSORY_MATERIALS = (
    "cotton", "wool", "cashmere", "linen", "silk", "viscose", "polyester",
    "acrylic", "leather", "fur", "mixed",
)
_JEWELRY_MATERIALS = (
    "gold", "silver", "steel", "metal", "titanium", "platinum", "ceramic",
    "leather", "textile", "plastic", "wood", "glass", "gemstone", "pearls", "mixed",
)

CATEGORY_MATERIALS: dict[str, tuple[str, ...]] = {
    category: _APPAREL_MATERIALS for category in CATEGORY_ATTRIBUTES
}
CATEGORY_MATERIALS.update({
    **{category: _KNITWEAR_MATERIALS for category in ("sweater", "cardigan", "turtleneck")},
    **{category: _OUTERWEAR_MATERIALS for category in ("jacket", "blazer", "puffer", "coat", "trench", "vest")},
    **{category: _FOOTWEAR_MATERIALS for category in ("sneakers", "boots", "shoes", "heels", "loafers", "sandals", "slippers")},
    **{category: _BAG_MATERIALS for category in ("bag", "backpack", "wallet")},
    **{category: _TEXTILE_ACCESSORY_MATERIALS for category in ("cap", "beanie", "hat", "headwear", "scarf", "gloves")},
    "belt": ("leather", "faux_leather", "suede", "textile", "metal", "plastic", "mixed"),
    "eyewear": ("metal", "steel", "titanium", "plastic", "acetate", "mixed"),
    "watch": ("steel", "metal", "titanium", "gold", "silver", "leather", "ceramic", "plastic", "textile", "mixed"),
    "tie": ("silk", "cotton", "wool", "linen", "polyester", "mixed"),
    "accessory": ALLOWED_ATTRIBUTES["material"],
    **{category: _JEWELRY_MATERIALS for category in ("necklace", "ring", "bracelet", "earrings", "brooch")},
})
CATEGORY_MATERIALS = {
    category: materials
    if "unknown" in materials
    else (*materials, "unknown")
    for category, materials in CATEGORY_MATERIALS.items()
}

_FOOTWEAR_CLOSURES = ("none", "laces", "zip", "velcro", "buckle")
_BAG_CLOSURES = ("none", "zip", "snap", "magnetic", "drawstring", "buckle")
_JEWELRY_STYLES = (
    "minimalist", "classic", "vintage", "statement", "everyday", "evening",
)
_WATCH_STYLES = ("classic", "sport", "casual", "smart", "luxury")


def attribute_options_for(category: str, attribute: str) -> tuple[str, ...]:
    """Return the same category-specific option IDs exposed by the app UI."""
    normalized = normalize_category(category) or category
    if attribute == "material":
        return CATEGORY_MATERIALS.get(normalized, ALLOWED_ATTRIBUTES["material"])
    if attribute == "closure":
        if normalized in {
            "sneakers", "boots", "shoes", "heels", "loafers", "sandals",
            "slippers",
        }:
            return _FOOTWEAR_CLOSURES
        if normalized in {"bag", "backpack", "wallet"}:
            return _BAG_CLOSURES
    if attribute == "style":
        if normalized in {"necklace", "ring", "bracelet", "earrings", "brooch"}:
            return _JEWELRY_STYLES
        if normalized == "watch":
            return _WATCH_STYLES
    return ALLOWED_ATTRIBUTES.get(attribute, ())
