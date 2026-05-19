import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../models/product.dart';
import '../services/background_removal_service.dart';
import '../widgets/app_image.dart';

class OutfitOnlyItemScreen extends StatefulWidget {
  const OutfitOnlyItemScreen({
    super.key,
    required this.sidePadding,
    required this.onClose,
    required this.onAdd,
    this.onUploadImage,
  });

  final double sidePadding;
  final VoidCallback onClose;
  final Future<void> Function(Product product) onAdd;
  final Future<String?> Function(XFile imageFile, {String? folder})?
  onUploadImage;

  @override
  State<OutfitOnlyItemScreen> createState() => _OutfitOnlyItemScreenState();
}

class _OutfitOnlyItemScreenState extends State<OutfitOnlyItemScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final Uuid _uuid = const Uuid();

  XFile? _photo;
  XFile? _cutoutPhoto;
  String? _previewImage;
  bool _isProcessingBackground = false;
  bool _isSaving = false;

  bool get _canAdd =>
      !_isSaving &&
      !_isProcessingBackground &&
      _photo != null &&
      _titleController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _photo == null) {
        _pickPhoto();
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1800,
      maxHeight: 1800,
      imageQuality: 86,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _photo = picked;
      _cutoutPhoto = null;
      _previewImage = picked.path;
      _isProcessingBackground = true;
    });
    _processPhotoBackground(picked);
  }

  Future<void> _processPhotoBackground(XFile photo) async {
    try {
      final result = await removeBackgroundFromBytes(
        await photo.readAsBytes(),
        fileName: 'outfit-only-item.png',
      );
      if (!mounted || _photo != photo) return;
      setState(() {
        _cutoutPhoto = result.file;
        _previewImage = result.preview;
        _isProcessingBackground = false;
      });
    } catch (_) {
      if (!mounted || _photo != photo) return;
      setState(() => _isProcessingBackground = false);
    }
  }

  Future<void> _addItem() async {
    if (!_canAdd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Добавьте фото и название'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    final uploaded = await widget.onUploadImage?.call(
      _photo!,
      folder: 'outfits/items',
    );
    final uploadedCutout = _cutoutPhoto == null
        ? null
        : await widget.onUploadImage?.call(
            _cutoutPhoto!,
            folder: 'outfits/items/cutouts',
          );
    if (!mounted) return;

    if (uploaded == null) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось загрузить фото'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final title = _titleController.text.trim();
    await widget.onAdd(
      Product(
        id: _uuid.v4(),
        title: title,
        detailTitle: title,
        price: '',
        detailPrice: '',
        priceValue: 0,
        image: uploaded,
        images: [uploaded],
        outfitImages: uploadedCutout == null ? const [] : [uploadedCutout],
        category: 'Образ',
        brand: '',
        size: '',
        color: '',
        condition: '',
        dotsOnDark: false,
        isLocal: false,
        isHidden: true,
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
            _buildPhotoBox(),
            const SizedBox(height: 24),
            _buildTitleField(),
            const SizedBox(height: 28),
            _buildAddButton(),
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
                'Вещь для образа',
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

  Widget _buildPhotoBox() {
    return GestureDetector(
      onTap: _pickPhoto,
      child: Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8F9),
          border: Border.all(color: const Color(0xFFE7E7EA)),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: _photo == null
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '+',
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Добавить фото',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0B0B0B),
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Можно добавить только 1 фото',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFF8F8F94)),
                  ),
                ],
              )
            : Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: AppImage(
                  imageUrl: _previewImage ?? _photo!.path,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  placeholderColor: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildTitleField() {
    return TextField(
      controller: _titleController,
      onChanged: (_) => setState(() {}),
      maxLines: 1,
      textInputAction: TextInputAction.done,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Color(0xFF0B0B0B),
      ),
      decoration: const InputDecoration(
        labelText: 'Название',
        hintText: 'Например: рубашка',
        floatingLabelStyle: TextStyle(color: Color(0xFF0B0B0B)),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE2E2E6)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF0B0B0B)),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return GestureDetector(
      onTap: _isSaving ? null : _addItem,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: _canAdd ? Colors.black : const Color(0xFFC8C8CE),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Center(
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  'Добавить в образ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _canAdd ? Colors.white : const Color(0xFF8E8E93),
                  ),
                ),
        ),
      ),
    );
  }
}
