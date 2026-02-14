import 'dart:convert';
import 'package:http/http.dart' as http;
import 'weather_client.dart';

class OpenMeteoClient implements WeatherClient {
  const OpenMeteoClient();

  static const int _maxRetries = 2;
  static const Duration _timeout = Duration(seconds: 15);

  @override
  Future<WeatherData> fetchCurrent({
    required double latitude,
    required double longitude,
    String language = 'zh',
    String? apiKey,
  }) async {
    // 使用重试机制获取天气数据
    final forecastUri = Uri.https(
      'api.open-meteo.com',
      '/v1/forecast',
      <String, String>{
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        'current': 'temperature_2m,weather_code,wind_speed_10m',
        'timezone': 'auto',
      },
    );
    final forecastJson = await _getJsonWithRetry(forecastUri);
    final current = forecastJson['current'];
    if (current is! Map<String, dynamic>) {
      throw const FormatException('Open-Meteo 响应缺少 current 字段');
    }

    final time = DateTime.tryParse('${current['time']}') ?? DateTime.now();
    final temperature = _asDouble(current['temperature_2m']);
    final weatherCode = _asInt(current['weather_code']);
    final wind = _asDouble(current['wind_speed_10m']);

    // 获取位置名称，失败时显示坐标
    String? locationName;
    try {
      locationName = await _reverseGeocode(
        latitude: latitude,
        longitude: longitude,
        language: language,
      );
    } catch (_) {
      // 地理编码失败时，显示格式化的坐标
      locationName = _formatCoordinates(latitude, longitude);
    }

    return WeatherData(
      time: time,
      temperatureC: temperature,
      weatherCode: weatherCode,
      windSpeedKmh: wind,
      locationName: locationName,
    );
  }

  /// 格式化坐标为可读字符串
  String _formatCoordinates(double latitude, double longitude) {
    final latDir = latitude >= 0 ? 'N' : 'S';
    final lonDir = longitude >= 0 ? 'E' : 'W';
    return '${latitude.abs().toStringAsFixed(2)}°$latDir, ${longitude.abs().toStringAsFixed(2)}°$lonDir';
  }

  /// 反向地理编码：将坐标转换为地名
  Future<String?> _reverseGeocode({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    // 尝试多个可能的 API 端点
    final endpoints = [
      '/v1/search',  // 新版 API
      '/v1/reverse', // 旧版 API
    ];

    for (final endpoint in endpoints) {
      try {
        final uri = Uri.https(
          'geocoding-api.open-meteo.com',
          endpoint,
          <String, String>{
            'latitude': latitude.toStringAsFixed(6),
            'longitude': longitude.toStringAsFixed(6),
            'language': language,
            'count': '1',
          },
        );
        
        final json = await _getJsonWithRetry(uri, maxRetries: 1);
        final results = json['results'];
        if (results is! List || results.isEmpty) continue;
        
        final first = results.first;
        if (first is! Map<String, dynamic>) continue;
        
        final name = (first['name'] as String?)?.trim();
        final admin1 = (first['admin1'] as String?)?.trim();
        final country = (first['country'] as String?)?.trim();

        final parts = <String>[];
        if (name != null && name.isNotEmpty) parts.add(name);
        if (admin1 != null && admin1.isNotEmpty && admin1 != name) {
          parts.add(admin1);
        }
        if (country != null && country.isNotEmpty) parts.add(country);
        
        if (parts.isNotEmpty) {
          return parts.join(' · ');
        }
      } catch (_) {
        // 尝试下一个端点
        continue;
      }
    }
    
    // 所有端点都失败，返回 null
    return null;
  }

  /// 带重试机制的 JSON 获取
  Future<Map<String, dynamic>> _getJsonWithRetry(
    Uri uri, {
    int maxRetries = _maxRetries,
  }) async {
    Exception? lastException;
    
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await _getJson(uri);
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

  /// 获取 JSON 数据（带超时）
  Future<Map<String, dynamic>> _getJson(Uri uri) async {
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
        throw const FormatException('Open-Meteo 响应不是 JSON 对象');
      }
      return decoded;
    } finally {
      client.close();
    }
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
