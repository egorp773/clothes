import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../widgets/app_image.dart';

class CreateScreen extends StatefulWidget {
  final double scale;
  final double sidePadding;
  final VoidCallback? onClose;
  final Function(int)? onTabChange;
  final Future<bool> Function(Product product)? onPublish;
  final Future<String?> Function(XFile imageFile, {String? folder})?
  onUploadImage;
  final String publishButtonText;
  final String successMessage;
  final String failureMessage;

  const CreateScreen({
    super.key,
    required this.scale,
    required this.sidePadding,
    this.onClose,
    this.onTabChange,
    this.onPublish,
    this.onUploadImage,
    this.publishButtonText = 'Опубликовать вещь',
    this.successMessage = 'Вещь опубликована',
    this.failureMessage = 'Не удалось сохранить вещь в базе',
  });

  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

class _CreateScreenState extends State<CreateScreen> {
  final ImagePicker _picker = ImagePicker();
  final Uuid _uuid = const Uuid();
  final List<XFile?> _pickedImages = List<XFile?>.filled(10, null);
  bool _isUploading = false;
  int _selectedCategoryIndex = 0;
  int _selectedColorIndex = 0;
  String _selectedItemType = 'Выберите тип вещи';

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _brandController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();

  String _selectedSize = 'Выберите размер';
  String _selectedCondition = 'Выберите состояние';

  final List<String> _categories = [
    'Верх',
    'Низ',
    'Обувь',
    'Аксессуары',
    'Украшения',
    'Другое',
  ];

  final Map<String, List<String>> _itemTypes = {
    'Верх': [
      'Худи',
      'Лонгслив',
      'Свитшот',
      'Футболка',
      'Рубашка',
      'Куртка',
      'Пальто',
      'Жилет',
      'Топ',
      'Кардиган',
    ],
    'Низ': [
      'Джинсы',
      'Брюки',
      'Шорты',
      'Юбка',
      'Карго',
      'Спортивные штаны',
      'Леггинсы',
    ],
    'Обувь': ['Кроссовки', 'Ботинки', 'Туфли', 'Лоферы', 'Сапоги', 'Сандалии'],
    'Аксессуары': [
      'Сумка',
      'Рюкзак',
      'Ремень',
      'Очки',
      'Головной убор',
      'Шарф',
    ],
    'Украшения': ['Подвеска', 'Кольцо', 'Браслет', 'Цепь', 'Серьги', 'Брошь'],
    'Другое': ['Другое'],
  };

  // Size options based on category
  List<String> get _sizes {
    if (_categories[_selectedCategoryIndex] == 'Обувь') {
      return ['35', '36', '37', '38', '39', '40', '41', '42', '43', '44', '45'];
    }
    return ['XXS', 'XS', 'S', 'M', 'L', 'XL', 'XXL', 'One Size'];
  }

  final List<_ColorOption> _mainColors = [
    _ColorOption(name: 'Чёрный', color: const Color(0xFF000000)),
    _ColorOption(name: 'Тёмно-серый', color: const Color(0xFF555555)),
    _ColorOption(name: 'Серый', color: const Color(0xFF888888)),
    _ColorOption(
      name: 'Белый',
      color: const Color(0xFFFFFFFF),
      border: const Color(0xFFD9D9DC),
    ),
    _ColorOption(name: 'Коричневый', color: const Color(0xFF8B4513)),
    _ColorOption(name: 'Бежевый', color: const Color(0xFFF5DEB3)),
    _ColorOption(name: 'Синий', color: const Color(0xFF0066CC)),
    _ColorOption(name: 'Зелёный', color: const Color(0xFF228B22)),
    _ColorOption(name: 'Красный', color: const Color(0xFFDC143C)),
  ];

