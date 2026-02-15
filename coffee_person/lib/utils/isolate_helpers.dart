import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Isolate 辅助工具类 - 用于在后台线程执行耗时操作

// ============ 1. 图像解码 ============

class ImageDecodeParams {
  final Uint8List bytes;
  
  const ImageDecodeParams(this.bytes);
}

/// 在 Isolate 中解码图像
Future<img.Image?> decodeImageInIsolate(Uint8List bytes) async {
  return compute(_decodeImageTask, ImageDecodeParams(bytes));
}

img.Image? _decodeImageTask(ImageDecodeParams params) {
  return img.decodeImage(params.bytes);
}

// ============ 2. 图像编码 ============

class ImageEncodeParams {
  final img.Image image;
  
  const ImageEncodeParams(this.image);
}

/// 在 Isolate 中编码 PNG
Future<Uint8List> encodePngInIsolate(img.Image image) async {
  return compute(_encodePngTask, ImageEncodeParams(image));
}

Uint8List _encodePngTask(ImageEncodeParams params) {
  return Uint8List.fromList(img.encodePng(params.image));
}

// ============ 3. 图像裁剪和缩放 ============

class ImageCropResizeParams {
  final Uint8List imageBytes;
  final Rect? cropRect;
  final int targetWidth;
  final img.Image? alphaMask;
  
  const ImageCropResizeParams({
    required this.imageBytes,
    required this.cropRect,
    required this.targetWidth,
    this.alphaMask,
  });
}

class ImageCropResizeResult {
  final img.Image resized;
  final img.Image? resizedMask;
  
  const ImageCropResizeResult(this.resized, this.resizedMask);
}

/// 在 Isolate 中裁剪和缩放图像
Future<ImageCropResizeResult?> cropAndResizeImageInIsolate({
  required Uint8List imageBytes,
  required Rect? cropRect,
  required int targetWidth,
  img.Image? alphaMask,
}) async {
  return compute(
    _cropAndResizeTask,
    ImageCropResizeParams(
      imageBytes: imageBytes,
      cropRect: cropRect,
      targetWidth: targetWidth,
      alphaMask: alphaMask,
    ),
  );
}

ImageCropResizeResult? _cropAndResizeTask(ImageCropResizeParams params) {
  final original = img.decodeImage(params.imageBytes);
  if (original == null) return null;
  
  // 裁剪
  final cropped = params.cropRect == null
      ? original
      : img.copyCrop(
          original,
          x: params.cropRect!.left.toInt(),
          y: params.cropRect!.top.toInt(),
          width: params.cropRect!.width.toInt(),
          height: params.cropRect!.height.toInt(),
        );
  
  // 裁剪 mask
  final croppedMask = params.alphaMask == null
      ? null
      : params.cropRect == null
          ? params.alphaMask
          : img.copyCrop(
              params.alphaMask!,
              x: params.cropRect!.left.toInt(),
              y: params.cropRect!.top.toInt(),
              width: params.cropRect!.width.toInt(),
              height: params.cropRect!.height.toInt(),
            );
  
  // 缩放
  final resized = img.copyResize(cropped, width: params.targetWidth);
  final resizedMask = croppedMask == null
      ? null
      : img.copyResize(
          croppedMask,
          width: resized.width,
          height: resized.height,
          interpolation: img.Interpolation.linear,
        );
  
  return ImageCropResizeResult(resized, resizedMask);
}

// ============ 4. Alpha 合成和羽化 ============

class AlphaCompositeParams {
  final img.Image image;
  final img.Image? alphaMask;
  final int featherRadius;
  
  const AlphaCompositeParams({
    required this.image,
    required this.alphaMask,
    required this.featherRadius,
  });
}

/// 在 Isolate 中应用 alpha 合成和羽化
Future<img.Image> applyAlphaCompositeInIsolate({
  required img.Image image,
  required img.Image? alphaMask,
  int featherRadius = 2,
}) async {
  return compute(
    _applyAlphaCompositeTask,
    AlphaCompositeParams(
      image: image,
      alphaMask: alphaMask,
      featherRadius: featherRadius,
    ),
  );
}

