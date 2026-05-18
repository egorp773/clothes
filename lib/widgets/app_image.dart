import 'dart:io';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Color? placeholderColor;
  final Alignment alignment;

  const AppImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderColor,
    this.alignment = Alignment.center,
  });

  bool get _isHttpNetwork {
    return imageUrl.startsWith('http://') || imageUrl.startsWith('https://');
  }

  bool get _isBrowserBlob => imageUrl.startsWith('blob:');

  bool get _isDataImage => imageUrl.startsWith('data:image/');

  bool get _isAsset => imageUrl.startsWith('assets/');

  @override
  Widget build(BuildContext context) {
    Widget image;

    if (_isDataImage) {
      image = _MemoryDataImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        placeholder: _placeholder,
      );
    } else if (_isHttpNetwork) {
      image = CachedNetworkImage(
        imageUrl: imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        placeholder: (context, url) => _placeholder(),
        errorWidget: (context, url, error) => _placeholder(),
        fadeInDuration: const Duration(milliseconds: 200),
      );
    } else if (_isBrowserBlob) {
      image = Image.network(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    } else if (_isAsset) {
      image = Image.asset(
        imageUrl,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    } else if (!kIsWeb) {
      image = Image.file(
        File(imageUrl),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        errorBuilder: (context, error, stackTrace) => _placeholder(),
      );
    } else {
      image = _placeholder();
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: image,
      );
    }
    return image;
  }

  Widget _placeholder() {
    return Container(
      width: width,
      height: height,
      color: placeholderColor ?? const Color(0xFFF8F8F9),
      child: const Center(
        child: Icon(Icons.checkroom_outlined, color: Color(0xFFB8B8BE)),
      ),
    );
  }
}

class _MemoryDataImage extends StatefulWidget {
  const _MemoryDataImage({
    required this.imageUrl,
    required this.width,
    required this.height,
    required this.fit,
    required this.alignment,
    required this.placeholder,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final Widget Function() placeholder;

  @override
  State<_MemoryDataImage> createState() => _MemoryDataImageState();
}

class _MemoryDataImageState extends State<_MemoryDataImage> {
  late Uint8List _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _decode(widget.imageUrl);
  }

  @override
  void didUpdateWidget(covariant _MemoryDataImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _bytes = _decode(widget.imageUrl);
    }
  }

  Uint8List _decode(String value) {
    return base64Decode(value.substring(value.indexOf(',') + 1));
  }

  @override
  Widget build(BuildContext context) {
    return Image.memory(
      _bytes,
      gaplessPlayback: true,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      errorBuilder: (context, error, stackTrace) => widget.placeholder(),
    );
  }
}
