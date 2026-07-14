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
    CategoryDefinition("shirt", "tops", "clothing", ("a button-up shirt", "a collared shirt", "рубашка", "рубашка на пуговицах")),
    CategoryDefinition("sweater", "tops", "clothing", ("a knitted sweater", "a pullover", "свитер", "вязаный джемпер")),
    CategoryDefinition("top", "tops", "clothing", ("a fashion top", "a sleeveless top", "топ", "женский топ")),
    CategoryDefinition("jeans", "bottoms", "clothing", ("denim jeans", "a pair of jeans", "джинсы", "джинсовые брюки")),
    CategoryDefinition("trousers", "bottoms", "clothing", ("a pair of trousers", "formal pants", "брюки", "классические брюки")),
    CategoryDefinition("shorts", "bottoms", "clothing", ("a pair of shorts", "short pants", "шорты", "короткие шорты")),
    CategoryDefinition("skirt", "bottoms", "clothing", ("a skirt", "a fashion skirt", "юбка", "женская юбка")),
    CategoryDefinition("jacket", "outerwear", "clothing", ("a jacket", "an outerwear jacket", "куртка", "верхняя куртка")),
    CategoryDefinition("coat", "outerwear", "clothing", ("a long coat", "an overcoat", "пальто", "длинное пальто")),
    CategoryDefinition("vest", "outerwear", "clothing", ("a vest", "a sleeveless outerwear vest", "жилет", "безрукавка")),
    CategoryDefinition("dress", "dresses", "clothing", ("a dress", "a one-piece dress", "платье", "женское платье")),
    CategoryDefinition("jumpsuit", "dresses", "clothing", ("a jumpsuit", "a one-piece jumpsuit", "комбинезон", "цельный комбинезон")),
    CategoryDefinition("sneakers", "shoes_all", "shoes", ("a pair of sneakers", "athletic shoes", "кроссовки", "спортивная обувь")),
    CategoryDefinition("boots", "shoes_all", "shoes", ("a pair of boots", "ankle boots", "ботинки", "сапоги")),
    CategoryDefinition("shoes", "shoes_all", "shoes", ("a pair of formal shoes", "dress shoes", "туфли", "классическая обувь")),
    CategoryDefinition("sandals", "shoes_all", "shoes", ("a pair of sandals", "open toe shoes", "сандалии", "открытая обувь")),
    CategoryDefinition("bag", "accessories_all", "accessories", ("a handbag", "a shoulder bag", "сумка", "женская сумка")),
    CategoryDefinition("backpack", "accessories_all", "accessories", ("a backpack", "a rucksack", "рюкзак", "городской рюкзак")),
    CategoryDefinition("belt", "accessories_all", "accessories", ("a belt", "a leather belt", "ремень", "поясной ремень")),
    CategoryDefinition("scarf", "accessories_all", "accessories", ("a scarf", "a neck scarf", "шарф", "шейный платок")),
    CategoryDefinition("headwear", "accessories_all", "accessories", ("a hat", "a beanie", "головной убор", "шапка")),
    CategoryDefinition("necklace", "jewelry_all", "jewelry", ("a necklace", "a pendant necklace", "подвеска", "ожерелье")),
    CategoryDefinition("ring", "jewelry_all", "jewelry", ("a ring", "a jewelry ring", "кольцо", "ювелирное кольцо")),
    CategoryDefinition("bracelet", "jewelry_all", "jewelry", ("a bracelet", "a wrist bracelet", "браслет", "украшение на руку")),
    CategoryDefinition("earrings", "jewelry_all", "jewelry", ("a pair of earrings", "ear jewelry", "серьги", "украшение для ушей")),
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
    "shirt": "Рубашка",
    "sweater": "Свитер",
    "top": "Топ",
    "jeans": "Джинсы",
    "trousers": "Брюки",
    "shorts": "Шорты",
    "skirt": "Юбка",
    "jacket": "Куртка",
    "coat": "Пальто",
    "vest": "Жилет",
    "dress": "Платье",
    "jumpsuit": "Комбинезон",
    "sneakers": "Кроссовки",
    "boots": "Ботинки",
    "shoes": "Туфли",
    "sandals": "Сандалии",
    "bag": "Сумка",
    "backpack": "Рюкзак",
    "belt": "Ремень",
    "scarf": "Шарф",
    "headwear": "Головной убор",
    "necklace": "Ожерелье",
    "ring": "Кольцо",
    "bracelet": "Браслет",
    "earrings": "Серьги",
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
    "material": ("cotton", "wool", "linen", "denim", "leather", "polyester", "mixed"),
    "pattern": ("solid", "logo", "striped", "checked", "floral", "graphic", "other"),
    "season": ("all_season", "summer", "winter", "demi"),
    "style": ("casual", "sport", "classic", "streetwear", "business", "evening"),
    "fit": ("slim", "regular", "relaxed", "oversized"),
    "sleeve_length": ("sleeveless", "short", "three_quarter", "long"),
    "closure": ("none", "zip", "buttons", "laces", "velcro", "buckle"),
}


NORMALIZED_CATEGORIES: dict[str, str] = {
    "tshirt": "t_shirt",
    "top": "t_shirt",
    "hoodie": "hoodie",
    "sweatshirt": "hoodie",
    "sweater": "hoodie",
    "shirt": "shirt",
    "jacket": "jacket",
    "coat": "jacket",
    "vest": "jacket",
    "jeans": "jeans",
    "trousers": "trousers",
    "shorts": "trousers",
    "dress": "dress",
    "jumpsuit": "dress",
    "skirt": "skirt",
    "sneakers": "sneakers",
    "boots": "boots",
    "shoes": "boots",
    "sandals": "boots",
    "bag": "bag",
    "backpack": "bag",
    "belt": "accessory",
    "scarf": "accessory",
    "headwear": "accessory",
    "necklace": "accessory",
    "ring": "accessory",
    "bracelet": "accessory",
    "earrings": "accessory",
}
