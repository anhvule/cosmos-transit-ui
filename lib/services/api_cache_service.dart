import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// How long a cached response stays valid before the next sweep evicts it.
///
/// * [daily]  — valid until local midnight (today's calendar date).
/// * [weekly] — valid until the ISO week rolls (Monday of this week).
/// * [monthly] — valid until the calendar month rolls (YYYY-MM).
enum CacheScope { daily, weekly, monthly }

/// Lightweight period-scoped cache for API responses, backed by the Hive
/// `cache` box opened in [StorageService.init].
///
/// Entries auto-expire when the scope bucket rolls over: the bucket label
/// (today's date / this week's Monday / this month) is encoded into the
/// key, so the next period produces a different key and the old entry is
/// unreachable. [sweepStaleEntries] purges the unreachable keys on app
/// start.
class ApiCacheService {
  static const String _boxName = 'cache';
  static const String _keyPrefix = 'api:';

  /// Bump this when the API contract changes in a way that would make
  /// cached entries stale (e.g. backend bug fix that alters response
  /// values for the same inputs). All entries not matching the current
  /// version are evicted by [sweepStaleEntries] on app start.
  ///
  /// History:
  ///   v1 — initial cache release.
  ///   v2 — backend essence-cycle off-by-one transit fix + shifted
  ///        duality convention (commits 84d0b5a, 544b51a). Older
  ///        entries hold the buggy values and must be invalidated.
  static const String _cacheVersion = 'v2';

  static Box<String> get _box => Hive.box<String>(_boxName);

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _pad4(int n) => n.toString().padLeft(4, '0');

  static String _todayLocal() {
    final now = DateTime.now();
    return '${_pad4(now.year)}-${_pad2(now.month)}-${_pad2(now.day)}';
  }

  /// Monday-on-or-before today, ISO-week style (weekday 1..7, Mon..Sun).
  static String _weekBucketLocal() {
    final now = DateTime.now();
    final monday =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return '${_pad4(monday.year)}-${_pad2(monday.month)}-${_pad2(monday.day)}';
  }

  static String _monthBucketLocal() {
    final now = DateTime.now();
    return '${_pad4(now.year)}-${_pad2(now.month)}';
  }

  static String _bucketFor(CacheScope scope) {
    switch (scope) {
      case CacheScope.daily:
        return 'd:${_todayLocal()}';
      case CacheScope.weekly:
        return 'w:${_weekBucketLocal()}';
      case CacheScope.monthly:
        return 'm:${_monthBucketLocal()}';
    }
  }

  /// Deterministic short identifier from any request payload. Sorted keys
  /// so map iteration order can't cause a miss for equal requests.
  static String _inputHash(Map<String, dynamic> payload) {
    final sorted = Map.fromEntries(
      payload.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key)),
    );
    return jsonEncode(sorted).hashCode.toRadixString(16);
  }

  static String _keyFor(
    String endpoint,
    Map<String, dynamic> payload,
    CacheScope scope,
  ) =>
      '$_keyPrefix$_cacheVersion:$endpoint:${_bucketFor(scope)}:${_inputHash(payload)}';

  /// Returns the cached decoded JSON for the current scope bucket, or null.
  static Map<String, dynamic>? read(
    String endpoint,
    Map<String, dynamic> payload, {
    CacheScope scope = CacheScope.daily,
  }) {
    try {
      final v = _box.get(_keyFor(endpoint, payload, scope));
      if (v == null) return null;
      return jsonDecode(v) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('ApiCacheService.read error: $e');
      return null;
    }
  }

  /// Stores the decoded JSON response under the current scope bucket.
  static Future<void> write(
    String endpoint,
    Map<String, dynamic> payload,
    Map<String, dynamic> response, {
    CacheScope scope = CacheScope.daily,
  }) async {
    try {
      await _box.put(_keyFor(endpoint, payload, scope), jsonEncode(response));
    } catch (e) {
      debugPrint('ApiCacheService.write error: $e');
    }
  }

  /// One-time hard reset of every `api:` entry the first time the app
  /// runs at a given cache version. Belt-and-suspenders so a backend
  /// bug fix can't be masked by client-side caching.
  static const String _migrationKey = '__api_cache_migration__';

  static Future<void> _migrateForCurrentVersion() async {
    try {
      final completed = _box.get(_migrationKey);
      if (completed == _cacheVersion) return;
      final toDelete = _box.keys
          .whereType<String>()
          .where((k) => k.startsWith(_keyPrefix))
          .toList();
      if (toDelete.isNotEmpty) {
        await _box.deleteAll(toDelete);
        debugPrint(
            'ApiCacheService: cleared ${toDelete.length} entries for migration → $_cacheVersion');
      }
      await _box.put(_migrationKey, _cacheVersion);
    } catch (e) {
      debugPrint('ApiCacheService._migrateForCurrentVersion error: $e');
    }
  }

  /// Removes any `api:` entries that either belong to an older cache
  /// version OR whose encoded bucket no longer matches the current
  /// equivalent (today / this week / this month). Cheap prefix scan.
  /// Also runs the one-time version migration before the per-key sweep.
  static Future<void> sweepStaleEntries() async {
    await _migrateForCurrentVersion();
    try {
      final currentDaily = _bucketFor(CacheScope.daily);
      final currentWeekly = _bucketFor(CacheScope.weekly);
      final currentMonthly = _bucketFor(CacheScope.monthly);
      final toDelete = <dynamic>[];
      for (final key in _box.keys) {
        if (key is! String) continue;
        if (!key.startsWith(_keyPrefix)) continue;
        // Versioned key shape:    api:<ver>:<endpoint>:<scope:bucket>:<hash>
        // Pre-version (legacy):   api:<endpoint>:<scope:bucket>:<hash>
        final parts = key.split(':');
        // Detect & evict legacy (pre-version) entries — they always have
        // exactly 5 chunks where parts[1] is the endpoint name (not "vN").
        final isVersioned = parts.length >= 2 && parts[1].startsWith('v');
        if (!isVersioned) {
          toDelete.add(key);
          continue;
        }
        // Versioned key needs at least 6 chunks: api:vN:endpoint:scope:bucket:hash
        if (parts.length < 6) {
          toDelete.add(key);
          continue;
        }
        // Different version → stale, drop it.
        if (parts[1] != _cacheVersion) {
          toDelete.add(key);
          continue;
        }
        final scopeMarker = parts[3];
        final bucket = '${parts[3]}:${parts[4]}';
        String current;
        switch (scopeMarker) {
          case 'd':
            current = currentDaily;
            break;
          case 'w':
            current = currentWeekly;
            break;
          case 'm':
            current = currentMonthly;
            break;
          default:
            // Unknown scope — drop conservatively.
            toDelete.add(key);
            continue;
        }
        if (bucket != current) toDelete.add(key);
      }
      if (toDelete.isNotEmpty) {
        await _box.deleteAll(toDelete);
        debugPrint('ApiCacheService: swept ${toDelete.length} stale entries.');
      }
    } catch (e) {
      debugPrint('ApiCacheService.sweepStaleEntries error: $e');
    }
  }

  /// Manual clear — useful if the user wants to force a refresh.
  static Future<void> clearAll() async {
    try {
      final toDelete = _box.keys
          .whereType<String>()
          .where((k) => k.startsWith(_keyPrefix))
          .toList();
      await _box.deleteAll(toDelete);
    } catch (e) {
      debugPrint('ApiCacheService.clearAll error: $e');
    }
  }
}
