import 'dart:io';

import 'package:flutter/material.dart';

class StickerView extends StatelessWidget {
  const StickerView({
    super.key,
    required this.path,
    required this.size,
    this.fit = BoxFit.contain,
  });

  final String path;
  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final isFull = size == double.infinity;
    if (!file.existsSync()) {
      return SizedBox(
        width: isFull ? double.infinity : size,
        height: isFull ? double.infinity : size,
      );
    }
    if (size == double.infinity) {
      return Image.file(
        file,
        fit: fit,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: 800, // 限制缓存尺寸，节省内存
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        gaplessPlayback: true, // 平滑切换
      );
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.file(
        file,
        fit: fit,
        cacheWidth: (size * 2).toInt(), // 2倍像素密度
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        gaplessPlayback: true,
      ),
    );
  }
}
