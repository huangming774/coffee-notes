import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

import 'sticker_models.dart';
import 'sticker_view.dart';

class CalendarWithStickers extends StatelessWidget {
  const CalendarWithStickers({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onPageChanged,
    required this.stickersByDate,
    required this.primary,
    required this.secondary,
    required this.accent,
    required this.tileColor,
    this.onStickerTap,
    this.onStickerLongPress,
  });

  final DateTime focusedDay;
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;
  final ValueChanged<DateTime> onPageChanged;
  final Map<String, List<Sticker>> stickersByDate;
  final Color primary;
  final Color secondary;
  final Color accent;
  final Color tileColor;
  final ValueChanged<Sticker>? onStickerTap;
  final ValueChanged<Sticker>? onStickerLongPress;

  @override
  Widget build(BuildContext context) {
    return TableCalendar(
      firstDay: DateTime(2000),
      lastDay: DateTime(2100),
      focusedDay: focusedDay,
      headerVisible: false,
      daysOfWeekVisible: false,
      calendarStyle: const CalendarStyle(
        outsideDaysVisible: true,
        cellMargin: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      selectedDayPredicate: (day) => isSameDay(day, selectedDay),
      onDaySelected: (selected, focused) {
        onDaySelected(selected);
        onPageChanged(focused);
      },
      onPageChanged: onPageChanged,
      calendarBuilders: CalendarBuilders(
        defaultBuilder: (context, day, _) =>
            _buildDayCell(context, day, false, false),
        todayBuilder: (context, day, _) =>
            _buildDayCell(context, day, false, true),
        selectedBuilder: (context, day, _) =>
            _buildDayCell(context, day, true, false),
        outsideBuilder: (context, day, _) =>
            _buildDayCell(context, day, false, false, isOutside: true),
      ),
      rowHeight: 60,
      availableGestures: AvailableGestures.horizontalSwipe,
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime day,
    bool selected,
    bool isToday, {
    bool isOutside = false,
  }) {
    final stickerKey = formatDateKey(day);
    final stickers = stickersByDate[stickerKey] ?? const [];
    final hasSticker = stickers.isNotEmpty;
    
    // 如果有贴纸，背景使用贴纸填充；否则使用默认背景
    final background = hasSticker ? Colors.transparent : (selected ? accent.withAlpha(210) : tileColor);
    final border = !selected && isToday
        ? Border.all(color: accent.withAlpha(120), width: 1.2)
        : (selected && hasSticker ? Border.all(color: accent, width: 2.5) : null);
    final textColor = hasSticker ? Colors.white : (selected ? Colors.white : primary);
    
    return Opacity(
      opacity: isOutside ? 0.3 : 1,
      child: RepaintBoundary( // 隔离重绘，提升性能
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: border,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 贴纸作为背景填充整个格子
                if (hasSticker)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onStickerTap?.call(stickers.first),
                    onLongPress: () => onStickerLongPress?.call(stickers.first),
                    child: StickerView(
                      path: stickers.first.path,
                      size: double.infinity,
                      fit: BoxFit.cover, // 填充整个格子
                    ),
                  ),
                if (!hasSticker)
                  Center(
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
