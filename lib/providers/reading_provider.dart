import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/daily_reading.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class ReadingProvider extends ChangeNotifier {
  DailyReading? _reading;
  bool _isLoading = false;
  String? _error;

  DailyReading? get reading => _reading;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasReading => _reading != null;

  Future<void> fetchReading() async {
    final profile = StorageService.getProfile();
    if (profile == null) return;

    // Check cache first
    // TODO: remove this comment when api is ready
    // final cached = StorageService.getCachedReading();
    // if (cached != null) {
    //   _reading = DailyReading.fromJson(
    //       jsonDecode(cached) as Map<String, dynamic>);
    //   notifyListeners();
    //   return;
    // }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _reading = await ApiService.fetchDailyReading(profile);
      // Cache the reading for today
      await StorageService.cacheReading(jsonEncode({
        'date': _reading!.date,
        'reading': _reading!.reading,
        'focusAreas': _reading!.focusAreas
            .map((fa) => {
                  'label': fa.label,
                  'icon': fa.icon,
                  'level': fa.level,
                })
            .toList(),
        'transitSummary': _reading!.transitSummary,
      }));
    } catch (e) {
      _error = 'Could not fetch your reading. Please try again.';
      debugPrint('Error fetching reading: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
