import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

Widget storedImage(
  String path, {
  BoxFit fit = BoxFit.cover,
}) {
  return Image.network(path, fit: fit);
}

Future<String> persistPickedImage(XFile file) async {
  return file.path;
}
