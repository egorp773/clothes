import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_profile.dart';
import '../widgets/app_image.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({
    super.key,
    required this.profile,
    required this.accountEmail,
    required this.isSignedIn,
    this.onUpdateIdentity,
    required this.onSave,
    required this.onConfirmEmail,
    required this.onDeleteAccount,
  });

  final AppProfile profile;
  final String accountEmail;
  final bool isSignedIn;
  final Future<String?> Function({
    required String name,
    required String handle,
  })?
  onUpdateIdentity;
  final Future<String?> Function(AppProfile profile, XFile? avatarFile) onSave;
  final Future<String?> Function(String email) onConfirmEmail;
  final Future<String?> Function() onDeleteAccount;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const _cities = <String>[
    'Москва',
    'Санкт-Петербург',
    'Новосибирск',
    'Екатеринбург',
    'Казань',
    'Нижний Новгород',
    'Краснодар',
    'Самара',
    'Ростов-на-Дону',
    'Уфа',
  ];

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  late final TextEditingController _lastNameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _handleController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late String _gender;
  late String _city;
  DateTime? _birthDate;
  XFile? _pickedAvatar;
  bool _removeAvatar = false;
  bool _saving = false;
  bool _confirmingEmail = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    final nameParts = widget.profile.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    _lastNameController = TextEditingController(
      text: widget.profile.lastName.trim().isNotEmpty
          ? widget.profile.lastName
          : nameParts.skip(1).join(' '),
    );
    _firstNameController = TextEditingController(
      text: widget.profile.firstName.trim().isNotEmpty
          ? widget.profile.firstName
          : (nameParts.isEmpty ? '' : nameParts.first),
    );
    _middleNameController = TextEditingController(
      text: widget.profile.middleName,
    );
    _handleController = TextEditingController(
      text: widget.profile.handle.trim().replaceFirst(RegExp(r'^@'), ''),
    );
    _phoneController = TextEditingController(
      text: _nationalPhone(widget.profile.phone),
    );
    _emailController = TextEditingController(
      text: widget.profile.email.trim().isNotEmpty
          ? widget.profile.email
          : widget.accountEmail,
    );
    _gender = widget.profile.gender == 'female' ? 'female' : 'male';
    _city = widget.profile.city;
    _birthDate = DateTime.tryParse(widget.profile.birthDate);
  }

  @override
  void dispose() {
    _lastNameController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _handleController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        toolbarHeight: 58,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 19),
        ),
        title: const Text(
          'Редактировать профиль',
          style: TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.25,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
            children: [
              Center(child: _buildAvatar()),
              const SizedBox(height: 30),
              const _SectionLabel(
                'Основная информация',
                description: 'Эти данные будут видны в вашем профиле',
              ),
              const SizedBox(height: 14),
              _UnderlineField(
                controller: _lastNameController,
                label: 'Фамилия',
                required: true,
                textCapitalization: TextCapitalization.words,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              _UnderlineField(
                controller: _firstNameController,
                label: 'Имя',
                required: true,
                textCapitalization: TextCapitalization.words,
                validator: _requiredValidator,
              ),
              const SizedBox(height: 10),
              _UnderlineField(
                controller: _middleNameController,
                label: 'Отчество',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 10),
              _UnderlineField(
                controller: _handleController,
                label: 'Имя пользователя',
                required: true,
                prefixText: '@',
                validator: _handleValidator,
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Пол'),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _GenderChoice(
                      label: 'Женский',
                      selected: _gender == 'female',
                      onTap: () => setState(() => _gender = 'female'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GenderChoice(
                      label: 'Мужской',
                      selected: _gender == 'male',
                      onTap: () => setState(() => _gender = 'male'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const _SectionLabel('Дата рождения'),
              const SizedBox(height: 10),
              _TapValueField(
                value: _birthDate == null
                    ? 'Не указана'
                    : _formatDate(_birthDate!),
                trailing: const Icon(Icons.keyboard_arrow_down, size: 17),
                onTap: _pickBirthDate,
              ),
              const SizedBox(height: 26),
              const _SectionLabel(
                'Город',
                description: 'Поможет показывать предложения рядом',
              ),
              const SizedBox(height: 10),
              _TapValueField(
                value: _city.trim().isEmpty ? 'Выберите город' : _city,
                trailing: const Icon(Icons.keyboard_arrow_down, size: 17),
                onTap: _selectCity,
              ),
              const SizedBox(height: 28),
              const _SectionLabel(
                'Контакты',
                description: 'Не отображаются в публичном профиле',
              ),
              const SizedBox(height: 14),
              _PhoneField(controller: _phoneController),
              const SizedBox(height: 10),
              _UnderlineField(
                controller: _emailController,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
              const SizedBox(height: 12),
              _OutlineActionButton(
                label: 'Подтвердить email',
                loading: _confirmingEmail,
                onPressed: _confirmEmail,
              ),
              const SizedBox(height: 26),
              _BlackActionButton(
                label: 'Сохранить изменения',
                loading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 42),
              const Divider(height: 1, color: Color(0xFFE7E7EA)),
              const SizedBox(height: 22),
              const _SectionLabel('Управление аккаунтом'),
              const SizedBox(height: 12),
              _OutlineActionButton(
                label: 'Удалить аккаунт',
                loading: _deleting,
                onPressed: _askToDelete,
                destructive: true,
              ),
              const SizedBox(height: 10),
              const Text(
                'После удаления восстановить профиль и связанные с ним данные не получится.',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                  color: Color(0xFF7A7A80),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final selectedSource = _pickedAvatar?.path ?? '';
    final source = selectedSource.isNotEmpty
        ? selectedSource
        : (_removeAvatar ? '' : widget.profile.avatarUrl);
    return Semantics(
      button: true,
      label: 'Изменить фото профиля',
      child: InkWell(
        onTap: _showAvatarActions,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 92,
                height: 88,
                child: Stack(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F1F3),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFE3E3E6)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: source.isEmpty
                          ? const Icon(
                              Icons.person_outline_rounded,
                              size: 40,
                              color: Color(0xFF77777E),
                            )
                          : AppImage(
                              imageUrl: source,
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2.5),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Изменить фото',
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAvatarActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать из галереи'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Сделать фото'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            if (widget.profile.avatarUrl.isNotEmpty || _pickedAvatar != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Удалить фото',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'remove') {
      setState(() {
        _pickedAvatar = null;
        _removeAvatar = true;
      });
      return;
    }
    try {
      final image = await _picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image != null && mounted) {
        setState(() {
          _pickedAvatar = image;
          _removeAvatar = false;
        });
      }
    } catch (_) {
      _showMessage('Не удалось открыть фото. Проверьте разрешения приложения.');
    }
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'ДАТА РОЖДЕНИЯ',
      cancelText: 'ОТМЕНА',
      confirmText: 'ГОТОВО',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  Future<void> _selectCity() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
              child: Text(
                'Выберите город',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            for (final city in _cities)
              ListTile(
                title: Text(city),
                trailing: city == _city ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, city),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) setState(() => _city = selected);
  }

  Future<void> _save() async {
    if (_saving) return;
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid) {
      _showMessage('Заполните обязательные поля');
      return;
    }
    setState(() => _saving = true);
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final displayName = '$firstName $lastName'.trim();
    final handle = '@${_handleController.text.trim().replaceFirst('@', '')}';
    final phoneDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final updated = widget.profile.copyWith(
      name: displayName,
      handle: handle,
      firstName: firstName,
      lastName: lastName,
      middleName: _middleNameController.text.trim(),
      gender: _gender,
      birthDate: _birthDate?.toIso8601String().split('T').first ?? '',
      city: _city.trim(),
      phone: phoneDigits.isEmpty ? '' : '+7$phoneDigits',
      email: _emailController.text.trim().toLowerCase(),
      avatarUrl: _removeAvatar ? '' : widget.profile.avatarUrl,
    );
    try {
      final identityError = await widget.onUpdateIdentity?.call(
        name: displayName,
        handle: handle,
      );
      if (!mounted) return;
      if (identityError != null) {
        _showMessage(identityError);
        return;
      }
      final error = await widget.onSave(updated, _pickedAvatar);
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      _showMessage('Данные профиля сохранены');
      Navigator.of(context).pop();
    } catch (_) {
      _showMessage('Не удалось сохранить профиль. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmEmail() async {
    if (_confirmingEmail) return;
    if (_emailController.text.trim().isEmpty) {
      _showMessage('Укажите email');
      return;
    }
    final emailError = _emailValidator(_emailController.text);
    if (emailError != null) {
      _showMessage(emailError);
      return;
    }
    setState(() => _confirmingEmail = true);
    try {
      final result = await widget.onConfirmEmail(
        _emailController.text.trim().toLowerCase(),
      );
      if (!mounted) return;
      _showMessage(result ?? 'Письмо для подтверждения отправлено');
    } catch (_) {
      _showMessage('Не удалось отправить письмо. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _confirmingEmail = false);
    }
  }

  Future<void> _askToDelete() async {
    if (_deleting) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: Text(
          widget.isSignedIn
              ? 'Профиль и связанные с ним данные будут удалены без возможности восстановления.'
              : 'Локальные данные профиля будут удалены без возможности восстановления.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ОТМЕНА'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('УДАЛИТЬ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      final error = await widget.onDeleteAccount();
      if (!mounted) return;
      if (error != null) {
        _showMessage(error);
        return;
      }
      Navigator.of(context).pop();
    } catch (_) {
      _showMessage('Не удалось удалить аккаунт. Попробуйте ещё раз.');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String? _requiredValidator(String? value) {
    return value == null || value.trim().isEmpty ? 'Обязательное поле' : null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return null;
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Проверьте формат email';
    }
    return null;
  }

  String? _handleValidator(String? value) {
    final handle = (value ?? '').trim().replaceFirst('@', '');
    if (handle.isEmpty) return 'Укажите имя пользователя';
    if (!RegExp(r'^[A-Za-z0-9_]{3,24}$').hasMatch(handle)) {
      return '3–24 символа: латиница, цифры и _';
    }
    return null;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _nationalPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      return digits.substring(1);
    }
    return digits.length > 10 ? digits.substring(digits.length - 10) : digits;
  }

  static String _formatDate(DateTime date) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text, {this.description});

  final String text;
  final String? description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontFamily: 'Montserrat',
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.15,
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 4),
          Text(
            description!,
            style: const TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
              color: Color(0xFF85858B),
            ),
          ),
        ],
      ],
    );
  }
}

class _UnderlineField extends StatelessWidget {
  const _UnderlineField({
    required this.controller,
    required this.label,
    this.required = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.validator,
    this.prefixText,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;
  final String? prefixText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (required) ...[
              Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF001F),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(label),
          ],
        ),
        prefixText: prefixText,
        prefixStyle: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        labelStyle: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Color(0xFF67676D),
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        filled: true,
        fillColor: const Color(0xFFF5F5F7),
        contentPadding: const EdgeInsets.fromLTRB(15, 16, 15, 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Colors.black, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFD60000)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFD60000), width: 1.2),
        ),
      ),
    );
  }
}

