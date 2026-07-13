import 'dart:math';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_profile.dart';

/// Local persistence layer.
///
/// Profiles
/// --------
/// The app supports multiple saved profiles (so a single device can quickly
/// switch between e.g. self / partner / parent without re-typing birth data).
/// Each profile lives in the `profile` Hive box keyed by a random-hex id.
/// The id of the currently-active profile is stored in the `cache` box
/// under `active_profile_id`.
///
/// `getProfile()` returns the active profile and is the single read path
/// the rest of the app uses. The pre-existing 'current' key (single-profile
/// world) is migrated to a fresh id on first read so old installs keep
/// working without losing data.
class StorageService {
  static const String _profileBox = 'profile';
  static const String _cacheBox = 'cache';
  // Cache box doubles as a key/value store for app-wide singletons —
  // currently the device key used to scope server-side favourites and the
  // active-profile pointer for the multi-profile feature.
  static const String _deviceKeyKey = 'device_key';
  static const String _activeProfileIdKey = 'active_profile_id';
  // Legacy single-profile key. Read on first multi-profile access and
  // migrated to a generated id; never written to again.
  static const String _legacyProfileKey = 'current';

  static Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(UserProfileAdapter());
    await Hive.openBox<UserProfile>(_profileBox);
    await Hive.openBox<String>(_cacheBox);
    // Run the legacy migration synchronously so subsequent reads see the
    // canonical (id-keyed) layout.
    _migrateLegacyProfileIfPresent();
  }

  /// Stable opaque identifier for this install. Generated once on first call
  /// and cached in Hive — survives app restarts but not reinstalls. Used
  /// purely as a `userKey` to scope server-side favourites; if it's lost,
  /// the rows it owns become unreachable (acceptable trade-off for a no-auth
  /// feature).
  ///
  /// 16 bytes of crypto-strong randomness encoded as 32 hex chars (~UUID
  /// strength) — no extra package needed.
  static String getDeviceKey() {
    final box = Hive.box<String>(_cacheBox);
    final existing = box.get(_deviceKeyKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final hex = _randomHexId();
    box.put(_deviceKeyKey, hex);
    return hex;
  }

  // ─── Profiles (multi) ──────────────────────────────────────────────────

  /// Active profile, or null if the user hasn't onboarded yet.
  static UserProfile? getProfile() {
    final cache = Hive.box<String>(_cacheBox);
    final profiles = Hive.box<UserProfile>(_profileBox);
    final activeId = cache.get(_activeProfileIdKey);
    if (activeId != null) {
      final p = profiles.get(activeId);
      if (p != null) return p;
    }
    // No active id (or it points to a deleted row): fall back to the first
    // profile in insertion order. Keeps the app usable if the active id
    // gets out of sync.
    return profiles.values.isNotEmpty ? profiles.values.first : null;
  }

  /// All saved profiles, paired with their ids so callers can switch/delete.
  static List<MapEntry<String, UserProfile>> getAllProfiles() {
    final box = Hive.box<UserProfile>(_profileBox);
    return box.keys
        .whereType<String>()
        .map((k) => MapEntry(k, box.get(k)!))
        .toList();
  }

  /// Id of the active profile (or null if none).
  static String? getActiveProfileId() {
    return Hive.box<String>(_cacheBox).get(_activeProfileIdKey);
  }

  /// Add a new profile. Returns the newly-assigned id. The new profile
  /// becomes active by default — saving a profile is almost always
  /// followed by wanting to use it.
  static Future<String> addProfile(UserProfile profile,
      {bool makeActive = true}) async {
    final box = Hive.box<UserProfile>(_profileBox);
    final id = _randomHexId();
    await box.put(id, profile);
    if (makeActive) {
      await Hive.box<String>(_cacheBox).put(_activeProfileIdKey, id);
    }
    return id;
  }

  /// Update an existing profile in place by id. No-op if the id isn't found.
  static Future<void> updateProfile(String id, UserProfile profile) async {
    final box = Hive.box<UserProfile>(_profileBox);
    if (!box.containsKey(id)) return;
    await box.put(id, profile);
  }

  /// Switch which profile the rest of the app reads.
  static Future<void> setActiveProfileId(String id) async {
    await Hive.box<String>(_cacheBox).put(_activeProfileIdKey, id);
  }

  /// Delete a saved profile. If it was active, the active pointer falls
  /// back to the first remaining profile (or clears if none left).
  static Future<void> deleteProfile(String id) async {
    final box = Hive.box<UserProfile>(_profileBox);
    final cache = Hive.box<String>(_cacheBox);
    await box.delete(id);
    if (cache.get(_activeProfileIdKey) == id) {
      final remaining = box.keys.whereType<String>().toList();
      if (remaining.isEmpty) {
        await cache.delete(_activeProfileIdKey);
      } else {
        await cache.put(_activeProfileIdKey, remaining.first);
      }
    }
  }

  /// Backward-compat shim for callers that just want to "save the profile":
  /// updates the active one, or adds a new one if there's no active.
  static Future<void> saveProfile(UserProfile profile) async {
    final activeId = getActiveProfileId();
    if (activeId != null && Hive.box<UserProfile>(_profileBox).containsKey(activeId)) {
      await updateProfile(activeId, profile);
    } else {
      await addProfile(profile);
    }
  }

  // ─── Reading cache (unchanged) ─────────────────────────────────────────

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

  // ─── Internals ─────────────────────────────────────────────────────────

  /// Migrate a pre-existing 'current' profile (single-profile world) to a
  /// generated id so the rest of the app sees the canonical layout. Runs
  /// once on first launch after upgrade; idempotent.
  static void _migrateLegacyProfileIfPresent() {
    final profiles = Hive.box<UserProfile>(_profileBox);
    final cache = Hive.box<String>(_cacheBox);
    if (cache.get(_activeProfileIdKey) != null) return;
    final legacy = profiles.get(_legacyProfileKey);
    if (legacy == null) return;
    final id = _randomHexId();
    profiles.put(id, legacy);
    profiles.delete(_legacyProfileKey);
    cache.put(_activeProfileIdKey, id);
  }

  static String _randomHexId() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
