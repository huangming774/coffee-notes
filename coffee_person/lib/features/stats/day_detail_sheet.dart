import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/coffee_record.dart';
import '../../theme/app_theme.dart';
import '../stickers/sticker_models.dart';

/// 日期详情底部抽屉
/// 显示某一天的咖啡记录统计和列表
class DayDetailSheet extends StatelessWidget {
  const DayDetailSheet({
    super.key,
    required this.date,
    required this.records,
    required this.stickers,
    required this.onAddCoffee,
    required this.onRecordTap,
  });

  final DateTime date;
  final List<CoffeeRecord> records;
  final List<Sticker> stickers;
  final VoidCallback onAddCoffee;
  final ValueChanged<CoffeeRecord> onRecordTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary =
        isDark ? AppTheme.textPrimaryDark : AppTheme.textPrimaryLight;
    final secondary =
        isDark ? AppTheme.textSecondaryDark : AppTheme.textSecondaryLight;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final accent = AppTheme.accentOf(context);

    // 统计数据
    final totalCups = records.length;
    final totalCaffeine = records.fold<int>(0, (sum, r) => sum + r.caffeineMg);
    final totalSugar = records.fold<int>(0, (sum, r) => sum + r.sugarG);

    // 日期格式化
    final weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekday = weekdays[date.weekday - 1];
    final dateStr = '${date.month}月${date.day}日';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 拖动指示器
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: secondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 日期标题
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: primary,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),

            // 统计卡片
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      value: '$totalCups',
                      label: '杯数',
                      color: primary,
                      secondaryColor: secondary,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: secondary.withValues(alpha: 0.2),
                    ),
                    _StatItem(
                      value: '$totalCaffeine',
                      label: '咖啡因 /mg',
                      color: primary,
                      secondaryColor: secondary,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: secondary.withValues(alpha: 0.2),
                    ),
                    _StatItem(
                      value: '$totalSugar',
                      label: '糖量 /g',
                      color: primary,
                      secondaryColor: secondary,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 添加一杯按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onAddCoffee,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 24),
                      SizedBox(width: 8),
                      Text(
                        '添加一杯',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 咖啡记录列表
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '咖啡记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: primary,
                    ),
                  ),
                  Text(
                    '$totalCups 杯',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: secondary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 记录列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final record = records[index];
                  return _RecordItem(
                    record: record,
                    sticker: stickers.isNotEmpty ? stickers.first : null,
                    onTap: () => onRecordTap(record),
                    isDark: isDark,
                    primary: primary,
                    secondary: secondary,
                    cardColor: cardColor,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
    required this.color,
    required this.secondaryColor,
  });

  final String value;
  final String label;
  final Color color;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: secondaryColor,
          ),
        ),
      ],
    );
  }
}

class _RecordItem extends StatelessWidget {
  const _RecordItem({
    required this.record,
    required this.sticker,
    required this.onTap,
    required this.isDark,
    required this.primary,
    required this.secondary,
    required this.cardColor,
  });

  final CoffeeRecord record;
  final Sticker? sticker;
  final VoidCallback onTap;
  final bool isDark;
  final Color primary;
  final Color secondary;
  final Color cardColor;

  @override
  Widget build(BuildContext context) {
    final hour = record.createdAt.hour;
    final minute = record.createdAt.minute;
    final period = hour < 12 ? '上午' : (hour < 18 ? '下午' : '晚上');
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    final timeStr = '$displayHour:${minute.toString().padLeft(2, '0')}';
    final cupSize = record.cupSize ?? '中杯';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                // 贴纸缩略图
                if (sticker != null)
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: (isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.05),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(sticker!.path),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.accentOf(context).withValues(alpha: 0.1),
                    ),
                    child: Icon(
                      Icons.coffee,
                      color: AppTheme.accentOf(context),
                      size: 28,
                    ),
                  ),

                const SizedBox(width: 16),

                // 咖啡信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            record.type,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentOf(context)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              cupSize,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.accentOf(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$cupSize · $period $timeStr',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // 咖啡因含量
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${record.caffeineMg}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: primary,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'mg',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
