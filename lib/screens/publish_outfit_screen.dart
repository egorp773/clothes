import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/created_outfit.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';

class PublishOutfitScreen extends StatefulWidget {
  const PublishOutfitScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
    required this.onPublish,
    required this.onAddItem,
    required this.products,
    this.onUploadImage,
  });

  final double sidePadding;
  final VoidCallback onClose;
  final Future<void> Function(CreatedOutfit outfit) onPublish;
  final VoidCallback onAddItem;
  final List<Product> products;
  final Future<String?> Function(XFile imageFile, {String? folder})?
  onUploadImage;

  @override
  State<PublishOutfitScreen> createState() => _PublishOutfitScreenState();
}

class _PublishOutfitScreenState extends State<PublishOutfitScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<XFile?> _photos = List<XFile?>.filled(10, null);
  final Map<int, String> _uploadedPhotos = {};
  final Set<String> _selectedIds = {};
  final Uuid _uuid = const Uuid();
  bool _isPublishing = false;

  Map<String, Product> get _productsById {
    return {for (final product in widget.products) product.id: product};
  }

  List<OutfitItem> get _myItems {
    return widget.products
        .map(
          (product) => OutfitItem(
            id: product.id,
            name: product.title,
            price: product.price,
            image: product.outfitDisplayImage,
          ),
        )
        .toList();
  }

  List<OutfitItem> get _selectedItems {
    return _myItems.where((item) => _selectedIds.contains(item.id)).toList();
  }

  bool get _canPublish =>
      !_isPublishing &&
      _photos.any((photo) => photo != null) &&
      _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant PublishOutfitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    super.dispose();
  }

  bool _isProductProcessing(String productId) {
    final product = _productsById[productId];
    if (product == null || product.isLocal) return false;
    return product.outfitImages.isEmpty;
  }

  String? _photoPath(int index) {
    return _uploadedPhotos[index] ?? _photos[index]?.path;
  }

  int? get _firstEmptyPhotoIndex {
    final index = _photos.indexWhere((photo) => photo == null);
    return index == -1 ? null : index;
  }

  Future<void> _pickNextPhoto() async {
    final index = _firstEmptyPhotoIndex;
    if (index == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Можно добавить до 10 фото'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    await _pickPhoto(index);
  }

  Future<void> _pickPhoto(int index) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 86,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photos[index] = picked;
      _uploadedPhotos.remove(index);
    });
  }

  void _removePhoto(int index) {
    setState(() {
      _photos[index] = null;
      _uploadedPhotos.remove(index);
    });
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

  Future<List<OutfitItem>?> _prepareSelectedItems() async {
    final productsById = _productsById;
    final prepared = <OutfitItem>[];

    for (final item in _selectedItems) {
      final product = productsById[item.id];
      final image = product?.outfitDisplayImage ?? item.image;

      prepared.add(
        OutfitItem(
          id: item.id,
          name: item.name,
          price: item.price,
          image: image,
        ),
      );
    }

    return prepared;
  }

  Future<void> _publish() async {
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

    setState(() => _isPublishing = true);
    final uploadedPhotos = <String>[];

    for (var index = 0; index < _photos.length; index++) {
      final photo = _photos[index];
      if (photo == null) continue;

      final uploaded =
          _uploadedPhotos[index] ??
          await widget.onUploadImage?.call(photo, folder: 'outfits/photos');
      if (uploaded == null) {
        if (!mounted) return;
        setState(() => _isPublishing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось загрузить фото образа'),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
        return;
      }

      _uploadedPhotos[index] = uploaded;
      uploadedPhotos.add(uploaded);
    }

    final preparedItems = await _prepareSelectedItems();
    if (preparedItems == null) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось подготовить вещи для образа'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    await widget.onPublish(
      CreatedOutfit(
        id: _uuid.v4(),
        photos: uploadedPhotos,
        items: preparedItems,
      ),
    );

    if (mounted) {
      setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          widget.sidePadding,
          topInset + 14,
          widget.sidePadding,
          110,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            _buildUploadBoxV2(),
            const SizedBox(height: 12),
            _buildThumbsV2(),
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
                  fontWeight: FontWeight.w500,
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

  Widget _buildUploadBoxV2() {
    return GestureDetector(
      onTap: _pickNextPhoto,
      child: Container(
        width: double.infinity,
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE7E7EA)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '+',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
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
              'Можно добавить до 10 фото',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF8F8F94)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbsV2() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _photos.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final photo = _photoPath(index);
          return GestureDetector(
            onTap: () => _pickPhoto(index),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE7E7EA)),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: photo == null
                  ? Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF9A9A9F),
                        ),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        AppImage(imageUrl: photo, fit: BoxFit.contain),
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
          );
        },
      ),
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
        if (_myItems.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF6F6F7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Сначала добавьте вещь, потом соберите из нее образ',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF8F8F94)),
            ),
          )
        else
          GridView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myItems.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 11,
              mainAxisSpacing: 16,
              mainAxisExtent: 266,
            ),
            itemBuilder: (context, index) {
              final item = _myItems[index];
              return _ItemCard(
                item: item,
                isSelected: _selectedIds.contains(item.id),
                isProcessing: _isProductProcessing(item.id),
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
                style: TextStyle(fontSize: 13, color: Color(0xFF8F8F94)),
              ),
            ),
          )
        else
          SizedBox(
            height: 264,
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
      onTap: _isPublishing ? null : _publish,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: _canPublish ? Colors.black : const Color(0xFFC8C8CE),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: _isPublishing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
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
    required this.isProcessing,
    required this.onTap,
  });

  final OutfitItem item;
  final bool isSelected;
  final bool isProcessing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 256,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(5),
                    border: isSelected
                        ? Border.all(color: Colors.black, width: 2)
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(1),
                        child: AppImage(
                          imageUrl: item.image,
                          fit: BoxFit.contain,
                          alignment: Alignment.center,
                          placeholderColor: Colors.white,
                        ),
                      ),
                      if (isProcessing)
                        Container(
                          color: Colors.white.withValues(alpha: 0.74),
                          child: const Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF111111),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                width: 24,
                height: 24,
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
  const _SelectedItemCard({required this.item, required this.onRemove});

  final OutfitItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 188,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 256,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(1),
                  child: AppImage(
                    imageUrl: item.image,
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    placeholderColor: Colors.white,
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
                      child: const Icon(
                        Icons.close,
                        size: 14,
                        color: Color(0xFF111111),
                      ),
                    ),
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
