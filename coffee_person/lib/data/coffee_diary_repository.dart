import 'dart:io';

import 'package:isar/isar.dart';

import 'coffee_diary_entry.dart';

abstract class CoffeeDiaryRepository {
  Stream<List<CoffeeDiaryEntry>> watchAll();
  Future<void> upsertEntry(CoffeeDiaryEntry entry);
  Future<void> deleteEntry(Id id);
}

class IsarCoffeeDiaryRepository implements CoffeeDiaryRepository {
  const IsarCoffeeDiaryRepository(this.isar);

  final Isar isar;

  @override
  Stream<List<CoffeeDiaryEntry>> watchAll() {
    return isar.coffeeDiaryEntrys
        .where()
        .sortByDateDesc()
        .watch(fireImmediately: true);
  }

  @override
  Future<void> upsertEntry(CoffeeDiaryEntry entry) async {
    await isar.writeTxn(() async {
      await isar.coffeeDiaryEntrys.put(entry);
    });
  }

  @override
  Future<void> deleteEntry(Id id) async {
    CoffeeDiaryEntry? entry;
    await isar.writeTxn(() async {
      entry = await isar.coffeeDiaryEntrys.get(id);
      await isar.coffeeDiaryEntrys.delete(id);
    });
    final imagePaths = entry?.imagePaths ?? const <String>[];
    final videoPaths = entry?.motionVideoPaths ?? const <String>[];
    final paths = <String>[...imagePaths, ...videoPaths];
    for (final path in paths) {
      if (path.trim().isEmpty) continue;
      try {
        final file = File(path);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }
}
