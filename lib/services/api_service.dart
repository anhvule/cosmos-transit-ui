import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/daily_reading.dart';
import '../models/user_profile.dart';

class ApiService {
  // TODO: Update with deployed Railway URL
  // static const String _baseUrl = 'https://cosmictransit-api.up.railway.app';
  static const String _baseUrl = 'http://localhost:3000';

  static Future<DailyReading> fetchDailyReading(UserProfile profile) async {
    debugPrint('Fetching daily reading for profile: ${profile.toApiJson()}');
    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/reading'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(profile.toApiJson()),
        )
        .timeout(const Duration(seconds: 50));

    if (response.statusCode == 200) {
      return DailyReading.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>);
    } else {
      throw Exception('Failed to fetch reading: ${response.statusCode}');
    }
  }
}
