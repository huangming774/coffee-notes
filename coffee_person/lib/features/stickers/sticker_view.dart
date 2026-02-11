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
    if (size == double.infinity) {
      // 填充整个容器
      return Image.file(
        File(path),
        fit: fit,
        width: double.infinity,
        height: double.infinity,
      );
    }
    
    return SizedBox(
      width: size,
      height: size,
      child: Image.file(
        File(path),
        fit: fit,
      ),
    );
  }
}