  final List<_ColorOption> _allColors = [
    _ColorOption(name: 'Чёрный', color: const Color(0xFF000000)),
    _ColorOption(name: 'Тёмно-серый', color: const Color(0xFF555555)),
    _ColorOption(name: 'Серый', color: const Color(0xFF888888)),
    _ColorOption(
      name: 'Белый',
      color: const Color(0xFFFFFFFF),
      border: const Color(0xFFD9D9DC),
    ),
    _ColorOption(name: 'Коричневый', color: const Color(0xFF8B4513)),
    _ColorOption(name: 'Бежевый', color: const Color(0xFFF5DEB3)),
    _ColorOption(name: 'Кремовый', color: const Color(0xFFFFFDD0)),
    _ColorOption(name: 'Оливковый', color: const Color(0xFF808000)),
    _ColorOption(name: 'Хаки', color: const Color(0xFFC3B091)),
    _ColorOption(name: 'Зелёный', color: const Color(0xFF228B22)),
    _ColorOption(name: 'Мятный', color: const Color(0xFF98FF98)),
    _ColorOption(name: 'Голубой', color: const Color(0xFF87CEEB)),
    _ColorOption(name: 'Синий', color: const Color(0xFF0066CC)),
    _ColorOption(name: 'Тёмно-синий', color: const Color(0xFF000080)),
    _ColorOption(name: 'Фиолетовый', color: const Color(0xFF8B008B)),
    _ColorOption(name: 'Лавандовый', color: const Color(0xFFE6E6FA)),
    _ColorOption(name: 'Розовый', color: const Color(0xFFFFC0CB)),
    _ColorOption(name: 'Малиновый', color: const Color(0xFFE0115F)),
    _ColorOption(name: 'Красный', color: const Color(0xFFDC143C)),
    _ColorOption(name: 'Бордовый', color: const Color(0xFF800020)),
    _ColorOption(name: 'Оранжевый', color: const Color(0xFFFF6600)),
    _ColorOption(name: 'Жёлтый', color: const Color(0xFFFFD700)),
    _ColorOption(name: 'Золотой', color: const Color(0xFFDAA520)),
    _ColorOption(name: 'Серебристый', color: const Color(0xFFC0C0C0)),
  ];

