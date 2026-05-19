import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PhoneLoginScreen extends StatefulWidget {
  const PhoneLoginScreen({
    super.key,
    required this.onBack,
    required this.onClose,
  });

  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
                    'введите номер телефона',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  left: 30 * sx,
                  right: 30 * sx,
                  top: 289 * sy + yShift,
                  child: const Text(
                    'Позвоним и отправим код. Введите\n'
                    'последние 4 цифры номера телефона или\n'
                    'код из сообщения.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                      letterSpacing: 0,
                      color: Colors.black,
                    ),
                  ),
                ),
                Positioned(
                  left: 15 * sx,
                  right: 15 * sx,
                  top: 380 * sy + yShift,
                  height: 34,
                  child: _PhoneNumberField(controller: _phoneController),
                ),
                Positioned(
                  left: 15 * sx,
                  right: 15 * sx,
                  top: 438 * sy + yShift,
                  height: 43,
                  child: ElevatedButton(
                    onPressed: () {
                      // TODO: Request phone confirmation code.
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.zero,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                    ),
                    child: const Text(
                      'ПОЛУЧИТЬ КОД',
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: Colors.white,
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
                    onTap: () {
                      // TODO: Skip phone login.
                    },
                    child: const Text(
                      'НЕ СЕЙЧАС',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1,
                        letterSpacing: 0,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 20 * sx,
                  right: 20 * sx,
                  bottom: 44 * sy,
                  child: const Text(
                    'При входе и регистрации вы соглашаетесь с политикой\n'
                    'обработки персональных данных.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.25,
                      letterSpacing: 0,
                      color: Color(0xFF9B9B9B),
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
      splashRadius: 18,
      icon: Icon(icon, size: iconSize, color: Colors.black),
    );
  }
}

class _PhoneNumberField extends StatelessWidget {
  const _PhoneNumberField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    const phoneTextStyle = TextStyle(
      fontFamily: 'Montserrat',
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.2,
      letterSpacing: 0,
      color: Colors.black,
    );

    return SizedBox(
      height: 34,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(
            width: 44,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: Text('+7', style: phoneTextStyle),
                ),
                Positioned(
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
                      cursorColor: Colors.black,
                      style: phoneTextStyle,
                      decoration: const InputDecoration(
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

class _PhoneUnderline extends StatelessWidget {
  const _PhoneUnderline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFCFCFCF));
  }
}

class _PhoneNumberInputFormatter extends TextInputFormatter {
  const _PhoneNumberInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
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
