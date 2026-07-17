import 'package:flutter/material.dart';

import '../core/app_appearance.dart';
import '../models/created_outfit.dart';
import '../widgets/app_image.dart';

class CreateOutfitScreen extends StatefulWidget {
  const CreateOutfitScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
    required this.onPublish,
  });

  final double sidePadding;
  final VoidCallback onClose;
  final ValueChanged<CreatedOutfit> onPublish;

  @override
  State<CreateOutfitScreen> createState() => _CreateOutfitScreenState();
}

class _CreateOutfitScreenState extends State<CreateOutfitScreen> {
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

  static const List<OutfitItem> _likedItems = [
    OutfitItem(
      id: 'baggy-jeans',
      name: 'Багги джинсы',
      price: '12 300 ₽',
      image: 'assets/products/baggy_jeans.jpg',
    ),
    OutfitItem(
      id: 'camo-skirt',
      name: 'Камуфляжная юбка',
      price: '7 400 ₽',
      image: 'assets/products/camo_skirt.jpg',
    ),
    OutfitItem(
      id: 'open-shoulder-top',
      name: 'Топ с открытыми плечами',
      price: '5 500 ₽',
      image: 'assets/products/open_shoulder_top.jpg',
    ),
    OutfitItem(
      id: 'graphic-hoodie',
      name: 'Графическое худи',
      price: '8 800 ₽',
      image: 'assets/products/graphic_hoodie.jpg',
    ),
  ];

  final Set<String> _selectedIds = {};

  int _selectedTab = 0;

  List<OutfitItem> get _visibleItems =>
      _selectedTab == 0 ? _myItems : _likedItems;

  List<OutfitItem> get _selectedItems {
    return [
      ..._myItems,
      ..._likedItems,
    ].where((item) => _selectedIds.contains(item.id)).toList();
  }

  bool get _hasSelection => _selectedIds.isNotEmpty;

  void _toggleItem(OutfitItem item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
      } else {
        _selectedIds.add(item.id);
      }
    });
  }

  void _save() {
    if (_hasSelection) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Образ сохранён'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
    widget.onClose();
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
            _buildItemsSection(),
            const SizedBox(height: 24),
            _buildSelectedSection(),
            const SizedBox(height: 24),
            _buildSaveButton(),
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
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.close, size: 26, color: context.appPalette.ink),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                'Создать образ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.appPalette.ink,
                ),
              ),
            ),
          ),
          const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Выберите вещи',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.appPalette.ink,
          ),
        ),
        const SizedBox(height: 12),
        _buildTabs(),
        const SizedBox(height: 14),
        GridView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _visibleItems.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 190,
          ),
          itemBuilder: (context, index) {
            final item = _visibleItems[index];
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

  Widget _buildTabs() {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: context.appPalette.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _SegmentButton(
            label: 'Мои вещи',
            isSelected: _selectedTab == 0,
            onTap: () => setState(() => _selectedTab = 0),
          ),
          _SegmentButton(
            label: 'Понравившиеся',
            isSelected: _selectedTab == 1,
            onTap: () => setState(() => _selectedTab = 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Вещи в образе (${_selectedItems.length})',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: context.appPalette.ink,
          ),
        ),
        const SizedBox(height: 12),
        if (_selectedItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: context.appPalette.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'Выберите вещи из списка выше',
                style: TextStyle(fontSize: 13, color: context.appPalette.muted),
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

  Widget _buildSaveButton() {
    final scheme = Theme.of(context).colorScheme;
    final palette = context.appPalette;

    return GestureDetector(
      onTap: _save,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: _hasSelection ? scheme.primary : palette.surfaceMuted,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: Text(
            'Сохранить',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _hasSelection ? scheme.onPrimary : palette.muted,
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected ? scheme.onPrimary : context.appPalette.ink,
              ),
            ),
          ),
        ),
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
    final palette = context.appPalette;
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(
            color: isSelected ? scheme.primary : palette.border,
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
                        color: palette.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: AppImage(
                          imageUrl: item.image,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.price,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
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
                  color: isSelected ? scheme.primary : palette.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? scheme.primary : palette.border,
                    width: 1.5,
                  ),
                ),
                child: isSelected
                    ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
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
  const _SelectedItemCard({required this.item, required this.onRemove});

  final OutfitItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;

    return Container(
      width: 130,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: palette.surfaceMuted,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(13),
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: AppImage(imageUrl: item.image, fit: BoxFit.contain),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: GestureDetector(
                      onTap: onRemove,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: palette.surfaceRaised,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close, size: 14, color: palette.ink),
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.price,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: palette.ink,
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
