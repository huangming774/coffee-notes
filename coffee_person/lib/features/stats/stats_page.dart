import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:isar/isar.dart';
import 'package:motion_photos/motion_photos.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/coffee_record.dart';

import '../../data/coffee_diary_entry.dart';
import '../../data/coffee_diary_repository.dart';
import '../../data/coffee_repository.dart';
import '../../features/diary/asset_picker_page.dart';
import '../../features/stickers/calendar_with_stickers.dart';
import '../../features/stickers/camera_service.dart';
import '../../features/stickers/detection_service.dart';
import '../../features/stickers/sticker_models.dart';
import '../../features/stickers/sticker_store.dart';
import '../../features/stickers/sticker_view.dart';
import '../../features/widgets/coffee_home_widget.dart';
import '../../features/weather/weather_client.dart';
import '../../features/weather/weather_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/stored_image.dart';

const double _segmentButtonWidth = 60;
const double _statsSegmentSpacing = 12;
const double _themeSegmentSpacing = 12;
const double _bottomNavHeight = 84;
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
  DateTime _anchorDate = DateTime.now();
  static const String _openAiApiKeyKey = 'openai_api_key';
  static const String _openAiBaseUrlKey = 'openai_base_url';
  static const String _openAiModelKey = 'openai_model';

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
    final summary =
        await widget.repository.getStats(_range, anchorDate: _anchorDate);
    if (!mounted) return;
    setState(() {
      _summary = summary;
    });
    await _updateHomeWidgetToday();
  }

  Future<void> _updateHomeWidgetToday() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final records = await widget.repository.getRecordsInRange(today, tomorrow);
    var todayCaffeine = 0;
    for (final r in records) {
      todayCaffeine += r.caffeineMg;
    }
    await CoffeeHomeWidget.updateToday(
      caffeineMg: todayCaffeine,
      cups: records.length,
      date: today,
    );
  }

  Future<void> _pickAnchorDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _anchorDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      _anchorDate = picked;
    });
    await _load();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Uri? _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (!(parsed.scheme == 'http' || parsed.scheme == 'https')) return null;
    if (parsed.host.isEmpty) return null;
    return parsed;
  }

  Uri _appendPath(Uri base, List<String> segmentsToAdd) {
    final segments = <String>[
      ...base.pathSegments.where((s) => s.isNotEmpty),
      ...segmentsToAdd,
    ];
    return base.replace(pathSegments: segments);
  }

  String _rangeLabel() {
    switch (_range) {
      case StatsRange.week:
        return '周';
      case StatsRange.month:
        return '月';
      case StatsRange.year:
        return '年';
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

  Future<String> _fetchAiCaffeineAnalysis() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_openAiApiKeyKey) ?? '';
    final baseUrl = prefs.getString(_openAiBaseUrlKey) ?? '';
    final model = (prefs.getString(_openAiModelKey) ?? '').trim();
    final userDailyLimit = prefs.getDouble('daily_caffeine_limit');

    if (apiKey.trim().isEmpty || baseUrl.trim().isEmpty) {
      throw Exception('请先在设置页配置 AI（Base URL 与 API Key）');
    }

    final baseUri = _normalizeBaseUrl(baseUrl);
    if (baseUri == null) {
      throw Exception('Base URL 格式不正确');
    }

    final uri = _appendPath(baseUri, const ['chat', 'completions']);

    final now = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day);
    final rangeStart = _rangeStart(now, _range);
    final rangeEnd = _rangeEnd(rangeStart, _range);
    final daysElapsed = _daysElapsed(rangeStart, rangeEnd, now);

    final seriesUnit = _range == StatsRange.year ? '月' : '日';
    final maxCupsInUnit =
        _summary.dailyCounts.isEmpty ? 0 : _summary.dailyCounts.reduce(max);
    final maxCaffeineInUnit = _summary.caffeineSeries.isEmpty
        ? 0
        : _summary.caffeineSeries.reduce(max);
    final avgCupsPerDay =
        daysElapsed == 0 ? 0 : (_summary.totalCups / daysElapsed);

    final prompt = [
      '你是专业健康分析师，现在需要基于以下用户数据进行咖啡因摄入分析和行为评价：',
      '',
      '用户数据：',
      '1) 统计周期：${_monthLabel()}（${_rangeLabel()}），锚点日期：${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      '2) 咖啡因摄入：总计 ${_summary.totalCaffeine} mg；日均 ${_summary.avgDailyCaffeine} mg/天；最高单$seriesUnit $maxCaffeineInUnit mg',
      '3) 饮用频率：总杯数 ${_summary.totalCups} 杯；平均 ${avgCupsPerDay.toStringAsFixed(2)} 杯/天；最高单$seriesUnit $maxCupsInUnit 杯',
      if (userDailyLimit != null)
        '4) 用户设置的每日咖啡因上限：${userDailyLimit.round()} mg（推荐上限仍按 400mg 对比）',
      if (_summary.favoriteType.isNotEmpty)
        '5) 偏好：最常喝 ${_summary.favoriteType}（${_summary.favoriteCount} 杯）',
      if (_summary.dailyCounts.isNotEmpty)
        '6) 每$seriesUnit杯数序列：${_summary.dailyCounts.join(', ')}',
      if (_summary.caffeineSeries.isNotEmpty)
        '7) 每$seriesUnit咖啡因序列（mg）：${_summary.caffeineSeries.join(', ')}',
      '',
      '你的分析框架：',
      '1. 计算总咖啡因摄入量，对比每日推荐上限（400mg），判断是否超标。',
      '2. 分析过量摄入对神经系统、心血管系统和情绪状态的短期及长期影响。',
      '3. 评价其行为模式：是否存在咖啡因依赖、是否用咖啡因应对疲劳或压力、是否忽视身体信号。',
      '4. 给出具体建议：',
      '   - 逐步减量计划',
      '   - 调整饮用时间的策略',
      '',
      '输出要求：',
      '- 结构清晰，分点明确，语言易懂，避免专业术语堆砌。',
      '- 重点帮助用户理解问题并采取行动，语气支持而非指责。',
    ].join('\n');

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: <String, String>{
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': model.isEmpty ? 'gpt-4o-mini' : model,
              'temperature': 0.6,
              'max_tokens': 900,
              'messages': [
                {
                  'role': 'system',
                  'content': '你是专业健康分析师，表达支持、具体、可执行。',
                },
                {
                  'role': 'user',
                  'content': prompt,
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception('请求超时：请检查网络或 Base URL（建议先在设置页点“测试”）');
    } catch (_) {
      throw Exception('请求失败：无法连接到服务器（请检查网络/Base URL）');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map) {
          final message = error['message'];
          if (message is String && message.trim().isNotEmpty) {
            throw Exception('接口返回错误：${message.trim()}');
          }
        }
      }
      final text = _extractChatCompletionText(decoded);
      if (text != null && text.trim().isNotEmpty) {
        return text.trim();
      }
      throw Exception(
          '返回内容解析失败：请确认 Base URL 使用 OpenAI 兼容接口（/v1/chat/completions）');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw Exception('API Key 无效或无权限');
    }

    throw Exception('请求失败：HTTP ${response.statusCode}');
  }

  String? _extractChatCompletionText(dynamic decoded) {
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map) return null;

    final message = first['message'];
    if (message is Map) {
      final content = message['content'];
      final extracted = _extractContentText(content);
      final reasoning = _extractReasoningText(message);
      if (extracted != null && extracted.trim().isNotEmpty) {
        return extracted;
      }
      if (reasoning != null && reasoning.trim().isNotEmpty) {
        return reasoning;
      }
    }

    final text = first['text'];
    if (text is String) return text;

    final delta = first['delta'];
    if (delta is Map) {
      final content = delta['content'];
      final extracted = _extractContentText(content);
      if (extracted != null) return extracted;
    }

    return null;
  }

  String? _extractReasoningText(Map message) {
    final reasoning = message['reasoning_content'];
    if (reasoning is String) return reasoning;
    return null;
  }

  String? _extractContentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map) {
          final type = part['type'];
          if (type == null || type == 'text') {
            final text = part['text'];
            if (text is String) buffer.write(text);
          }
        }
      }
      final result = buffer.toString();
      return result.isEmpty ? null : result;
    }
    if (content is Map) {
      final text = content['text'];
      if (text is String) return text;
    }
    return null;
  }

  String _aiErrorText(Object? error) {
    if (error == null) return '未知错误';
    if (error is TimeoutException) {
      return '请求超时：请检查网络或 Base URL（建议先在设置页点“测试”）';
    }
    var raw = '$error';
    if (raw.startsWith('Exception: ')) {
      raw = raw.substring('Exception: '.length);
    }
    if (raw.contains('Base URL')) return raw;
    if (raw.contains('API Key')) return raw;
    if (raw.contains('HTTP')) return raw;
    return '请求失败：$raw';
  }

  Future<void> _showAiCaffeineAnalysisSheet() async {
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
        Future<String> future = _fetchAiCaffeineAnalysis();
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary =
            isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.only(
                  left: 22,
                  right: 22,
                  top: 6,
                  bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'AI 分析 · 咖啡因',
                            style:
                                textTheme.titleMedium?.copyWith(color: primary),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('关闭'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: min(
                        340.0,
                        MediaQuery.sizeOf(context).height * 0.42,
                      ),
                      child: Container(
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
                        child: FutureBuilder<String>(
                          future: future,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                          AppTheme.accentOf(context),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '分析中…',
                                      style: textTheme.bodyMedium
                                          ?.copyWith(color: secondary),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final text = snapshot.hasError
                                ? _aiErrorText(snapshot.error)
                                : (snapshot.data ?? '').trim();
                            final display = text.isEmpty ? '暂无结果' : text;
                            return Scrollbar(
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  display,
                                  style: TextStyle(
                                    fontSize: 13,
                                    height: 1.35,
                                    color:
                                        snapshot.hasError ? secondary : primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setModalState(() {
                                future = _fetchAiCaffeineAnalysis();
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.accentOf(context),
                              side: BorderSide(
                                color:
                                    AppTheme.accentOf(context).withAlpha(120),
                              ),
                            ),
                            child: const Text('重试'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              try {
                                final text = await future;
                                await Clipboard.setData(
                                  ClipboardData(text: text),
                                );
                                if (context.mounted) _showMessage('已复制分析结果');
                              } catch (_) {
                                if (context.mounted) _showMessage('暂无可复制内容');
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.accentOf(context),
                              side: BorderSide(
                                color:
                                    AppTheme.accentOf(context).withAlpha(120),
                              ),
                            ),
                            child: const Text('复制'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
                      ],
                    ),
                    const Spacer(),
                    Material(
                      color: cardColor,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _pickAnchorDate,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Center(
                            child: Icon(
                              Icons.calendar_today_outlined,
                              size: 18,
                              color: AppTheme.accentOf(context),
                            ),
                          ),
                        ),
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
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _showAiCaffeineAnalysisSheet,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentOf(context),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('AI 分析'),
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
                const SizedBox(height: 14),
                _StatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '类型分布',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      _TypeDistributionChart(typeCounts: _summary.typeCounts),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _StatCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _range == StatsRange.year
                            ? '咖啡因热力图（每月）'
                            : '咖啡因热力图（最近 28 天）',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      _CaffeineHeatmapChart(
                        range: _range,
                        anchorDate: _anchorDate,
                        values: _summary.caffeineSeries,
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
                        _range == StatsRange.year
                            ? '杯数 × 咖啡因（每月）'
                            : '杯数 × 咖啡因（每日）',
                        style: textTheme.bodyMedium?.copyWith(fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      _CupsCaffeineScatterChart(
                        cups: _summary.dailyCounts,
                        caffeineMg: _summary.caffeineSeries,
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
                      ? CoffeeDiaryPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : index == 3
                          ? OcrPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            )
                          : SettingsPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
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
    final start = _rangeStart(_anchorDate, _range);
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
  WeatherData? _weather;
  bool _weatherLoading = false;
  String? _weatherError;
  bool _weatherNeedsPermission = false;
  bool _weatherNeedsService = false;
  bool _weatherNeedsSettings = false;
  DateTime? _weatherFetchedAt;
  final GlobalKey _sharePosterKey = GlobalKey();
  static const MethodChannel _shareChannel =
      MethodChannel('coffee_person/share');
  final CameraService _cameraService = CameraService();

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

    final todayMonthStart = DateTime(_today.year, _today.month, 1);
    if (_isSameMonth(monthStart, todayMonthStart)) {
      var todayCaffeine = 0;
      var todayCups = 0;
      for (final r in records) {
        if (_isSameDay(r.createdAt, _today)) {
          todayCaffeine += r.caffeineMg;
          todayCups += 1;
        }
      }
      await CoffeeHomeWidget.updateToday(
        caffeineMg: todayCaffeine,
        cups: todayCups,
        date: _today,
      );
    }
  }

  Future<XFile?> _pickStickerImage(BuildContext context) async {
    if (_monthLoading) return null;
    return showModalBottomSheet<XFile?>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () async {
                    final file = await _cameraService.pickFromCamera();
                    if (!context.mounted) return;
                    Navigator.of(context).pop(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap: () async {
                    final file = await _cameraService.pickFromGallery();
                    if (!context.mounted) return;
                    Navigator.of(context).pop(file);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addStickerForDay(DateTime date) async {
    final picked = await _pickStickerImage(context);
    if (picked == null) return;
    final persisted = await persistPickedImage(picked);
    if (!mounted) return;
    await context.read<StickerStore>().addStickerFromImage(
          date: date,
          imagePath: persisted,
        );
  }

  Future<void> _showStickerActionsForDay(DateTime date) async {
    final dateKey = formatDateKey(date);
    final stickers =
        context.read<StickerStore>().stickersByDate[dateKey] ?? const [];
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.add_a_photo_outlined),
                  title: const Text('添加贴纸'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _addStickerForDay(date);
                  },
                ),
                if (stickers.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.collections_outlined),
                    title: const Text('查看贴纸'),
                    subtitle: Text('${stickers.length} 张'),
                    onTap: () {
                      Navigator.of(context).pop();
                      _openStickerList(date);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openStickerViewer(String path) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: StickerView(path: path, size: 320),
          ),
        );
      },
    );
  }

  void _openStickerList(DateTime date) {
    final dateKey = formatDateKey(date);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final store = context.watch<StickerStore>();
        final stickers = store.stickersByDate[dateKey] ?? const [];
        final primary = Theme.of(context).brightness == Brightness.dark
            ? AppTheme.textPrimaryDark
            : AppTheme.textPrimaryLight;
        final secondary = Theme.of(context).brightness == Brightness.dark
            ? AppTheme.textSecondaryDark
            : AppTheme.textSecondaryLight;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${date.month}月${date.day}日 贴纸',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                      ),
                      Text(
                        '${stickers.length} 张',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: stickers.isEmpty
                        ? Center(
                            child: Text(
                              '暂无贴纸',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: secondary,
                              ),
                            ),
                          )
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 1,
                            ),
                            itemCount: stickers.length,
                            itemBuilder: (context, index) {
                              final sticker = stickers[index];
                              return GestureDetector(
                                onTap: () => _openStickerViewer(sticker.path),
                                onLongPress: () async {
                                  await context
                                      .read<StickerStore>()
                                      .removeSticker(
                                        dateKey: dateKey,
                                        stickerId: sticker.id,
                                      );
                                },
                                child: StickerView(
                                  path: sticker.path,
                                  size: 110,
                                ),
                              );
                            },
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

      final prefs = await SharedPreferences.getInstance();
      final service = WeatherService(prefs);
      final weather = await service.fetchWeather(
        latitude: position.latitude,
        longitude: position.longitude,
        force: force,
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

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _shareSelectedDay() async {
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
        final day = _selectedDate;
        final records = _recordsForDay(day);
        final cups = records.length;
        final caffeine = _caffeineForDay(day);
        final showWeather = _isSameDay(day, _today) && _weather != null;
        final weather = showWeather ? _weather : null;

        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              6,
              22,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '喝咖日常晒圈',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontSize: 18),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('关闭'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: RepaintBoundary(
                      key: _sharePosterKey,
                      child: _CoffeeSharePoster(
                        dateLabel: _dateLabel(day),
                        cups: cups,
                        caffeineMg: caffeine,
                        accent: AppTheme.accentOf(context),
                        weatherLine: weather == null
                            ? null
                            : '${weather.locationName ?? '所在地'} · ${_weatherDescription(weather.weatherCode)} · ${weather.temperatureC.round()}° · 风 ${weather.windSpeedKmh.round()} km/h',
                        coffeeTitles: records
                            .take(4)
                            .map((r) => r.type.trim())
                            .where((s) => s.isNotEmpty)
                            .toList(growable: false),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await WidgetsBinding.instance.endOfFrame;
                      final renderObject =
                          _sharePosterKey.currentContext?.findRenderObject();
                      if (renderObject is! RenderRepaintBoundary) {
                        _showMessage('生成分享图失败');
                        return;
                      }
                      final boundary = renderObject;
                      dynamic image;
                      try {
                        image = await boundary.toImage(pixelRatio: 3);
                      } catch (_) {
                        _showMessage('生成分享图失败');
                        return;
                      }
                      final data = await image.toByteData(
                        format: ImageByteFormat.png,
                      );
                      if (data == null) {
                        _showMessage('生成分享图失败');
                        return;
                      }
                      final pngBytes = data.buffer.asUint8List();
                      final shareText =
                          '咖记 · ${_dateLabel(day)}：$cups 杯 · ${caffeine}mg';
                      try {
                        await _shareChannel.invokeMethod<void>(
                          'shareImage',
                          <String, Object?>{
                            'bytes': pngBytes,
                            'text': shareText,
                          },
                        );
                      } catch (_) {
                        _showMessage('当前平台暂不支持分享');
                      }
                    },
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('分享图片'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final stickersByDate = context.watch<StickerStore>().stickersByDate;

    final month = DateTime(_selectedDate.year, _selectedDate.month, 1);

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
                  Row(
                    children: [
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            final nextMonthStart =
                                DateTime(_today.year, _today.month, 1);
                            setState(() {
                              _selectedDate = _today;
                              _monthStart = nextMonthStart;
                            });
                            _loadMonth(nextMonthStart);
                            _loadWeather(requestPermission: false, force: true);
                          },
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(context)
                                  .scaffoldBackgroundColor
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
                      ),
                      const SizedBox(width: 10),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _shareSelectedDay,
                          borderRadius: BorderRadius.circular(18),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentOf(context).withAlpha(16),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color:
                                    AppTheme.accentOf(context).withAlpha(110),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.ios_share_outlined,
                                  size: 16,
                                  color: AppTheme.accentOf(context),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '晒圈',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accentOf(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
                padding: const EdgeInsets.fromLTRB(10, 18, 10, 18),
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
                    const SizedBox(height: 12),
                    Stack(
                      children: [
                        CalendarWithStickers(
                          focusedDay: _selectedDate,
                          selectedDay: _selectedDate,
                          onDaySelected: (day) {
                            final isSame = _isSameDay(day, _selectedDate);
                            final nextMonthStart =
                                DateTime(day.year, day.month, 1);
                            setState(() {
                              _selectedDate = day;
                            });
                            if (!_isSameMonth(nextMonthStart, _monthStart)) {
                              _monthStart = nextMonthStart;
                              _loadMonth(_monthStart);
                            }
                            if (isSame) {
                              _showStickerActionsForDay(day);
                            }
                          },
                          onStickerTap: (sticker) =>
                              _openStickerViewer(sticker.path),
                          onStickerLongPress: (sticker) =>
                              context.read<StickerStore>().removeSticker(
                                    dateKey: sticker.dateKey,
                                    stickerId: sticker.id,
                                  ),
                          onPageChanged: (focused) {
                            final nextMonthStart =
                                DateTime(focused.year, focused.month, 1);
                            if (_isSameMonth(nextMonthStart, _monthStart)) {
                              return;
                            }
                            setState(() {
                              _selectedDate = nextMonthStart;
                              _monthStart = nextMonthStart;
                            });
                            _loadMonth(nextMonthStart);
                          },
                          stickersByDate: stickersByDate,
                          primary: primary,
                          secondary: secondary,
                          accent: AppTheme.accentOf(context),
                          tileColor: tileColor,
                        ),
                      ],
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
                      ? CoffeeDiaryPage(
                          repository: widget.repository,
                          themeMode: widget.themeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: widget.accentPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : index == 3
                          ? OcrPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            )
                          : SettingsPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
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

class _CoffeeSharePoster extends StatelessWidget {
  const _CoffeeSharePoster({
    required this.dateLabel,
    required this.cups,
    required this.caffeineMg,
    required this.accent,
    required this.coffeeTitles,
    this.weatherLine,
  });

  final String dateLabel;
  final int cups;
  final int caffeineMg;
  final Color accent;
  final String? weatherLine;
  final List<String> coffeeTitles;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final bg = isDark ? const Color(0xFF171311) : const Color(0xFFF6EFE7);
    final bg2 = isDark ? const Color(0xFF241B16) : const Color(0xFFFFFFFF);

    final coffeeLine = coffeeTitles.isEmpty ? '暂无记录' : coffeeTitles.join(' · ');

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bg, bg2],
          ),
          border: Border.all(
            color: accent.withAlpha(isDark ? 60 : 45),
            width: 1,
          ),
        ),
        child: AspectRatio(
          aspectRatio: 4 / 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withAlpha(isDark ? 32 : 22),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '喝咖日常',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '咖记',
                    style: TextStyle(
                      color: primary.withAlpha(isDark ? 215 : 190),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                dateLabel,
                style: TextStyle(
                  color: secondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    cups.toString(),
                    style: TextStyle(
                      color: primary,
                      fontSize: 54,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '杯',
                      style: TextStyle(
                        color: secondary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black)
                          .withAlpha(isDark ? 14 : 10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '$caffeineMg mg',
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '今日喝了：$coffeeLine',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primary.withAlpha(isDark ? 220 : 200),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (weatherLine != null && weatherLine!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(isDark ? 22 : 16),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accent.withAlpha(isDark ? 55 : 40),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    weatherLine!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons.local_cafe_outlined,
                    size: 16,
                    color: accent.withAlpha(isDark ? 220 : 200),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '打卡分享 · 喝咖日常晒圈',
                    style: TextStyle(
                      color: secondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
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
  static const String _openAiApiKeyKey = 'openai_api_key';
  static const String _openAiBaseUrlKey = 'openai_base_url';
  static const String _openAiModelKey = 'openai_model';
  static const String _useMlKitDetectionKey = 'use_mlkit_detection';
  static const String _githubRepoUrl =
      'https://github.com/huangming774/coffee-notes';

  late AppAccentPalette _selectedPalette;
  late ThemeMode _selectedThemeMode;
  bool _aiTesting = false;
  bool _useMlKitDetection = false;
  final TextEditingController _openAiApiKeyController = TextEditingController();
  final TextEditingController _openAiBaseUrlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final TextEditingController _openAiModelController = TextEditingController();

  WeatherSource _selectedWeatherSource = WeatherSource.openMeteo;
  final TextEditingController _owmApiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedPalette = widget.accentPalette;
    _selectedThemeMode = widget.themeMode;
    _loadCaffeineLimit();
    _loadDetectionEngine();
    _loadAiConfig();
    _loadWeatherConfig();
  }

  @override
  void dispose() {
    _openAiApiKeyController.dispose();
    _openAiBaseUrlController.dispose();
    _openAiModelController.dispose();
    _owmApiKeyController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accentPalette != widget.accentPalette) {
      _selectedPalette = widget.accentPalette;
    }
    if (oldWidget.themeMode != widget.themeMode) {
      _selectedThemeMode = widget.themeMode;
    }
  }

  void _setThemeMode(ThemeMode mode) {
    if (_selectedThemeMode == mode) return;
    setState(() {
      _selectedThemeMode = mode;
    });
    widget.onThemeModeChange(mode);
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

  Future<void> _openGithubRepo() async {
    final uri = Uri.parse(_githubRepoUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      await Clipboard.setData(const ClipboardData(text: _githubRepoUrl));
      _showMessage('已复制 GitHub 地址');
    }
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
                  GestureDetector(
                    onTap: _openGithubRepo,
                    behavior: HitTestBehavior.translucent,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            color: AppTheme.accentOf(context),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GitHub 项目地址',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _githubRepoUrl,
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
                            Icons.open_in_new,
                            color: secondary,
                            size: 18,
                          ),
                        ],
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

  Future<void> _showWeatherConfigSheet() async {
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
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;

        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                              '天气配置',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await _clearWeatherConfig();
                              if (context.mounted) Navigator.of(context).pop();
                            },
                            child: const Text('清空并关闭'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '配置天气数据来源及相关 API Key。',
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '天气源',
                        style: textTheme.bodySmall?.copyWith(
                          color: secondary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                        child: Column(
                          children: [
                            RadioListTile<WeatherSource>(
                              title: const Text('Open-Meteo'),
                              subtitle: const Text('免费，无需 API Key'),
                              value: WeatherSource.openMeteo,
                              groupValue: _selectedWeatherSource,
                              activeColor: AppTheme.accentOf(context),
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() {
                                    _selectedWeatherSource = val;
                                  });
                                  setState(() {
                                    _selectedWeatherSource = val;
                                  });
                                }
                              },
                            ),
                            Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withAlpha(10),
                            ),
                            RadioListTile<WeatherSource>(
                              title: const Text('OpenWeatherMap'),
                              subtitle: const Text('需配置 API Key'),
                              value: WeatherSource.openWeatherMap,
                              groupValue: _selectedWeatherSource,
                              activeColor: AppTheme.accentOf(context),
                              onChanged: (val) {
                                if (val != null) {
                                  setSheetState(() {
                                    _selectedWeatherSource = val;
                                  });
                                  setState(() {
                                    _selectedWeatherSource = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      if (_selectedWeatherSource ==
                          WeatherSource.openWeatherMap) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _owmApiKeyController,
                          autocorrect: false,
                          enableSuggestions: false,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'OpenWeatherMap API Key',
                            hintText: '输入你的 API Key',
                            filled: true,
                            fillColor: cardColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withAlpha(10),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                              borderSide: BorderSide(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withAlpha(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: () async {
                            await _saveWeatherConfig();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accentOf(context),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            '保存配置',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
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
      '• photo_manager',
      '• motion_photos',
      '• video_player',
      '• url_launcher',
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
                  GestureDetector(
                    onTap: _openGithubRepo,
                    behavior: HitTestBehavior.translucent,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.link,
                            color: AppTheme.accentOf(context),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'GitHub 项目地址',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontSize: 15,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _githubRepoUrl,
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
                            Icons.open_in_new,
                            color: secondary,
                            size: 18,
                          ),
                        ],
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

  Future<void> _loadDetectionEngine() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_useMlKitDetectionKey) ?? false;
    if (!mounted) return;
    setState(() {
      _useMlKitDetection = saved;
    });
  }

  Future<void> _saveDetectionEngine(bool useMlKit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useMlKitDetectionKey, useMlKit);
  }

  Future<void> _loadAiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString(_openAiApiKeyKey) ?? '';
    final baseUrl =
        prefs.getString(_openAiBaseUrlKey) ?? 'https://api.openai.com/v1';
    final model = prefs.getString(_openAiModelKey) ?? '';
    if (!mounted) return;
    _openAiApiKeyController.text = apiKey;
    _openAiBaseUrlController.text = baseUrl;
    _openAiModelController.text = model;
  }

  Future<bool> _saveAiConfig() async {
    final apiKey = _openAiApiKeyController.text.trim();
    final baseUrl = _openAiBaseUrlController.text.trim();
    final model = _openAiModelController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      _showMessage('请填写 Base URL 与 API Key');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_openAiApiKeyKey, apiKey);
    await prefs.setString(_openAiBaseUrlKey, baseUrl);
    await prefs.setString(_openAiModelKey, model);
    _showMessage('AI 配置已保存');
    return true;
  }

  Future<void> _clearAiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_openAiApiKeyKey);
    await prefs.remove(_openAiBaseUrlKey);
    await prefs.remove(_openAiModelKey);
    if (!mounted) return;
    _openAiApiKeyController.clear();
    _openAiBaseUrlController.text = 'https://api.openai.com/v1';
    _openAiModelController.clear();
    _showMessage('AI 配置已清空');
  }

  Future<void> _loadWeatherConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final service = WeatherService(prefs);
    if (!mounted) return;
    setState(() {
      _selectedWeatherSource = service.source;
      _owmApiKeyController.text = service.owmApiKey;
    });
  }

  Future<void> _saveWeatherConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final service = WeatherService(prefs);
    await service.setSource(_selectedWeatherSource);
    await service.setOwmApiKey(_owmApiKeyController.text.trim());
    _showMessage('天气配置已保存');
  }

  Future<void> _clearWeatherConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('weather_source');
    await prefs.remove('owm_api_key');
    await prefs.remove('weather_cache');
    if (!mounted) return;
    setState(() {
      _selectedWeatherSource = WeatherSource.openMeteo;
      _owmApiKeyController.clear();
    });
    _showMessage('天气配置已清空');
  }

  Uri? _normalizeBaseUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) return null;
    if (!(parsed.scheme == 'http' || parsed.scheme == 'https')) return null;
    if (parsed.host.isEmpty) return null;
    return parsed;
  }

  Uri _appendPath(Uri base, String segment) {
    final segments = <String>[...base.pathSegments];
    if (segments.isNotEmpty && segments.last.isEmpty) {
      segments.removeLast();
    }
    segments.add(segment);
    return base.replace(pathSegments: segments);
  }

  Future<void> _testAiConfig() async {
    if (_aiTesting) return;
    final apiKey = _openAiApiKeyController.text.trim();
    final baseUrl = _openAiBaseUrlController.text.trim();
    final model = _openAiModelController.text.trim();
    if (apiKey.isEmpty || baseUrl.isEmpty) {
      _showMessage('请先填写 Base URL 与 API Key');
      return;
    }

    final baseUri = _normalizeBaseUrl(baseUrl);
    if (baseUri == null) {
      _showMessage('Base URL 格式不正确');
      return;
    }

    setState(() {
      _aiTesting = true;
    });

    try {
      final modelsUri = _appendPath(baseUri, 'models');
      final response = await http.get(
        modelsUri,
        headers: <String, String>{
          'Authorization': 'Bearer $apiKey',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        if (model.isEmpty) {
          _showMessage('测试成功：连接正常');
          return;
        }
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          final data = decoded is Map<String, dynamic> ? decoded['data'] : null;
          if (data is List) {
            final ids = data
                .whereType<Map>()
                .map((e) => e['id'])
                .whereType<String>()
                .toSet();
            if (ids.contains(model)) {
              _showMessage('测试成功：模型可用');
            } else {
              _showMessage('连接成功，但未找到该模型');
            }
          } else {
            _showMessage('测试成功：连接正常');
          }
        } catch (_) {
          _showMessage('测试成功：连接正常');
        }
        return;
      }

      if (response.statusCode == 401 || response.statusCode == 403) {
        _showMessage('测试失败：API Key 无效或无权限');
        return;
      }

      _showMessage('测试失败：HTTP ${response.statusCode}');
    } on TimeoutException {
      _showMessage('测试超时：请检查网络或 Base URL');
    } catch (_) {
      _showMessage('测试失败：无法连接到服务器');
    } finally {
      if (mounted) {
        setState(() {
          _aiTesting = false;
        });
      }
    }
  }

  Future<void> _showAiConfigSheet() async {
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
        final cardColor = isDark ? AppTheme.darkCard : Colors.white;
        final secondary =
            isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
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
                          'AI 配置（OpenAI）',
                          style: textTheme.titleMedium?.copyWith(fontSize: 18),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _clearAiConfig();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: const Text('清空并关闭'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '信息仅保存在本机，用于后续 AI 功能调用。',
                    style: textTheme.bodyMedium?.copyWith(color: secondary),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _openAiBaseUrlController,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Base URL',
                      hintText: 'https://api.openai.com/v1',
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _openAiApiKeyController,
                    autocorrect: false,
                    enableSuggestions: false,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _openAiModelController,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Model（可选）',
                      hintText: 'gpt-4o-mini',
                      filled: true,
                      fillColor: cardColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlpha(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _aiTesting ? null : _testAiConfig,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accentOf(context),
                            side: BorderSide(
                              color: AppTheme.accentOf(context).withAlpha(120),
                            ),
                          ),
                          child: Text(_aiTesting ? '测试中' : '测试'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _aiTesting
                              ? null
                              : () async {
                                  final ok = await _saveAiConfig();
                                  if (ok && context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.accentOf(context),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('保存'),
                        ),
                      ),
                    ],
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
                              selected: _selectedThemeMode == ThemeMode.light,
                              onTap: () => _setThemeMode(ThemeMode.light),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _themeSegmentSpacing),
                            _SegmentButton(
                              text: '跟随',
                              selected: _selectedThemeMode == ThemeMode.system,
                              onTap: () => _setThemeMode(ThemeMode.system),
                              width: _segmentButtonWidth,
                            ),
                            const SizedBox(width: _themeSegmentSpacing),
                            _SegmentButton(
                              text: '深色',
                              selected: _selectedThemeMode == ThemeMode.dark,
                              onTap: () => _setThemeMode(ThemeMode.dark),
                              width: _segmentButtonWidth,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _StatCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '贴纸识别引擎',
                      style: textTheme.titleMedium?.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _useMlKitDetection ? '当前：ML Kit' : '当前：YOLOv8 本地模型',
                      style: textTheme.bodyMedium?.copyWith(color: secondary),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: () {
                          final next = !_useMlKitDetection;
                          setState(() {
                            _useMlKitDetection = next;
                          });
                          _saveDetectionEngine(next);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentOf(context),
                          side: BorderSide(
                            color: AppTheme.accentOf(context).withAlpha(120),
                          ),
                        ),
                        child: Text(
                          _useMlKitDetection ? '切换到 YOLOv8' : '切换到 ML Kit',
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
                  onTap: _showAiConfigSheet,
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
                          Icons.smart_toy_outlined,
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
                              'AI 配置（OpenAI）',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击配置 Base URL / API Key 等',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: secondary),
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
                  onTap: _showWeatherConfigSheet,
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
                          Icons.cloud_outlined,
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
                              '天气配置',
                              style:
                                  textTheme.titleMedium?.copyWith(fontSize: 18),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '配置天气源与 API Key',
                              style: textTheme.bodyMedium
                                  ?.copyWith(color: secondary),
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
            selectedIndex: 4,
            onSelect: (index) {
              if (index == 4) return;
              final target = index == 0
                  ? CoffeePage(
                      repository: widget.repository,
                      themeMode: _selectedThemeMode,
                      onThemeModeChange: widget.onThemeModeChange,
                      accentPalette: _selectedPalette,
                      onAccentPaletteChange: widget.onAccentPaletteChange,
                    )
                  : index == 1
                      ? StatsPage(
                          repository: widget.repository,
                          themeMode: _selectedThemeMode,
                          onThemeModeChange: widget.onThemeModeChange,
                          accentPalette: _selectedPalette,
                          onAccentPaletteChange: widget.onAccentPaletteChange,
                        )
                      : index == 2
                          ? CoffeeDiaryPage(
                              repository: widget.repository,
                              themeMode: _selectedThemeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: _selectedPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            )
                          : OcrPage(
                              repository: widget.repository,
                              themeMode: _selectedThemeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: _selectedPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            );
              Navigator.of(context)
                  .pushReplacement(_transitionRoute(target, 4, index));
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

class CoffeeDiaryPage extends StatefulWidget {
  const CoffeeDiaryPage({
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
  State<CoffeeDiaryPage> createState() => _CoffeeDiaryPageState();
}

class _CoffeeDiaryPageState extends State<CoffeeDiaryPage> {
  String _dateLabel(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _openEditor({CoffeeDiaryEntry? initial}) async {
    final changed = await Navigator.of(context).push<bool>(
      _bottomUpRoute<bool>(
        AddDiaryEntryPage(initialEntry: initial),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      setState(() {});
    }
  }

  Future<void> _openDetail(Id entryId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiaryEntryDetailPage(entryId: entryId),
      ),
    );
    if (!mounted) return;
    if (changed == true) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final diaryRepository = context.read<CoffeeDiaryRepository>();
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
                  const SizedBox(width: 70),
                  Text(
                    '日记',
                    style: textTheme.titleMedium
                        ?.copyWith(fontSize: 18, color: primary),
                  ),
                  GestureDetector(
                    onTap: () => _openEditor(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 90 : 18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Text(
                        '写日记',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<CoffeeDiaryEntry>>(
                stream: diaryRepository.watchAll(),
                builder: (context, snapshot) {
                  final entries = snapshot.data ?? const [];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        '还没有日记',
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: EdgeInsets.fromLTRB(
                      18,
                      12,
                      18,
                      _bottomNavReservedSpace(context) + 12,
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final images = entry.imagePaths;
                      final preview = images.take(3).toList(growable: false);
                      return GestureDetector(
                        onTap: () => _openDetail(entry.id),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 55 : 10),
                                blurRadius: 18,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _dateLabel(entry.date),
                                style: textTheme.titleMedium?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: primary,
                                ),
                              ),
                              if ((entry.text ?? '').trim().isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  entry.text!.trim(),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: secondary,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                              if (preview.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 76,
                                  child: ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemBuilder: (context, i) {
                                      final path = preview[i];
                                      final videoPath =
                                          i < entry.motionVideoPaths.length
                                              ? entry.motionVideoPaths[i]
                                              : '';
                                      return Stack(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(18),
                                            child: SizedBox(
                                              width: 76,
                                              height: 76,
                                              child: storedImage(
                                                path,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          if (videoPath.trim().isNotEmpty)
                                            Positioned(
                                              left: 6,
                                              top: 6,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 3,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.black
                                                      .withAlpha(110),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: const Text(
                                                  'LIVE',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(width: 10),
                                    itemCount: preview.length,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: entries.length,
                  );
                },
              ),
            ),
          ],
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
                      : index == 3
                          ? OcrPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            )
                          : SettingsPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
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

class DiaryEntryDetailPage extends StatefulWidget {
  const DiaryEntryDetailPage({super.key, required this.entryId});

  final Id entryId;

  @override
  State<DiaryEntryDetailPage> createState() => _DiaryEntryDetailPageState();
}

class _DiaryEntryDetailPageState extends State<DiaryEntryDetailPage> {
  String _dateLabel(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _openImage(String imagePath) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1,
              child: storedImage(imagePath, fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMedia({
    required String imagePath,
    required String videoPath,
    required bool preferMotion,
  }) async {
    if (preferMotion && videoPath.trim().isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (_) => _MotionPreviewDialog(videoPath: videoPath),
      );
      return;
    }
    await _openImage(imagePath);
  }

  Future<void> _edit(CoffeeDiaryEntry entry) async {
    final changed = await Navigator.of(context).push<bool>(
      _bottomUpRoute<bool>(AddDiaryEntryPage(initialEntry: entry)),
    );
    if (!mounted) return;
    if (changed == true) {
      setState(() {});
    }
  }

  Future<void> _delete(CoffeeDiaryEntry entry) async {
    final repo = context.read<CoffeeDiaryRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final errorColor = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: const Text('删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await repo.deleteEntry(entry.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<CoffeeDiaryRepository>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textTheme = Theme.of(context).textTheme;
    final cardColor = isDark ? AppTheme.darkCard : AppTheme.lightCard;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<CoffeeDiaryEntry>>(
          stream: repo.watchAll(),
          builder: (context, snapshot) {
            final entry = (snapshot.data ?? const [])
                .where((e) => e.id == widget.entryId)
                .cast<CoffeeDiaryEntry?>()
                .firstWhere((e) => e != null, orElse: () => null);
            if (entry == null) {
              return Center(
                child: Text(
                  '日记不存在或已删除',
                  style: textTheme.bodyMedium?.copyWith(color: secondary),
                ),
              );
            }
            final images = entry.imagePaths;
            final videos = entry.motionVideoPaths;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? AppTheme.darkCard : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(isDark ? 90 : 18),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Text(
                            '返回',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: primary,
                            ),
                          ),
                        ),
                      ),
                      Text(
                        _dateLabel(entry.date),
                        style: textTheme.titleMedium
                            ?.copyWith(fontSize: 18, color: primary),
                      ),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _edit(entry),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    isDark ? AppTheme.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha(isDark ? 90 : 18),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.edit_outlined,
                                color: primary,
                                size: 18,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: () => _delete(entry),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color:
                                    isDark ? AppTheme.darkCard : Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withAlpha(isDark ? 90 : 18),
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (images.isNotEmpty) ...[
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (final e in images.asMap().entries)
                                Stack(
                                  children: [
                                    GestureDetector(
                                      onTap: () => _openMedia(
                                        imagePath: e.value,
                                        videoPath: e.key < videos.length
                                            ? videos[e.key]
                                            : '',
                                        preferMotion: false,
                                      ),
                                      onLongPress: () => _openMedia(
                                        imagePath: e.value,
                                        videoPath: e.key < videos.length
                                            ? videos[e.key]
                                            : '',
                                        preferMotion: true,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(18),
                                        child: SizedBox(
                                          width: 110,
                                          height: 110,
                                          child: storedImage(
                                            e.value,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (e.key < videos.length &&
                                        videos[e.key].trim().isNotEmpty)
                                      Positioned(
                                        left: 8,
                                        top: 8,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(110),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'LIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                        ],
                        if ((entry.text ?? '').trim().isNotEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withAlpha(10),
                              ),
                            ),
                            child: Text(
                              entry.text!.trim(),
                              style: textTheme.bodyMedium?.copyWith(
                                color: secondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class AddDiaryEntryPage extends StatefulWidget {
  const AddDiaryEntryPage({super.key, this.initialEntry});

  final CoffeeDiaryEntry? initialEntry;

  @override
  State<AddDiaryEntryPage> createState() => _AddDiaryEntryPageState();
}

class _AddDiaryEntryPageState extends State<AddDiaryEntryPage> {
  final TextEditingController _textController = TextEditingController();
  final CameraService _cameraService = CameraService();
  DateTime _date = DateTime.now();
  List<String> _imagePaths = [];
  List<String> _motionVideoPaths = [];
  bool _saving = false;

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialEntry;
    if (initial != null) {
      _date = initial.date;
      _textController.text = (initial.text ?? '').trim();
      _imagePaths = List<String>.from(initial.imagePaths);
      final rawVideos = initial.motionVideoPaths;
      if (rawVideos.length == _imagePaths.length) {
        _motionVideoPaths = List<String>.from(rawVideos);
      } else {
        _motionVideoPaths = List<String>.filled(_imagePaths.length, '');
      }
    } else {
      _motionVideoPaths = [];
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String _dateLabel(DateTime date) {
    final y = date.year.toString();
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

  Future<void> _pickDate() async {
    if (_saving) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
    });
  }

  Future<void> _pickImage() async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () async {
                    final file = await _cameraService.pickFromCamera();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    if (file == null) return;
                    await _addPickedXFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap: () async {
                    final file = await _cameraService.pickFromGallery();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    if (file == null) return;
                    await _addPickedXFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.motion_photos_on_outlined),
                  title: const Text('从相册选择（支持实况）'),
                  onTap: () async {
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    await _pickFromSystemGallery();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _persistDiaryFile(File file) async {
    final dir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${dir.path}/diary_media');
    if (!targetDir.existsSync()) {
      targetDir.createSync(recursive: true);
    }
    final path = file.path;
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 ? path.substring(dot) : '.jpg';
    final filename = 'diary_${DateTime.now().millisecondsSinceEpoch}$ext';
    final targetPath = '${targetDir.path}/$filename';
    await file.copy(targetPath);
    return targetPath;
  }

  Future<void> _addPickedXFile(XFile file) async {
    final persisted = await persistPickedImage(file);
    if (!mounted) return;
    setState(() {
      _imagePaths = [..._imagePaths, persisted];
      _motionVideoPaths = [..._motionVideoPaths, ''];
    });
  }

  Future<void> _pickFromSystemGallery() async {
    if (kIsWeb) return;
    final asset = await Navigator.of(context).push<AssetEntity?>(
      MaterialPageRoute(builder: (_) => const DiaryAssetPickerPage()),
    );
    if (!mounted) return;
    if (asset == null) return;
    final origin = await asset.originFile;
    if (!mounted) return;
    if (origin == null) return;
    final persistedImage = await _persistDiaryFile(origin);
    var persistedVideo = '';
    var isMotion = false;
    var usedPairedVideo = false;
    try {
      final motionPhotos = MotionPhotos(origin.path);
      isMotion = await motionPhotos.isMotionPhoto();
      if (isMotion) {
        final dir = await getApplicationDocumentsDirectory();
        final targetDir = Directory('${dir.path}/diary_media');
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }
        final file = await motionPhotos.getMotionVideoFile(
          targetDir,
          fileName: 'motion_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        persistedVideo = file.path;
      }
    } catch (_) {}
    if (persistedVideo.trim().isEmpty) {
      final paired = await _tryFindPairedMotionVideo(asset);
      if (!mounted) return;
      if (paired.trim().isNotEmpty) {
        persistedVideo = paired;
        usedPairedVideo = true;
      }
    }
    if (persistedVideo.trim().isEmpty) {
      final manual = await _pickPairedVideo();
      if (!mounted) return;
      if (manual.trim().isNotEmpty) {
        persistedVideo = manual;
        usedPairedVideo = true;
      }
    }
    if (!mounted) return;
    setState(() {
      _imagePaths = [..._imagePaths, persistedImage];
      _motionVideoPaths = [..._motionVideoPaths, persistedVideo];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          persistedVideo.trim().isNotEmpty
              ? (usedPairedVideo ? '已识别实况照片（配对视频）' : '已识别实况照片')
              : (isMotion ? '实况检测成功但提取失败（将按普通照片保存）' : '未识别到实况视频（将按普通照片保存）'),
        ),
      ),
    );
  }

  Future<String> _pickPairedVideo() async {
    if (!mounted) return '';
    final navigator = Navigator.of(context);
    final shouldPick = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('未识别到实况视频'),
          content: const Text('是否手动选择配对视频？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('跳过'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('选择'),
            ),
          ],
        );
      },
    );
    if (!mounted) return '';
    if (shouldPick != true) return '';
    final picked = await navigator.push<AssetEntity?>(
      MaterialPageRoute(
        builder: (_) => const DiaryAssetPickerPage(
          requestType: RequestType.video,
          title: '选择配对视频',
        ),
      ),
    );
    if (!mounted) return '';
    if (picked == null) return '';
    final origin = await picked.originFile;
    if (!mounted) return '';
    if (origin == null) return '';
    final persisted = await _persistDiaryFile(origin);
    if (!mounted) return '';
    return persisted;
  }

  String _stripExt(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _extractTimeToken(String text) {
    final normalized = text.replaceAll('-', '_');
    final m1 = RegExp(r'\d{8}_\d{6}').firstMatch(normalized);
    if (m1 != null) {
      return m1.group(0)!.replaceAll('_', '');
    }
    final m2 = RegExp(r'\d{12,14}').firstMatch(text);
    if (m2 != null) return m2.group(0)!;
    final m3 = RegExp(r'\d{10,}').firstMatch(text);
    if (m3 != null) return m3.group(0)!;
    return '';
  }

  int _absInt(int v) => v < 0 ? -v : v;

  Future<String> _tryFindPairedMotionVideo(AssetEntity imageAsset) async {
    if (kIsWeb) return '';
    if (defaultTargetPlatform != TargetPlatform.android) return '';
    final imageTime = imageAsset.createDateTime;
    final imageTitle = imageAsset.title ?? '';
    final imageBase = _stripExt(imageTitle);
    final imageToken = _extractTimeToken(imageBase);
    final imageFolder = imageAsset.relativePath ?? '';
    final optionGroup = FilterOptionGroup(
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
    final videoPaths = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      filterOption: optionGroup,
      onlyAll: true,
    );
    if (!mounted) return '';
    if (videoPaths.isEmpty) return '';
    final allVideos = videoPaths.first;

    const windowSeconds = 20;
    const maxPages = 12;
    const size = 200;
    var bestScore = -1;
    AssetEntity? best;

    for (var page = 0; page < maxPages; page++) {
      final list = await allVideos.getAssetListPaged(page: page, size: size);
      if (!mounted) return '';
      if (list.isEmpty) break;
      for (final v in list) {
        if (v.type != AssetType.video) continue;
        final dt = _absInt(v.createDateTime.difference(imageTime).inSeconds);
        if (dt > windowSeconds) continue;
        var score = 0;
        if (dt <= 1) score += 8;
        if (dt <= 3) score += 6;
        if (dt <= 8) score += 4;
        if (dt <= 20) score += 2;
        final vFolder = v.relativePath ?? '';
        if (imageFolder.isNotEmpty && vFolder == imageFolder) score += 8;
        final vTitle = v.title ?? '';
        final vBase = _stripExt(vTitle);
        final vToken = _extractTimeToken(vBase);
        if (imageToken.isNotEmpty &&
            vToken.isNotEmpty &&
            (vToken.contains(imageToken) || imageToken.contains(vToken))) {
          score += 14;
          if (imageBase.startsWith('IMG') && vBase.startsWith('VID')) {
            score += 4;
          }
        }
        if (imageBase.isNotEmpty && vBase == imageBase) score += 10;
        if (imageBase.isNotEmpty &&
            (vBase.contains(imageBase) || imageBase.contains(vBase))) {
          score += 4;
        }
        final duration = v.duration;
        if (duration > 0 && duration <= 6) score += 4;
        if (duration > 6 && duration <= 10) score += 2;
        if (score > bestScore) {
          bestScore = score;
          best = v;
        }
      }
      final oldest = list.last.createDateTime;
      final tooOld =
          oldest.isBefore(imageTime.subtract(const Duration(minutes: 10)));
      if (tooOld) break;
    }

    if (best == null) return '';
    if (bestScore < 12) return '';
    final file = await best.originFile;
    if (!mounted) return '';
    if (file == null) return '';
    final persisted = await _persistDiaryFile(file);
    if (!mounted) return '';
    return persisted;
  }

  Future<void> _removeMediaAt(int index) async {
    if (_saving) return;
    final imagePath =
        index >= 0 && index < _imagePaths.length ? _imagePaths[index] : '';
    final videoPath = index >= 0 && index < _motionVideoPaths.length
        ? _motionVideoPaths[index]
        : '';
    setState(() {
      final nextImages = List<String>.from(_imagePaths)..removeAt(index);
      final nextVideos = List<String>.from(_motionVideoPaths)..removeAt(index);
      _imagePaths = nextImages;
      _motionVideoPaths = nextVideos;
    });
    for (final p in [imagePath, videoPath]) {
      if (p.trim().isEmpty) continue;
      try {
        final file = File(p);
        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _openMediaPreview(int index,
      {required bool preferMotion}) async {
    if (index < 0 || index >= _imagePaths.length) return;
    final imagePath = _imagePaths[index];
    final videoPath =
        index < _motionVideoPaths.length ? _motionVideoPaths[index] : '';
    if (preferMotion && videoPath.trim().isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => _MotionPreviewDialog(videoPath: videoPath),
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: AspectRatio(
              aspectRatio: 1,
              child: storedImage(imagePath, fit: BoxFit.cover),
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    final repo = context.read<CoffeeDiaryRepository>();
    final existing = widget.initialEntry;
    final entry = CoffeeDiaryEntry();
    if (existing != null) {
      entry.id = existing.id;
      entry.createdAt = existing.createdAt;
    } else {
      entry.createdAt = DateTime.now();
    }
    entry.date = DateTime(_date.year, _date.month, _date.day);
    final text = _textController.text.trim();
    entry.text = text.isEmpty ? null : text;
    entry.imagePaths = List<String>.from(_imagePaths);
    entry.motionVideoPaths = List<String>.from(_motionVideoPaths);
    await repo.upsertEntry(entry);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    if (_saving) return;
    final existing = widget.initialEntry;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final errorColor = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: const Text('删除这篇日记？'),
          content: const Text('删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
    });
    final repo = context.read<CoffeeDiaryRepository>();
    await repo.deleteEntry(existing.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
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
                  GestureDetector(
                    onTap:
                        _saving ? null : () => Navigator.of(context).pop(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 90 : 18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _isEditing ? '编辑日记' : '添加日记',
                    style: textTheme.titleMedium
                        ?.copyWith(fontSize: 18, color: primary),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: isDark ? AppTheme.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(isDark ? 90 : 18),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Text(
                        _saving ? '保存中' : '保存',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('日期'),
                    GestureDetector(
                      onTap: _pickDate,
                      child: Container(
                        height: 56,
                        width: double.infinity,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withAlpha(10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _dateLabel(_date),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                            Icon(Icons.calendar_month_outlined,
                                color: secondary),
                          ],
                        ),
                      ),
                    ),
                    _sectionTitle('图片（选填）'),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final e in _imagePaths.asMap().entries)
                          Stack(
                            children: [
                              GestureDetector(
                                onTap: () => _openMediaPreview(
                                  e.key,
                                  preferMotion: false,
                                ),
                                onLongPress: () => _openMediaPreview(
                                  e.key,
                                  preferMotion: true,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: SizedBox(
                                    width: 96,
                                    height: 96,
                                    child: storedImage(
                                      e.value,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                              if (e.key < _motionVideoPaths.length &&
                                  _motionVideoPaths[e.key].trim().isNotEmpty)
                                Positioned(
                                  left: 6,
                                  top: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(110),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'LIVE',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: _saving
                                      ? null
                                      : () => _removeMediaAt(e.key),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withAlpha(110),
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        GestureDetector(
                          onTap: _pickImage,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: cardColor.withAlpha(isDark ? 110 : 245),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withAlpha(10),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.add_a_photo_outlined,
                              color: AppTheme.accentOf(context).withAlpha(200),
                            ),
                          ),
                        ),
                      ],
                    ),
                    _sectionTitle('文字（选填）'),
                    TextField(
                      controller: _textController,
                      enabled: !_saving,
                      minLines: 6,
                      maxLines: 14,
                      decoration: InputDecoration(
                        hintText: '写下今天的咖啡心情…',
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
                    if (_isEditing) ...[
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                          onPressed: _saving ? null : _delete,
                          child: const Text(
                            '删除这篇日记',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _MotionPreviewDialog extends StatefulWidget {
  const _MotionPreviewDialog({required this.videoPath});

  final String videoPath;

  @override
  State<_MotionPreviewDialog> createState() => _MotionPreviewDialogState();
}

class _MotionPreviewDialogState extends State<_MotionPreviewDialog> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.file(File(widget.videoPath));
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio:
              _ready && controller != null ? controller.value.aspectRatio : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_ready && controller != null) VideoPlayer(controller),
              if (!_ready)
                const Center(
                  child: CircularProgressIndicator(),
                ),
              Positioned(
                right: 10,
                top: 10,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(110),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ),
              if (_ready && controller != null)
                Positioned(
                  left: 10,
                  top: 10,
                  child: GestureDetector(
                    onTap: () {
                      if (!controller.value.isInitialized) return;
                      if (controller.value.isPlaying) {
                        controller.pause();
                      } else {
                        controller.play();
                      }
                      setState(() {});
                    },
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(110),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        controller.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
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

  Future<void> _scanMenuFrom(ImageSource source) async {
    if (_menuBusy) return;
    if (!_supportsOcr) {
      _showMessage('当前平台不支持 OCR 识别');
      return;
    }
    setState(() => _menuBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
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
        _showMessage(source == ImageSource.camera
            ? '相机权限被拒绝，请到系统设置中开启相机权限'
            : '相册权限被拒绝，请到系统设置中开启相册权限');
      } else {
        _showMessage('打开相机失败，请检查权限或重试');
      }
    } catch (_) {
      _showMessage('打开相机失败，请检查权限或重试');
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _scanBeansFrom(ImageSource source) async {
    if (_beanBusy) return;
    if (!_supportsOcr) {
      _showMessage('当前平台不支持 OCR 识别');
      return;
    }
    setState(() => _beanBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
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
        _showMessage(source == ImageSource.camera
            ? '相机权限被拒绝，请到系统设置中开启相机权限'
            : '相册权限被拒绝，请到系统设置中开启相册权限');
      } else {
        _showMessage('打开相机失败，请检查权限或重试');
      }
    } catch (_) {
      _showMessage('打开相机失败，请检查权限或重试');
    } finally {
      if (mounted) setState(() => _beanBusy = false);
    }
  }

  Future<void> _scanMenu() => _scanMenuFrom(ImageSource.camera);
  Future<void> _scanMenuFromGallery() => _scanMenuFrom(ImageSource.gallery);
  Future<void> _scanBeans() => _scanBeansFrom(ImageSource.camera);
  Future<void> _scanBeansFromGallery() => _scanBeansFrom(ImageSource.gallery);

  Future<void> _clearOcrResults() async {
    setState(() {
      _menuItems = const [];
      _menuText = '';
      _beanInfo = null;
      _beanText = '';
    });
    _showMessage('已清空 OCR 结果');
  }

  Future<void> _openAddFromMenuItem(_MenuItem item) async {
    final createdAt = DateTime.now();
    await Navigator.of(context).push(
      _bottomUpRoute<bool>(
        AddCoffeePage(
          repository: widget.repository,
          initialCreatedAt: createdAt,
          initialName: item.name,
          initialCost: item.price,
        ),
      ),
    );
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
                              child: GestureDetector(
                                onTap: () async {
                                  Navigator.of(context).pop();
                                  await _openAddFromMenuItem(item);
                                },
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
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.chevron_right,
                                      color: AppTheme.accentOf(context),
                                      size: 18,
                                    ),
                                  ],
                                ),
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
              Row(
                children: [
                  Expanded(
                    child: Text('OCR识别', style: textTheme.headlineLarge),
                  ),
                  IconButton(
                    onPressed: (_menuText.isEmpty &&
                            _menuItems.isEmpty &&
                            _beanText.isEmpty &&
                            _beanInfo == null)
                        ? null
                        : _clearOcrResults,
                    icon: const Icon(Icons.delete_sweep_outlined),
                    color: AppTheme.accentOf(context),
                    tooltip: '清空',
                  ),
                ],
              ),
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
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _menuBusy ? null : _scanMenuFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('从相册识别'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentOf(context),
                          side: BorderSide(
                            color: AppTheme.accentOf(context).withAlpha(120),
                          ),
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
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
                              child: GestureDetector(
                                onTap: () => _openAddFromMenuItem(item),
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
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.add_circle_outline,
                                      color: AppTheme.accentOf(context),
                                      size: 18,
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
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _beanBusy ? null : _scanBeansFromGallery,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('从相册识别'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.accentOf(context),
                          side: BorderSide(
                            color: AppTheme.accentOf(context).withAlpha(120),
                          ),
                          minimumSize: const Size.fromHeight(46),
                        ),
                      ),
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
                      : index == 2
                          ? CoffeeDiaryPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
                            )
                          : SettingsPage(
                              repository: widget.repository,
                              themeMode: widget.themeMode,
                              onThemeModeChange: widget.onThemeModeChange,
                              accentPalette: widget.accentPalette,
                              onAccentPaletteChange:
                                  widget.onAccentPaletteChange,
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

class _TypeDistributionChart extends StatelessWidget {
  const _TypeDistributionChart({required this.typeCounts});

  final Map<String, int> typeCounts;

  List<MapEntry<String, int>> _normalizeEntries() {
    final entries = typeCounts.entries
        .where((e) => e.value > 0)
        .toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const [];
    if (entries.length <= 6) return entries;
    final top = entries.take(5).toList(growable: true);
    final other = entries.skip(5).fold<int>(0, (sum, e) => sum + e.value);
    if (other > 0) top.add(MapEntry('其他', other));
    return top;
  }

  List<Color> _segmentColors(BuildContext context, int count) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = AppTheme.accentOf(context);
    final hsl = HSLColor.fromColor(base);
    final baseLightness = isDark ? 0.62 : 0.52;
    final saturation = max(0.55, min(0.85, hsl.saturation + 0.15));
    return List<Color>.generate(count, (i) {
      final hue = (hsl.hue + i * 36) % 360;
      final lightness = (baseLightness + (i.isEven ? 0.06 : -0.03))
          .clamp(0.35, 0.75)
          .toDouble();
      return hsl
          .withHue(hue)
          .withSaturation(saturation)
          .withLightness(lightness)
          .toColor();
    }, growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final entries = _normalizeEntries();
    if (entries.isEmpty) {
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
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);
    final colors = _segmentColors(context, entries.length);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 140,
          height: 140,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(140, 140),
                painter: _DonutPainter(
                  values: entries.map((e) => e.value).toList(growable: false),
                  colors: colors,
                  backgroundColor: (isDark ? Colors.white : Colors.black)
                      .withAlpha(isDark ? 14 : 10),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    total.toString(),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '杯',
                    style: textTheme.bodyMedium?.copyWith(color: secondary) ??
                        TextStyle(color: secondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colors[i],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entries[i].key,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodyMedium?.copyWith(color: primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entries[i].value.toString(),
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.values,
    required this.colors,
    required this.backgroundColor,
  });

  final List<int> values;
  final List<Color> colors;
  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || colors.isEmpty) return;
    final total = values.fold<int>(0, (sum, v) => sum + v);
    if (total <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.26;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth);

    final basePaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, 0, pi * 2, false, basePaint);

    var startAngle = -pi / 2;
    const gap = 0.055;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v <= 0) continue;
      final sweep = (v / total) * pi * 2;
      final adjusted = max(0.0, sweep - gap);
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, startAngle, adjusted, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.backgroundColor != backgroundColor;
  }
}

class _CaffeineHeatmapChart extends StatelessWidget {
  const _CaffeineHeatmapChart({
    required this.range,
    required this.anchorDate,
    required this.values,
  });

  final StatsRange range;
  final DateTime anchorDate;
  final List<int> values;

  DateTime _stripTime(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _rangeStart(DateTime now, StatsRange range) {
    final date = _stripTime(now);
    switch (range) {
      case StatsRange.week:
        return date.subtract(Duration(days: date.weekday - 1));
      case StatsRange.month:
        return DateTime(date.year, date.month);
      case StatsRange.year:
        return DateTime(date.year);
    }
  }

  Color _cellColor(BuildContext context, int value, int maxValue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = AppTheme.accentOf(context);
    if (value <= 0) {
      return (isDark ? Colors.white : Colors.black).withAlpha(isDark ? 16 : 10);
    }
    final t = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);
    final minAlpha = isDark ? 48 : 38;
    final maxAlpha = isDark ? 210 : 200;
    final alpha = (minAlpha + (maxAlpha - minAlpha) * t).round();
    return base.withAlpha(alpha);
  }

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

    final isYear = range == StatsRange.year;
    final targetCount = isYear ? 12 : 28;

    final shown = values.length <= targetCount
        ? values
        : values.sublist(values.length - targetCount);
    final padded = <int>[
      ...List<int>.filled(max(0, targetCount - shown.length), 0),
      ...shown,
    ];

    final maxValue = padded.reduce(max);
    final start = _rangeStart(anchorDate, range);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final textTheme = Theme.of(context).textTheme;

    String dateLabel(int index) {
      if (range == StatsRange.year) {
        final month = index + 1;
        return '$month月';
      }
      final offsetDays = values.length <= targetCount
          ? index
          : (values.length - targetCount) + index;
      final date = start.add(Duration(days: offsetDays));
      return '${date.month}/${date.day}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var i = 0; i < padded.length; i++)
              GestureDetector(
                onTap: () {
                  final label = dateLabel(i);
                  final v = padded[i];
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label：$v mg')),
                  );
                },
                child: Container(
                  width: isYear ? 26 : 18,
                  height: isYear ? 26 : 18,
                  decoration: BoxDecoration(
                    color: _cellColor(context, padded[i], maxValue),
                    borderRadius: BorderRadius.circular(isYear ? 8 : 6),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              isYear ? '1月' : '起',
              style: textTheme.bodyMedium?.copyWith(color: secondary),
            ),
            const Spacer(),
            Text(
              isYear ? '12月' : '至',
              style: textTheme.bodyMedium?.copyWith(color: secondary),
            ),
          ],
        ),
      ],
    );
  }
}

class _CupsCaffeineScatterChart extends StatelessWidget {
  const _CupsCaffeineScatterChart({
    required this.cups,
    required this.caffeineMg,
  });

  final List<int> cups;
  final List<int> caffeineMg;

  @override
  Widget build(BuildContext context) {
    final n = min(cups.length, caffeineMg.length);
    if (n <= 1) {
      return SizedBox(
        height: 140,
        child: Center(
          child: Text(
            '暂无数据',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final xs = cups.take(n).toList(growable: false);
    final ys = caffeineMg.take(n).toList(growable: false);
    final maxX = max(1, xs.reduce(max));
    final maxY = max(1, ys.reduce(max));

    return SizedBox(
      width: double.infinity,
      height: 160,
      child: CustomPaint(
        painter: _ScatterPainter(
          xValues: xs,
          yValues: ys,
          maxX: maxX,
          maxY: maxY,
          accent: AppTheme.accentOf(context),
          isDark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _ScatterPainter extends CustomPainter {
  _ScatterPainter({
    required this.xValues,
    required this.yValues,
    required this.maxX,
    required this.maxY,
    required this.accent,
    required this.isDark,
  });

  final List<int> xValues;
  final List<int> yValues;
  final int maxX;
  final int maxY;
  final Color accent;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0;
    const bottom = 26.0;
    const top = 8.0;
    const right = 10.0;

    final w = size.width - left - right;
    final h = size.height - top - bottom;
    if (w <= 0 || h <= 0) return;

    final axisColor = (isDark ? Colors.white : Colors.black).withAlpha(28);
    final gridColor = (isDark ? Colors.white : Colors.black).withAlpha(14);
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final origin = Offset(left, top + h);
    canvas.drawLine(origin, Offset(left + w, top + h), axisPaint);
    canvas.drawLine(origin, const Offset(left, top), axisPaint);

    for (var i = 1; i <= 3; i++) {
      final y = top + h * (i / 4);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), gridPaint);
    }

    final points = <Offset>[];
    for (var i = 0; i < min(xValues.length, yValues.length); i++) {
      final x = xValues[i] / maxX;
      final y = yValues[i] / maxY;
      points.add(Offset(left + w * x, top + h * (1 - y)));
    }

    final dotPaint = Paint()..color = accent.withAlpha(isDark ? 220 : 210);
    for (final p in points) {
      canvas.drawCircle(p, 4, dotPaint);
      canvas.drawCircle(
        p,
        7,
        Paint()
          ..color = accent.withAlpha(isDark ? 34 : 24)
          ..style = PaintingStyle.fill,
      );
    }

    if (points.length >= 2) {
      var sumX = 0.0;
      var sumY = 0.0;
      var sumXX = 0.0;
      var sumXY = 0.0;
      final n = points.length.toDouble();
      for (var i = 0; i < points.length; i++) {
        final x = xValues[i].toDouble();
        final y = yValues[i].toDouble();
        sumX += x;
        sumY += y;
        sumXX += x * x;
        sumXY += x * y;
      }
      final denom = n * sumXX - sumX * sumX;
      if (denom.abs() > 1e-6) {
        final slope = (n * sumXY - sumX * sumY) / denom;
        final intercept = (sumY - slope * sumX) / n;
        final y0 = (intercept).clamp(0.0, maxY.toDouble());
        final y1 = (slope * maxX + intercept).clamp(0.0, maxY.toDouble());
        final p0 = Offset(left + w * 0, top + h * (1 - y0 / maxY));
        final p1 = Offset(left + w * 1, top + h * (1 - y1 / maxY));
        canvas.drawLine(
          p0,
          p1,
          Paint()
            ..color = accent.withAlpha(isDark ? 120 : 110)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    final textStyle = TextStyle(
      fontSize: 11,
      color: (isDark ? Colors.white : Colors.black).withAlpha(120),
      fontWeight: FontWeight.w600,
    );
    final tpX = TextPainter(
      text: TextSpan(text: '杯数', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tpX.paint(canvas, Offset(left + w - tpX.width, top + h + 6));

    final tpY = TextPainter(
      text: TextSpan(text: 'mg', style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tpY.paint(canvas, const Offset(6, top));
  }

  @override
  bool shouldRepaint(covariant _ScatterPainter oldDelegate) {
    return oldDelegate.xValues != xValues ||
        oldDelegate.yValues != yValues ||
        oldDelegate.maxX != maxX ||
        oldDelegate.maxY != maxY ||
        oldDelegate.accent != accent ||
        oldDelegate.isDark != isDark;
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
    final borderColor =
        isDark ? Colors.white.withAlpha(28) : Colors.black.withAlpha(16);
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? [
              const Color(0xFF2F2F34).withAlpha(18),
              const Color(0xFF1C1C1E).withAlpha(12),
              const Color(0xFF3B3B41).withAlpha(16),
            ]
          : [
              const Color(0xFFFFFFFF).withAlpha(30),
              const Color(0xFFE8EAEE).withAlpha(22),
              const Color(0xFFFFFFFF).withAlpha(28),
            ],
      stops: const [0, 0.55, 1],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(34),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 13, sigmaY: 13),
        child: Container(
          height: _bottomNavHeight,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(34),
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
            children: [
              Expanded(
                child: _NavItem(
                  icon: Icons.local_cafe_outlined,
                  selected: selectedIndex == 0,
                  onTap: () => onSelect(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.show_chart_outlined,
                  selected: selectedIndex == 1,
                  onTap: () => onSelect(1),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.menu_book_outlined,
                  selected: selectedIndex == 2,
                  onTap: () => onSelect(2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.document_scanner_outlined,
                  selected: selectedIndex == 3,
                  onTap: () => onSelect(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  icon: Icons.settings_outlined,
                  selected: selectedIndex == 4,
                  onTap: () => onSelect(4),
                ),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final raw = constraints.maxWidth.isFinite ? constraints.maxWidth : 60.0;
        final size = min(60.0, max(44.0, raw));
        final radius = size * (22 / 60);
        final iconSize = size * 0.5;
        return Center(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(radius),
              child: Container(
                width: size,
                height: size,
                alignment: Alignment.center,
                decoration: selected
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.accentOf(context).withAlpha(46),
                            AppTheme.accentOf(context).withAlpha(18),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(radius),
                        border: Border.all(
                          color: AppTheme.accentOf(context).withAlpha(70),
                          width: 1,
                        ),
                      )
                    : null,
                child: Icon(icon, color: color, size: iconSize),
              ),
            ),
          ),
        );
      },
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
    this.initialCost,
    this.initialNote,
  });

  final CoffeeStatsRepository repository;
  final DateTime initialCreatedAt;
  final CoffeeRecord? initialRecord;
  final String? initialName;
  final double? initialCost;
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
  String _beanRoast = '中烘';
  String _grindSize = '中细';
  String _brewTimeUnit = 'm';
  String? _imagePath;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _beanNameController = TextEditingController();
  final TextEditingController _beanOriginController = TextEditingController();
  final TextEditingController _beanFlavorController = TextEditingController();
  final TextEditingController _brewMethodController = TextEditingController();
  final TextEditingController _doseGController = TextEditingController();
  final TextEditingController _waterMlController = TextEditingController();
  final TextEditingController _brewTimeController = TextEditingController();
  final TextEditingController _brewNoteController = TextEditingController();
  final CameraService _cameraService = CameraService();
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
      final parsed = _extractHomemadeSection((initialRecord.note ?? '').trim());
      final cleanedNote = parsed.$1;
      final fields = parsed.$2;
      if (cleanedNote.trim().isNotEmpty) {
        _noteController.text = cleanedNote.trim();
      }
      _beanNameController.text = (fields['咖啡豆'] ?? '').trim();
      _beanOriginController.text = (fields['产地'] ?? '').trim();
      _beanRoast = (fields['烘焙'] ?? _beanRoast).trim();
      _beanFlavorController.text = (fields['风味'] ?? '').trim();
      _brewMethodController.text = (fields['冲煮'] ?? '').trim();
      _grindSize = (fields['研磨'] ?? _grindSize).trim();
      _doseGController.text = (fields['粉量(g)'] ?? '').trim();
      _waterMlController.text = (fields['水量(ml)'] ?? '').trim();
      final time = (fields['时间'] ?? '').trim();
      final timeMatch = RegExp(r'^(\d+)\s*([sm])$').firstMatch(time);
      if (timeMatch != null) {
        _brewTimeController.text = timeMatch.group(1) ?? '';
        _brewTimeUnit = timeMatch.group(2) ?? _brewTimeUnit;
      } else {
        _brewTimeController.text = time;
      }
      _brewNoteController.text = (fields['备注'] ?? '').trim();
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
    final initialCost = widget.initialCost;
    if (initialCost != null && initialCost > 0) {
      _priceController.text = initialCost % 1 == 0
          ? initialCost.toStringAsFixed(0)
          : initialCost.toStringAsFixed(2);
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
    _beanNameController.dispose();
    _beanOriginController.dispose();
    _beanFlavorController.dispose();
    _brewMethodController.dispose();
    _doseGController.dispose();
    _waterMlController.dispose();
    _brewTimeController.dispose();
    _brewNoteController.dispose();
    super.dispose();
  }

  (String, Map<String, String>) _extractHomemadeSection(String note) {
    const startMarker = '【自制咖啡】';
    const endMarker = '【/自制咖啡】';
    final start = note.indexOf(startMarker);
    if (start < 0) return (note, const {});
    final end = note.indexOf(endMarker, start);
    if (end < 0) {
      final cleaned = note.substring(0, start).trim();
      return (cleaned, const {});
    }
    final block = note.substring(start + startMarker.length, end).trim();
    final cleaned =
        (note.substring(0, start) + note.substring(end + endMarker.length))
            .trim();
    final map = <String, String>{};
    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final index = line.indexOf('：');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      if (key.isEmpty) continue;
      map[key] = value;
    }
    return (cleaned, map);
  }

  String _buildHomemadeSectionIfNeeded() {
    if (!_homemade) return '';
    final beanName = _beanNameController.text.trim();
    final origin = _beanOriginController.text.trim();
    final roast = _beanRoast.trim();
    final flavor = _beanFlavorController.text.trim();
    final method = _brewMethodController.text.trim();
    final grind = _grindSize.trim();
    final dose = _doseGController.text.trim();
    final water = _waterMlController.text.trim();
    final timeValue = _brewTimeController.text.trim();
    final time = timeValue.isEmpty ? '' : '$timeValue$_brewTimeUnit';
    final brewNote = _brewNoteController.text.trim();
    final hasAny = beanName.isNotEmpty ||
        origin.isNotEmpty ||
        flavor.isNotEmpty ||
        method.isNotEmpty ||
        dose.isNotEmpty ||
        water.isNotEmpty ||
        timeValue.isNotEmpty ||
        brewNote.isNotEmpty;
    if (!hasAny) return '';
    final lines = <String>[
      '【自制咖啡】',
      if (beanName.isNotEmpty) '咖啡豆：$beanName',
      if (origin.isNotEmpty) '产地：$origin',
      if (roast.isNotEmpty) '烘焙：$roast',
      if (flavor.isNotEmpty) '风味：$flavor',
      if (method.isNotEmpty) '冲煮：$method',
      if (grind.isNotEmpty) '研磨：$grind',
      if (dose.isNotEmpty) '粉量(g)：$dose',
      if (water.isNotEmpty) '水量(ml)：$water',
      if (time.isNotEmpty) '时间：$time',
      if (brewNote.isNotEmpty) '备注：$brewNote',
      '【/自制咖啡】',
    ];
    return lines.join('\n');
  }

  Widget _miniPillButton({required IconData icon, required String text}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8);
    final fg = isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg.withAlpha(190)),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg.withAlpha(210),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallOption({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withAlpha(10),
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: fg,
          ),
        ),
      ),
    );
  }

  InputDecoration _filledInputDecoration({
    required Color cardColor,
    required bool isDark,
    String? hintText,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: cardColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: (isDark ? Colors.white : Colors.black).withAlpha(10),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: BorderSide(
          color: (isDark ? Colors.white : Colors.black).withAlpha(10),
        ),
      ),
    );
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
    final picked = await showModalBottomSheet<XFile?>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(20),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('拍照'),
                  onTap: () async {
                    final file = await _cameraService.pickFromCamera();
                    if (!context.mounted) return;
                    Navigator.of(context).pop(file);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap: () async {
                    final file = await _cameraService.pickFromGallery();
                    if (!context.mounted) return;
                    Navigator.of(context).pop(file);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null) return;
    final persisted = await persistPickedImage(picked);
    if (!mounted) return;
    setState(() {
      _imagePath = persisted;
    });
    try {
      final day = DateTime(_createdAt.year, _createdAt.month, _createdAt.day);
      unawaited(
        context
            .read<StickerStore>()
            .addStickerFromImage(date: day, imagePath: persisted),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });
    final cost = double.tryParse(_priceController.text.trim()) ?? 0;
    final name = _nameController.text.trim();
    final noteRaw = _noteController.text.trim();
    final note = _extractHomemadeSection(noteRaw).$1.trim();
    final homemadeSection = _buildHomemadeSectionIfNeeded();
    final combinedNote = [
      note,
      homemadeSection,
    ].where((s) => s.trim().isNotEmpty).join('\n\n').trim();
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
        ..note = combinedNote.isEmpty ? null : combinedNote
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
        ..note = combinedNote.isEmpty ? null : combinedNote
        ..imagePath = _imagePath
        ..cost = cost
        ..createdAt = _createdAt;
      await widget.repository.addRecord(record);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    if (_saving) return;
    final existing = widget.initialRecord;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final errorColor = Theme.of(context).colorScheme.error;
        return AlertDialog(
          title: const Text('删除这条记录？'),
          content: const Text('删除后无法恢复。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: errorColor),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() {
      _saving = true;
    });
    await widget.repository.deleteRecord(existing.id);
    final deletedImagePath = (existing.imagePath ?? '').trim();
    if (deletedImagePath.isNotEmpty && mounted) {
      final dayStart = DateTime(
        existing.createdAt.year,
        existing.createdAt.month,
        existing.createdAt.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final remaining =
          await widget.repository.getRecordsInRange(dayStart, dayEnd);
      if (!mounted) return;
      final stillHasImage = remaining.any(
        (r) => (r.imagePath ?? '').trim().isNotEmpty,
      );
      if (!stillHasImage) {
        final dateKey = formatDateKey(dayStart);
        final store = context.read<StickerStore>();
        final stickers = store.stickersByDate[dateKey] ?? const [];
        if (stickers.isNotEmpty) {
          await store.removeSticker(
              dateKey: dateKey, stickerId: stickers.first.id);
        }
      }
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
                    text: _saving ? '处理中' : (_isEditing ? '保存修改' : '保存'),
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
                                    Icons.add_a_photo_outlined,
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
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: AppTheme.accentOf(context).withAlpha(120),
                        ),
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
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: AppTheme.accentOf(context).withAlpha(18),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.home_rounded,
                              color: AppTheme.accentOf(context).withAlpha(220),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '自制咖啡',
                                  style: textTheme.titleMedium?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '记录咖啡豆和冲煮详情',
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: secondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _homemade,
                            activeColor: AppTheme.accentOf(context),
                            onChanged: _saving
                                ? null
                                : (v) => setState(() => _homemade = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: !_homemade
                          ? const SizedBox.shrink()
                          : Column(
                              key: const ValueKey('homemade_form'),
                              children: [
                                _StatCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '咖啡豆',
                                            style:
                                                textTheme.titleMedium?.copyWith(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: primary,
                                            ),
                                          ),
                                          _miniPillButton(
                                            icon: Icons.folder_open_outlined,
                                            text: '模板',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '咖啡豆',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _beanNameController,
                                        enabled: !_saving,
                                        decoration: _filledInputDecoration(
                                          cardColor: cardColor,
                                          isDark: isDark,
                                          hintText: '埃塞俄比亚耶加雪菲',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '产地',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _beanOriginController,
                                        enabled: !_saving,
                                        decoration: _filledInputDecoration(
                                          cardColor: cardColor,
                                          isDark: isDark,
                                          hintText: '埃塞俄比亚，哥伦比亚',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '烘焙程度',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          for (final v in const [
                                            '浅烘',
                                            '中烘',
                                            '深烘'
                                          ])
                                            _smallOption(
                                              text: v,
                                              selected: _beanRoast == v,
                                              onTap: () => setState(
                                                  () => _beanRoast = v),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '风味描述',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _beanFlavorController,
                                        enabled: !_saving,
                                        decoration: _filledInputDecoration(
                                          cardColor: cardColor,
                                          isDark: isDark,
                                          hintText: '柑橘，花香，巧克力',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                                _StatCard(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '冲煮详情',
                                            style:
                                                textTheme.titleMedium?.copyWith(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800,
                                              color: primary,
                                            ),
                                          ),
                                          _miniPillButton(
                                            icon: Icons.folder_open_outlined,
                                            text: '模板',
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '冲煮方法',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _brewMethodController,
                                        enabled: !_saving,
                                        decoration: _filledInputDecoration(
                                          cardColor: cardColor,
                                          isDark: isDark,
                                          hintText: '例如：V60，法压壶，爱乐压',
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '研磨粗细',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: [
                                          for (final v in const [
                                            '极细',
                                            '细',
                                            '中细',
                                            '中',
                                            '粗'
                                          ])
                                            _smallOption(
                                              text: v,
                                              selected: _grindSize == v,
                                              onTap: () => setState(
                                                  () => _grindSize = v),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '粉量 (g)',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: secondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                TextField(
                                                  controller: _doseGController,
                                                  enabled: !_saving,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      _filledInputDecoration(
                                                    cardColor: cardColor,
                                                    isDark: isDark,
                                                    hintText: '15',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  '水量 (ml)',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                    color: secondary,
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                TextField(
                                                  controller:
                                                      _waterMlController,
                                                  enabled: !_saving,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  decoration:
                                                      _filledInputDecoration(
                                                    cardColor: cardColor,
                                                    isDark: isDark,
                                                    hintText: '250',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '冲煮时间',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _brewTimeController,
                                              enabled: !_saving,
                                              keyboardType:
                                                  TextInputType.number,
                                              decoration:
                                                  _filledInputDecoration(
                                                cardColor: cardColor,
                                                isDark: isDark,
                                                hintText: '2',
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: cardColor,
                                              borderRadius:
                                                  BorderRadius.circular(18),
                                              border: Border.all(
                                                color: (isDark
                                                        ? Colors.white
                                                        : Colors.black)
                                                    .withAlpha(10),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: DropdownButton<String>(
                                              value: _brewTimeUnit,
                                              underline:
                                                  const SizedBox.shrink(),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 's',
                                                  child: Text('s'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 'm',
                                                  child: Text('m'),
                                                ),
                                              ],
                                              onChanged: _saving
                                                  ? null
                                                  : (v) {
                                                      if (v == null) return;
                                                      setState(() {
                                                        _brewTimeUnit = v;
                                                      });
                                                    },
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        '冲煮备注',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      TextField(
                                        controller: _brewNoteController,
                                        enabled: !_saving,
                                        minLines: 3,
                                        maxLines: 6,
                                        decoration: _filledInputDecoration(
                                          cardColor: cardColor,
                                          isDark: isDark,
                                          hintText: '冲煮技巧，观察记录…',
                                        ),
                                      ),
                                    ],
                                  ),
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
                    if (_isEditing) ...[
                      const SizedBox(height: 18),
                      Material(
                        color: _saving
                            ? Theme.of(context).colorScheme.error.withAlpha(110)
                            : Theme.of(context).colorScheme.error,
                        borderRadius: BorderRadius.circular(30),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: _saving ? null : _delete,
                          child: const SizedBox(
                            height: 56,
                            width: double.infinity,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.delete_outline, color: Colors.white),
                                SizedBox(width: 10),
                                Text(
                                  '删除',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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
