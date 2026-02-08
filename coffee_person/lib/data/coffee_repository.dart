import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:isar/isar.dart';

import 'coffee_record.dart';

enum StatsRange { week, month, year }

class StatsSummary {
  const StatsSummary({
    required this.totalCups,
    required this.totalCost,
    required this.totalCaffeine,
    required this.avgDailyCaffeine,
    required this.favoriteType,
    required this.favoriteCount,
    required this.dailyCounts,
    required this.caffeineSeries,
    required this.typeCounts,
  });

  const StatsSummary.empty()
      : totalCups = 0,
        totalCost = 0,
        totalCaffeine = 0,
        avgDailyCaffeine = 0,
        favoriteType = '',
        favoriteCount = 0,
        dailyCounts = const [],
        caffeineSeries = const [],
        typeCounts = const {};

  final int totalCups;
  final int totalCost;
  final int totalCaffeine;
  final int avgDailyCaffeine;
  final String favoriteType;
  final int favoriteCount;
  final List<int> dailyCounts;
  final List<int> caffeineSeries;
  final Map<String, int> typeCounts;
}

abstract class CoffeeStatsRepository {
  Future<void> ensureSeeded();
  Future<StatsSummary> getStats(StatsRange range, {DateTime? anchorDate});
  int maxDailyCount(List<int> counts);
  Future<void> addRecord(CoffeeRecord record);
  Future<void> updateRecord(CoffeeRecord record);
  Future<void> deleteRecord(Id id);
  Future<List<CoffeeRecord>> getRecordsInRange(DateTime start, DateTime end);
}

class CoffeeRepository implements CoffeeStatsRepository {
  const CoffeeRepository(this.isar);

  final Isar isar;

  @override
  Future<void> addRecord(CoffeeRecord record) async {
    await isar.writeTxn(() async {
      await isar.coffeeRecords.put(record);
    });
  }

  @override
  Future<void> updateRecord(CoffeeRecord record) async {
    await isar.writeTxn(() async {
      await isar.coffeeRecords.put(record);
    });
  }

  @override
  Future<void> deleteRecord(Id id) async {
    await isar.writeTxn(() async {
      await isar.coffeeRecords.delete(id);
    });
  }

  @override
  Future<List<CoffeeRecord>> getRecordsInRange(
    DateTime start,
    DateTime end,
  ) {
    return isar.coffeeRecords
        .filter()
        .createdAtBetween(start, end, includeLower: true, includeUpper: false)
        .findAll();
  }

  @override
  Future<void> ensureSeeded() async {
    if (!kDebugMode) return;
    final count = await isar.coffeeRecords.count();
    if (count > 0) return;
    final now = DateTime.now();
    final seed = <CoffeeRecord>[
      CoffeeRecord()
        ..type = '拿铁'
        ..caffeineMg = 95
        ..cost = 7
        ..createdAt = now.subtract(const Duration(days: 1)),
      CoffeeRecord()
        ..type = '拿铁'
        ..caffeineMg = 94
        ..cost = 7
        ..createdAt = now.subtract(const Duration(days: 2)),
      CoffeeRecord()
        ..type = '美式'
        ..caffeineMg = 94
        ..cost = 7
        ..createdAt = now.subtract(const Duration(days: 4)),
    ];
    await isar.writeTxn(() async {
      await isar.coffeeRecords.putAll(seed);
    });
  }

  @override
  Future<StatsSummary> getStats(StatsRange range, {DateTime? anchorDate}) async {
    final now = anchorDate == null
        ? DateTime.now()
        : DateTime(anchorDate.year, anchorDate.month, anchorDate.day);
    final rangeStart = _rangeStart(now, range);
    final rangeEnd = _rangeEnd(rangeStart, range);
    final records = await getRecordsInRange(rangeStart, rangeEnd);
    final totalCups = records.length;
    final totalCost =
        records.fold<int>(0, (sum, item) => sum + item.cost.round());
    final totalCaffeine =
        records.fold<int>(0, (sum, item) => sum + item.caffeineMg);
    final favorite = _favorite(records);
    final daysElapsed = _daysElapsed(rangeStart, rangeEnd, now);
    final dailyCountsRaw = range == StatsRange.year
        ? _monthlyCounts(rangeStart, records)
        : _dailyCounts(rangeStart, rangeEnd, records);
    final caffeineSeriesRaw = range == StatsRange.year
        ? _monthlyCaffeine(rangeStart, records)
        : _dailyCaffeine(rangeStart, rangeEnd, records);
    final visibleCount = range == StatsRange.year
        ? dailyCountsRaw.length
        : min(daysElapsed, dailyCountsRaw.length);
    final dailyCounts =
        dailyCountsRaw.take(visibleCount).toList(growable: false);
    final caffeineSeries =
        caffeineSeriesRaw.take(visibleCount).toList(growable: false);
    final avgDailyCaffeine =
        daysElapsed == 0 ? 0 : (totalCaffeine / daysElapsed).round();
    return StatsSummary(
      totalCups: totalCups,
      totalCost: totalCost,
      totalCaffeine: totalCaffeine,
      avgDailyCaffeine: avgDailyCaffeine,
      favoriteType: favorite.$1,
      favoriteCount: favorite.$2,
      dailyCounts: dailyCounts,
      caffeineSeries: caffeineSeries,
      typeCounts: _typeCounts(records),
    );
  }

  DateTime _rangeStart(DateTime now, StatsRange range) {
    final date = DateTime(now.year, now.month, now.day);
    switch (range) {
      case StatsRange.week:
        return date.subtract(Duration(days: date.weekday - 1));
      case StatsRange.month:
        return DateTime(date.year, date.month);
      case StatsRange.year:
        return DateTime(date.year);
    }
  }

  DateTime _rangeEnd(DateTime start, StatsRange range) {
    switch (range) {
      case StatsRange.week:
        return start.add(const Duration(days: 7));
      case StatsRange.month:
        return DateTime(start.year, start.month + 1);
      case StatsRange.year:
        return DateTime(start.year + 1);
    }
  }

  int _daysElapsed(DateTime start, DateTime end, DateTime now) {
    final effectiveEnd =
        now.isBefore(end) ? now : end.subtract(const Duration(days: 1));
    if (effectiveEnd.isBefore(start)) return 0;
    return effectiveEnd.difference(start).inDays + 1;
  }

  (String, int) _favorite(List<CoffeeRecord> records) {
    if (records.isEmpty) return ('', 0);
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.type] = (counts[record.type] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.first;
    return (top.key, top.value);
  }

  List<int> _dailyCounts(
    DateTime start,
    DateTime end,
    List<CoffeeRecord> records,
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
    List<CoffeeRecord> records,
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

  List<int> _monthlyCounts(DateTime yearStart, List<CoffeeRecord> records) {
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

  List<int> _monthlyCaffeine(DateTime yearStart, List<CoffeeRecord> records) {
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

  Map<String, int> _typeCounts(List<CoffeeRecord> records) {
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.type] = (counts[record.type] ?? 0) + 1;
    }
    return counts;
  }

  @override
  int maxDailyCount(List<int> counts) {
    if (counts.isEmpty) return 0;
    return max(1, counts.reduce(max));
  }
}
