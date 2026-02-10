import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import 'sticker_models.dart';

class StorageService {
  Future<Map<String, List<Sticker>>> loadIndex() async {
    final file = await _indexFile();
    if (!file.existsSync()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    final data = jsonDecode(content) as Map<String, dynamic>;
    final result = <String, List<Sticker>>{};
    data.forEach((key, value) {
      final list = (value as List<dynamic>)
          .map((item) => Sticker.fromJson(item as Map<String, dynamic>))
          .toList();
      result[key] = list;
    });
    return result;
  }

  Future<void> saveIndex(Map<String, List<Sticker>> index) async {
    final file = await _indexFile();
    final encoded = <String, dynamic>{};
    index.forEach((key, value) {
      encoded[key] = value.map((item) => item.toJson()).toList();
    });
    await file.writeAsString(jsonEncode(encoded));
  }

  Future<void> deleteStickerFile(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<Sticker> createLowQualitySticker({
    required String imagePath,
    required String dateKey,
    required Rect? bbox,
    required String id,
  }) {
    return _createSticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: bbox,
      id: id,
      targetWidth: 256,
      isLowQuality: true,
    );
  }

  Future<Sticker> processHighQualitySticker({
    required String imagePath,
    required String dateKey,
    required Rect? bbox,
    required String id,
  }) {
    return _createSticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: bbox,
      id: id,
      targetWidth: 512,
      isLowQuality: false,
    );
  }

  Future<Sticker> _createSticker({
    required String imagePath,
    required String dateKey,
    required Rect? bbox,
    required String id,
    required int targetWidth,
    required bool isLowQuality,
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) {
      throw StateError('Unable to decode image');
    }
    final rect = _clampRect(bbox, original.width, original.height);
    final cropped = rect == null
        ? original
        : img.copyCrop(
            original,
            x: rect.left.toInt(),
            y: rect.top.toInt(),
            width: rect.width.toInt(),
            height: rect.height.toInt(),
          );
    final resized = img.copyResize(cropped, width: targetWidth);
    final processed = _applyAlphaComposite(resized);
    final dir = await _stickersDirForDate(dateKey);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final file = File('${dir.path}/$id.png');
    await file.writeAsBytes(img.encodePng(processed));
    return Sticker(
      id: id,
      dateKey: dateKey,
      path: file.path,
      width: processed.width,
      height: processed.height,
      createdAt: DateTime.now(),
      isLowQuality: isLowQuality,
    );
  }

  img.Image _applyAlphaComposite(img.Image image) {
    return image;
  }

  Rect? _clampRect(Rect? rect, int width, int height) {
    if (rect == null) return null;
    final left = rect.left.clamp(0, width - 1).toDouble();
    final top = rect.top.clamp(0, height - 1).toDouble();
    final right = rect.right.clamp(left + 1, width.toDouble());
    final bottom = rect.bottom.clamp(top + 1, height.toDouble());
    final w = right - left;
    final h = bottom - top;
    if (w <= 1 || h <= 1) return null;
    return Rect.fromLTWH(left, top, w, h);
  }

  Future<Directory> _stickersDirForDate(String dateKey) async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory('${dir.path}/stickers/$dateKey');
  }

  Future<File> _indexFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final stickersDir = Directory('${dir.path}/stickers');
    if (!stickersDir.existsSync()) {
      stickersDir.createSync(recursive: true);
    }
    return File('${stickersDir.path}/stickers_index.json');
  }
}