  final List<String> _conditions = [
    'Новое с биркой',
    'Новое без бирки',
    'Отличное',
    'Хорошее',
    'Есть следы носки',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<XFile> get _selectedImages => _pickedImages.whereType<XFile>().toList();

  int? get _firstEmptyImageIndex {
    final index = _pickedImages.indexWhere((image) => image == null);
    return index == -1 ? null : index;
  }

  Future<void> _pickNextImage(ImageSource source) async {
    final index = _firstEmptyImageIndex;
    if (index == null) {
      _showSnackBar('Можно добавить до 10 фото');
      return;
    }
    await _pickImage(source, slotIndex: index);
  }

  Future<void> _pickImage(
    ImageSource source, {
    bool isMain = false,
    int? slotIndex,
  }) async {
    final XFile? pickedFile = await _picker.pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    setState(() {
      if (slotIndex != null) {
        _pickedImages[slotIndex] = pickedFile;
      } else if (isMain) {
        _pickedImages[0] = pickedFile;
      } else {
        final index = _firstEmptyImageIndex;
        if (index != null) _pickedImages[index] = pickedFile;
      }
    });
  }

  Future<void> _removeImage(int index) async {
    setState(() => _pickedImages[index] = null);
  }

  Future<List<String>> _uploadImages() async {
    final images = _selectedImages;
    if (images.isEmpty) return [];
    final List<String> urls = [];
    for (final image in images) {
      final url = await widget.onUploadImage?.call(image, folder: 'items');
      if (url != null) urls.add(url);
    }
    return urls;
  }

  Future<void> _onPublish() async {
    if (_titleController.text.isEmpty || _priceController.text.isEmpty) {
      _showSnackBar('Заполните название и цену');
      return;
    }
    final priceValue =
        int.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
    final category = _categories[_selectedCategoryIndex];
    final title = _titleController.text.trim();
    final description = _descriptionController.text.trim();

    if (_selectedImages.isEmpty) {
      _showSnackBar('Добавьте фото вещи');
      return;
    }

    setState(() => _isUploading = true);
    final imageUrls = await _uploadImages();
    setState(() => _isUploading = false);

    if (imageUrls.isEmpty) {
      _showSnackBar('Не удалось загрузить фото в базу');
      return;
    }

    final product = Product(
      id: _uuid.v4(),
      title: title,
      detailTitle: title,
      description: description,
      price: '${_formatPrice(priceValue)} \u20BD',
      detailPrice: priceValue.toString(),
      priceValue: priceValue,
      image: imageUrls.first,
      images: imageUrls,
      category: category,
      brand: _brandController.text.trim().isEmpty
          ? 'Brand'
          : _brandController.text.trim(),
      size: _selectedSize.startsWith('Выберите') ? 'One Size' : _selectedSize,
      color: _allColors[_selectedColorIndex].name,
      condition: _selectedCondition.startsWith('Выберите')
          ? 'Хорошее'
          : _selectedCondition,
      dotsOnDark: _allColors[_selectedColorIndex].name != 'Белый',
    );
    final didPublish = await widget.onPublish?.call(product) ?? false;
    if (!mounted) return;
    _showSnackBar(didPublish ? widget.successMessage : widget.failureMessage);
  }

  String _formatPrice(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  void _showSizePicker() {
    _showSheet(
      title: 'Размер',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _sizes.map((size) {
          final isSelected = size == _selectedSize;
          return GestureDetector(
            onTap: () {
              setState(() => _selectedSize = size);
              Navigator.pop(context);
            },
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isSelected ? Colors.black : const Color(0xFFF2F2F4),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Center(
                child: Text(
                  size,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : const Color(0xFF111111),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showConditionPicker() {
    _showOptionSheet(
      title: 'Состояние',
      options: _conditions,
      selected: _selectedCondition,
      onSelected: (value) => setState(() => _selectedCondition = value),
    );
  }

  void _showOptionSheet({
    required String title,
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    _showSheet(
      title: title,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.56,
        ),
        child: ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          itemCount: options.length,
          separatorBuilder: (context, index) => const SizedBox(height: 2),
          itemBuilder: (ctx, index) {
            final value = options[index];
            final isSelected = value == selected;
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                onSelected(value);
                Navigator.pop(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 13,
                  horizontal: 2,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF0B0B0B),
                        ),
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 18,
                        color: Color(0xFF0B0B0B),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  void _showSheet({required String title, required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0B),
                ),
              ),
              const SizedBox(height: 16),
              child,
              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }

  void _showItemTypePicker() {
    final types = _itemTypes[_categories[_selectedCategoryIndex]] ?? ['Другое'];
    _showOptionSheet(
      title: 'Тип вещи',
      options: types,
      selected: _selectedItemType,
      onSelected: (value) => setState(() => _selectedItemType = value),
    );
  }

  void _selectColor(_ColorOption option) {
    final index = _allColors.indexWhere((color) => color.name == option.name);
    if (index != -1) {
      setState(() => _selectedColorIndex = index);
    }
  }

  void _showColorPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Выберите цвет',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0B),
                ),
              ),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.62,
                ),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 8,
                    childAspectRatio: 0.88,
                  ),
                  itemCount: _allColors.length,
                  itemBuilder: (ctx, index) {
                    final option = _allColors[index];
                    final isSelected = index == _selectedColorIndex;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedColorIndex = index);
                        Navigator.pop(ctx);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildColorDot(option, isSelected, size: 34),
                          const SizedBox(height: 6),
                          Text(
                            option.name,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF0B0B0B),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onCategoryChanged(int index) {
    setState(() {
      _selectedCategoryIndex = index;
      _selectedItemType = 'Выберите тип вещи';
      _selectedSize = 'Выберите размер';
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          widget.sidePadding,
          topInset + 14,
          widget.sidePadding,
          150,
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
            _buildTitleField(),
            const SizedBox(height: 20),
            _buildDescriptionField(),
            const SizedBox(height: 20),
            _buildCategoriesSection(),
            const SizedBox(height: 20),
            _buildItemTypeSection(),
            const SizedBox(height: 20),
            _buildBrandField(),
            const SizedBox(height: 20),
            _buildPriceField(),
            const SizedBox(height: 20),
            _buildDoubleSelect(),
            const SizedBox(height: 20),
            _buildColorsSection(),
            const SizedBox(height: 24),
            _buildPublishButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const SizedBox(
      height: 44,
      child: Center(
        child: Text(
          'Опубликовать вещь',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0B0B0B),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadBoxV2() {
    return GestureDetector(
      onTap: () => _showImageSourcePickerV2(),
      child: Container(
        width: double.infinity,
        height: 96,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE7E7EA)),
          borderRadius: BorderRadius.circular(12),
        ),
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
              'Добавить фото',
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
        itemCount: _pickedImages.length,
        separatorBuilder: (context, index) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final image = _pickedImages[index];
          return GestureDetector(
            onTap: () => _showImageSourcePickerV2(slotIndex: index),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE7E7EA)),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: image == null
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
                        AppImage(
                          imageUrl: image.path,
                          width: 64,
                          height: 64,
                          fit: BoxFit.contain,
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
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

  void _showImageSourcePickerV2({int? slotIndex}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Добавить фото',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0B),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Можно добавить до 10 фото',
                style: TextStyle(fontSize: 12, color: Color(0xFF8F8F94)),
              ),
              const SizedBox(height: 20),
              _SheetOption(
                label: 'Сделать фото',
                icon: Icons.camera_alt_outlined,
                onTap: () {
                  Navigator.pop(ctx);
                  if (slotIndex == null) {
                    _pickNextImage(ImageSource.camera);
                  } else {
                    _pickImage(ImageSource.camera, slotIndex: slotIndex);
                  }
                },
              ),
              _SheetOption(
                label: 'Выбрать из галереи',
                icon: Icons.photo_library_outlined,
                onTap: () {
                  Navigator.pop(ctx);
                  if (slotIndex == null) {
                    _pickNextImage(ImageSource.gallery);
                  } else {
                    _pickImage(ImageSource.gallery, slotIndex: slotIndex);
                  }
                },
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Название вещи',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _titleController,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF111111)),
          decoration: const InputDecoration(
            hintText: 'Введите название',
            hintStyle: TextStyle(fontSize: 12.5, color: Color(0xFF8F8F94)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const Divider(color: Color(0xFFE7E7EA), height: 1),
      ],
    );
  }

  Widget _buildDescriptionField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Описание (необязательно)',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _descriptionController,
                maxLines: null,
                minLines: 1,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF111111),
                ),
                decoration: const InputDecoration(
                  hintText:
                      'Расскажите о вещи: материал, бренд, состояние, размер и т.д.',
                  hintStyle: TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF8F8F94),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '0/300',
              style: TextStyle(fontSize: 11.5, color: const Color(0xFFB0B0B5)),
            ),
          ],
        ),
        const Divider(color: Color(0xFFE7E7EA), height: 1),
      ],
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Категория',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(_categories.length, (index) {
              final isActive = index == _selectedCategoryIndex;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _onCategoryChanged(index),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isActive
                          ? const Color(0xFF000000)
                          : const Color(0xFFF0F0F1),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Center(
                      child: Text(
                        _categories[index],
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF111111),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildItemTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Тип вещи',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _showItemTypePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE7E7EA))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedItemType,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: _selectedItemType == 'Выберите тип вещи'
                          ? const Color(0xFF8F8F94)
                          : const Color(0xFF111111),
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Color(0xFFC7C7CC),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Бренд',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 31,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE7E7EA))),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _brandController,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF111111),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Введите бренд',
                    hintStyle: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF8F8F94),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.only(bottom: 9),
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: Color(0xFFC7C7CC),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Цена',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF111111),
                ),
                decoration: const InputDecoration(
                  hintText: 'Введите цену',
                  hintStyle: TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF8F8F94),
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Text(
              '\u20BD',
              style: TextStyle(fontSize: 12.5, color: const Color(0xFF0B0B0B)),
            ),
          ],
        ),
        const Divider(color: Color(0xFFE7E7EA), height: 1),
      ],
    );
  }

  Widget _buildDoubleSelect() {
    return Row(
      children: [
        Expanded(
          child: _buildSelectBox('Размер', _selectedSize, _showSizePicker),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSelectBox(
            'Состояние',
            _selectedCondition,
            _showConditionPicker,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectBox(String title, String value, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE7E7EA)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      color: value.startsWith('Выберите')
                          ? const Color(0xFF8F8F94)
                          : const Color(0xFF111111),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(
                  Icons.keyboard_arrow_down,
                  size: 14,
                  color: Color(0xFFC7C7CC),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorsSection() {
    final selectedColor = _allColors[_selectedColorIndex];
    final selectedIsMain = _mainColors.any(
      (option) => option.name == selectedColor.name,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Цвет',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B0B0B),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            ..._mainColors.map((option) {
              final isActive = option.name == selectedColor.name;
              return GestureDetector(
                onTap: () => _selectColor(option),
                child: _buildColorDot(option, isActive, size: 22),
              );
            }),
            if (!selectedIsMain)
              GestureDetector(
                onTap: _showColorPicker,
                child: _buildColorDot(selectedColor, true, size: 22),
              ),
            GestureDetector(
              onTap: _showColorPicker,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFDCDCE0)),
                ),
                child: const Center(
                  child: Text(
                    '+',
                    style: TextStyle(
                      fontSize: 15,
                      color: Color(0xFF0B0B0B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildColorDot(
    _ColorOption option,
    bool isActive, {
    required double size,
  }) {
    final ringColor = option.color == const Color(0xFFFFFFFF)
        ? const Color(0xFFBFC0C5)
        : const Color(0xFF0B0B0B);

    return Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: isActive ? Border.all(color: ringColor, width: 1.5) : null,
      ),
      child: Center(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: option.color,
            border: Border.all(
              color: option.border ?? Colors.transparent,
              width: option.border == null ? 0 : 1,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublishButton() {
    return GestureDetector(
      onTap: _isUploading ? null : _onPublish,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: _isUploading
              ? const Color(0xFF888888)
              : const Color(0xFF000000),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: _isUploading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.publishButtonText,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SheetOption({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 22, color: const Color(0xFF0B0B0B)),
            const SizedBox(width: 14),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0B0B0B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorOption {
  final String name;
  final Color color;
  final Color? border;

  _ColorOption({required this.name, required this.color, this.border});
}
