import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

Widget storedImage(
  String path, {
  BoxFit fit = BoxFit.cover,
}) {
  return Image.file(File(path), fit: fit);
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
