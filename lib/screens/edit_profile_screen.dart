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
    required this.onSave,
    required this.onConfirmEmail,
    required this.onDeleteAccount,
  });

  final AppProfile profile;
  final String accountEmail;
  final bool isSignedIn;
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
    _lastNameController = TextEditingController(text: widget.profile.lastName);
    _firstNameController = TextEditingController(
      text: widget.profile.firstName,
    );
    _middleNameController = TextEditingController(
      text: widget.profile.middleName,
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
        centerTitle: true,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
        ),
        title: const Text(
          'профиль',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Align(alignment: Alignment.centerLeft, child: _buildAvatar()),
              const SizedBox(height: 28),
              const Text(
                'личная информация',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 3),
              const Text(
                'Не забудьте сохранить данные',
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 12),
              _UnderlineField(
                controller: _lastNameController,
                label: 'Фамилия',
                required: true,
                textCapitalization: TextCapitalization.words,
                validator: _requiredValidator,
              ),
              _UnderlineField(
                controller: _firstNameController,
                label: 'Имя',
                required: true,
                textCapitalization: TextCapitalization.words,
                validator: _requiredValidator,
              ),
              _UnderlineField(
                controller: _middleNameController,
                label: 'Отчество',
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  _GenderChoice(
                    label: 'женщина',
                    selected: _gender == 'female',
                    onTap: () => setState(() => _gender = 'female'),
                  ),
                  const SizedBox(width: 22),
                  _GenderChoice(
                    label: 'мужчина',
                    selected: _gender == 'male',
                    onTap: () => setState(() => _gender = 'male'),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              const _SectionLabel('дата рождения'),
              _TapValueField(
                value: _birthDate == null
                    ? '00/00/0000'
                    : _formatDate(_birthDate!),
                required: true,
                trailing: const Icon(Icons.keyboard_arrow_down, size: 17),
                onTap: _pickBirthDate,
              ),
              if (_birthDate == null)
                const Padding(
                  padding: EdgeInsets.only(top: 5),
                  child: Text(
                    'Укажите дату рождения',
                    style: TextStyle(fontSize: 10, color: Color(0xFFD60000)),
                  ),
                ),
              const SizedBox(height: 38),
              const _SectionLabel('город'),
              _TapValueField(
                value: _city.trim().isEmpty ? 'Выберите город' : _city,
                trailing: const Icon(Icons.keyboard_arrow_down, size: 17),
                onTap: _selectCity,
              ),
              const SizedBox(height: 34),
              const _SectionLabel('контакты'),
              const SizedBox(height: 3),
              _PhoneField(controller: _phoneController),
              _UnderlineField(
                controller: _emailController,
                label: 'Email',
                required: true,
                keyboardType: TextInputType.emailAddress,
                validator: _emailValidator,
              ),
              const SizedBox(height: 29),
              _OutlineActionButton(
                label: 'ПОДТВЕРДИТЬ EMAIL',
                loading: _confirmingEmail,
                onPressed: _confirmEmail,
              ),
              const SizedBox(height: 7),
              _BlackActionButton(
                label: 'СОХРАНИТЬ',
                loading: _saving,
                onPressed: _save,
              ),
              const SizedBox(height: 58),
              _OutlineActionButton(
                label: 'УДАЛИТЬ АККАУНТ',
                loading: _deleting,
                onPressed: _askToDelete,
              ),
              const SizedBox(height: 9),
              const Text(
                'После удаления аккаунта восстановить его будет\nневозможно.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 8.5, height: 1.35),
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
      child: GestureDetector(
        onTap: _showAvatarActions,
        child: SizedBox(
          width: 84,
          height: 78,
          child: Stack(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFF1F1F1),
                  shape: BoxShape.circle,
                ),
                clipBehavior: Clip.antiAlias,
                child: source.isEmpty
                    ? const Icon(Icons.person_outline, size: 38)
                    : AppImage(
                        imageUrl: source,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
              ),
              Positioned(
                right: 4,
                bottom: 5,
                child: Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.2),
                  ),
                  child: const Icon(Icons.photo_camera_outlined, size: 15),
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
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || _birthDate == null) {
      _showMessage('Заполните обязательные поля');
      return;
    }
    setState(() => _saving = true);
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final phoneDigits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    final updated = widget.profile.copyWith(
      name: '$firstName $lastName'.trim(),
      firstName: firstName,
      lastName: lastName,
      middleName: _middleNameController.text.trim(),
      gender: _gender,
      birthDate: _birthDate!.toIso8601String().split('T').first,
      city: _city.trim(),
      phone: phoneDigits.isEmpty ? '' : '+7$phoneDigits',
      email: _emailController.text.trim().toLowerCase(),
      avatarUrl: _removeAvatar ? '' : widget.profile.avatarUrl,
    );
    final error = await widget.onSave(updated, _pickedAvatar);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    _showMessage('Данные профиля сохранены');
    Navigator.of(context).pop();
  }

  Future<void> _confirmEmail() async {
    final emailError = _emailValidator(_emailController.text);
    if (emailError != null) {
      _showMessage(emailError);
      return;
    }
    setState(() => _confirmingEmail = true);
    final result = await widget.onConfirmEmail(
      _emailController.text.trim().toLowerCase(),
    );
    if (!mounted) return;
    setState(() => _confirmingEmail = false);
    _showMessage(result ?? 'Письмо для подтверждения отправлено');
  }

  Future<void> _askToDelete() async {
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
    final error = await widget.onDeleteAccount();
    if (!mounted) return;
    setState(() => _deleting = false);
    if (error != null) {
      _showMessage(error);
      return;
    }
    Navigator.of(context).pop();
  }

  String? _requiredValidator(String? value) {
    return value == null || value.trim().isEmpty ? 'Обязательное поле' : null;
  }

  String? _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Укажите email';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      return 'Проверьте формат email';
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
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
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
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      validator: validator,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
        labelStyle: const TextStyle(fontSize: 11, color: Colors.black),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFD5D5D5)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.black),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const SizedBox(
          height: 48,
          width: 47,
          child: Row(
            children: [
              Text('+7', style: TextStyle(fontSize: 11)),
              Spacer(),
              Icon(Icons.keyboard_arrow_down, size: 14),
              SizedBox(width: 8),
            ],
          ),
        ),
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
              _PhoneInputFormatter(),
            ],
            style: const TextStyle(fontSize: 11),
            decoration: const InputDecoration(
              hintText: '900-000-00-00',
              contentPadding: EdgeInsets.only(bottom: 8),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Color(0xFFD5D5D5)),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.black),
              ),
            ),
          ),
        ),
      ],
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
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
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
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontSize: 11)),
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
    this.required = false,
  });

  final String value;
  final VoidCallback onTap;
  final Widget trailing;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 39,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFD5D5D5))),
        ),
        child: Row(
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
            Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
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
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: OutlinedButton(
        onPressed: loading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(),
          side: const BorderSide(color: Colors.black),
          foregroundColor: Colors.black,
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
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
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
      height: 40,
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          shape: const RoundedRectangleBorder(),
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
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