img.Image _applyAlphaCompositeTask(AlphaCompositeParams params) {
  if (params.alphaMask == null) {
    return params.image;
  }
  
  // 羽化 mask
  final featheredMask = _featherMask(params.alphaMask!, radius: params.featherRadius);
  
  // 应用 alpha 合成
  final base = params.image.convert(numChannels: 4, alpha: 255);
  
  for (var y = 0; y < base.height; y++) {
    for (var x = 0; x < base.width; x++) {
      final p = base.getPixel(x, y);
      final maskAlpha = featheredMask.getPixel(x, y).a.round().clamp(0, 255);
      base.setPixelRgba(x, y, p.r, p.g, p.b, maskAlpha);
    }
  }
  
  return base;
}

img.Image _featherMask(img.Image mask, {required int radius}) {
  if (radius <= 0) return mask;
  
  final width = mask.width;
  final height = mask.height;
  final result = mask.clone();
  
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

// ============ 5. 连通区域过滤 ============

class ComponentFilterParams {
  final img.Image alphaMask;
  final int threshold;
  
  const ComponentFilterParams({
    required this.alphaMask,
    required this.threshold,
  });
}

/// 在 Isolate 中保留最大连通区域
Future<img.Image> keepLargestComponentInIsolate({
  required img.Image alphaMask,
  int threshold = 128,
}) async {
  return compute(
    _keepLargestComponentTask,
    ComponentFilterParams(
      alphaMask: alphaMask,
      threshold: threshold,
    ),
  );
}

img.Image _keepLargestComponentTask(ComponentFilterParams params) {
  final alphaMask = params.alphaMask;
  final threshold = params.threshold;
  
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
        
        final neighbors = [
          current - 1,
          current + 1,
          current - width,
          current + width,
        ];
        
        for (final n in neighbors) {
          if (n < 0 || n >= width * height) continue;
          if (visited[n]) continue;
          
          final ny = n ~/ width;
          final nx = n - ny * width;
          
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
  
  final filtered = alphaMask.convert(numChannels: 4, alpha: 0);
  for (final p in bestPixels) {
    final y = p ~/ width;
    final x = p - y * width;
    final originalAlpha = alphaMask.getPixel(x, y).a;
    filtered.setPixelRgba(x, y, 0, 0, 0, originalAlpha);
  }
  
  return filtered;
}

// ============ 6. JSON 序列化 ============

/// 在 Isolate 中解析 JSON
Future<Map<String, dynamic>> jsonDecodeInIsolate(String jsonString) async {
  return compute(_jsonDecodeTask, jsonString);
}

Map<String, dynamic> _jsonDecodeTask(String jsonString) {
  return jsonDecode(jsonString) as Map<String, dynamic>;
}

/// 在 Isolate 中编码 JSON
Future<String> jsonEncodeInIsolate(Map<String, dynamic> data) async {
  return compute(_jsonEncodeTask, data);
}

String _jsonEncodeTask(Map<String, dynamic> data) {
  return jsonEncode(data);
}

// ============ 8. 统计计算（针对大量数据） ============

class StatsCalculationParams {
  final List<Map<String, dynamic>> recordsJson;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime now;
  final String rangeType; // 'week', 'month', 'year'
  
  const StatsCalculationParams({
    required this.recordsJson,
    required this.rangeStart,
    required this.rangeEnd,
    required this.now,
    required this.rangeType,
  });
}

class StatsCalculationResult {
  final List<int> dailyCounts;
  final List<int> caffeineSeries;
  final Map<String, int> typeCounts;
  final String favoriteType;
  final int favoriteCount;
  
  const StatsCalculationResult({
    required this.dailyCounts,
    required this.caffeineSeries,
    required this.typeCounts,
    required this.favoriteType,
    required this.favoriteCount,
  });
}

/// 在 Isolate 中计算统计数据（适用于大量记录）
Future<StatsCalculationResult> calculateStatsInIsolate({
  required List<Map<String, dynamic>> recordsJson,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime now,
  required String rangeType,
}) async {
  return compute(
    _calculateStatsTask,
    StatsCalculationParams(
      recordsJson: recordsJson,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      rangeType: rangeType,
    ),
  );
}

StatsCalculationResult _calculateStatsTask(StatsCalculationParams params) {
  // 重建记录对象（简化版）
  final records = params.recordsJson.map((json) {
    return _SimpleRecord(
      type: json['type'] as String,
      caffeineMg: json['caffeineMg'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }).toList();
  
  // 计算每日/每月统计
  List<int> dailyCounts;
  List<int> caffeineSeries;
  
  if (params.rangeType == 'year') {
    dailyCounts = _monthlyCounts(params.rangeStart, records);
    caffeineSeries = _monthlyCaffeine(params.rangeStart, records);
  } else {
    dailyCounts = _dailyCounts(params.rangeStart, params.rangeEnd, records);
    caffeineSeries = _dailyCaffeine(params.rangeStart, params.rangeEnd, records);
  }
  
  // 计算类型统计
  final typeCounts = <String, int>{};
  for (final record in records) {
    typeCounts[record.type] = (typeCounts[record.type] ?? 0) + 1;
  }
  
  // 计算最喜欢的类型
  String favoriteType = '';
  int favoriteCount = 0;
  if (typeCounts.isNotEmpty) {
    final entries = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    favoriteType = entries.first.key;
    favoriteCount = entries.first.value;
  }
  
  return StatsCalculationResult(
    dailyCounts: dailyCounts,
    caffeineSeries: caffeineSeries,
    typeCounts: typeCounts,
    favoriteType: favoriteType,
    favoriteCount: favoriteCount,
  );
}

class _SimpleRecord {
  final String type;
  final int caffeineMg;
  final DateTime createdAt;
  
  const _SimpleRecord({
    required this.type,
    required this.caffeineMg,
    required this.createdAt,
  });
}

List<int> _dailyCounts(
  DateTime start,
  DateTime end,
  List<_SimpleRecord> records,
) {
  final days = end.difference(start).inDays;
  final counts = List<int>.filled(days, 0);
  for (final record in records) {
    final local = record.createdAt.toLocal();
    final dayIndex =
        DateTime(local.year, local.month, local.day).difference(start).inDays;
    if (dayIndex >= 0 && dayIndex < counts.length) {
      counts[dayIndex] += 1;
    }
  }
  return counts;
}

List<int> _dailyCaffeine(
  DateTime start,
  DateTime end,
  List<_SimpleRecord> records,
) {
  final days = end.difference(start).inDays;
  final totals = List<int>.filled(days, 0);
  for (final record in records) {
    final local = record.createdAt.toLocal();
    final dayIndex =
        DateTime(local.year, local.month, local.day).difference(start).inDays;
    if (dayIndex >= 0 && dayIndex < totals.length) {
      totals[dayIndex] += record.caffeineMg;
    }
  }
  return totals;
}

List<int> _monthlyCounts(DateTime yearStart, List<_SimpleRecord> records) {
  final counts = List<int>.filled(12, 0);
  for (final record in records) {
    final local = record.createdAt.toLocal();
    if (local.year != yearStart.year) continue;
    final monthIndex = local.month - 1;
    if (monthIndex >= 0 && monthIndex < 12) {
      counts[monthIndex] += 1;
    }
  }
  return counts;
}

List<int> _monthlyCaffeine(DateTime yearStart, List<_SimpleRecord> records) {
  final totals = List<int>.filled(12, 0);
  for (final record in records) {
    final local = record.createdAt.toLocal();
    if (local.year != yearStart.year) continue;
    final monthIndex = local.month - 1;
    if (monthIndex >= 0 && monthIndex < 12) {
      totals[monthIndex] += record.caffeineMg;
    }
  }
  return totals;
}

// ============ 7. 文件读写 ============

class FileReadParams {
  final String path;
  
  const FileReadParams(this.path);
}

class FileWriteParams {
  final String path;
  final Uint8List bytes;
  
  const FileWriteParams(this.path, this.bytes);
}

/// 在 Isolate 中读取文件
Future<Uint8List> readFileBytesInIsolate(String path) async {
  return compute(_readFileBytesTask, FileReadParams(path));
}

Uint8List _readFileBytesTask(FileReadParams params) {
  return File(params.path).readAsBytesSync();
}

/// 在 Isolate 中写入文件
Future<void> writeFileBytesInIsolate(String path, Uint8List bytes) async {
  return compute(_writeFileBytesTask, FileWriteParams(path, bytes));
}

void _writeFileBytesTask(FileWriteParams params) {
  File(params.path).writeAsBytesSync(params.bytes);
}

