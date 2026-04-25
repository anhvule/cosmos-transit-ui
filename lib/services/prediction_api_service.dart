import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prediction_reading.dart';
import '../models/investment_forecast.dart';
import '../models/dasha_reading.dart';
import 'api_cache_service.dart';

class PredictionRequest {
  final String name;
  final String birthDate; // YYYY-MM-DD
  final String birthTime; // HH:mm
  final double latitude;
  final double longitude;
  final String timezone;
  final String transitDate; // YYYY-MM-DD

  PredictionRequest({
    required this.name,
    required this.birthDate,
    required this.birthTime,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    required this.transitDate,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'birthDate': birthDate,
        'birthTime': birthTime,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
        'transitDate': transitDate,
      };
}

enum PredictionArea {
  career,
  relationship,
  investment,
  advice,
  gain,
  loss,
  food,
}

extension PredictionAreaLabel on PredictionArea {
  String get label {
    switch (this) {
      case PredictionArea.career:
        return 'Career';
      case PredictionArea.relationship:
        return 'Relationship';
      case PredictionArea.investment:
        return 'Investment';
      case PredictionArea.advice:
        return 'Advice';
      case PredictionArea.gain:
        return 'Gain';
      case PredictionArea.loss:
        return 'Loss';
      case PredictionArea.food:
        return 'Food';
    }
  }

  String get path {
    switch (this) {
      case PredictionArea.career:
        return 'career';
      case PredictionArea.relationship:
        return 'relationship';
      case PredictionArea.investment:
        return 'investment';
      case PredictionArea.advice:
        return 'advice';
      case PredictionArea.gain:
        return 'gain';
      case PredictionArea.loss:
        return 'loss';
      case PredictionArea.food:
        return 'food';
    }
  }
}

class PredictionApiService {
  static const String _baseUrl =
      'https://radiant-mountain-37973-4b7f67ce5fbe.herokuapp.com';

  static Future<PredictionReading> fetch(
    PredictionArea area,
    PredictionRequest request, {
    bool forceRefresh = false,
  }) async {
    final endpoint = area.path;
    final body = request.toJson();

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body);
      if (cached != null) return PredictionReading.fromJson(cached);
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/$endpoint'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await ApiCacheService.write(endpoint, body, decoded);
      return PredictionReading.fromJson(decoded);
    }
    throw Exception(
        'Failed to fetch ${area.label} prediction: ${response.statusCode} ${response.body}');
  }

  /// Shared payload (excluding the period-specific field).
  static Map<String, dynamic> _baseBody({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required String timezone,
  }) =>
      {
        'name': name,
        'birthDate': birthDate,
        'birthTime': birthTime,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
      };

  static Future<InvestmentForecast> fetchInvestmentWeekly({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required String timezone,
    required String weekStart, // YYYY-MM-DD
    bool forceRefresh = false,
  }) async {
    const endpoint = 'investment-weekly';
    final body = {
      ..._baseBody(
        name: name,
        birthDate: birthDate,
        birthTime: birthTime,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      ),
      'weekStart': weekStart,
    };

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body,
          scope: CacheScope.weekly);
      if (cached != null) return InvestmentForecast.fromJson(cached);
    }

    // Use a fresh client so this call doesn't contend with any other
    // in-flight long request (e.g. monthly) on the default shared client.
    Future<http.Response> doPost() {
      final client = http.Client();
      return client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30))
          .whenComplete(client.close);
    }

    http.Response response;
    try {
      response = await doPost();
    } on Exception {
      // One retry — covers a cold Heroku dyno that's slow on the first hit.
      response = await doPost();
    }
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      await ApiCacheService.write(endpoint, body, decoded,
          scope: CacheScope.weekly);
      return InvestmentForecast.fromJson(decoded);
    }
    throw Exception(
        'Failed to fetch weekly forecast: ${response.statusCode} ${response.body}');
  }

  static Future<InvestmentForecast> fetchInvestmentMonthly({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required String timezone,
    required String month, // YYYY-MM
    bool forceRefresh = false,
  }) async {
    const endpoint = 'investment-monthly';
    final body = {
      ..._baseBody(
        name: name,
        birthDate: birthDate,
        birthTime: birthTime,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      ),
      'month': month,
    };

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body,
          scope: CacheScope.monthly);
      if (cached != null) return InvestmentForecast.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 240));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded,
            scope: CacheScope.monthly);
        return InvestmentForecast.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch monthly forecast: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  static Future<DashaReading> fetchDasha(
    PredictionRequest request, {
    bool forceRefresh = false,
  }) async {
    const endpoint = 'dasha';
    final body = request.toJson();

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body);
      if (cached != null) return DashaReading.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded);
        return DashaReading.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch dasha: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }
}
