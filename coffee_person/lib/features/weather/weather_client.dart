class WeatherData {
  const WeatherData({
    required this.time,
    required this.temperatureC,
    required this.weatherCode,
    required this.windSpeedKmh,
    this.locationName,
    this.condition,
    this.icon,
  });

  final DateTime time;
  final double temperatureC;
  final int weatherCode; // WMO code for compatibility with existing logic
  final double windSpeedKmh;
  final String? locationName;
  final String? condition; // e.g. "Sunny"
  final String? icon; // e.g. "01d"

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temperatureC': temperatureC,
        'weatherCode': weatherCode,
        'windSpeedKmh': windSpeedKmh,
        'locationName': locationName,
        'condition': condition,
        'icon': icon,
      };

  factory WeatherData.fromJson(Map<String, dynamic> json) => WeatherData(
        time: DateTime.parse(json['time']),
        temperatureC: json['temperatureC'],
        weatherCode: json['weatherCode'],
        windSpeedKmh: json['windSpeedKmh'],
        locationName: json['locationName'],
        condition: json['condition'],
        icon: json['icon'],
      );
}

abstract class WeatherClient {
  Future<WeatherData> fetchCurrent({
    required double latitude,
    required double longitude,
    String language = 'zh',
    String? apiKey,
  });
}
