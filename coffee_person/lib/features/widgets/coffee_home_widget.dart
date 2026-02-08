import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoffeeHomeWidget {
  static const MethodChannel _channel = MethodChannel('coffee_person/widget');
  static const String _keyTodayCaffeineMg = 'widget_today_caffeine_mg';
  static const String _keyTodayCups = 'widget_today_cups';
  static const String _keyTodayDate = 'widget_today_date';

  static String _formatDate(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static Future<void> updateToday({
    required int caffeineMg,
    required int cups,
    required DateTime date,
  }) async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyTodayCaffeineMg, caffeineMg);
    await prefs.setInt(_keyTodayCups, cups);
    await prefs.setString(_keyTodayDate, _formatDate(date));

    try {
      await _channel.invokeMethod<void>('updateCoffeeWidget');
    } catch (_) {}
  }
}

