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
    final background = selected ? accent.withAlpha(210) : tileColor;
    final border = !selected && isToday
        ? Border.all(color: accent.withAlpha(120), width: 1.2)
        : null;
    final textColor = selected ? Colors.white : primary;
    final stickerKey = formatDateKey(day);
    final stickers = stickersByDate[stickerKey] ?? const [];
    final preview = stickers.take(3).toList();
    return Opacity(
      opacity: isOutside ? 0.3 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(18),
          border: border,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest.shortestSide;
            final stickerSize = (size * 0.62).clamp(22.0, 40.0);
            return Stack(
              children: [
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
                if (preview.isNotEmpty)
                  Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => onStickerTap?.call(preview.first),
                      onLongPress: () =>
                          onStickerLongPress?.call(preview.first),
                      child: SizedBox(
                        width: stickerSize + 24,
                        height: stickerSize + 18,
                        child: Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            for (var i = 0; i < preview.length; i++)
                              Transform.translate(
                                offset: Offset(-i * 12.0, i * 6.0),
                                child: StickerView(
                                  path: preview[i].path,
                                  size: stickerSize,
                                ),
                              ),
                          ],
                        ),
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
