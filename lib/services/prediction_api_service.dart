import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/prediction_reading.dart';
import '../models/investment_forecast.dart';
import '../models/dasha_reading.dart';
import '../models/essence_cycle.dart';
import '../models/yearly_summary.dart';
import '../models/monthly_prediction.dart';
import '../models/wealth_analysis.dart';
import '../models/favourite.dart';
import 'api_cache_service.dart';

class PredictionRequest {
  final String name;
  final String birthDate; // YYYY-MM-DD
  final String birthTime; // HH:mm
  final double latitude;
  final double longitude;
  // Numeric UTC offset in hours, e.g. 7 for Vietnam, -5 for US Eastern.
  // The backend resolver maps this to an IANA fixed-offset zone before
  // running the chart calculation.
  final int timezone;
  final String transitDate; // YYYY-MM-DD

  const PredictionRequest({
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

/// Non-investment prediction topics surfaced on the Predictions screen.
/// Investment / gain / loss were removed because the dasha-only model
/// is empirically uncalibrated for capital-deployment guidance — those
/// concerns are now centralized on the dedicated Vimshottari Dasha
/// screen with its accuracy banner.
enum PredictionArea {
  career,
  relationship,
  advice,
  food,
}

extension PredictionAreaLabel on PredictionArea {
  String get label {
    switch (this) {
      case PredictionArea.career:
        return 'Career';
      case PredictionArea.relationship:
        return 'Relationship';
      case PredictionArea.advice:
        return 'Advice';
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
      case PredictionArea.advice:
        return 'advice';
      case PredictionArea.food:
        return 'food';
    }
  }
}

class PredictionApiService {
  static const String _baseUrl =
      'https://radiant-mountain-37973-4b7f67ce5fbe.herokuapp.com';

  /// Last raw response body the essence-cycle endpoint returned (or last
  /// cached body it served). Exposed solely for the in-app debug overlay
  /// — never read by production code paths.
  static String? lastEssenceCycleRawBody;
  static String? lastEssenceCycleSource; // 'cache' | 'network'

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
  ///
  /// `timezone` is a numeric UTC offset in hours (e.g. 7, -5). The backend
  /// accepts integers in the range [-12, 14]; fractional offsets are not
  /// supported yet.
  static Map<String, dynamic> _baseBody({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required int timezone,
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
    required int timezone,
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
    required int timezone,
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

  /// Fetch the year's CAUTION pratyantardasha windows across the three
  /// bundled celebrity profiles (Druckenmiller / Ackman / Soros). Used
  /// by the "Yearly Caution Forecast" section on the Vimshottari Dasha
  /// screen to highlight ~50-100-day windows where contrarian charts
  /// agree the period needs risk-down posture.
  static Future<CautionForecast> fetchCautionDates({
    required int year,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'caution-dates';
    final body = {'year': year};

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body);
      if (cached != null) return CautionForecast.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded);
        return CautionForecast.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch caution dates: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  /// Search every Vimshottari dasha period (MD/AD/PD/SD) overlapping
  /// [fromDate, toDate]. Each entry is tagged with favorable / reasons /
  /// warnings — same shape as /api/dasha. Backend caps the range at 10
  /// years; the UI defaults to ~1 year.
  static Future<DashaRange> fetchDashaRange({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required int timezone,
    required String fromDate,
    required String toDate,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'dasha-range';
    final body = <String, dynamic>{
      ..._baseBody(
        name: name,
        birthDate: birthDate,
        birthTime: birthTime,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      ),
      'fromDate': fromDate,
      'toDate': toDate,
    };

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, body);
      if (cached != null) return DashaRange.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded);
        return DashaRange.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch dasha range: ${response.statusCode} ${response.body}');
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

  /// Tajika annual summary — Combined effect of factors analysed.
  static Future<YearlySummary> fetchYearlySummary({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required int timezone,
    required int year,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'yearly-summary';
    final body = {
      ..._baseBody(
        name: name,
        birthDate: birthDate,
        birthTime: birthTime,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      ),
      'year': year,
    };

    if (!forceRefresh) {
      // Annual chart is fixed for a given (birth, year), so monthly cache
      // is more than enough.
      final cached =
          ApiCacheService.read(endpoint, body, scope: CacheScope.monthly);
      if (cached != null) return YearlySummary.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded,
            scope: CacheScope.monthly);
        return YearlySummary.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch yearly summary: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  /// Sun-transit monthly predictions for a Tajika year.
  static Future<MonthlyPrediction> fetchMonthlyPrediction({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required int timezone,
    required int year,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'monthly-prediction';
    final body = {
      ..._baseBody(
        name: name,
        birthDate: birthDate,
        birthTime: birthTime,
        latitude: latitude,
        longitude: longitude,
        timezone: timezone,
      ),
      'year': year,
    };
    // Cache key carries a schema version so old flat-string `prediction`
    // payloads cached before the work/health/relationship/investment
    // restructuring are not reused (the new model parses them to empty).
    // Bump this whenever the response shape changes.
    final cacheBody = {...body, '_schema': 2};

    if (!forceRefresh) {
      final cached = ApiCacheService.read(endpoint, cacheBody,
          scope: CacheScope.monthly);
      if (cached != null) return MonthlyPrediction.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          // The backend computes a Sun-return bisect plus 12 sign ingresses,
          // each spawning a kerykeion subprocess. On a cold dyno it can take
          // close to 60s.
          .timeout(const Duration(seconds: 90));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, cacheBody, decoded,
            scope: CacheScope.monthly);
        return MonthlyPrediction.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch monthly prediction: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  /// Vedic wealth analysis from the natal chart — five-section report
  /// (lagna, nakshatra, house analysis, hora, yogas).
  static Future<WealthAnalysis> fetchWealthAnalysis({
    required String name,
    required String birthDate,
    required String birthTime,
    required double latitude,
    required double longitude,
    required int timezone,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'wealth-analysis';
    final body = _baseBody(
      name: name,
      birthDate: birthDate,
      birthTime: birthTime,
      latitude: latitude,
      longitude: longitude,
      timezone: timezone,
    );

    if (!forceRefresh) {
      // Natal chart never changes for a given (birth) — monthly cache scope
      // is more than sufficient.
      final cached =
          ApiCacheService.read(endpoint, body, scope: CacheScope.monthly);
      if (cached != null) return WealthAnalysis.fromJson(cached);
    }

    final client = http.Client();
    try {
      final response = await client
          .post(
            Uri.parse('$_baseUrl/api/$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded,
            scope: CacheScope.monthly);
        return WealthAnalysis.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch wealth analysis: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  static Future<EssenceCycle> fetchEssenceCycle({
    required String fullName,
    required String dob, // YYYY-MM-DD
    required int startYear,
    bool forceRefresh = false,
  }) async {
    const endpoint = 'essence-cycle';
    final body = <String, dynamic>{
      'full_name': fullName,
      'dob': dob,
      'start_year': startYear,
    };

    if (!forceRefresh) {
      // Numerology data is fixed for a given (name, dob, start_year);
      // monthly scope is plenty without ever going stale visibly.
      final cached = ApiCacheService.read(endpoint, body,
          scope: CacheScope.monthly);
      if (cached != null) {
        lastEssenceCycleRawBody =
            const JsonEncoder.withIndent('  ').convert(cached);
        lastEssenceCycleSource = 'cache';
        return EssenceCycle.fromJson(cached);
      }
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
        lastEssenceCycleRawBody = response.body;
        lastEssenceCycleSource = 'network';
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        await ApiCacheService.write(endpoint, body, decoded,
            scope: CacheScope.monthly);
        return EssenceCycle.fromJson(decoded);
      }
      throw Exception(
          'Failed to fetch essence cycle: ${response.statusCode} ${response.body}');
    } finally {
      client.close();
    }
  }

  // ─── Favourites — per-user transit-date bookmarks ────────────────────────

  /// Save a transit date to the user's favourites list with a memory note.
  static Future<Favourite> createFavourite({
    required String userKey,
    required String transitDate, // YYYY-MM-DD
    String? title,
    required String description,
  }) async {
    final body = <String, dynamic>{
      'userKey': userKey,
      'transitDate': transitDate,
      if (title != null && title.isNotEmpty) 'title': title,
      'description': description,
    };
    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/favourites'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 201) {
      return Favourite.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception(
        'Failed to save favourite: ${response.statusCode} ${response.body}');
  }

  /// List all favourites belonging to the given device key, newest transit
  /// dates first.
  static Future<List<Favourite>> listFavourites(String userKey) async {
    final response = await http
        .get(Uri.parse(
            '$_baseUrl/api/favourites?userKey=${Uri.encodeQueryComponent(userKey)}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as List;
      return decoded
          .map((e) => Favourite.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(
        'Failed to list favourites: ${response.statusCode} ${response.body}');
  }

  /// Delete one favourite. The server only deletes when the userKey matches
  /// the row owner — a 404 means either the row doesn't exist or another
  /// device wrote it.
  static Future<void> deleteFavourite({
    required int id,
    required String userKey,
  }) async {
    final response = await http
        .delete(Uri.parse(
            '$_baseUrl/api/favourites/$id?userKey=${Uri.encodeQueryComponent(userKey)}'))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 204) {
      throw Exception(
          'Failed to delete favourite: ${response.statusCode} ${response.body}');
    }
  }
}
