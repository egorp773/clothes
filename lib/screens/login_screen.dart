import 'dart:async';

import 'package:flutter/material.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({
    super.key,
    required this.onClose,
    required this.onYandexTap,
    required this.onVkTap,
    required this.onPhoneTap,
    required this.isSigningIn,
    this.authError,
  });

  final VoidCallback onClose;
  final Future<void> Function() onYandexTap;
  final Future<void> Function() onVkTap;
  final VoidCallback onPhoneTap;
  final bool isSigningIn;
  final String? authError;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).viewPadding.top;
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(11, topInset + 4, 11, 14 + bottomInset),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close, size: 24, color: Colors.black),
                  splashRadius: 22,
                ),
              ),
              const SizedBox(height: 54),
              const SizedBox(
                width: 300,
                child: Text(
                  'войти в личный\nкабинет',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    height: 1.12,
                    fontWeight: FontWeight.w500,
                    color: Colors.black,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              const Spacer(flex: 2),
              const Text(
                'через сервис',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  fontWeight: FontWeight.w500,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ServiceLoginButton(
                    key: const Key('login-yandex'),
                    label: 'Яндекс ID',
                    logo: 'Я',
                    onTap: isSigningIn ? null : onYandexTap,
                  ),
                  const SizedBox(width: 22),
                  _ServiceLoginButton(
                    key: const Key('login-vk'),
                    label: 'VK ID',
                    logo: 'VK',
                    onTap: isSigningIn ? null : onVkTap,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 42,
                child: isSigningIn
                    ? const Center(
                        child: SizedBox(
                          key: Key('login-auth-loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        ),
                      )
                    : authError?.trim().isNotEmpty == true
                    ? Center(
                        child: Text(
                          authError!.trim(),
                          key: const Key('login-auth-error'),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFB3261E),
                          ),
                        ),
                      )
                    : null,
              ),
              const Spacer(flex: 5),
              _PhoneLoginButton(
                key: const Key('login-phone'),
                onTap: isSigningIn ? null : onPhoneTap,
              ),
              const SizedBox(height: 11),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'При входе и регистрации вы соглашаетесь с политикой\nобработки персональных данных.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceLoginButton extends StatelessWidget {
  const _ServiceLoginButton({
    super.key,
    required this.label,
    required this.logo,
    required this.onTap,
  });

  final String label;
  final String logo;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null ? null : () => unawaited(onTap!()),
      child: SizedBox(
        width: 78,
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: onTap == null ? const Color(0xFFB6B6BA) : Colors.black,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  logo,
                  style: TextStyle(
                    fontSize: logo.length > 1 ? 20 : 28,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1,
                fontWeight: FontWeight.w500,
                color: onTap == null ? const Color(0xFF8E8E93) : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhoneLoginButton extends StatelessWidget {
  const _PhoneLoginButton({super.key, required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: onTap == null
                ? const Color(0xFFB6B6BA)
                : const Color(0xFF222222),
            width: 0.8,
          ),
        ),
        child: Center(
          child: Text(
            'ПО НОМЕРУ ТЕЛЕФОНА',
            style: TextStyle(
              fontSize: 13,
              height: 1,
              fontWeight: FontWeight.w500,
              color: onTap == null ? const Color(0xFF8E8E93) : Colors.black,
              letterSpacing: 0,
            ),
          ),
        ),
      ),
    );
  }
}
