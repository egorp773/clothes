import 'package:flutter/material.dart';

import '../models/created_outfit.dart';

class PublishOutfitScreen extends StatefulWidget {
  const PublishOutfitScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
    required this.onPublish,
    required this.onAddItem,
  });

  final double sidePadding;
  final VoidCallback onClose;
  final ValueChanged<CreatedOutfit> onPublish;
  final VoidCallback onAddItem;

  @override
  State<PublishOutfitScreen> createState() => _PublishOutfitScreenState();
}

class _PublishOutfitScreenState extends State<PublishOutfitScreen> {
  static const List<String> _photoAssets = [
    'assets/mock/outfit_hero.jpg',
    'assets/mock/outfit_hero_premium.jpg',
    'assets/mock/outfit_ref_hero_clean.png',
    'assets/mock/outfit_ref_hero.png',
  ];

  static const List<OutfitItem> _myItems = [
    OutfitItem(
      id: 'rebirth-longsleeve',
      name: 'Лонгслив Rebirth',
      price: '8 400 ₽',
      image: 'assets/mock/item_longsleeve.jpg',
    ),
    OutfitItem(
      id: 'shadow-shorts',
      name: 'Шорты Shadow',
      price: '7 200 ₽',
      image: 'assets/mock/item_shorts.jpg',
    ),
    OutfitItem(
      id: 'track-boots',
      name: 'Ботинки Track',
      price: '14 900 ₽',
      image: 'assets/mock/item_boots.jpg',
    ),
    OutfitItem(
      id: 'cross-necklace',
      name: 'Подвеска Cross',
      price: '6 900 ₽',
      image: 'assets/mock/item_cross.jpg',
    ),
  ];

  final List<String?> _photos = List<String?>.filled(4, null);
  final Set<String> _selectedIds = {};

  int _nextPhotoAssetIndex = 0;

  List<OutfitItem> get _selectedItems {
    return _myItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();
  }

  bool get _canPublish =>
      _photos.any((photo) => photo != null) && _selectedIds.isNotEmpty;

  void _addPhoto(int index) {
    setState(() {
      _photos[index] = _photoAssets[_nextPhotoAssetIndex % _photoAssets.length];
      _nextPhotoAssetIndex += 1;
    });
  }

  void _removePhoto(int index) {
    setState(() => _photos[index] = null);
  }

  void _toggleItem(OutfitItem item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
    });
  }

  void _publish() {
    if (!_canPublish) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Добавьте фото и выберите вещи'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    widget.onPublish(
      CreatedOutfit(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        photos: _photos.whereType<String>().toList(),
        items: _selectedItems,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          widget.sidePadding,
          14,
          widget.sidePadding,
          110,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildUploadBox(),
            const SizedBox(height: 12),
            _buildThumbs(),
            const SizedBox(height: 22),
            _buildItemsSection(),
            const SizedBox(height: 24),
            _buildSelectedSection(),
            const SizedBox(height: 24),
            _buildPublishButton(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close, size: 26, color: Color(0xFF0B0B0B)),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Опубликовать образ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0B0B0B),
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildUploadBox() {
    final photo = _photos.first;

    return GestureDetector(
      onTap: () => _addPhoto(0),
      child: Container(
        width: double.infinity,
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE7E7EA)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: photo == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '+',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Добавить фото образа',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Покажите весь образ целиком',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFF8F8F94),
                    ),
                  ),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(photo, fit: BoxFit.cover),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _RemoveButton(onTap: () => _removePhoto(0)),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildThumbs() {
    return Row(
      children: List.generate(4, (index) {
        final photo = _photos[index];
        final isFirst = index == 0;
        return Expanded(
          child: GestureDetector(
            onTap: () => _addPhoto(index),
            child: Container(
              height: 64,
              margin: EdgeInsets.only(right: index < 3 ? 10 : 0),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE7E7EA)),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: photo == null
                  ? Center(
                      child: Text(
                        isFirst ? '+' : '${index + 1}',
                        style: TextStyle(
                          fontSize: isFirst ? 22 : 14,
                          fontWeight: FontWeight.w500,
                          color: isFirst
                              ? const Color(0xFF111111)
                              : const Color(0xFF9A9A9F),
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.asset(photo, fit: BoxFit.cover),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: _RemoveButton(
                            onTap: () => _removePhoto(index),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Выберите вещи',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: widget.onAddItem,
          child: Container(
            height: 78,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE7E7EA)),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6F6F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add,
                    size: 22,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Добавить вещь',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111111),
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Создайте вещь для публикации',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF8F8F94),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: Color(0xFFB8B8BE),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _myItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 190,
          ),
          itemBuilder: (context, index) {
            final item = _myItems[index];
            return _ItemCard(
              item: item,
              isSelected: _selectedIds.contains(item.id),
              onTap: () => _toggleItem(item),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSelectedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Вещи в образе (${_selectedItems.length})',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'Выберите вещи из списка выше',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8F8F94),
                ),
              ),
            ),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _selectedItems.length,
              separatorBuilder: (context, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = _selectedItems[index];
                return _SelectedItemCard(
                  item: item,
                  onRemove: () => _toggleItem(item),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPublishButton() {
    return GestureDetector(
      onTap: _publish,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: _canPublish ? Colors.black : const Color(0xFFC8C8CE),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            'Опубликовать образ',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _canPublish ? Colors.white : const Color(0xFF8E8E93),
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoveButton extends StatelessWidget {
  const _RemoveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(Icons.close, size: 14, color: Color(0xFF111111)),
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final OutfitItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
            color: isSelected ? Colors.black : const Color(0xFFE7E7EA),
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Image.asset(
                          item.image,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(Icons.checkroom_outlined, size: 40),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.price,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF111111),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? Colors.black : const Color(0xFFC7C7CC),
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedItemCard extends StatelessWidget {
  const _SelectedItemCard({
    required this.item,
    required this.onRemove,
  });

  final OutfitItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE7E7EA)),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Color(0xFFF8F8F8),
                borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Image.asset(
                      item.image,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.checkroom_outlined, size: 32),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Color(0xFF111111)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.price,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111111),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
