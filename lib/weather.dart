import 'dart:convert';

import 'package:http/http.dart' as http;

class WeatherNow {
  final double tempC;
  final int code;
  final DateTime fetched;

  WeatherNow({required this.tempC, required this.code, required this.fetched});

  bool get rainy => (code >= 51 && code <= 67) || (code >= 80 && code <= 82) || code >= 95;
  bool get snowy => (code >= 71 && code <= 77) || code == 85 || code == 86;
  bool get cloudy => code >= 1 && code <= 48;

  bool get isToday {
    final n = DateTime.now();
    return n.year == fetched.year && n.month == fetched.month && n.day == fetched.day;
  }

  Map<String, dynamic> toJson() => {'t': tempC, 'c': code, 'f': fetched.millisecondsSinceEpoch};

  static WeatherNow? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return WeatherNow(
        tempC: (j['t'] as num).toDouble(),
        code: (j['c'] as num).toInt(),
        fetched: DateTime.fromMillisecondsSinceEpoch((j['f'] as num).toInt()),
      );
    } catch (_) {
      return null;
    }
  }
}

class GeoPlace {
  final String name;
  final double lat;
  final double lon;
  GeoPlace(this.name, this.lat, this.lon);
}

/// Free weather data from open-meteo.com (no API key needed).
class WeatherService {
  static Future<GeoPlace?> geocode(String city, String lang) async {
    try {
      final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': city,
        'count': '1',
        'language': lang,
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = data['results'] as List?;
      if (list == null || list.isEmpty) return null;
      final r = list.first as Map<String, dynamic>;
      return GeoPlace(
        (r['name'] ?? city) as String,
        (r['latitude'] as num).toDouble(),
        (r['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<WeatherNow?> fetch(double lat, double lon) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'current': 'temperature_2m,weather_code',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = data['current'] as Map<String, dynamic>;
      return WeatherNow(
        tempC: (cur['temperature_2m'] as num).toDouble(),
        code: (cur['weather_code'] as num).toInt(),
        fetched: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Average daily high for the next [days] days (for trip packing).
  static Future<double?> averageHigh(double lat, double lon, {int days = 7}) async {
    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'daily': 'temperature_2m_max',
        'forecast_days': days.clamp(1, 16).toString(),
        'timezone': 'auto',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final list = ((data['daily'] as Map<String, dynamic>)['temperature_2m_max'] as List).whereType<num>().toList();
      if (list.isEmpty) return null;
      return list.fold<double>(0, (a, b) => a + b.toDouble()) / list.length;
    } catch (_) {
      return null;
    }
  }
}
