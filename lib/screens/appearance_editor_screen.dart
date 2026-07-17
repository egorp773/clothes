import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/app_appearance.dart';
import '../core/app_typography.dart';
import '../widgets/app_appearance_background.dart';
import '../widgets/app_color_picker_sheet.dart';

class AppearanceEditorResult {
  const AppearanceEditorResult({required this.settings, this.wallpaperFile});

  final AppAppearanceSettings settings;
  final XFile? wallpaperFile;
}

class AppearanceEditorScreen extends StatefulWidget {
  const AppearanceEditorScreen({super.key, required this.initialSettings});

  final AppAppearanceSettings initialSettings;

  @override
  State<AppearanceEditorScreen> createState() => _AppearanceEditorScreenState();
}

class _AppearanceEditorScreenState extends State<AppearanceEditorScreen> {
  static const _darkBackground = Color(0xFF202228);
  static const _lightBackground = Color(0xFFF5F4F1);
  static const _darkPattern = Color(0xFFF2F2F4);
  static const _lightPattern = Color(0xFF4D5562);

  late AppAppearanceSettings _draft = widget.initialSettings.copyWith(
    theme: AppThemePreference.custom,
  );
  XFile? _wallpaperFile;
  Uint8List? _wallpaperBytes;
  bool _isPickingPhoto = false;

  Brightness get _brightness =>
      _draft.customDark ? Brightness.dark : Brightness.light;

  void _update(AppAppearanceSettings settings) {
    setState(
      () => _draft = settings.copyWith(theme: AppThemePreference.custom),
    );
  }

