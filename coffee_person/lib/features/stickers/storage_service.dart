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
    final bytes = await File(imagePath).readAsBytes();
    final original = img.decodeImage(bytes);
    if (original == null) {
      throw StateError('Unable to decode image');
    }
    final filteredMask = _keepLargestComponent(alphaMask, threshold: 128);
    final maskRect = _alphaMaskBounds(filteredMask);
    final rect = _clampRect(maskRect ?? bbox, original.width, original.height);
    final cropped = rect == null
        ? original
        : img.copyCrop(
            original,
            x: rect.left.toInt(),
            y: rect.top.toInt(),
            width: rect.width.toInt(),
            height: rect.height.toInt(),
          );
    final croppedMask = filteredMask == null
        ? null
        : rect == null
            ? filteredMask
            : img.copyCrop(
                filteredMask,
                x: rect.left.toInt(),
                y: rect.top.toInt(),
                width: rect.width.toInt(),
                height: rect.height.toInt(),
              );
    final resized = img.copyResize(cropped, width: targetWidth);
    final resizedMask = croppedMask == null
        ? null
        : img.copyResize(
            croppedMask,
            width: resized.width,
            height: resized.height,
            interpolation: img.Interpolation.linear,
          );
    
    // 对 mask 进行轻微羽化，让边缘更平滑
    final featheredMask = resizedMask == null ? null : _featherMask(resizedMask, radius: 2);
    
    final processed = _applyAlphaComposite(resized, alphaMask: featheredMask);
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

  img.Image _applyAlphaComposite(img.Image image,
      {required img.Image? alphaMask}) {
    if (alphaMask == null) {
      return image;
    }
    
    final base = image.convert(numChannels: 4, alpha: 255);
    
    // 使用平滑的 alpha 通道，而不是硬阈值
    for (var y = 0; y < base.height; y++) {
      for (var x = 0; x < base.width; x++) {
        final p = base.getPixel(x, y);
        final maskAlpha = alphaMask.getPixel(x, y).a.round().clamp(0, 255);
        
        // 直接使用 mask 的 alpha 值，保留平滑边缘
        base.setPixelRgba(x, y, p.r, p.g, p.b, maskAlpha);
      }
    }
    
    return base;
  }

  /// 对 mask 进行羽化处理，让边缘更平滑
  img.Image _featherMask(img.Image mask, {required int radius}) {
    if (radius <= 0) return mask;
    
    final width = mask.width;
    final height = mask.height;
    final result = mask.clone();
    
    // 简单的高斯模糊近似（box blur）
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var sum = 0;
        var count = 0;
        
        for (var dy = -radius; dy <= radius; dy++) {
          for (var dx = -radius; dx <= radius; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              sum += mask.getPixel(nx, ny).a.round();
              count++;
            }
          }
        }
        
        final avgAlpha = (sum / count).round().clamp(0, 255);
        result.setPixelRgba(x, y, 0, 0, 0, avgAlpha);
      }
    }
    
    return result;
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

  img.Image? _keepLargestComponent(img.Image? alphaMask,
      {required int threshold}) {
    if (alphaMask == null) return null;
    
    final width = alphaMask.width;
    final height = alphaMask.height;
    final visited = List<bool>.filled(width * height, false);
    var bestCount = 0;
    List<int>? bestPixels;
    
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final idx = y * width + x;
        if (visited[idx]) continue;
        final a = alphaMask.getPixel(x, y).a;
        if (a < threshold) {
          visited[idx] = true;
          continue;
        }
        
        // BFS 查找连通区域
        final queue = <int>[idx];
        final pixels = <int>[];
        visited[idx] = true;
        
        while (queue.isNotEmpty) {
          final current = queue.removeAt(0);
          pixels.add(current);
          final cy = current ~/ width;
          final cx = current - cy * width;
          
          // 检查 4 个邻居
          final neighbors = [
            current - 1,      // 左
            current + 1,      // 右
            current - width,  // 上
            current + width,  // 下
          ];
          
          for (final n in neighbors) {
            if (n < 0 || n >= width * height) continue;
            if (visited[n]) continue;
            
            final ny = n ~/ width;
            final nx = n - ny * width;
            
            // 确保是相邻像素
            if ((ny - cy).abs() + (nx - cx).abs() != 1) continue;
            
            final na = alphaMask.getPixel(nx, ny).a;
            if (na < threshold) {
              visited[n] = true;
              continue;
            }
            
            visited[n] = true;
            queue.add(n);
          }
        }
        
        if (pixels.length > bestCount) {
          bestCount = pixels.length;
          bestPixels = pixels;
        }
      }
    }
    
    if (bestPixels == null || bestCount == 0) {
      return alphaMask;
    }
    
    // 创建新的 mask，保留原始 alpha 值（平滑边缘）
    final filtered = alphaMask.convert(numChannels: 4, alpha: 0);
    for (final p in bestPixels) {
      final y = p ~/ width;
      final x = p - y * width;
      final originalAlpha = alphaMask.getPixel(x, y).a;
      filtered.setPixelRgba(x, y, 0, 0, 0, originalAlpha);
    }
    
    return filtered;
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
