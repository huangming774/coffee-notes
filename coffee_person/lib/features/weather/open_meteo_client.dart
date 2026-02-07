import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenMeteoCurrentWeather {
  const OpenMeteoCurrentWeather({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
    required this.windSpeedKmh,
    this.locationName,
  });

  final DateTime time;
  final double temperatureC;
  final int weatherCode;
  final double windSpeedKmh;
  final String? locationName;
}

class OpenMeteoClient {
  const OpenMeteoClient();

  Future<OpenMeteoCurrentWeather> fetchCurrent({
    required double latitude,
    required double longitude,
    String language = 'zh',
  }) async {
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
    final forecastJson = await _getJson(forecastUri);
    final current = forecastJson['current'];
    if (current is! Map<String, dynamic>) {
      throw const FormatException('Open-Meteo 响应缺少 current 字段');
    }

    final time = DateTime.tryParse('${current['time']}') ?? DateTime.now();
    final temperature = _asDouble(current['temperature_2m']);
    final weatherCode = _asInt(current['weather_code']);
    final wind = _asDouble(current['wind_speed_10m']);

    String? locationName;
    try {
      locationName = await _reverseGeocode(
        latitude: latitude,
        longitude: longitude,
        language: language,
      );
    } catch (_) {}

    return OpenMeteoCurrentWeather(
      time: time,
      temperatureC: temperature,
      weatherCode: weatherCode,
      windSpeedKmh: wind,
      locationName: locationName,
    );
  }

  Future<String?> _reverseGeocode({
    required double latitude,
    required double longitude,
    required String language,
  }) async {
    final uri = Uri.https(
      'geocoding-api.open-meteo.com',
      '/v1/reverse',
      <String, String>{
        'latitude': latitude.toStringAsFixed(6),
        'longitude': longitude.toStringAsFixed(6),
        'language': language,
        'format': 'json',
      },
    );
    final json = await _getJson(uri);
    final results = json['results'];
    if (results is! List) return null;
    if (results.isEmpty) return null;
    final first = results.first;
    if (first is! Map<String, dynamic>) return null;
    final name = (first['name'] as String?)?.trim();
    final admin1 = (first['admin1'] as String?)?.trim();
    final country = (first['country'] as String?)?.trim();

    final parts = <String>[];
    if (name != null && name.isNotEmpty) parts.add(name);
    if (admin1 != null && admin1.isNotEmpty && admin1 != name) parts.add(admin1);
    if (country != null && country.isNotEmpty) parts.add(country);
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = http.Client();
    try {
      final response = await client.get(
        uri,
        headers: <String, String>{
          'accept': 'application/json',
        },
      );
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
