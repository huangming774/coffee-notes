import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/coffee_record.dart';

import '../../data/coffee_repository.dart';
import '../../features/weather/open_meteo_client.dart';
import '../../theme/app_theme.dart';
import '../../utils/stored_image.dart';

const double _segmentButtonWidth = 60;
const double _statsSegmentSpacing = 12;
const double _themeSegmentSpacing = 12;
const double _segmentIndicatorWidth = 20;
const double _bottomNavHeight = 68;
const double _bottomNavBottomPadding = 16;

double _bottomNavReservedSpace(BuildContext context) {
  return _bottomNavHeight +
      _bottomNavBottomPadding +
      MediaQuery.of(context).padding.bottom;
}

class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChange,
    required this.accentPalette,
    required this.onAccentPaletteChange,
  });

  final CoffeeStatsRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final AppAccentPalette accentPalette;
  final ValueChanged<AppAccentPalette> onAccentPaletteChange;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> with WidgetsBindingObserver {
  StatsRange _range = StatsRange.week;
  StatsSummary _summary = const StatsSummary.empty();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
    }
  }

  Future<void> _load() async {
    final summary = await widget.repository.getStats(_range);
    if (!mounted) return;
    setState(() {
      _summary = summary;
    });
  }

  Future<void> _switchRange(StatsRange range) async {
    if (_range == range) return;
    setState(() {
      _range = range;
    });
    await _load();
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 200) return;
    final ranges = [StatsRange.week, StatsRange.month, StatsRange.year];
    final currentIndex = ranges.indexOf(_range);
    if (velocity < 0 && currentIndex < ranges.length - 1) {
      _switchRange(ranges[currentIndex + 1]);
    } else if (velocity > 0 && currentIndex > 0) {
      _switchRange(ranges[currentIndex - 1]);
    }
  }

  Alignment _rangeIndicatorAlignment() {
    switch (_range) {
      case StatsRange.week:
        return Alignment.centerLeft;
      case StatsRange.month:
        return Alignment.center;
      case StatsRange.year:
        return Alignment.centerRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final dividerColor = isDark
        ? AppTheme.textSecondaryDark.withAlpha(51)
        : AppTheme.textSecondaryLight.withAlpha(51);
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: GestureDetector(
          onHorizontalDragEnd: _handleSwipe,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              22,
              12,
              22,
              24 + _bottomNavReservedSpace(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('统计', style: textTheme.headlineLarge),
                const SizedBox(height: 10),
                Text(
                  _monthLabel(),
                  style: textTheme.bodyMedium?.copyWith(
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _SegmentButton(
                              text: '周',
                              selected: _range == StatsRange.week,
                              onTap: () => _switchRange(StatsRange.week),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _statsSegmentSpacing),
                            _SegmentButton(
                              text: '月',
                              selected: _range == StatsRange.month,
                              onTap: () => _switchRange(StatsRange.month),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _statsSegmentSpacing),
                            _SegmentButton(
                              text: '年',
                              selected: _range == StatsRange.year,
                              onTap: () => _switchRange(StatsRange.year),
                              width: _segmentButtonWidth,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: _segmentButtonWidth * 3 +
                              _statsSegmentSpacing * 2,
                          height: 3,
                          child: Stack(
                            children: [
                              AnimatedAlign(
                                alignment: _rangeIndicatorAlignment(),
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                child: Container(
                                  width: _segmentIndicatorWidth,
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentOf(context),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppTheme.accentOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _StatCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatValue(
                        label: '总杯数',
                        value: _summary.totalCups,
                      ),
                      Container(width: 1, height: 48, color: dividerColor),
                      _StatValue(
                        label: '总花销',
                        value: _summary.totalCost,
                        unit: '',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _StatCard(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatValue(
                        label: '总咖啡因',
                        value: _summary.totalCaffeine,
                        unit: 'mg',
                      ),
                      Container(width: 1, height: 48, color: dividerColor),
                      _StatValue(
                        label: '日均',
                        value: _summary.avgDailyCaffeine,
                        unit: 'mg',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _StatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '最受欢迎',
                        style: textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: AppTheme.accentOf(context).withAlpha(38),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.local_cafe_outlined,
                              size: 18,
                              color: AppTheme.accentOf(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _summary.favoriteType.isEmpty
                                ? '暂无'
                                : _summary.favoriteType,
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _summary.favoriteCount == 0
                                ? ''
                                : '${_summary.favoriteCount} 杯',
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              color: AppTheme.accentOf(context),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _StatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _range == StatsRange.year ? '咖啡因趋势（每月）' : '咖啡因趋势（每日）',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      _CaffeineTrendChart(values: _summary.caffeineSeries),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _StatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _range == StatsRange.year ? '每月杯数' : '每日杯数',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      _DailyChart(
                        counts: _summary.dailyCounts,
                        maxValue: widget.repository.maxDailyCount(
                          _summary.dailyCounts,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 0, 22, _bottomNavBottomPadding),
          child: _BottomNavBar(
            selectedIndex: 1,
            onSelect: (index) {
              if (index == 1) return;
              final target = index == 0
                  ? CoffeePage(
                      repository: widget.repository,
                      themeMode: widget.themeMode,
                      onThemeModeChange: widget.onThemeModeChange,
                      accentPalette: widget.accentPalette,
                      onAccentPaletteChange: widget.onAccentPaletteChange,
                    )
                  : index == 2
                      ? OcrPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : SettingsPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        );
              Navigator.of(context)
                  .pushReplacement(_transitionRoute(target, 1, index));
            },
          ),
        ),
      ),
    );
  }

  String _monthLabel() {
    final now = DateTime.now();
    final start = _rangeStart(now, _range);
    switch (_range) {
      case StatsRange.week:
        return '${start.year}年${start.month}月';
      case StatsRange.month:
        return '${start.year}年${start.month}月';
      case StatsRange.year:
        return '${start.year}年';
    }
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
}

class CoffeePage extends StatefulWidget {
  const CoffeePage({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChange,
    required this.accentPalette,
    required this.onAccentPaletteChange,
  });

  final CoffeeStatsRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final AppAccentPalette accentPalette;
  final ValueChanged<AppAccentPalette> onAccentPaletteChange;

  @override
  State<CoffeePage> createState() => _CoffeePageState();
}

class _CoffeePageState extends State<CoffeePage> with WidgetsBindingObserver {
  late DateTime _selectedDate;
  late DateTime _today;
  DateTime _monthStart = DateTime.now();
  List<CoffeeRecord> _monthRecords = const [];
  bool _monthLoading = true;
  double _caffeineTarget = 400;
  static const String _caffeineLimitKey = 'daily_caffeine_limit';
  static const double _todayRecordsRowMinHeight = 54;
  OpenMeteoCurrentWeather? _weather;
  bool _weatherLoading = false;
  String? _weatherError;
  bool _weatherNeedsPermission = false;
  bool _weatherNeedsService = false;
  bool _weatherNeedsSettings = false;
  DateTime? _weatherFetchedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _today = _stripTime(DateTime.now());
    _selectedDate = _today;
    _monthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
    _loadMonth(_monthStart);
    _loadCaffeineLimit();
    _loadWeather(requestPermission: false);
  }

  Future<void> _loadCaffeineLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLimit = prefs.getDouble(_caffeineLimitKey);
    if (savedLimit != null && mounted) {
      setState(() {
        _caffeineTarget = savedLimit;
      });
    }
  }

  DateTime _stripTime(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _weekdayLabel(DateTime date) {
    const labels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return labels[date.weekday - 1];
  }

  String _dateLabel(DateTime date) {
    final prefix = _isSameDay(date, _today) ? '今天 ' : '';
    return '$prefix${date.month}月${date.day}日 ${_weekdayLabel(date)}';
  }

  Future<void> _loadMonth(DateTime monthStart) async {
    setState(() {
      _monthLoading = true;
    });
    final end = DateTime(monthStart.year, monthStart.month + 1, 1);
    final records = await widget.repository.getRecordsInRange(monthStart, end);
    if (!mounted) return;
    setState(() {
      _monthRecords = records;
      _monthLoading = false;
    });
  }

  String _weatherDescription(int code) {
    if (code == 0) return '晴';
    if (code >= 1 && code <= 3) return '多云';
    if (code == 45 || code == 48) return '雾';
    if (code >= 51 && code <= 57) return '毛毛雨';
    if (code >= 61 && code <= 67) return '雨';
    if (code >= 71 && code <= 77) return '雪';
    if (code >= 80 && code <= 82) return '阵雨';
    if (code >= 85 && code <= 86) return '阵雪';
    if (code >= 95 && code <= 99) return '雷暴';
    return '天气';
  }

  IconData _weatherIcon(int code) {
    if (code == 0) return Icons.wb_sunny_outlined;
    if (code >= 1 && code <= 3) return Icons.cloud_outlined;
    if (code == 45 || code == 48) return Icons.blur_on_outlined;
    if (code >= 51 && code <= 57) return Icons.grain_outlined;
    if (code >= 61 && code <= 67) return Icons.water_drop_outlined;
    if (code >= 71 && code <= 77) return Icons.ac_unit;
    if (code >= 80 && code <= 82) return Icons.grain_outlined;
    if (code >= 85 && code <= 86) return Icons.ac_unit;
    if (code >= 95 && code <= 99) return Icons.thunderstorm_outlined;
    return Icons.cloud_outlined;
  }

  String _weatherTimeLabel(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _loadWeather({
    required bool requestPermission,
    bool force = false,
  }) async {
    if (_weatherLoading) return;
    if (kIsWeb) {
      setState(() {
        _weatherError = 'Web 暂不支持定位天气';
        _weatherNeedsPermission = false;
        _weatherNeedsService = false;
        _weatherNeedsSettings = false;
      });
      return;
    }
    final fetchedAt = _weatherFetchedAt;
    if (!force &&
        fetchedAt != null &&
        DateTime.now().difference(fetchedAt) < const Duration(minutes: 15)) {
      return;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _weatherNeedsService = true;
        _weatherNeedsPermission = false;
        _weatherNeedsSettings = false;
        _weatherError = '定位服务未开启';
      });
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermission) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      if (!mounted) return;
      setState(() {
        _weatherNeedsPermission = true;
        _weatherNeedsService = false;
        _weatherNeedsSettings = false;
        _weatherError = '未授予定位权限';
      });
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _weatherNeedsPermission = false;
        _weatherNeedsService = false;
        _weatherNeedsSettings = true;
        _weatherError = '定位权限被永久拒绝';
      });
      return;
    }

    setState(() {
      _weatherLoading = true;
      _weatherError = null;
      _weatherNeedsPermission = false;
      _weatherNeedsService = false;
      _weatherNeedsSettings = false;
    });

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      final weather = await const OpenMeteoClient().fetchCurrent(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      setState(() {
        _weather = weather;
        _weatherFetchedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weatherError = '获取失败';
      });
    } finally {
      if (mounted) {
        setState(() {
          _weatherLoading = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadCaffeineLimit();
  }

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool _hasCoffeeForDay(DateTime day) {
    for (final r in _monthRecords) {
      if (_isSameDay(r.createdAt, day)) return true;
    }
    return false;
  }

  int _caffeineForDay(DateTime day) {
    var sum = 0;
    for (final r in _monthRecords) {
      if (_isSameDay(r.createdAt, day)) sum += r.caffeineMg;
    }
    return sum;
  }

  List<CoffeeRecord> _recordsForDay(DateTime day) {
    final list = _monthRecords
        .where((r) => _isSameDay(r.createdAt, day))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _recordSubtitle(CoffeeRecord record) {
    final parts = <String>[
      _formatTime(record.createdAt),
      '${record.caffeineMg} mg',
      '¥${record.cost.toStringAsFixed(0)}',
    ];
    if (record.sugarG > 0) parts.add('糖 ${record.sugarG}g');
    if (record.homemade) parts.add('自制');
    return parts.join(' · ');
  }

  Future<void> _openRecordEditor(CoffeeRecord record) async {
    final updated = await Navigator.of(context).push<bool>(
      _bottomUpRoute<bool>(
        AddCoffeePage(
          repository: widget.repository,
          initialCreatedAt: record.createdAt,
          initialRecord: record,
        ),
      ),
    );
    if (updated == true) {
      _loadMonth(_monthStart);
    }
  }

  Future<void> _openDayRecords(DateTime day) async {
    final records = _recordsForDay(day);
    if (records.isEmpty) return;
    if (records.length == 1) {
      await _openRecordEditor(records.first);
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final textTheme = Theme.of(context).textTheme;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final r = records[index];
                return GestureDetector(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _openRecordEditor(r);
                  },
                  child: Container(
                    constraints: const BoxConstraints(
                      minHeight: _todayRecordsRowMinHeight,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withAlpha(isDark ? 10 : 6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppTheme.accentOf(context).withAlpha(28),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.local_cafe_outlined,
                            size: 18,
                            color: AppTheme.accentOf(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                (r.name ?? '').trim().isEmpty
                                    ? r.type
                                    : r.name!.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontSize: 15,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _recordSubtitle(r),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: AppTheme.accentOf(context),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _loadWeather(requestPermission: false);
    final nextToday = _stripTime(DateTime.now());
    if (_isSameDay(nextToday, _today)) return;
    final previousToday = _today;
    setState(() {
      _today = nextToday;
      if (_isSameDay(_selectedDate, previousToday)) {
        _selectedDate = nextToday;
      }
    });
    final nextMonthStart = DateTime(_selectedDate.year, _selectedDate.month, 1);
    if (!_isSameMonth(nextMonthStart, _monthStart)) {
      _monthStart = nextMonthStart;
      _loadMonth(_monthStart);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  List<DateTime?> _calendarCellsForMonth(DateTime month) {
    final firstDay = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstDay.weekday - 1;
    final total = leading + daysInMonth;
    final rowCount = ((total + 6) / 7).floor();
    final cellCount = rowCount * 7;
    return List<DateTime?>.generate(cellCount, (index) {
      final day = index - leading + 1;
      if (day < 1 || day > daysInMonth) return null;
      return DateTime(month.year, month.month, day);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final tileColor = Color.lerp(
          Theme.of(context).scaffoldBackgroundColor,
          cardColor,
          0.35,
        ) ??
        cardColor;

    final month = DateTime(_selectedDate.year, _selectedDate.month, 1);
    final cells = _calendarCellsForMonth(month);

    final caffeineSelected = _caffeineForDay(_selectedDate);
    final caffeineProgress =
        (caffeineSelected / _caffeineTarget).clamp(0.0, 1.0);
    final caffeineLabel = _isSameDay(_selectedDate, _today) ? '今日咖啡因' : '当日咖啡因';

    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            24 + _bottomNavReservedSpace(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${month.month}月',
                    style: textTheme.headlineLarge?.copyWith(
                      fontSize: 44,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      if (_isSameDay(_selectedDate, _today)) return;
                      setState(() {
                        _selectedDate = _today;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: (Theme.of(context).scaffoldBackgroundColor)
                            .withAlpha(70),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: AppTheme.accentOf(context).withAlpha(80),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '今天',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentOf(context),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _dateLabel(_selectedDate),
                style: textTheme.bodyMedium?.copyWith(
                  fontSize: 15,
                  color: secondary,
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Builder(
                  builder: (context) {
                    final accent = AppTheme.accentOf(context);
                    final weather = _weather;

                    String title = '所在地天气';
                    String subtitle = '点击获取天气';
                    String? tempText;
                    String? actionText;
                    VoidCallback? action;

                    if (_weatherLoading) {
                      title = '正在获取天气';
                      subtitle = '需要定位权限与网络';
                    } else if (weather != null) {
                      title = weather.locationName ?? '所在地天气';
                      subtitle =
                          '${_weatherDescription(weather.weatherCode)} · 风 ${weather.windSpeedKmh.round()} km/h · ${_weatherTimeLabel(weather.time)}';
                      tempText = '${weather.temperatureC.round()}°';
                    } else if (_weatherNeedsService) {
                      title = '无法获取天气';
                      subtitle = '请开启定位服务';
                      actionText = '去开启';
                      action = () => Geolocator.openLocationSettings();
                    } else if (_weatherNeedsSettings) {
                      title = '无法获取天气';
                      subtitle = '定位权限被永久拒绝';
                      actionText = '去设置';
                      action = () => Geolocator.openAppSettings();
                    } else if (_weatherNeedsPermission) {
                      title = '获取所在地天气';
                      subtitle = '点击授权定位权限';
                      actionText = '授权';
                      action = () => _loadWeather(
                            requestPermission: true,
                            force: true,
                          );
                    } else if ((_weatherError ?? '').isNotEmpty) {
                      title = '无法获取天气';
                      subtitle = _weatherError!;
                      actionText = '重试';
                      action = () => _loadWeather(
                            requestPermission: false,
                            force: true,
                          );
                    }

                    IconData icon = Icons.cloud_outlined;
                    if (_weatherNeedsPermission || _weatherNeedsSettings) {
                      icon = Icons.location_off_outlined;
                    } else if (_weatherNeedsService) {
                      icon = Icons.location_disabled_outlined;
                    } else if (weather != null) {
                      icon = _weatherIcon(weather.weatherCode);
                    }

                    return Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(28),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: _weatherLoading
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accent,
                                  ),
                                )
                              : Icon(icon, color: accent, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (tempText != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tempText,
                                style: textTheme.titleMedium?.copyWith(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: primary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _loadWeather(
                                  requestPermission: false,
                                  force: true,
                                ),
                                child: Icon(
                                  Icons.refresh,
                                  color: secondary,
                                ),
                              ),
                            ],
                          )
                        else
                          TextButton(
                            onPressed: action ??
                                () => _loadWeather(
                                      requestPermission: true,
                                      force: true,
                                    ),
                            child: Text(actionText ?? '获取'),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(isDark ? 51 : 15),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        for (final label in const [
                          '一',
                          '二',
                          '三',
                          '四',
                          '五',
                          '六',
                          '日'
                        ])
                          Expanded(
                            child: Center(
                              child: Text(
                                label,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: secondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 1,
                      ),
                      itemCount: cells.length,
                      itemBuilder: (context, index) {
                        final date = cells[index];
                        if (date == null) {
                          return const SizedBox.shrink();
                        }
                        final selected = _isSameDay(date, _selectedDate);
                        final isToday = _isSameDay(date, _today);
                        final hasCoffee = _hasCoffeeForDay(date);
                        final background = selected
                            ? AppTheme.accentOf(context).withAlpha(210)
                            : tileColor;
                        final border = !selected && isToday
                            ? Border.all(
                                color:
                                    AppTheme.accentOf(context).withAlpha(120),
                                width: 1.2,
                              )
                            : null;
                        final textColor = selected ? Colors.white : primary;
                        return GestureDetector(
                          onTap: () {
                            if (_isSameDay(date, _selectedDate)) return;
                            final nextMonthStart =
                                DateTime(date.year, date.month, 1);
                            setState(() {
                              _selectedDate = date;
                            });
                            if (!_isSameMonth(nextMonthStart, _monthStart)) {
                              _monthStart = nextMonthStart;
                              _loadMonth(_monthStart);
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(16),
                              border: border,
                            ),
                            child: Stack(
                              children: [
                                Center(
                                  child: Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: textColor,
                                    ),
                                  ),
                                ),
                                if (hasCoffee)
                                  const Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Text(
                                      '☕️',
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _monthLoading
                    ? null
                    : () async {
                        final createdAt = DateTime(
                          _selectedDate.year,
                          _selectedDate.month,
                          _selectedDate.day,
                          DateTime.now().hour,
                          DateTime.now().minute,
                        );
                        final added = await Navigator.of(context).push<bool>(
                          _bottomUpRoute<bool>(
                            AddCoffeePage(
                              repository: widget.repository,
                              initialCreatedAt: createdAt,
                            ),
                          ),
                        );
                        if (added == true) {
                          _loadMonth(_monthStart);
                        }
                      },
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.accentOf(context),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.accentOf(context).withAlpha(56),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 20, color: Colors.white),
                      SizedBox(width: 10),
                      Text(
                        '添加一杯',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '今日咖啡',
                style: textTheme.titleMedium?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: primary,
                ),
              ),
              const SizedBox(height: 12),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(caffeineLabel, style: textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: caffeineProgress,
                        minHeight: 10,
                        backgroundColor:
                            (isDark ? Colors.white : Colors.black).withAlpha(8),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppTheme.accentOf(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$caffeineSelected mg',
                          style: textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        ),
                        Text(
                          '${_caffeineTarget.round()} mg',
                          style: textTheme.bodyMedium?.copyWith(
                            color: secondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _openDayRecords(_selectedDate),
                      behavior: HitTestBehavior.translucent,
                      child: Row(
                        children: [
                          Text(
                            '当日记录',
                            style:
                                textTheme.titleMedium?.copyWith(fontSize: 18),
                          ),
                          const Spacer(),
                          Text(
                            '${_recordsForDay(_selectedDate).length} 条',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: secondary),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            color: AppTheme.accentOf(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final records = _recordsForDay(_selectedDate);
                        if (records.isEmpty) {
                          return Text(
                            _isSameDay(_selectedDate, _today)
                                ? '今天还没有记录'
                                : '当日还没有记录',
                            style: textTheme.bodyMedium
                                ?.copyWith(color: secondary),
                          );
                        }
                        final visible = records.take(3).toList(growable: false);
                        return Column(
                          children: [
                            for (final r in visible)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 6),
                                child: GestureDetector(
                                  onTap: () => _openRecordEditor(r),
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      minHeight: _todayRecordsRowMinHeight,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (isDark ? Colors.white : Colors.black)
                                              .withAlpha(isDark ? 10 : 6),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: (isDark
                                                ? Colors.white
                                                : Colors.black)
                                            .withAlpha(10),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentOf(context)
                                                .withAlpha(28),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.local_cafe_outlined,
                                            size: 18,
                                            color: AppTheme.accentOf(context),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                (r.name ?? '').trim().isEmpty
                                                    ? r.type
                                                    : r.name!.trim(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: textTheme.titleMedium
                                                    ?.copyWith(
                                                  fontSize: 15,
                                                  color: primary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                _recordSubtitle(r),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: textTheme.bodyMedium
                                                    ?.copyWith(
                                                        color: secondary),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: AppTheme.accentOf(context),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            if (records.length > 3) ...[
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () => _openDayRecords(_selectedDate),
                                child: Container(
                                  height: 44,
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accentOf(context)
                                        .withAlpha(22),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    '查看全部',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontSize: 15,
                                      color: AppTheme.accentOf(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 0, 22, _bottomNavBottomPadding),
          child: _BottomNavBar(
            selectedIndex: 0,
            onSelect: (index) {
              if (index == 0) return;
              final target = index == 1
                  ? StatsPage(
                      repository: widget.repository,
                      themeMode: widget.themeMode,
                      onThemeModeChange: widget.onThemeModeChange,
                      accentPalette: widget.accentPalette,
                      onAccentPaletteChange: widget.onAccentPaletteChange,
                    )
                  : index == 2
                      ? OcrPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : SettingsPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        );
              Navigator.of(context)
                  .pushReplacement(_transitionRoute(target, 0, index));
            },
          ),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChange,
    required this.accentPalette,
    required this.onAccentPaletteChange,
  });

  final CoffeeStatsRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final AppAccentPalette accentPalette;
  final ValueChanged<AppAccentPalette> onAccentPaletteChange;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _caffeineLimit = 400;
  static const String _caffeineLimitKey = 'daily_caffeine_limit';
  late AppAccentPalette _selectedPalette;

  @override
  void initState() {
    super.initState();
    _selectedPalette = widget.accentPalette;
    _loadCaffeineLimit();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accentPalette != widget.accentPalette) {
      _selectedPalette = widget.accentPalette;
    }
  }

  void _setPalette(AppAccentPalette palette) {
    if (_selectedPalette == palette) return;
    setState(() {
      _selectedPalette = palette;
    });
    widget.onAccentPaletteChange(palette);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _showAboutSheet() async {
    if (!mounted) return;
    final aboutText = [
      '咖记',
      '',
      '这是我写的一个咖啡记录与统计工具，帮助你更直观地管理每天的咖啡摄入。',
      '',
      '主要功能：',
      '• 记录咖啡：类型/咖啡因/糖/是否自制/备注/图片',
      '• 日历视图：查看当日记录与咖啡因进度',
      '• 统计分析：周/月/年趋势与偏好统计',
      '• OCR 识别：拍照识别菜单与咖啡豆包装信息',
      '',
      '感谢使用，希望你每天都喝到喜欢的那一杯。',
    ].join('\n');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '关于',
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: aboutText),
                          );
                          if (context.mounted) Navigator.of(context).pop();
                          _showMessage('已复制介绍内容');
                        },
                        child: const Text('复制并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: SelectableText(
                      aboutText,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '提示：如需更换主题或每日咖啡因上限，可在设置页直接调整。',
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showOpenSourceSheet() async {
    if (!mounted) return;
    final content = [
      '本应用使用了以下开源库（部分）：',
      '',
      '• Flutter SDK',
      '• cupertino_icons',
      '• google_fonts',
      '• isar / isar_flutter_libs',
      '• path_provider',
      '• shared_preferences',
      '• image_picker / cross_file',
      '• google_mlkit_text_recognition',
      '• flutter_displaymode',
      '',
      '你可以在下方打开系统的许可列表查看完整 License 文本。',
    ].join('\n');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '开源许可',
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (context.mounted) Navigator.of(context).pop();
                          _showMessage('已复制开源库列表');
                        },
                        child: const Text('复制并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        showLicensePage(
                          context: this.context,
                          applicationName: '咖记',
                        );
                      },
                      child: Text(
                        '查看完整许可列表',
                        style: textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          color: AppTheme.accentOf(context),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '说明：许可列表由 Flutter 自动汇总，具体内容以该页面为准。',
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPrivacySheet() async {
    if (!mounted) return;
    final content = [
      '隐私政策',
      '',
      '1. 数据收集',
      '本应用不要求注册账号，不主动收集可用于识别你身份的个人信息。',
      '',
      '2. 本地存储',
      '你添加的咖啡记录、设置项以及选择的图片路径等信息，会存储在你的设备本地，用于应用正常功能。',
      '',
      '3. 相机与相册权限',
      '当你使用拍照/OCR 或选择图片时，应用会请求相机/相册权限。相关图片仅用于本地处理与展示。',
      '',
      '4. OCR 识别',
      'OCR 依赖系统/第三方的本地文字识别能力（例如 ML Kit）。应用不会主动上传你的图片或识别内容到我们的服务器。',
      '',
      '5. 第三方服务',
      '本应用不集成广告 SDK，不包含第三方统计/跟踪代码。',
      '',
      '6. 联系方式',
      '如你对隐私政策有疑问，可通过你发布应用时提供的联系渠道与开发者联系。',
    ].join('\n');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '隐私政策',
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: content));
                          if (context.mounted) Navigator.of(context).pop();
                          _showMessage('已复制隐私政策');
                        },
                        child: const Text('复制并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: SelectableText(
                      content,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadCaffeineLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLimit = prefs.getDouble(_caffeineLimitKey);
    if (savedLimit != null && mounted) {
      setState(() {
        _caffeineLimit = savedLimit;
      });
    }
  }

  Future<void> _saveCaffeineLimit(double limit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_caffeineLimitKey, limit);
  }

  Alignment _themeIndicatorAlignment() {
    switch (widget.themeMode) {
      case ThemeMode.light:
        return Alignment.centerLeft;
      case ThemeMode.system:
        return Alignment.center;
      case ThemeMode.dark:
        return Alignment.centerRight;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            24 + _bottomNavReservedSpace(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: textTheme.headlineLarge),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '主题模式',
                          style: textTheme.titleMedium?.copyWith(fontSize: 18),
                        ),
                        Row(
                          children: [
                            _SegmentButton(
                              text: '浅色',
                              selected: widget.themeMode == ThemeMode.light,
                              onTap: () =>
                                  widget.onThemeModeChange(ThemeMode.light),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _themeSegmentSpacing),
                            _SegmentButton(
                              text: '跟随',
                              selected: widget.themeMode == ThemeMode.system,
                              onTap: () =>
                                  widget.onThemeModeChange(ThemeMode.system),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _themeSegmentSpacing),
                            _SegmentButton(
                              text: '深色',
                              selected: widget.themeMode == ThemeMode.dark,
                              onTap: () =>
                                  widget.onThemeModeChange(ThemeMode.dark),
                              width: _segmentButtonWidth,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: _segmentButtonWidth * 3 + _themeSegmentSpacing * 2,
                      height: 3,
                      child: AnimatedAlign(
                        alignment: _themeIndicatorAlignment(),
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        child: Container(
                          width: _segmentIndicatorWidth + 12,
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppTheme.accentOf(context),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '每日咖啡因上限',
                      style: textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_caffeineLimit.round()} mg',
                      style: textTheme.bodyMedium?.copyWith(
                        color: AppTheme.accentOf(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Slider(
                      value: _caffeineLimit,
                      min: 0,
                      max: 800,
                      divisions: 160,
                      onChanged: (v) {
                        setState(() {
                          _caffeineLimit = v;
                        });
                        _saveCaffeineLimit(v);
                      },
                      activeColor: AppTheme.accentOf(context),
                      inactiveColor:
                          (isDark ? Colors.white : Colors.black).withAlpha(10),
                    ),
                    Text(
                      '建议上限 400 mg',
                      style: textTheme.bodyMedium?.copyWith(
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '主题配色',
                      style: textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final palette in AppAccentPalette.values)
                          GestureDetector(
                            onTap: () => _setPalette(palette),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              curve: Curves.easeOut,
                              width: 72,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withAlpha(isDark ? 10 : 6),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: palette == _selectedPalette
                                      ? palette.color.withAlpha(220)
                                      : (isDark ? Colors.white : Colors.black)
                                          .withAlpha(10),
                                  width: palette == _selectedPalette ? 1.6 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: palette.color,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      AnimatedOpacity(
                                        opacity:
                                            palette == _selectedPalette ? 1 : 0,
                                        duration:
                                            const Duration(milliseconds: 160),
                                        child: const Icon(
                                          Icons.check,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    palette.label,
                                    style: textTheme.bodyMedium?.copyWith(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppTheme.textPrimaryDark
                                          : AppTheme.textPrimaryLight,
                                      fontWeight: palette == _selectedPalette
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: GestureDetector(
                  onTap: _showAboutSheet,
                  behavior: HitTestBehavior.translucent,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.accentOf(context).withAlpha(28),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.info_outline,
                          color: AppTheme.accentOf(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '关于',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '介绍软件与主要功能',
                              style: textTheme.bodyMedium?.copyWith(
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: AppTheme.accentOf(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: GestureDetector(
                  onTap: _showOpenSourceSheet,
                  behavior: HitTestBehavior.translucent,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.accentOf(context).withAlpha(28),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.article_outlined,
                          color: AppTheme.accentOf(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开源许可',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '查看使用的开源库与许可',
                              style: textTheme.bodyMedium?.copyWith(
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: AppTheme.accentOf(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: GestureDetector(
                  onTap: _showPrivacySheet,
                  behavior: HitTestBehavior.translucent,
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.accentOf(context).withAlpha(28),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.privacy_tip_outlined,
                          color: AppTheme.accentOf(context),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '隐私政策',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '了解数据与权限使用说明',
                              style: textTheme.bodyMedium?.copyWith(
                                color: secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: AppTheme.accentOf(context)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 0, 22, _bottomNavBottomPadding),
          child: _BottomNavBar(
            selectedIndex: 3,
            onSelect: (index) {
              if (index == 3) return;
              final target = index == 0
                  ? CoffeePage(
                      repository: widget.repository,
                      themeMode: widget.themeMode,
                      onThemeModeChange: widget.onThemeModeChange,
                      accentPalette: widget.accentPalette,
                      onAccentPaletteChange: widget.onAccentPaletteChange,
                    )
                  : index == 1
                      ? StatsPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : OcrPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        );
              Navigator.of(context)
                  .pushReplacement(_transitionRoute(target, 3, index));
            },
          ),
        ),
      ),
    );
  }
}

class OcrPage extends StatefulWidget {
  const OcrPage({
    super.key,
    required this.repository,
    required this.themeMode,
    required this.onThemeModeChange,
    required this.accentPalette,
    required this.onAccentPaletteChange,
  });

  final CoffeeStatsRepository repository;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChange;
  final AppAccentPalette accentPalette;
  final ValueChanged<AppAccentPalette> onAccentPaletteChange;

  @override
  State<OcrPage> createState() => _OcrPageState();
}

class _OcrPageState extends State<OcrPage> {
  bool _menuBusy = false;
  bool _beanBusy = false;
  List<_MenuItem> _menuItems = const [];
  String _menuText = '';
  _BeanInfo? _beanInfo;
  String _beanText = '';

  bool get _supportsOcr {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  Future<String> _recognizeText(String path) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
    try {
      final input = InputImage.fromFilePath(path);
      final result = await recognizer.processImage(input);
      return result.text;
    } catch (e) {
      _showMessage('识别失败，请重试');
      return '';
    } finally {
      await recognizer.close();
    }
  }

  Future<void> _scanMenu() async {
    if (_menuBusy) return;
    if (!_supportsOcr) {
      _showMessage('当前平台不支持 OCR 识别');
      return;
    }
    setState(() => _menuBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final text = await _recognizeText(picked.path);
      final items = _parseMenuItems(text);
      if (!mounted) return;
      setState(() {
        _menuText = text;
        _menuItems = items;
      });
      setState(() => _menuBusy = false);
      await _showMenuResultSheet(text: text, items: items);
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied' ||
          e.code == 'camera_access_denied_without_prompt') {
        _showMessage('相机权限被拒绝，请到系统设置中开启相机权限');
      } else {
        _showMessage('打开相机失败，请检查权限或重试');
      }
    } catch (_) {
      _showMessage('打开相机失败，请检查权限或重试');
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _scanBeans() async {
    if (_beanBusy) return;
    if (!_supportsOcr) {
      _showMessage('当前平台不支持 OCR 识别');
      return;
    }
    setState(() => _beanBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (picked == null) return;
      final text = await _recognizeText(picked.path);
      final info = _extractBeanInfo(text);
      if (!mounted) return;
      setState(() {
        _beanText = text;
        _beanInfo = info;
      });
      setState(() => _beanBusy = false);
      await _showBeanResultSheet(text: text, info: info);
    } on PlatformException catch (e) {
      if (e.code == 'camera_access_denied' ||
          e.code == 'photo_access_denied' ||
          e.code == 'camera_access_denied_without_prompt') {
        _showMessage('相机权限被拒绝，请到系统设置中开启相机权限');
      } else {
        _showMessage('打开相机失败，请检查权限或重试');
      }
    } catch (_) {
      _showMessage('打开相机失败，请检查权限或重试');
    } finally {
      if (mounted) setState(() => _beanBusy = false);
    }
  }

  List<_MenuItem> _parseMenuItems(String text) {
    final items = <_MenuItem>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final matches = RegExp(r'(¥?\s*\d+(\.\d{1,2})?)').allMatches(line);
      if (matches.isEmpty) continue;
      final match = matches.last;
      final priceRaw = match.group(0) ?? '';
      final priceValue =
          double.tryParse(priceRaw.replaceAll(RegExp(r'[^0-9.]'), ''));
      if (priceValue == null || priceValue <= 0) continue;
      final name = line
          .replaceAll(priceRaw, '')
          .replaceAll(RegExp(r'[¥￥]'), '')
          .replaceAll(RegExp(r'[:：\-]+'), ' ')
          .trim();
      if (name.isEmpty) continue;
      items.add(_MenuItem(name: name, price: priceValue));
    }
    return items;
  }

  _BeanInfo? _extractBeanInfo(String text) {
    String name = '';
    String origin = '';
    String process = '';
    String roast = '';
    String flavor = '';
    String weight = '';
    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final originLabel = RegExp(r'(产地|产区|产国)[:：]?\s*([^\s/，,;；]+)');
    final processLabel = RegExp(r'(处理|处理法)[:：]?\s*([^\s/，,;；]+)');
    final roastLabel = RegExp(r'(烘焙|烘焙度)[:：]?\s*([^\s/，,;；]+)');
    final nameHint = RegExp(r'(咖啡豆|咖啡|coffee|COFFEE)');
    final flavorLabel = RegExp(r'(风味|口味|香气)[:：]?\s*(.+)');
    final weightLabel = RegExp(r'(\d+(\.\d+)?)\s*(g|G|克|KG|kg|Kg|千克|公克)\b');
    for (final line in lines) {
      if (name.isEmpty &&
          nameHint.hasMatch(line) &&
          !line.contains('风味') &&
          !line.contains('口味') &&
          !line.contains('香气') &&
          !line.contains('产地') &&
          !line.contains('产区') &&
          !line.contains('产国') &&
          !line.contains('烘焙') &&
          !line.contains('处理') &&
          !line.contains('净含量') &&
          !line.contains('内容量')) {
        name = line;
      }
      if (origin.isEmpty) {
        final match = originLabel.firstMatch(line);
        if (match != null) {
          origin = match.group(2) ?? '';
        }
      }
      if (process.isEmpty) {
        final match = processLabel.firstMatch(line);
        if (match != null) {
          process = match.group(2) ?? '';
        }
      }
      if (roast.isEmpty) {
        final match = roastLabel.firstMatch(line);
        if (match != null) {
          roast = match.group(2) ?? '';
        }
      }
      if (flavor.isEmpty) {
        final match = flavorLabel.firstMatch(line);
        if (match != null) {
          flavor = (match.group(2) ?? '').trim();
        }
      }
      if (weight.isEmpty) {
        final match = weightLabel.firstMatch(line);
        if (match != null) {
          weight = match.group(0) ?? '';
        }
      }
    }
    if (origin.isEmpty) {
      for (final keyword in const [
        '埃塞',
        '埃塞俄比亚',
        '哥伦比亚',
        '云南',
        '巴西',
        '肯尼亚',
        '危地马拉',
        '印尼',
        '卢旺达',
        '巴拿马',
        '哥斯达黎加',
      ]) {
        if (text.contains(keyword)) {
          origin = keyword;
          break;
        }
      }
    }
    if (process.isEmpty) {
      for (final keyword in const [
        '日晒',
        '水洗',
        '蜜处理',
        '厌氧',
        '半水洗',
        '湿刨',
      ]) {
        if (text.contains(keyword)) {
          process = keyword;
          break;
        }
      }
    }
    if (roast.isEmpty) {
      for (final keyword in const [
        '浅烘',
        '浅中烘',
        '中烘',
        '中深烘',
        '深烘',
      ]) {
        if (text.contains(keyword)) {
          roast = keyword;
          break;
        }
      }
    }
    if (name.isEmpty) {
      for (final line in lines) {
        if (line.length < 2) continue;
        if (RegExp(r'\d').hasMatch(line)) continue;
        if (line.contains('风味') ||
            line.contains('口味') ||
            line.contains('香气') ||
            line.contains('产地') ||
            line.contains('产区') ||
            line.contains('产国') ||
            line.contains('烘焙') ||
            line.contains('处理') ||
            line.contains('净含量') ||
            line.contains('内容量')) {
          continue;
        }
        name = line;
        break;
      }
    }
    if (weight.isEmpty) {
      final match = weightLabel.firstMatch(text);
      if (match != null) {
        weight = match.group(0) ?? '';
      }
    }
    if (origin.isEmpty &&
        process.isEmpty &&
        roast.isEmpty &&
        flavor.isEmpty &&
        weight.isEmpty &&
        name.isEmpty) {
      return null;
    }
    return _BeanInfo(
      name: name,
      origin: origin,
      process: process,
      roast: roast,
      flavor: flavor,
      weight: weight,
    );
  }

  Widget _actionButton({
    required String text,
    required IconData icon,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? AppTheme.darkCard : Colors.white;
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 90 : 18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.accentOf(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                busy ? '识别中...' : text,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark
                      ? AppTheme.textPrimaryDark
                      : AppTheme.textPrimaryLight,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.accentOf(context)),
          ],
        ),
      ),
    );
  }

  Widget _beanRow(String label, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    return Row(
      children: [
        SizedBox(
          width: 44,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: secondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '未识别' : value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight,
            ),
          ),
        ),
      ],
    );
  }

  String _beanNoteSummary(_BeanInfo info) {
    final lines = <String>[];
    if (info.origin.isNotEmpty) {
      lines.add('产区：${info.origin}');
    }
    if (info.process.isNotEmpty) {
      lines.add('处理：${info.process}');
    }
    if (info.roast.isNotEmpty) {
      lines.add('烘焙度：${info.roast}');
    }
    if (info.flavor.isNotEmpty) {
      lines.add('风味：${info.flavor}');
    }
    if (info.weight.isNotEmpty) {
      lines.add('净含量：${info.weight}');
    }
    return lines.join('\n');
  }

  Widget _buildBeanRecordButton() {
    final info = _beanInfo;
    if (info == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        final createdAt = DateTime.now();
        Navigator.of(context).push(
          _bottomUpRoute<bool>(
            AddCoffeePage(
              repository: widget.repository,
              initialCreatedAt: createdAt,
              initialName: info.name.isEmpty ? null : info.name,
              initialNote: _beanNoteSummary(info),
            ),
          ),
        );
      },
      child: Container(
        height: 46,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppTheme.accentOf(context),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentOf(context).withAlpha(isDark ? 120 : 80),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Text(
          '新增记录页（已自动填写）',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Future<void> _showMenuResultSheet({
    required String text,
    required List<_MenuItem> items,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '识别结果（菜单）',
                          style: textTheme.titleMedium?.copyWith(
                            fontSize: 18,
                            color: primary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          _showMessage('已复制识别内容');
                        },
                        child: const Text('复制并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (items.isEmpty)
                    Text(
                      '未识别到可用条目',
                      style: textTheme.bodyMedium?.copyWith(color: secondary),
                    ),
                  if (items.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          for (final item in items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: textTheme.titleMedium?.copyWith(
                                        fontSize: 16,
                                        color: primary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '¥${item.price.toStringAsFixed(0)}',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontSize: 16,
                                      color: AppTheme.accentOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    '原文',
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: SelectableText(
                      text.isEmpty ? '（空）' : text,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBeanResultSheet({
    required String text,
    required _BeanInfo? info,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final textTheme = Theme.of(context).textTheme;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              left: 22,
              right: 22,
              top: 6,
              bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '识别结果（咖啡豆）',
                          style: textTheme.titleMedium?.copyWith(fontSize: 18),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: text));
                          if (context.mounted) {
                            Navigator.of(context).pop();
                          }
                          _showMessage('已复制识别内容');
                        },
                        child: const Text('复制并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (info == null)
                    Text(
                      '未识别到可用信息',
                      style: textTheme.bodyMedium?.copyWith(color: secondary),
                    ),
                  if (info != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _beanRow('☕ 咖啡豆名称', info.name),
                          const SizedBox(height: 8),
                          _beanRow('🌍 产区', info.origin),
                          const SizedBox(height: 8),
                          _beanRow('🔥 烘焙度', info.roast),
                          const SizedBox(height: 8),
                          _beanRow('👃 风味', info.flavor),
                          const SizedBox(height: 8),
                          _beanRow('⚖️ 净含量', info.weight),
                          const SizedBox(height: 16),
                          _buildBeanRecordButton(),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    '原文',
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(10),
                      ),
                    ),
                    child: SelectableText(
                      text.isEmpty ? '（空）' : text,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: isDark
                            ? AppTheme.textPrimaryDark
                            : AppTheme.textPrimaryLight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final subtitleStyle = textTheme.bodyMedium?.copyWith(color: secondary);
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            22,
            12,
            22,
            24 + _bottomNavReservedSpace(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('OCR识别', style: textTheme.headlineLarge),
              const SizedBox(height: 14),
              _StatCard(
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: AppTheme.accentOf(context).withAlpha(38),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.document_scanner_outlined,
                        color: AppTheme.accentOf(context),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '识别咖啡单据或标签',
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              color: primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '点击下方按钮开始识别',
                            style: textTheme.bodyMedium?.copyWith(
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('拍照菜单', style: subtitleStyle),
                    const SizedBox(height: 10),
                    _actionButton(
                      text: '识别成品名/价格',
                      icon: Icons.photo_camera_outlined,
                      busy: _menuBusy,
                      onTap: _scanMenu,
                    ),
                    const SizedBox(height: 12),
                    if (_menuItems.isEmpty && _menuText.isNotEmpty)
                      Text('未识别到可用条目', style: subtitleStyle),
                    if (_menuItems.isEmpty && _menuText.isEmpty)
                      Text('等待识别结果', style: subtitleStyle),
                    if (_menuItems.isNotEmpty)
                      Column(
                        children: [
                          for (final item in _menuItems)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: textTheme.titleMedium?.copyWith(
                                        fontSize: 16,
                                        color: primary,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '¥${item.price.toStringAsFixed(0)}',
                                    style: textTheme.titleMedium?.copyWith(
                                      fontSize: 16,
                                      color: AppTheme.accentOf(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('扫描咖啡豆包装', style: subtitleStyle),
                    const SizedBox(height: 10),
                    _actionButton(
                      text: '识别产区/处理/烘焙',
                      icon: Icons.document_scanner_outlined,
                      busy: _beanBusy,
                      onTap: _scanBeans,
                    ),
                    const SizedBox(height: 12),
                    if (_beanInfo == null && _beanText.isNotEmpty)
                      Text('未识别到可用信息', style: subtitleStyle),
                    if (_beanInfo == null && _beanText.isEmpty)
                      Text('等待识别结果', style: subtitleStyle),
                    if (_beanInfo != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _beanRow('☕ 咖啡豆名称', _beanInfo?.name ?? ''),
                          const SizedBox(height: 8),
                          _beanRow('🌍 产区', _beanInfo?.origin ?? ''),
                          const SizedBox(height: 8),
                          _beanRow('🔥 烘焙度', _beanInfo?.roast ?? ''),
                          const SizedBox(height: 8),
                          _beanRow('👃 风味', _beanInfo?.flavor ?? ''),
                          const SizedBox(height: 8),
                          _beanRow('⚖️ 净含量', _beanInfo?.weight ?? ''),
                          const SizedBox(height: 16),
                          _buildBeanRecordButton(),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(22, 0, 22, _bottomNavBottomPadding),
          child: _BottomNavBar(
            selectedIndex: 2,
            onSelect: (index) {
              if (index == 2) return;
              final target = index == 0
                  ? CoffeePage(
                      repository: widget.repository,
                      themeMode: widget.themeMode,
                      onThemeModeChange: widget.onThemeModeChange,
                      accentPalette: widget.accentPalette,
                      onAccentPaletteChange: widget.onAccentPaletteChange,
                    )
                  : index == 1
                      ? StatsPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : SettingsPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        );
              Navigator.of(context)
                  .pushReplacement(_transitionRoute(target, 2, index));
            },
          ),
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem({required this.name, required this.price});

  final String name;
  final double price;
}

class _BeanInfo {
  const _BeanInfo({
    required this.name,
    required this.origin,
    required this.process,
    required this.roast,
    required this.flavor,
    required this.weight,
  });

  final String name;
  final String origin;
  final String process;
  final String roast;
  final String flavor;
  final String weight;
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.text,
    required this.selected,
    required this.onTap,
    this.width,
  });

  final String text;
  final bool selected;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = selected
        ? AppTheme.accentOf(context)
        : (isDark ? AppTheme.darkCard : AppTheme.lightCard);
    final textColor = selected
        ? Colors.white
        : (isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppTheme.accentOf(context).withAlpha(64),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: width == null ? content : SizedBox(width: width, child: content),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : AppTheme.lightCard,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 51 : 15),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({
    required this.label,
    required this.value,
    this.unit = '',
  });

  final String label;
  final int value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: secondary),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
            if (unit.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(
                  unit,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: secondary,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DailyChart extends StatelessWidget {
  const _DailyChart({required this.counts, required this.maxValue});

  final List<int> counts;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    if (counts.isEmpty) {
      return SizedBox(
        height: 80,
        child: Center(
          child: Text(
            '暂无数据',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return SizedBox(
      height: 96,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < counts.length; i++)
            Expanded(
              child: _ChartBar(
                value: counts[i],
                maxValue: maxValue,
                showLabel: counts[i] > 0,
              ),
            ),
        ],
      ),
    );
  }
}

class _CaffeineTrendChart extends StatelessWidget {
  const _CaffeineTrendChart({required this.values});

  final List<int> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return SizedBox(
        height: 110,
        child: Center(
          child: Text(
            '暂无数据',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    final maxValue = max(1, values.reduce(max));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lineColor = AppTheme.accentOf(context);
    final fillColor = lineColor.withAlpha(isDark ? 45 : 30);
    return SizedBox(
      width: double.infinity,
      height: 120,
      child: CustomPaint(
        painter: _CaffeineTrendPainter(
          values: values,
          maxValue: maxValue,
          lineColor: lineColor,
          fillColor: fillColor,
        ),
      ),
    );
  }
}

class _CaffeineTrendPainter extends CustomPainter {
  _CaffeineTrendPainter({
    required this.values,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
  });

  final List<int> values;
  final int maxValue;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 10.0;
    final width = size.width - inset * 2;
    final height = size.height - inset * 2;
    if (width <= 0 || height <= 0) return;
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final t = values.length == 1 ? 0.5 : i / (values.length - 1);
      final x = inset + width * t;
      final y = inset + height * (1 - values[i] / maxValue);
      points.add(Offset(x, y));
    }

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    final areaPath = Path()
      ..addPath(linePath, Offset.zero)
      ..lineTo(points.last.dx, inset + height)
      ..lineTo(points.first.dx, inset + height)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, fillPaint);

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final dotPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CaffeineTrendPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor;
  }
}

class _ChartBar extends StatelessWidget {
  const _ChartBar({
    required this.value,
    required this.maxValue,
    required this.showLabel,
  });

  final int value;
  final int maxValue;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final normalized = maxValue == 0 ? 0.0 : value / maxValue;
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.max,
      children: [
        SizedBox(
          height: 18,
          child: showLabel
              ? Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: normalized,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentOf(context),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF1C1C1E).withAlpha(88)
        : Colors.white.withAlpha(130);
    final borderColor =
        isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(16);
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 64, sigmaY: 64),
        child: Container(
          height: _bottomNavHeight,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 110 : 38),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavItem(
                icon: Icons.local_cafe_outlined,
                selected: selectedIndex == 0,
                onTap: () => onSelect(0),
              ),
              _NavItem(
                icon: Icons.show_chart_outlined,
                selected: selectedIndex == 1,
                onTap: () => onSelect(1),
              ),
              _NavItem(
                icon: Icons.document_scanner_outlined,
                selected: selectedIndex == 2,
                onTap: () => onSelect(2),
              ),
              _NavItem(
                icon: Icons.settings_outlined,
                selected: selectedIndex == 3,
                onTap: () => onSelect(3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? AppTheme.accentOf(context)
        : (isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: selected
            ? BoxDecoration(
                color: AppTheme.accentOf(context).withAlpha(31),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

class AddCoffeePage extends StatefulWidget {
  const AddCoffeePage({
    super.key,
    required this.repository,
    required this.initialCreatedAt,
    this.initialRecord,
    this.initialName,
    this.initialNote,
  });

  final CoffeeStatsRepository repository;
  final DateTime initialCreatedAt;
  final CoffeeRecord? initialRecord;
  final String? initialName;
  final String? initialNote;

  @override
  State<AddCoffeePage> createState() => _AddCoffeePageState();
}

class _AddCoffeePageState extends State<AddCoffeePage> {
  late DateTime _createdAt;
  String _type = '拿铁';
  String _cupSize = '中杯';
  String _temp = '冰';
  double _caffeineMg = 75;
  double _sugarG = 0;
  bool _homemade = false;
  String? _imagePath;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  bool _saving = false;

  bool get _isEditing => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final initialRecord = widget.initialRecord;
    if (initialRecord != null) {
      _createdAt = initialRecord.createdAt;
      _type = initialRecord.type;
      _cupSize = initialRecord.cupSize ?? _cupSize;
      _temp = initialRecord.temperature ?? _temp;
      _caffeineMg = initialRecord.caffeineMg.toDouble();
      _sugarG = initialRecord.sugarG.toDouble();
      _homemade = initialRecord.homemade;
      _imagePath = initialRecord.imagePath;
      if ((initialRecord.name ?? '').trim().isNotEmpty) {
        _nameController.text = initialRecord.name!.trim();
      }
      if ((initialRecord.note ?? '').trim().isNotEmpty) {
        _noteController.text = initialRecord.note!.trim();
      }
      final cost = initialRecord.cost;
      _priceController.text =
          cost % 1 == 0 ? cost.toStringAsFixed(0) : cost.toStringAsFixed(2);
      return;
    }
    _createdAt = widget.initialCreatedAt;
    final initialName = widget.initialName;
    if (initialName != null && initialName.isNotEmpty) {
      _nameController.text = initialName;
    }
    final initialNote = widget.initialNote;
    if (initialNote != null && initialNote.isNotEmpty) {
      _noteController.text = initialNote;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _dateTimeLabel(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final weekday =
        const ['周一', '周二', '周三', '周四', '周五', '周六', '周日'][dt.weekday - 1];
    return '${dt.month}月${dt.day}日 $weekday  ${two(dt.hour)}:${two(dt.minute)}';
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_createdAt),
    );
    if (time == null) return;
    setState(() {
      _createdAt = DateTime(
        _createdAt.year,
        _createdAt.month,
        _createdAt.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickImage() async {
    if (_saving) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
    );
    if (picked == null) return;
    final persisted = await persistPickedImage(picked);
    if (!mounted) return;
    setState(() {
      _imagePath = persisted;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    final cost = double.tryParse(_priceController.text.trim()) ?? 0;
    final name = _nameController.text.trim();
    final note = _noteController.text.trim();
    final existing = widget.initialRecord;
    if (existing != null) {
      final record = CoffeeRecord()
        ..id = existing.id
        ..type = _type
        ..caffeineMg = _caffeineMg.round()
        ..sugarG = _sugarG.round()
        ..homemade = _homemade
        ..name = name.isEmpty ? null : name
        ..cupSize = _cupSize
        ..temperature = _temp
        ..note = note.isEmpty ? null : note
        ..imagePath = _imagePath
        ..cost = cost
        ..createdAt = _createdAt;
      await widget.repository.updateRecord(record);
    } else {
      final record = CoffeeRecord()
        ..type = _type
        ..caffeineMg = _caffeineMg.round()
        ..sugarG = _sugarG.round()
        ..homemade = _homemade
        ..name = name.isEmpty ? null : name
        ..cupSize = _cupSize
        ..temperature = _temp
        ..note = note.isEmpty ? null : note
        ..imagePath = _imagePath
        ..cost = cost
        ..createdAt = _createdAt;
      await widget.repository.addRecord(record);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Widget _topPillButton({
    required String text,
    required VoidCallback onTap,
    Color? background,
    Color? textColor,
  }) {
    return GestureDetector(
      onTap: _saving ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: background ??
              (Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.darkCard
                  : Colors.white),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(
                Theme.of(context).brightness == Brightness.dark ? 90 : 18,
              ),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: textColor ??
                (Theme.of(context).brightness == Brightness.dark
                    ? AppTheme.textPrimaryDark
                    : AppTheme.textPrimaryLight),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _choiceCard({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = selected
        ? AppTheme.accentOf(context).withAlpha(210)
        : (isDark ? AppTheme.darkCard : Colors.white);
    final fg = selected
        ? Colors.white
        : (isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight);
    return GestureDetector(
      onTap: _saving ? null : onTap,
      child: Container(
        width: 106,
        height: 72,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 55 : 10),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _topPillButton(
                    text: '取消',
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  Text(_isEditing ? '编辑咖啡' : '添加咖啡',
                      style: textTheme.titleMedium
                          ?.copyWith(fontSize: 18, color: primary)),
                  _topPillButton(
                    text: _saving ? '保存中' : (_isEditing ? '保存修改' : '保存'),
                    onTap: _save,
                    background: cardColor,
                    textColor: AppTheme.accentOf(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('图片（选填）'),
                    GestureDetector(
                      onTap: _saving ? null : _pickImage,
                      child: Container(
                        height: 150,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardColor.withAlpha(isDark ? 110 : 245),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(18),
                            width: 1,
                          ),
                        ),
                        child: _imagePath == null
                            ? Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.photo_camera_outlined,
                                    color: AppTheme.accentOf(context)
                                        .withAlpha(180),
                                    size: 34,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '添加图片',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.accentOf(context)
                                          .withAlpha(220),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '记录咖啡时光',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: secondary,
                                    ),
                                  ),
                                ],
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(26),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    storedImage(_imagePath!, fit: BoxFit.cover),
                                    Positioned(
                                      top: 10,
                                      right: 10,
                                      child: GestureDetector(
                                        onTap: _saving
                                            ? null
                                            : () {
                                                setState(() {
                                                  _imagePath = null;
                                                });
                                              },
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(110),
                                            borderRadius:
                                                BorderRadius.circular(14),
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.close,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _saving ? null : _pickTime,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(isDark ? 55 : 10),
                              blurRadius: 18,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppTheme.accentOf(context).withAlpha(24),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.calendar_month_outlined,
                                size: 20,
                                color: AppTheme.accentOf(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _dateTimeLabel(_createdAt),
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: primary),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('点击修改时间',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: secondary)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: secondary),
                          ],
                        ),
                      ),
                    ),
                    _sectionTitle('名称（选填）'),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                      ),
                    ),
                    _sectionTitle('自制咖啡'),
                    _StatCard(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '自制',
                            style: textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              color: primary,
                            ),
                          ),
                          Switch(
                            value: _homemade,
                            activeColor: AppTheme.accentOf(context),
                            onChanged: _saving
                                ? null
                                : (v) {
                                    setState(() {
                                      _homemade = v;
                                    });
                                  },
                          ),
                        ],
                      ),
                    ),
                    _sectionTitle('咖啡类型'),
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final t in const [
                          '美式',
                          '卡布奇诺',
                          '摩卡',
                          '浓缩',
                          '拿铁',
                          '馥芮白'
                        ])
                          _choiceCard(
                            text: t,
                            selected: _type == t,
                            onTap: () => setState(() => _type = t),
                          ),
                      ],
                    ),
                    _sectionTitle('杯型'),
                    Row(
                      children: [
                        _SegmentButton(
                          text: '小杯',
                          selected: _cupSize == '小杯',
                          onTap: () => setState(() => _cupSize = '小杯'),
                          width: 84,
                        ),
                        const SizedBox(width: 12),
                        _SegmentButton(
                          text: '中杯',
                          selected: _cupSize == '中杯',
                          onTap: () => setState(() => _cupSize = '中杯'),
                          width: 84,
                        ),
                        const SizedBox(width: 12),
                        _SegmentButton(
                          text: '大杯',
                          selected: _cupSize == '大杯',
                          onTap: () => setState(() => _cupSize = '大杯'),
                          width: 84,
                        ),
                      ],
                    ),
                    _sectionTitle('温度'),
                    Row(
                      children: [
                        _SegmentButton(
                          text: '🧊  冰',
                          selected: _temp == '冰',
                          onTap: () => setState(() => _temp = '冰'),
                          width: 150,
                        ),
                        const SizedBox(width: 14),
                        _SegmentButton(
                          text: '♨️  热',
                          selected: _temp == '热',
                          onTap: () => setState(() => _temp = '热'),
                          width: 150,
                        ),
                      ],
                    ),
                    _sectionTitle('咖啡因：${_caffeineMg.round()} mg'),
                    Slider(
                      value: _caffeineMg,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _caffeineMg = v),
                      min: 0,
                      max: 300,
                      divisions: 300,
                      activeColor: AppTheme.accentOf(context),
                      inactiveColor:
                          (isDark ? Colors.white : Colors.black).withAlpha(10),
                    ),
                    _sectionTitle('糖量：${_sugarG.round()} g'),
                    Slider(
                      value: _sugarG,
                      onChanged:
                          _saving ? null : (v) => setState(() => _sugarG = v),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      activeColor: AppTheme.accentOf(context),
                      inactiveColor:
                          (isDark ? Colors.white : Colors.black).withAlpha(10),
                    ),
                    _sectionTitle('价格（选填）'),
                    TextField(
                      controller: _priceController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        hintText: '',
                        filled: true,
                        fillColor: cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                      ),
                    ),
                    _sectionTitle('备注（选填）'),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '下午茶…',
                        filled: true,
                        fillColor: cardColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Route<T> _transitionRoute<T>(Widget target, int from, int to) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => target,
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
        child: SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero)
                  .animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

Route<T> _bottomUpRoute<T>(Widget target) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => target,
    transitionDuration: const Duration(milliseconds: 520),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
