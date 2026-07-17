import 'package:flutter/material.dart';

import '../../core/app_appearance.dart';
import '../../models/message_thread.dart';
import '../../widgets/app_image.dart';
import 'chat_tokens.dart';

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.size = 54,
    this.isGroup = false,
    this.members = const [],
    this.productImage = '',
    this.showOnline = false,
    this.isProduct = false,
  });

  factory ChatAvatar.thread({
    Key? key,
    required MessageThread thread,
    required String currentUserId,
    double size = 54,
    bool showOnline = false,
  }) {
    final hasProduct = thread.productImage.trim().isNotEmpty;
    final showProductAsPrimary = thread.isProductChat && hasProduct;
    return ChatAvatar(
      key: key,
      imageUrl: showProductAsPrimary
          ? thread.productImage
          : thread.displayAvatar(currentUserId),
      name: showProductAsPrimary
          ? thread.productTitle
          : thread.displayTitle(currentUserId),
      size: size,
      isGroup: !showProductAsPrimary && thread.isGroup,
      members: showProductAsPrimary
          ? const []
          : thread.members
                .where((member) => member.id != currentUserId)
                .toList(growable: false),
      productImage: '',
      showOnline: showOnline,
      isProduct: showProductAsPrimary,
    );
  }

  final String imageUrl;
  final String name;
  final double size;
  final bool isGroup;
  final List<ConversationMember> members;
  final String productImage;
  final bool showOnline;
  final bool isProduct;

  @override
  Widget build(BuildContext context) {
    final productSize = size * 0.38;
    return SizedBox(
      width: size + (productImage.isEmpty ? 0 : 3),
      height: size + (productImage.isEmpty ? 0 : 3),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            top: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isProduct ? size * 0.2 : 999),
              child: SizedBox(
                width: size,
                height: size,
                child: imageUrl.trim().isNotEmpty
                    ? AppImage(
                        imageUrl: imageUrl,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      )
                    : isGroup && members.length > 1
                    ? _GroupAvatar(members: members)
                    : _InitialsAvatar(name: name),
              ),
            ),
          ),
          if (productImage.trim().isNotEmpty)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: productSize,
                height: productSize,
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: context.appPalette.surface,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: AppImage(imageUrl: productImage, fit: BoxFit.cover),
                ),
              ),
            )
          else if (showOnline)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: size * 0.24,
                height: size * 0.24,
                decoration: BoxDecoration(
                  color: ChatTokens.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.appPalette.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+'));
    final initials = parts
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase());
    final label = initials.isEmpty ? '?' : initials.join();
    return ColoredBox(
      color: context.appPalette.ink,
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: context.appPalette.page,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar({required this.members});

  final List<ConversationMember> members;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF202124),
      child: Stack(
        children: [
          Align(
            alignment: const Alignment(-0.43, -0.38),
            child: _MemberInitial(member: members.first),
          ),
          Align(
            alignment: const Alignment(0.43, 0.38),
            child: _MemberInitial(member: members[1]),
          ),
        ],
      ),
    );
  }
}

class _MemberInitial extends StatelessWidget {
  const _MemberInitial({required this.member});

  final ConversationMember member;

  @override
  Widget build(BuildContext context) {
    final initial = member.name.trim().isEmpty
        ? '?'
        : member.name.trim().characters.first.toUpperCase();
    return Container(
      width: 28,
      height: 28,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1),
      ),
      child: ClipOval(
        child: member.avatarUrl.trim().isNotEmpty
            ? AppImage(imageUrl: member.avatarUrl, fit: BoxFit.cover)
            : Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
      ),
    );
  }
}
