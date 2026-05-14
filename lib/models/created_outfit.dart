class OutfitItem {
  const OutfitItem({
    required this.id,
    required this.name,
    required this.price,
    required this.image,
  });

  final String id;
  final String name;
  final String price;
  final String image;
}

class CreatedOutfit {
  const CreatedOutfit({
    required this.id,
    required this.photos,
    required this.items,
  });

  final String id;
  final List<String> photos;
  final List<OutfitItem> items;
}
