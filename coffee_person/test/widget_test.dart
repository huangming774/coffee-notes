import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coffee_person/data/coffee_repository.dart';
import 'package:coffee_person/data/coffee_record.dart';
import 'package:coffee_person/features/stats/stats_page.dart';
import 'package:coffee_person/theme/app_theme.dart';
import 'package:isar/isar.dart';

class _FakeCoffeeRepository implements CoffeeStatsRepository {
  final List<CoffeeRecord> _records = [];

  @override
  Future<void> ensureSeeded() async {}

  @override
  Future<StatsSummary> getStats(StatsRange range) async {
    return const StatsSummary(
      totalCups: 3,
      totalCost: 21,
      totalCaffeine: 283,
      avgDailyCaffeine: 95,
      favoriteType: '拿铁',
      favoriteCount: 2,
      dailyCounts: [1, 1, 1],
      caffeineSeries: [90, 96, 97],
      typeCounts: {'拿铁': 2, '美式': 1},
    );
  }

  @override
  int maxDailyCount(List<int> counts) {
    var maxValue = 0;
    for (final value in counts) {
      if (value > maxValue) maxValue = value;
    }
    return maxValue == 0 ? 1 : maxValue;
  }

  @override
  Future<void> addRecord(CoffeeRecord record) async {
    _records.add(record);
  }

  @override
  Future<void> updateRecord(CoffeeRecord record) async {
    final index = _records.indexWhere((r) => r.id == record.id);
    if (index == -1) {
      _records.add(record);
      return;
    }
    _records[index] = record;
  }

  @override
  Future<void> deleteRecord(Id id) async {
    _records.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<CoffeeRecord>> getRecordsInRange(
      DateTime start, DateTime end) async {
    return _records
        .where(
          (r) => !r.createdAt.isBefore(start) && r.createdAt.isBefore(end),
        )
        .toList();
  }
}

void main() {
  testWidgets('Stats page renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: StatsPage(
          repository: _FakeCoffeeRepository(),
          themeMode: ThemeMode.light,
          onThemeModeChange: (_) {},
          accentPalette: AppAccentPalette.coffee,
          onAccentPaletteChange: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('统计'), findsOneWidget);
  });
}
