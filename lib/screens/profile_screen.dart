import 'package:flutter/material.dart';

import '../models/app_profile.dart';
import '../models/created_outfit.dart';
import '../models/product.dart';
import '../widgets/app_image.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.profile,
    required this.products,
    required this.outfits,
    required this.isSignedIn,
    required this.isSigningIn,
    required this.accountLabel,
    required this.authError,
    required this.onSignInWithYandex,
    required this.onSignInWithTelegram,
    required this.onSignOut,
    required this.onUpdateProfile,
  });

  final AppProfile profile;
  final List<Product> products;
  final List<CreatedOutfit> outfits;
  final bool isSignedIn;
  final bool isSigningIn;
  final String? accountLabel;
  final String? authError;
  final Future<void> Function() onSignInWithYandex;
  final VoidCallback onSignInWithTelegram;
  final Future<void> Function() onSignOut;
  final Future<void> Function({required String name, required String handle})
  onUpdateProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, left: 18, right: 18),
          child: Text(
            'Профиль',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF070707),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
            child: Column(
              children: [
                _AuthPanel(
                  isSignedIn: isSignedIn,
                  isSigningIn: isSigningIn,
                  accountLabel: accountLabel,
                  authError: authError,
                  onSignInWithYandex: onSignInWithYandex,
                  onSignInWithTelegram: onSignInWithTelegram,
                  onSignOut: onSignOut,
                ),
                const SizedBox(height: 18),
                _ProfileHeader(profile: profile),
                _EditProfileButton(
                  profile: profile,
                  isEnabled: isSignedIn,
                  onSave: onUpdateProfile,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StatBox(
                        value: products.length.toString(),
                        label: 'вещей',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        value: outfits.length.toString(),
                        label: 'образов',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBox(
                        value: profile.rating.toStringAsFixed(1),
                        label: 'рейтинг',
                      ),
                    ),
                  ],
                ),
                if (products.isEmpty && outfits.isEmpty) ...[
                  const SizedBox(height: 56),
                  const Icon(
                    Icons.person_outline,
                    size: 44,
                    color: Color(0xFF050505),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Ваш профиль',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF070707),
                    ),
                  ),
                  const SizedBox(height: 9),
                  const SizedBox(
                    width: 280,
                    child: Text(
                      'Сохранённые вещи, образы и настройки аккаунта будут здесь.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF85858B),
                        height: 1.35,
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 18),
                  _SectionTitle('Мои вещи'),
                  const SizedBox(height: 12),
                  GridView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          mainAxisExtent: 224,
                        ),
                    itemBuilder: (context, index) {
                      return _ProfileProductCard(product: products[index]);
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.isSignedIn,
    required this.isSigningIn,
    required this.accountLabel,
    required this.authError,
    required this.onSignInWithYandex,
    required this.onSignInWithTelegram,
    required this.onSignOut,
  });

  final bool isSignedIn;
  final bool isSigningIn;
  final String? accountLabel;
  final String? authError;
  final Future<void> Function() onSignInWithYandex;
  final VoidCallback onSignInWithTelegram;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSignedIn ? Icons.verified_user_outlined : Icons.login,
                  size: 22,
                  color: const Color(0xFF0B0B0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSignedIn ? 'Аккаунт подключен' : 'Войдите в аккаунт',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF070707),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isSignedIn
                          ? accountLabel ?? 'Вход выполнен'
                          : 'Публикация вещей и образов доступна после входа.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF85858B),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (authError != null) ...[
            const SizedBox(height: 12),
            Text(
              authError!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB00020)),
            ),
          ],
          const SizedBox(height: 14),
          if (isSignedIn)
            _AuthButton(
              label: 'Выйти',
              icon: Icons.logout,
              isPrimary: false,
              onTap: isSigningIn ? null : onSignOut,
            )
          else ...[
            _AuthButton(
              label: 'Войти через Яндекс ID',
              icon: Icons.account_circle_outlined,
              isPrimary: true,
              isLoading: isSigningIn,
              onTap: isSigningIn ? null : onSignInWithYandex,
            ),
            const SizedBox(height: 10),
            _AuthButton(
              label: 'Telegram',
              icon: Icons.telegram,
              isPrimary: false,
              onTap: isSigningIn
                  ? null
                  : () async {
                      onSignInWithTelegram();
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  const _AuthButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
    this.isLoading = false,
  });

  final String label;
  final IconData icon;
  final bool isPrimary;
  final Future<void> Function()? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        height: 46,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF070707) : Colors.white,
          borderRadius: BorderRadius.circular(23),
          border: isPrimary ? null : Border.all(color: const Color(0xFFE1E1E5)),
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 19,
                      color: isPrimary ? Colors.white : const Color(0xFF070707),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: isPrimary
                            ? Colors.white
                            : const Color(0xFF070707),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.profile});

  final AppProfile profile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFF3F3F4),
          ),
          child: const Icon(
            Icons.person_outline,
            size: 34,
            color: Color(0xFF050505),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                profile.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF070707),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${profile.handle} · ${profile.city}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF8F8F94)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EditProfileButton extends StatelessWidget {
  const _EditProfileButton({
    required this.profile,
    required this.isEnabled,
    required this.onSave,
  });

  final AppProfile profile;
  final bool isEnabled;
  final Future<void> Function({required String name, required String handle})
  onSave;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: isEnabled ? () => _showEditSheet(context) : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(top: 12),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: isEnabled ? Colors.black : const Color(0xFFE7E7EA),
            borderRadius: BorderRadius.circular(19),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              isEnabled
                  ? 'Редактировать профиль'
                  : 'Войдите, чтобы редактировать',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isEnabled ? Colors.white : const Color(0xFF8F8F94),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EditProfileSheet(profile: profile, onSave: onSave),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({required this.profile, required this.onSave});

  final AppProfile profile;
  final Future<void> Function({required String name, required String handle})
  onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _handleController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile.name);
    _handleController = TextEditingController(text: widget.profile.handle);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    await widget.onSave(
      name: _nameController.text,
      handle: _handleController.text,
    );
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Профиль',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF070707),
              ),
            ),
            const SizedBox(height: 18),
            _ProfileTextField(
              label: 'Имя',
              controller: _nameController,
              hintText: 'Как вас показывать',
            ),
            const SizedBox(height: 14),
            _ProfileTextField(
              label: 'Username',
              controller: _handleController,
              hintText: '@username',
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _isSaving ? null : _save,
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black,
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
                      : const Text(
                          'Сохранить',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.label,
    required this.controller,
    required this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF070707),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hintText,
            filled: true,
            fillColor: const Color(0xFFF6F6F7),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF070707),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8F8F94)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF070707),
        ),
      ),
    );
  }
}

class _ProfileProductCard extends StatelessWidget {
  const _ProfileProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8F9),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: AppImage(
              imageUrl: product.image,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          product.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13, color: Color(0xFF070707)),
        ),
        const SizedBox(height: 3),
        Text(
          product.price,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF070707),
          ),
        ),
      ],
    );
  }
}
