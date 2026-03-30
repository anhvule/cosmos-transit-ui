import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_profile.dart';

class StorageService {
  static const String _profileBox = 'profile';
  static const String _cacheBox = 'cache';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserProfileAdapter());
    await Hive.openBox<UserProfile>(_profileBox);
    await Hive.openBox<String>(_cacheBox);
  }

  static UserProfile? getProfile() {
    final box = Hive.box<UserProfile>(_profileBox);
    return box.get('current');
  }

  static Future<void> saveProfile(UserProfile profile) async {
    final box = Hive.box<UserProfile>(_profileBox);
    await box.put('current', profile);
  }

  static String? getCachedReading() {
    final box = Hive.box<String>(_cacheBox);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return box.get('reading_$today');
  }

  static Future<void> cacheReading(String readingJson) async {
    final box = Hive.box<String>(_cacheBox);
    final today = DateTime.now().toIso8601String().substring(0, 10);
    await box.put('reading_$today', readingJson);
  }

  static bool get isOnboarded => getProfile() != null;
}
