
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'weather_client.dart';

class OpenWeatherMapClient implements WeatherClient {
  const OpenWeatherMapClient();

  static const int _maxRetries = 2;
  static const Duration _timeout = Duration(seconds: 15);

  @override
  Future<WeatherData> fetchCurrent({
    required double latitude,
    required double longitude,
    String language = 'zh',
    String? apiKey,
  }) async {
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('OpenWeatherMap API Key 未配置');
    }

    final uri = Uri.https(
      'api.openweathermap.org',
      '/data/2.5/weather',
      <String, String>{
        'lat': latitude.toStringAsFixed(6),
        'lon': longitude.toStringAsFixed(6),
        'appid': apiKey,
        'units': 'metric',
        'lang': language == 'zh' ? 'zh_cn' : language,
      },
    );

    // 使用重试机制获取数据
    final json = await _getJsonWithRetry(uri);

      final main = json['main'];
      final weatherList = json['weather'] as List?;
      final weather = weatherList?.first as Map<String, dynamic>?;
      final wind = json['wind'];

      final temp = _asDouble(main?['temp']);
      final owmCode = _asInt(weather?['id']);
      final windSpeed = _asDouble(wind?['speed']) * 3.6; // m/s to km/h
      final condition = weather?['description'] as String?;
      final icon = weather?['icon'] as String?;
      final name = json['name'] as String?;

      return WeatherData(
        time: DateTime.now(),
        temperatureC: temp,
        weatherCode: _mapOwmToWmo(owmCode),
        windSpeedKmh: windSpeed,
        locationName: name,
        condition: condition,
        icon: icon,
      );
  }

  /// 带重试机制的 JSON 获取
  Future<Map<String, dynamic>> _getJsonWithRetry(
    Uri uri, {
    int maxRetries = _maxRetries,
  }) async {
    Exception? lastException;
    
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final client = http.Client();
        try {
          final response = await client
              .get(
                uri,
                headers: <String, String>{
                  'accept': 'application/json',
                  'user-agent': 'CoffeePerson/1.0',
                },
              )
              .timeout(_timeout);

          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw Exception('HTTP ${response.statusCode}: ${response.body}');
          }

          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('OpenWeatherMap 响应不是 JSON 对象');
          }
          return decoded;
    } finally {
      client.close();
    }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        
        // 如果不是最后一次尝试，等待后重试
        if (attempt < maxRetries) {
          // 指数退避：1秒、2秒、4秒...
          final delaySeconds = 1 << attempt;
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      }
    }
    
    // 所有重试都失败
    throw lastException ?? Exception('请求失败');
  }

  int _mapOwmToWmo(int owmCode) {
    if (owmCode >= 200 && owmCode < 300) return 95; // Thunderstorm
    if (owmCode >= 300 && owmCode < 400) return 51; // Drizzle
    if (owmCode >= 500 && owmCode < 600) return 61; // Rain
    if (owmCode >= 600 && owmCode < 700) return 71; // Snow
    if (owmCode >= 700 && owmCode < 800) return 45; // Fog/Atmosphere
    if (owmCode == 800) return 0; // Clear
    if (owmCode > 800) return 1; // Clouds
    return 0;
  }

  double _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }
}
