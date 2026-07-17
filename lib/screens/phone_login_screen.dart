import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_appearance.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({
    super.key,
    required this.onBack,
    required this.onClose,
    required this.onRequestCode,
    required this.onVerifyCode,
  });

  final VoidCallback onBack;
  final VoidCallback onClose;
  final Future<String?> Function(String phone) onRequestCode;
  final Future<String?> Function(String phone, String code) onVerifyCode;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  bool _codeRequested = false;
  bool _isSubmitting = false;
  String? _errorText;

  String get _normalizedPhone {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    return '+7$digits';
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    FocusScope.of(context).unfocus();
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) {
      setState(() => _errorText = 'Введите 10 цифр номера телефона');
      return;
    }
    final code = _codeController.text.replaceAll(RegExp(r'\D'), '');
    if (_codeRequested && code.length < 4) {
      setState(() => _errorText = 'Введите код из сообщения');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    final isVerifying = _codeRequested;
    String? error;
    try {
      error = isVerifying
          ? await widget.onVerifyCode(_normalizedPhone, code)
          : await widget.onRequestCode(_normalizedPhone);
    } catch (_) {
      error = isVerifying
          ? 'Не удалось подтвердить код. Попробуйте ещё раз'
          : 'Не удалось отправить код. Попробуйте ещё раз';
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorText = error;
      if (error == null && !_codeRequested) _codeRequested = true;
    });
    if (error == null && isVerifying) {
      widget.onClose();
    }
  }

  Future<void> _resendCode() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    String? error;
    try {
      error = await widget.onRequestCode(_normalizedPhone);
    } catch (_) {
      error = 'Не удалось отправить код. Попробуйте ещё раз';
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _errorText = error ?? 'Новый код отправлен';
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final sx = w / 360;
            final sy = h / 760;
            final yShift = MediaQuery.of(context).viewPadding.top;
            final titleSize = (21.5 * sx).clamp(21.0, 23.0);

            return Stack(
              children: [
                Positioned(
                  left: 14 * sx,
                  top: 48 * sy + yShift,
                  child: _HeaderIconButton(
                    icon: Icons.chevron_left,
                    iconSize: 26,
                    onPressed: widget.onBack,
                  ),
                ),
                Positioned(
                  right: 14 * sx,
                  top: 48 * sy + yShift,
                  child: _HeaderIconButton(
                    icon: Icons.close,
                    iconSize: 24,
                    onPressed: widget.onClose,
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 245 * sy + yShift,
                  child: Text(
                    _codeRequested
                        ? 'введите код подтверждения'
                        : 'введите номер телефона',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      letterSpacing: 0,
                      color: palette.ink,
                    ),
                  ),
                ),
                Positioned(
                  left: 30 * sx,
                  right: 30 * sx,
                  top: 289 * sy + yShift,
                  child: Text(
                    _codeRequested
                        ? 'Код отправлен на $_normalizedPhone.\n'
                              'Введите его, чтобы продолжить.'
                        : 'Отправим код подтверждения в сообщении.\n'
                              'Номер нужен для безопасного входа.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      letterSpacing: 0,
                      color: palette.ink,
                    ),
                  ),
                ),
                Positioned(
                  left: 15 * sx,
                  right: 15 * sx,
                  top: 380 * sy + yShift,
                  height: 34,
                  child: _codeRequested
                      ? _ConfirmationCodeField(controller: _codeController)
                      : _PhoneNumberField(controller: _phoneController),
                ),
                if (_errorText != null)
                  Positioned(
                    left: 20 * sx,
                    right: 20 * sx,
                    top: 414 * sy + yShift,
                    child: Text(
                      _errorText!,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        height: 1.25,
                        color: _errorText == 'Новый код отправлен'
                            ? const Color(0xFF4E7B55)
                            : const Color(0xFFB3261E),
                      ),
                    ),
                  ),
                Positioned(
                  left: 15 * sx,
                  right: 15 * sx,
                  top: 438 * sy + yShift,
                  height: 43,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      overlayColor: Colors.transparent,
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: _isSubmitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(
                            _codeRequested ? 'ВОЙТИ' : 'ПОЛУЧИТЬ КОД',
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              height: 1,
                              letterSpacing: 0,
                              color: colorScheme.onPrimary,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 507 * sy + yShift,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _isSubmitting
                        ? null
                        : (_codeRequested ? _resendCode : widget.onClose),
                    child: Text(
                      _codeRequested ? 'ОТПРАВИТЬ КОД ЕЩЁ РАЗ' : 'НЕ СЕЙЧАС',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: palette.ink,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20 * sx,
                  right: 20 * sx,
                  bottom: 44 * sy,
                  child: Text(
                    'При входе и регистрации вы соглашаетесь с политикой\n'
                    'обработки персональных данных.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      letterSpacing: 0,
                      color: palette.muted,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.iconSize,
    required this.onPressed,
  });

  final IconData icon;
  final double iconSize;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      icon: Icon(icon, size: iconSize, color: context.appPalette.ink),
    );
  }
}

class _PhoneNumberField extends StatelessWidget {
  const _PhoneNumberField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    final phoneTextStyle = TextStyle(
      fontFamily: 'Montserrat',
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: 0,
      color: palette.ink,
    );

    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Text('+7', style: phoneTextStyle),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PhoneUnderline(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  child: SizedBox(
                    height: 22,
                    child: TextField(
                      controller: controller,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      inputFormatters: const [_PhoneNumberInputFormatter()],
                      cursorColor: palette.ink,
                      style: phoneTextStyle,
                      decoration: InputDecoration(
                        hintText: '900-000-00-00',
                        hintStyle: phoneTextStyle,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _PhoneUnderline(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationCodeField extends StatelessWidget {
  const _ConfirmationCodeField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final palette = context.appPalette;
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(8),
      ],
      onSubmitted: (_) => FocusScope.of(context).unfocus(),
      cursorColor: palette.ink,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Montserrat',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: 7,
        color: palette.ink,
      ),
      decoration: InputDecoration(
        hintText: '000000',
        hintStyle: TextStyle(
          fontFamily: 'Montserrat',
          fontSize: 20,
          fontWeight: FontWeight.w500,
          letterSpacing: 7,
          color: palette.muted,
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: palette.ink),
        ),
        contentPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }
}

class _PhoneUnderline extends StatelessWidget {
  const _PhoneUnderline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: context.appPalette.border);
  }
}

class _PhoneNumberInputFormatter extends TextInputFormatter {
  const _PhoneNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10 &&
        (digits.startsWith('7') || digits.startsWith('8'))) {
      digits = digits.substring(1);
    }
    final limitedDigits = digits.length > 10 ? digits.substring(0, 10) : digits;
    final buffer = StringBuffer();

    for (var i = 0; i < limitedDigits.length; i += 1) {
      if (i == 3 || i == 6 || i == 8) {
        buffer.write('-');
      }
      buffer.write(limitedDigits[i]);
    }

    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
