import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Widget storedImage(
  String path, {
  BoxFit fit = BoxFit.cover,
  double? width,
  double? height,
}) {
  final file = File(path);
  
  // 计算合适的缓存尺寸（2倍像素密度）
  int? cacheWidth;
  int? cacheHeight;
  
  if (width != null) {
    cacheWidth = (width * 2).toInt();
  }
  if (height != null) {
    cacheHeight = (height * 2).toInt();
  }
  
  // 如果都没指定，使用合理的默认值避免内存过大
  if (cacheWidth == null && cacheHeight == null) {
    cacheWidth = 800; // 默认最大宽度
  }
  
  return Image.file(
    file,
    fit: fit,
    width: width,
    height: height,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    gaplessPlayback: true, // 平滑切换，避免闪烁
    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
  );
}

Future<String> persistPickedImage(XFile file) async {
  final dir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory('${dir.path}/coffee_images');
  if (!imagesDir.existsSync()) {
    imagesDir.createSync(recursive: true);
  }
  final name = file.name;
  final extIndex = name.lastIndexOf('.');
  final ext = extIndex >= 0 ? name.substring(extIndex) : '.jpg';
  final filename = 'coffee_${DateTime.now().millisecondsSinceEpoch}$ext';
  final targetPath = '${imagesDir.path}/$filename';
  await File(file.path).copy(targetPath);
  return targetPath;
}
