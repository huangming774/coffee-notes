
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'weather_client.dart';
import 'open_meteo_client.dart';
import 'open_weather_map_client.dart';

enum WeatherSource {
  openMeteo,
  openWeatherMap,
}

class WeatherService {
  WeatherService(this._prefs);

  final SharedPreferences _prefs;

  static const String _cacheKey = 'weather_cache';
  static const String _sourceKey = 'weather_source';
  static const String _owmApiKeyKey = 'owm_api_key';

  WeatherSource get source {
    final val = _prefs.getString(_sourceKey);
    return WeatherSource.values.firstWhere(
      (e) => e.name == val,
      orElse: () => WeatherSource.openMeteo,
    );
  }

  Future<void> setSource(WeatherSource source) async {
    await _prefs.setString(_sourceKey, source.name);
  }

  String get owmApiKey => _prefs.getString(_owmApiKeyKey) ?? '';

  Future<void> setOwmApiKey(String key) async {
    await _prefs.setString(_owmApiKeyKey, key);
  }

  Future<WeatherData?> getCachedWeather() async {
    final jsonStr = _prefs.getString(_cacheKey);
    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr);
      final weather = WeatherData.fromJson(json);
      
      // Check if cache is within 30 minutes
      if (DateTime.now().difference(weather.time).inMinutes < 30) {
        return weather;
      }
    } catch (_) {
      await _prefs.remove(_cacheKey);
    }
    return null;
  }

  Future<WeatherData> fetchWeather({
    required double latitude,
    required double longitude,
    String language = 'zh',
    bool force = false,
  }) async {
    if (!force) {
      final cached = await getCachedWeather();
      if (cached != null) return cached;
    }

    final currentSource = source;
    WeatherClient client;
    String? apiKey;

    switch (currentSource) {
      case WeatherSource.openMeteo:
        client = const OpenMeteoClient();
        break;
      case WeatherSource.openWeatherMap:
        client = const OpenWeatherMapClient();
        apiKey = owmApiKey;
        break;
    }

    final weather = await client.fetchCurrent(
      latitude: latitude,
      longitude: longitude,
      language: language,
      apiKey: apiKey,
    );

    // Update cache
    await _prefs.setString(_cacheKey, jsonEncode(weather.toJson()));
    
    return weather;
  }
}
