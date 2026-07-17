import 'package:flutter/material.dart';

import '../core/app_typography.dart';

class SellerFollowButton extends StatefulWidget {
  const SellerFollowButton({
    super.key,
    required this.sellerId,
    this.listenable,
    this.canFollow,
    this.isFollowing,
    this.onToggle,
  });

  final String sellerId;
  final Listenable? listenable;
  final bool Function(String sellerId)? canFollow;
  final bool Function(String sellerId)? isFollowing;
  final Future<bool> Function(String sellerId)? onToggle;

  @override
  State<SellerFollowButton> createState() => _SellerFollowButtonState();
}

class _SellerFollowButtonState extends State<SellerFollowButton> {
  bool _isBusy = false;

  bool get _canFollow {
    final sellerId = widget.sellerId.trim();
    if (sellerId.isEmpty || widget.onToggle == null) return false;
    return widget.canFollow?.call(sellerId) ?? true;
  }

  bool get _isFollowing =>
      widget.isFollowing?.call(widget.sellerId.trim()) ?? false;

  Future<void> _toggle() async {
    if (_isBusy || !_canFollow) return;
    setState(() => _isBusy = true);
    try {
      await widget.onToggle!(widget.sellerId.trim());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.listenable;
    if (listenable == null) return _buildButton();
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) => _buildButton(),
    );
  }

  Widget _buildButton() {
    final following = _isFollowing;
    final isOwnProfile =
        widget.sellerId.trim().isNotEmpty &&
        widget.onToggle != null &&
        !(widget.canFollow?.call(widget.sellerId.trim()) ?? true);
    final enabled = _canFollow && !_isBusy;
    final background = following
        ? const Color(0xFFEDEDEF)
        : enabled
        ? Colors.black
        : const Color(0xFFF1F1F2);
    final foreground = following || !enabled
        ? const Color(0xFF242429)
        : Colors.white;

    return Semantics(
      button: true,
      toggled: following,
      label: isOwnProfile
          ? 'Ваш профиль'
          : following
          ? 'Вы подписаны'
          : 'Подписаться',
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: enabled ? _toggle : null,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            constraints: const BoxConstraints(minWidth: 106),
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            child: _isBusy
                ? SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: foreground,
                    ),
                  )
                : Text(
                    isOwnProfile
                        ? 'ВАШ ПРОФИЛЬ'
                        : following
                        ? 'ВЫ ПОДПИСАНЫ'
                        : 'ПОДПИСАТЬСЯ',
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 9.5,
                      height: 1,
                      fontWeight: AppTypography.bold,
                      letterSpacing: 0.2,
                      color: foreground,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