class _PhoneField extends StatelessWidget {
  const _PhoneField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.phone,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(10),
        _PhoneInputFormatter(),
      ],
      style: const TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: 'Телефон',
        hintText: '900-000-00-00',
        prefixText: '+7  ',
        labelStyle: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 12,
          color: Color(0xFF67676D),
        ),
        prefixStyle: const TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        filled: true,
        fillColor: const Color(0xFFF5F5F7),
        contentPadding: const EdgeInsets.fromLTRB(15, 16, 15, 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Colors.black, width: 1.2),
        ),
      ),
    );
  }
}

class _PhoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length && i < 10; i++) {
      if (i == 3 || i == 6 || i == 8) buffer.write('-');
      buffer.write(digits[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _GenderChoice extends StatelessWidget {
  const _GenderChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEEEF0) : const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFE8E8EB),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? Colors.black : Colors.white,
                border: Border.all(color: Colors.black, width: 1.2),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 9),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TapValueField extends StatelessWidget {
  const _TapValueField({
    required this.value,
    required this.onTap,
    required this.trailing,
  });

  final String value;
  final VoidCallback onTap;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Ink(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F5F7),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _OutlineActionButton extends StatelessWidget {
  const _OutlineActionButton({
    required this.label,
    required this.loading,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(
            color: destructive
                ? const Color(0xFFFFD4D1)
                : const Color(0xFFDADADF),
          ),
          foregroundColor: destructive ? const Color(0xFFD92D20) : Colors.black,
          backgroundColor: destructive ? const Color(0xFFFFF7F6) : Colors.white,
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _BlackActionButton extends StatelessWidget {
  const _BlackActionButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        child: loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
