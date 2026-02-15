import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import 'detection_service.dart';
import 'sticker_models.dart';
import 'storage_service.dart';

class StickerStore extends ChangeNotifier {
  StickerStore({
    required this.storageService,
    required this.detectionService,
  });

  final StorageService storageService;
  final DetectionService detectionService;

  Map<String, List<Sticker>> _stickersByDate = {};

  Map<String, List<Sticker>> get stickersByDate => _stickersByDate;

  Future<void> load() async {
    _stickersByDate = await storageService.loadIndex();
    notifyListeners();
  }

  List<Sticker> stickersForDate(DateTime date) {
    final key = formatDateKey(date);
    return List<Sticker>.from(_stickersByDate[key] ?? const []);
  }

  Future<void> addStickerFromImage({
    required DateTime date,
    required String imagePath,
  }) async {
    final dateKey = formatDateKey(date);
    final existing = List<Sticker>.from(_stickersByDate[dateKey] ?? const []);
    for (final item in existing) {
      await storageService.deleteStickerFile(item.path);
    }
    final id = 'sticker_${DateTime.now().millisecondsSinceEpoch}';
    final cutout = await detectionService.detectStickerCutout(imagePath);
    final lowSticker = await storageService.createLowQualitySticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: cutout.bbox,
      alphaMask: cutout.alphaMask,
      id: id,
    );
    _insertSticker(lowSticker);
    await storageService.saveIndex(_stickersByDate);
    notifyListeners();
    unawaited(_upgradeStickerQuality(
      dateKey: dateKey,
      imagePath: imagePath,
      bbox: cutout.bbox,
      alphaMask: cutout.alphaMask,
      id: id,
    ));
  }

  Future<void> _upgradeStickerQuality({
    required String dateKey,
    required String imagePath,
    required Rect? bbox,
    required img.Image? alphaMask,
    required String id,
  }) async {
    final updated = await storageService.processHighQualitySticker(
      imagePath: imagePath,
      dateKey: dateKey,
      bbox: bbox,
      alphaMask: alphaMask,
      id: id,
    );
    final list = _stickersByDate[dateKey];
    if (list == null) return;
    final index = list.indexWhere((item) => item.id == id);
    if (index < 0) return;
    list[index] = updated;
    await storageService.saveIndex(_stickersByDate);
    notifyListeners();
  }

  Future<void> removeSticker({
    required String dateKey,
    required String stickerId,
  }) async {
    final list = _stickersByDate[dateKey];
    if (list == null || list.isEmpty) return;
    final index = list.indexWhere((item) => item.id == stickerId);
    if (index < 0) return;
    final item = list.removeAt(index);
    await storageService.deleteStickerFile(item.path);
    if (list.isEmpty) {
      _stickersByDate.remove(dateKey);
    }
    await storageService.saveIndex(_stickersByDate);
    notifyListeners();
  }

  void _insertSticker(Sticker sticker) {
    _stickersByDate[sticker.dateKey] = [sticker];
  }
}