  Future<void> _pickPhoto() async {
    if (_isPickingPhoto) return;
    setState(() => _isPickingPhoto = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2200,
        imageQuality: 88,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _wallpaperFile = file;
        _wallpaperBytes = bytes;
        _draft = _draft.copyWith(
          theme: AppThemePreference.custom,
          background: AppBackgroundStyle.photo,
          wallpaperPath: file.path,
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть фото. Попробуйте ещё раз.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _selectPhoto() {
    _pickPhoto();
  }

  void _removePhoto() {
    setState(() {
      _wallpaperFile = null;
      _wallpaperBytes = null;
      _draft = _draft.copyWith(
        theme: AppThemePreference.custom,
        background: AppBackgroundStyle.plain,
        wallpaperPath: '',
      );
    });
  }

  Future<void> _pickThemeColor({
    required String title,
    required Color initialColor,
    required ValueChanged<Color> onSelected,
  }) async {
    final color = await showAppColorPicker(
      context: context,
      title: title,
      initialColor: initialColor,
    );
    if (color == null || !mounted) return;
    onSelected(color);
  }

  void _apply() {
    Navigator.pop(
      context,
      AppearanceEditorResult(
        settings: _draft.copyWith(theme: AppThemePreference.custom),
        wallpaperFile: _wallpaperFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editorTheme = buildAppTheme(_brightness, settings: _draft);
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    return Theme(
      data: editorTheme,
      child: Builder(
        builder: (context) {
          final palette = context.appPalette;
          return Scaffold(
            backgroundColor: palette.page.withValues(alpha: 1),
            appBar: AppBar(
              title: const Text(
                'Своя тема',
                style: TextStyle(fontSize: 18, fontWeight: AppTypography.bold),
              ),
              actions: [
                TextButton(
                  key: const Key('appearance-editor-apply'),
                  onPressed: _apply,
                  child: Text(
                    'Применить',
                    style: TextStyle(
                      color: palette.accent,
                      fontWeight: AppTypography.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            body: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(16, 8, 16, 28 + systemBottom),
              children: [
                _ThemePreview(
                  key: const Key('appearance-editor-preview'),
                  settings: _draft,
                  wallpaperBytes: _wallpaperBytes,
                ),
                const SizedBox(height: 20),
                _EditorSection(
                  title: 'Основа',
                  child: _ChoiceRow(
                    children: [
                      _ChoiceButton(
                        icon: Icons.light_mode_outlined,
                        label: 'Светлая',
                        selected: !_draft.customDark,
                        onTap: () => _setBrightness(false),
                      ),
                      _ChoiceButton(
                        icon: Icons.dark_mode_outlined,
                        label: 'Тёмная',
                        selected: _draft.customDark,
                        onTap: () => _setBrightness(true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _EditorSection(
                  title: 'Акцент',
                  subtitle: 'Кнопки и выбранные элементы',
                  child: _ColorPickerField(
                    key: const Key('appearance-accent-color'),
                    value: _draft.accentColor,
                    label: 'Цвет акцента',
                    onTap: () => _pickThemeColor(
                      title: 'Цвет акцента',
                      initialColor: _draft.accentColor,
                      onSelected: (color) => _update(
                        _draft.copyWith(accentColorValue: color.toARGB32()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _EditorSection(
                  title: 'Цвет фона',
                  subtitle: 'Карточки сохранят безопасный контраст',
                  child: _ColorPickerField(
                    key: const Key('appearance-background-color'),
                    value: _draft.backgroundColor,
                    label: 'Основной фон',
                    onTap: () => _pickThemeColor(
                      title: 'Цвет фона',
                      initialColor: _draft.backgroundColor,
                      onSelected: (color) => _update(
                        _draft.copyWith(backgroundColorValue: color.toARGB32()),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _EditorSection(
                  title: 'Фон страницы',
                  child: Column(
                    children: [
                      _ChoiceRow(
                        children: [
                          _ChoiceButton(
                            key: const Key('appearance-editor-plain-mode'),
                            icon: Icons.crop_square_rounded,
                            label: 'Чистый',
                            selected:
                                _draft.background == AppBackgroundStyle.plain,
                            onTap: () => _update(
                              _draft.copyWith(
                                background: AppBackgroundStyle.plain,
                              ),
                            ),
                          ),
                          _ChoiceButton(
                            key: const Key('appearance-editor-pattern-mode'),
                            icon: Icons.pattern_rounded,
                            label: 'Узор',
                            selected:
                                _draft.background == AppBackgroundStyle.pattern,
                            onTap: () => _update(
                              _draft.copyWith(
                                background: AppBackgroundStyle.pattern,
                              ),
                            ),
                          ),
                          _ChoiceButton(
                            key: const Key('appearance-editor-pick-photo'),
                            icon: Icons.photo_outlined,
                            label: 'Фото',
                            selected:
                                _draft.background == AppBackgroundStyle.photo,
                            loading: _isPickingPhoto,
                            onTap: _selectPhoto,
                          ),
                        ],
                      ),
                      if (_draft.background == AppBackgroundStyle.pattern) ...[
                        const SizedBox(height: 16),
                        _PatternChoices(
                          value: _draft.pattern,
                          backgroundColor: _draft.backgroundColor,
                          patternColor: _draft.patternColor,
                          intensity: _draft.patternIntensity,
                          onChanged: (value) =>
                              _update(_draft.copyWith(pattern: value)),
                        ),
                        const SizedBox(height: 12),
                        _ColorPickerField(
                          key: const Key('appearance-pattern-color'),
                          value: _draft.patternColor,
                          label: 'Цвет узора',
                          compact: true,
                          onTap: () => _pickThemeColor(
                            title: 'Цвет узора',
                            initialColor: _draft.patternColor,
                            onSelected: (color) => _update(
                              _draft.copyWith(
                                patternColorValue: color.toARGB32(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _LabeledSlider(
                          label: 'Интенсивность',
                          value: _draft.patternIntensity,
                          onChanged: (value) =>
                              _update(_draft.copyWith(patternIntensity: value)),
                        ),
                      ],
                      if (_draft.background == AppBackgroundStyle.photo) ...[
                        const SizedBox(height: 14),
                        if (_draft.wallpaperPath.trim().isNotEmpty ||
                            _wallpaperBytes != null)
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  key: const Key(
                                    'appearance-editor-replace-photo',
                                  ),
                                  onPressed: _isPickingPhoto
                                      ? null
                                      : _pickPhoto,
                                  icon: const Icon(
                                    Icons.photo_library_outlined,
                                  ),
                                  label: const Text('Заменить'),
                                  style: OutlinedButton.styleFrom(
                                    overlayColor: Colors.transparent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                key: const Key(
                                  'appearance-editor-remove-photo',
                                ),
                                onPressed: _removePhoto,
                                icon: const Icon(Icons.delete_outline_rounded),
                                label: const Text('Удалить'),
                                style: TextButton.styleFrom(
                                  foregroundColor: palette.muted,
                                  overlayColor: Colors.transparent,
                                ),
                              ),
                            ],
                          ),
                        _LabeledSlider(
                          label: 'Затемнение',
                          value: _draft.photoDim,
                          onChanged: (value) =>
                              _update(_draft.copyWith(photoDim: value)),
                        ),
                        _LabeledSlider(
                          label: 'Размытие',
                          value: _draft.photoBlur / 18,
                          onChanged: (value) =>
                              _update(_draft.copyWith(photoBlur: value * 18)),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Текст, иконки и кнопки подстраиваются автоматически. '
                  'Фото и узор приглушаются, чтобы товары и сообщения оставались главным.',
                  style: TextStyle(
                    color: palette.muted,
                    height: 1.45,
                    fontSize: 12,
                    fontWeight: AppTypography.medium,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _setBrightness(bool dark) {
    _update(
      _draft.copyWith(
        customDark: dark,
        backgroundColorValue: (dark ? _darkBackground : _lightBackground)
            .toARGB32(),
        patternColorValue: (dark ? _darkPattern : _lightPattern).toARGB32(),
      ),
    );
  }
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    super.key,
    required this.settings,
    required this.wallpaperBytes,
  });

  final AppAppearanceSettings settings;
  final Uint8List? wallpaperBytes;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final content = ColoredBox(
      color: palette.page,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.accent,
                  ),
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 18,
                    color: _onColor(palette.accent),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ваша тема',
                        style: TextStyle(
                          fontWeight: AppTypography.bold,
                          color: palette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Предпросмотр интерфейса',
                        style: TextStyle(fontSize: 10.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.settings_outlined, color: palette.ink, size: 20),
              ],
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: palette.surfaceRaised,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: palette.border),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadow,
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 48,
                    decoration: BoxDecoration(
                      color: palette.surfaceMuted,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(Icons.checkroom_outlined, color: palette.muted),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Новая вещь',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppTypography.bold,
                            color: palette.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          'Спокойный фон · чёткий текст',
                          style: TextStyle(fontSize: 10, color: palette.muted),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Открыть',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: AppTypography.bold,
                        color: _onColor(palette.accent),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final preview =
        wallpaperBytes != null &&
            settings.background == AppBackgroundStyle.photo
        ? Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: settings.photoBlur,
                  sigmaY: settings.photoBlur,
                ),
                child: Transform.scale(
                  scale: settings.photoBlur > 0 ? 1.04 : 1,
                  child: Image.memory(wallpaperBytes!, fit: BoxFit.cover),
                ),
              ),
              ColoredBox(
                color: settings.backgroundColor.withValues(
                  alpha: settings.photoDim,
                ),
              ),
              content,
            ],
          )
        : AppAppearanceBackground(settings: settings, child: content);

    return Container(
      height: 224,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: preview,
    );
  }
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: AppTypography.bold,
              color: palette.ink,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 11, color: palette.muted),
            ),
          ],
          const SizedBox(height: 13),
          child,
        ],
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          Expanded(child: children[index]),
          if (index != children.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ChoiceButton extends StatelessWidget {
  const _ChoiceButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 58,
        decoration: BoxDecoration(
          color: selected ? palette.surfaceMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? palette.accent : palette.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 17,
                height: 17,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.ink,
                ),
              )
            else
              Icon(icon, size: 19, color: palette.ink),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected
                    ? AppTypography.bold
                    : AppTypography.medium,
                color: selected ? palette.ink : palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorPickerField extends StatelessWidget {
  const _ColorPickerField({
    super.key,
    required this.value,
    required this.label,
    required this.onTap,
    this.compact = false,
  });

  final Color value;
  final String label;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final hex = (value.toARGB32() & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase();
    return Semantics(
      button: true,
      label: '$label, цвет #$hex',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: compact ? 56 : 64,
          padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 13),
          decoration: BoxDecoration(
            color: palette.surfaceMuted,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 34 : 40,
                height: compact ? 34 : 40,
                decoration: BoxDecoration(
                  color: value,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: palette.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.colorize_rounded,
                  size: compact ? 14 : 16,
                  color: _onColor(value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: compact ? 12 : 13,
                        fontWeight: AppTypography.semiBold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '#$hex · любой цвет',
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: compact ? 10 : 11,
                      ),
                    ),
                  ],
                ),
              ),
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFF5C7A),
                    Color(0xFFFFB84D),
                    Color(0xFF65D6A6),
                    Color(0xFF67B7FF),
                    Color(0xFF9A7CFF),
                  ],
                ).createShader(bounds),
                child: const Icon(
                  Icons.palette_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatternChoices extends StatelessWidget {
  const _PatternChoices({
    required this.value,
    required this.backgroundColor,
    required this.patternColor,
    required this.intensity,
    required this.onChanged,
  });

  final AppPatternStyle value;
  final Color backgroundColor;
  final Color patternColor;
  final double intensity;
  final ValueChanged<AppPatternStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return SizedBox(
      height: 94,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: AppPatternStyle.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final style = AppPatternStyle.values[index];
          final selected = style == value;
          final label = _patternLabel(style);
          return Semantics(
            button: true,
            selected: selected,
            label: 'Узор $label',
            child: GestureDetector(
              key: Key('appearance-pattern-${style.name}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(style),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                width: 76,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: selected ? palette.accent : palette.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AppAppearancePattern(
                            style: style,
                            color: patternColor,
                            intensity: intensity,
                          ),
                          if (selected)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                width: 20,
                                height: 20,
                                decoration: BoxDecoration(
                                  color: palette.accent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 14,
                                  color: _onColor(palette.accent),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      height: 25,
                      alignment: Alignment.center,
                      color: palette.surfaceMuted,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? palette.ink : palette.muted,
                          fontSize: 9,
                          fontWeight: selected
                              ? AppTypography.bold
                              : AppTypography.medium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(fontSize: 11.5, color: palette.muted),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: palette.accent,
              inactiveTrackColor: palette.surfaceMuted,
              thumbColor: palette.accent,
              overlayColor: Colors.transparent,
              trackHeight: 3,
            ),
            child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${(value.clamp(0, 1) * 100).round()}%',
            textAlign: TextAlign.end,
            style: TextStyle(fontSize: 10.5, color: palette.muted),
          ),
        ),
      ],
    );
  }
}

String _patternLabel(AppPatternStyle style) => switch (style) {
  AppPatternStyle.dots => 'Точки',
  AppPatternStyle.diagonal => 'Линии',
  AppPatternStyle.waves => 'Волны',
  AppPatternStyle.grid => 'Сетка',
  AppPatternStyle.doodles => 'Дудлы',
  AppPatternStyle.confetti => 'Конфетти',
  AppPatternStyle.bubbles => 'Круги',
};

Color _onColor(Color color) {
  final luminance = color.computeLuminance();
  final blackContrast = (luminance + 0.05) / 0.05;
  final whiteContrast = 1.05 / (luminance + 0.05);
  return blackContrast >= whiteContrast
      ? const Color(0xFF121316)
      : Colors.white;
}
