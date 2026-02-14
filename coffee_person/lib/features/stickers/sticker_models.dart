 import 'package:flutter/foundation.dart';

@immutable
class Sticker {
  const Sticker({
    required this.id,
    required this.dateKey,
    required this.path,
    required this.width,
    required this.height,
    required this.createdAt,
    required this.isLowQuality,
  });

  final String id;
  final String dateKey;
  final String path;
  final int width;
  final int height;
  final DateTime createdAt;
  final bool isLowQuality;

  Sticker copyWith({
    String? id,
    String? dateKey,
    String? path,
    int? width,
    int? height,
    DateTime? createdAt,
    bool? isLowQuality,
  }) {
    return Sticker(
      id: id ?? this.id,
      dateKey: dateKey ?? this.dateKey,
      path: path ?? this.path,
      width: width ?? this.width,
      height: height ?? this.height,
      createdAt: createdAt ?? this.createdAt,
      isLowQuality: isLowQuality ?? this.isLowQuality,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'dateKey': dateKey,
      'path': path,
      'width': width,
      'height': height,
      'createdAt': createdAt.toIso8601String(),
      'isLowQuality': isLowQuality,
    };
  }

  static Sticker fromJson(Map<String, dynamic> json) {
    return Sticker(
      id: json['id'] as String,
      dateKey: json['dateKey'] as String,
      path: json['path'] as String,
      width: (json['width'] as num).toInt(),
      height: (json['height'] as num).toInt(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      isLowQuality: json['isLowQuality'] as bool? ?? false,
    );
  }
}

String formatDateKey(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
