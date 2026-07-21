import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../models/product.dart';
import '../data/listing_edit_repository.dart';

class ListingEditScreen extends StatefulWidget {
  const ListingEditScreen({super.key, required this.product, this.repository});

  final Product product;
  final ListingEditRepository? repository;

  @override
  State<ListingEditScreen> createState() => _ListingEditScreenState();
}

class _ListingEditScreenState extends State<ListingEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ListingEditRepository _repository;
  late final Map<String, TextEditingController> _fields;
  final _picker = ImagePicker();
  final String _idempotencyKey = const Uuid().v4();
  final Set<String> _accepted = <String>{};
  List<XFile> _photos = const [];
  late String _audience;
  late bool _hasDefects;
  bool _submitting = false;

  static const _confirmations = <String, String>{
    'owns_item': 'Вещь принадлежит мне',
    'has_right_to_sell': 'Я имею право её продать',
    'has_item_in_possession': 'Вещь находится у меня',
    'owns_photos': 'Фотографии принадлежат мне',
    'description_is_accurate': 'Описание и состояние указаны достоверно',
    'item_is_authentic': 'Товар не является подделкой',
    'item_is_not_prohibited': 'Товар не запрещён к продаже',
  };

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? ListingEditRepository();
    final product = widget.product;
    _fields = {
      'title': TextEditingController(text: product.title),
      'description': TextEditingController(text: product.description),
      'price': TextEditingController(text: product.priceValue.toString()),
      'category': TextEditingController(
        text: product.categoryId.isNotEmpty
            ? product.categoryId
            : product.category,
      ),
      'brand': TextEditingController(text: product.brand),
      'size': TextEditingController(text: product.size),
      'primary_color': TextEditingController(
        text: product.primaryColor.isNotEmpty
            ? product.primaryColor
            : product.color,
      ),
      'condition': TextEditingController(text: product.condition),
      'material': TextEditingController(text: product.material),
      'pattern': TextEditingController(text: product.pattern),
      'season': TextEditingController(text: product.season),
      'style': TextEditingController(text: product.style),
      'fit': TextEditingController(text: product.fit),
      'sleeve_length': TextEditingController(text: product.sleeveLength),
      'closure': TextEditingController(text: product.closure),
      'secondary_colors': TextEditingController(
        text: product.secondaryColors.join(', '),
      ),
      'city': TextEditingController(
        text: product.city.isNotEmpty ? product.city : product.location,
      ),
      'defects_description': TextEditingController(
        text: product.defectsDescription,
      ),
    };
    _audience =
        const {'male', 'female', 'unisex', 'kids'}.contains(product.audience)
        ? product.audience
        : 'unisex';
    _hasDefects = product.hasDefects;
  }

  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final photos = await _picker.pickMultiImage(imageQuality: 92, limit: 8);
    if (!mounted || photos.isEmpty) return;
    setState(() => _photos = photos.take(8).toList(growable: false));
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    if (_accepted.length != _confirmations.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Подтвердите все заявления продавца'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final edited = await _repository.submit(
        product: widget.product,
        idempotencyKey: _idempotencyKey,
        changes: {
          for (final entry in _fields.entries)
            if (entry.key != 'secondary_colors' &&
                entry.key != 'defects_description')
              entry.key: entry.key == 'price'
                  ? int.parse(entry.value.text.trim())
                  : entry.value.text.trim(),
          'color': _fields['primary_color']!.text.trim(),
          'secondary_colors': _fields['secondary_colors']!.text
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(8)
              .toList(growable: false),
          'audience': _audience,
          'gender': _audience,
          'has_defects': _hasDefects,
          'defects_reviewed': true,
          'defects_description': _hasDefects
              ? _fields['defects_description']!.text.trim()
              : '',
        },
        replacementPhotos: _photos,
        confirmations: {
          for (final key in _confirmations.keys) key: _accepted.contains(key),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Изменения отправлены на модерацию'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(edited);
    } on ListingEditException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Редактировать объявление')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
          children: [
            const Text(
              'После сохранения объявление будет скрыто до повторной модерации.',
            ),
            const SizedBox(height: 18),
            _field('title', 'Название', maxLength: 80, required: true),
            _field('description', 'Описание', maxLength: 2000, maxLines: 5),
            _field(
              'price',
              'Цена, ₽',
              keyboardType: TextInputType.number,
              required: true,
              validator: (value) {
                final price = int.tryParse(value?.trim() ?? '');
                return price == null || price <= 0
                    ? 'Укажите цену больше нуля'
                    : null;
              },
            ),
            _field('category', 'Категория', required: true),
            _field('brand', 'Бренд', required: true),
            _field('size', 'Размер', required: true),
            _field('primary_color', 'Цвет', required: true),
            _field('condition', 'Состояние', required: true),
            DropdownButtonFormField<String>(
              key: const Key('listing-edit-audience'),
              initialValue: _audience,
              decoration: const InputDecoration(labelText: 'Для кого'),
              items: const [
                DropdownMenuItem(value: 'female', child: Text('Женское')),
                DropdownMenuItem(value: 'male', child: Text('Мужское')),
                DropdownMenuItem(value: 'unisex', child: Text('Унисекс')),
                DropdownMenuItem(value: 'kids', child: Text('Детское')),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      if (value != null) setState(() => _audience = value);
                    },
            ),
            const SizedBox(height: 12),
            _field('material', 'Материал'),
            _field('pattern', 'Узор'),
            _field('season', 'Сезон'),
            _field('style', 'Стиль'),
            _field('fit', 'Посадка'),
            _field('sleeve_length', 'Длина рукава'),
            _field('closure', 'Застёжка'),
            _field('secondary_colors', 'Дополнительные цвета через запятую'),
            _field('city', 'Город'),
            SwitchListTile.adaptive(
              key: const Key('listing-edit-has-defects'),
              contentPadding: EdgeInsets.zero,
              value: _hasDefects,
              title: const Text('У вещи есть дефекты'),
              subtitle: const Text(
                'Укажите все известные повреждения и следы носки',
              ),
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _hasDefects = value),
            ),
            if (_hasDefects)
              _field(
                'defects_description',
                'Описание дефектов',
                maxLength: 1000,
                maxLines: 4,
                required: true,
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('listing-edit-replace-photos'),
              onPressed: _submitting ? null : _pickPhotos,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(
                _photos.isEmpty
                    ? 'Заменить фотографии'
                    : 'Выбрано фото: ${_photos.length}',
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Подтверждения продавца',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            for (final entry in _confirmations.entries)
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _accepted.contains(entry.key),
                title: Text(entry.value),
                onChanged: _submitting
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          _accepted.add(entry.key);
                        } else {
                          _accepted.remove(entry.key);
                        }
                      }),
              ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(18),
        child: FilledButton(
          key: const Key('listing-edit-submit'),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Отправить на модерацию'),
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    int? maxLength,
    int maxLines = 1,
    bool required = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _fields[key],
        maxLength: maxLength,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(labelText: label),
        validator:
            validator ??
            (required
                ? (value) =>
                      (value?.trim().isEmpty ?? true) ? 'Заполните поле' : null
                : null),
      ),
    );
  }
}
