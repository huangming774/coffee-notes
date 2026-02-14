import 'dart:io';
import 'dart:ui';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../utils/isolate_helpers.dart';
import 'sticker_models.dart';

class StorageService {
  Future<Map<String, List<Sticker>>> loadIndex() async {
    final file = await _indexFile();
    if (!file.existsSync()) return {};
    final content = await file.readAsString();
    if (content.trim().isEmpty) return {};
    
    // 使用 Isolate 解析 JSON（大文件时更流畅）
    final data = await jsonDecodeInIsolate(content);
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
    
    // 使用 Isolate 编码 JSON（大文件时更流畅）
    final jsonString = await jsonEncodeInIsolate(encoded);
    await file.writeAsString(jsonString);
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
    img.Image? alphaMask,
    required String id,
  }) {
    return _createSticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: bbox,
      alphaMask: alphaMask,
      id: id,
      targetWidth: 256,
      isLowQuality: true,
    );
  }

  Future<Sticker> processHighQualitySticker({
    required String imagePath,
    required String dateKey,
    required Rect? bbox,
    img.Image? alphaMask,
    required String id,
  }) {
    return _createSticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: bbox,
      alphaMask: alphaMask,
      id: id,
      targetWidth: 512,
      isLowQuality: false,
    );
  }

  Future<Sticker> _createSticker({
    required String imagePath,
    required String dateKey,
    required Rect? bbox,
    required img.Image? alphaMask,
    required String id,
    required int targetWidth,
    required bool isLowQuality,
  }) async {
    // 使用 Isolate 读取文件（避免阻塞 UI）
    final bytes = await readFileBytesInIsolate(imagePath);
    
    // 使用 Isolate 解码图像（耗时操作）
    final original = await decodeImageInIsolate(bytes);
    if (original == null) {
      throw StateError('Unable to decode image');
    }
    
    // 使用 Isolate 过滤最大连通区域（耗时操作）
    final filteredMask = alphaMask == null 
        ? null 
        : await keepLargestComponentInIsolate(alphaMask: alphaMask, threshold: 128);
    
    final maskRect = _alphaMaskBounds(filteredMask);
    final rect = _clampRect(maskRect ?? bbox, original.width, original.height);
    
    // 使用 Isolate 裁剪和缩放（耗时操作）
    final cropResizeResult = await cropAndResizeImageInIsolate(
      imageBytes: bytes,
      cropRect: rect,
      targetWidth: targetWidth,
      alphaMask: filteredMask,
    );
    
    if (cropResizeResult == null) {
      throw StateError('Failed to crop and resize image');
    }
    
    final resized = cropResizeResult.resized;
    final resizedMask = cropResizeResult.resizedMask;
    
    // 使用 Isolate 应用 alpha 合成和羽化（耗时操作）
    final processed = await applyAlphaCompositeInIsolate(
      image: resized,
      alphaMask: resizedMask,
      featherRadius: 2,
    );
    
    final dir = await _stickersDirForDate(dateKey);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    
    // 使用 Isolate 编码 PNG（耗时操作）
    final pngBytes = await encodePngInIsolate(processed);
    
    final file = File('${dir.path}/$id.png');
    // 使用 Isolate 写入文件（避免阻塞 UI）
    await writeFileBytesInIsolate(file.path, pngBytes);
    
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

  Rect? _alphaMaskBounds(img.Image? alphaMask) {
    if (alphaMask == null) return null;
    var minX = alphaMask.width;
    var minY = alphaMask.height;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < alphaMask.height; y++) {
      for (var x = 0; x < alphaMask.width; x++) {
        final a = alphaMask.getPixel(x, y).a;
        if (a < 128) continue;
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
      }
    }
    if (maxX < 0 || maxY < 0) return null;
    final left = minX.toDouble();
    final top = minY.toDouble();
    final right = (maxX + 1).toDouble();
    final bottom = (maxY + 1).toDouble();
    return Rect.fromLTRB(left, top, right, bottom);
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
