# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

CosmicTransit — a Flutter app (package name `cosmictransit`) delivering Vedic-astrology readings (daily/monthly/yearly predictions, Vimshottari dasha, numerology "essence cycle", wealth analysis) plus a speculative-market-signal feature built on famous investors' natal charts. iOS-only (no `android/` directory).

## Commands

```bash
flutter pub get                     # install dependencies
flutter run                         # run on connected device/simulator
flutter analyze                     # static analysis (flutter_lints)
flutter test                        # run all tests
flutter test test/widget_test.dart  # run a single test file

# After changing a @HiveType model (e.g. lib/models/user_profile.dart),
# regenerate the *.g.dart adapter:
dart run build_runner build --delete-conflicting-outputs

# Regenerate iOS launcher icons from assets/app_icon.png:
dart run flutter_launcher_icons
```

## Architecture

**State management:** screens call service classes directly and manage their own `StatefulWidget` state; there is no app-wide provider (the legacy `ReadingProvider` flow was removed).

**Backend client:**
- `PredictionApiService` ([lib/services/prediction_api_service.dart](lib/services/prediction_api_service.dart)) — the real backend (Heroku), backs every current screen: career/relationship/advice/food predictions, investment forecasts, dasha, yearly summary, monthly prediction, wealth analysis, essence cycle, market signal, and the favourites CRUD endpoints. Each fetch method follows the same shape: check `ApiCacheService` unless `forceRefresh`, POST/GET, decode, write-through cache, return a typed model.

**Entry point / navigation:** [lib/main.dart](lib/main.dart) sets `home:` directly to `PredictionsScreen`, which is the real hub screen (~1600 lines) containing tabs/menu rows that push to every feature screen (dasha, investment forecast, yearly, wealth, essence cycle, market signal, favourites, profiles).

**Caching (`ApiCacheService`, [lib/services/api_cache_service.dart](lib/services/api_cache_service.dart)):** period-scoped local cache over the Hive `cache` box. Cache keys encode a bucket (`d:<today>` / `w:<monday>` / `m:<YYYY-MM>`) so entries auto-expire when the period rolls; `sweepStaleEntries()` (called on app start) purges unreachable keys. A module-level `_cacheVersion` constant is bumped whenever a backend response-shape/bug fix would make old cached values wrong — this forces a one-time full-cache eviction. When changing what a `PredictionApiService` endpoint returns, bump `_cacheVersion` (or add a payload `_schema` field, as `fetchMonthlyPrediction` does) rather than relying on natural cache expiry.

**Local persistence (`StorageService`, [lib/services/storage_service.dart](lib/services/storage_service.dart)):** Hive-backed. Supports multiple saved profiles in the `profile` box (keyed by random hex id), with the active profile's id stored in the `cache` box. `getProfile()` is the single read path the rest of the app uses for "the current user". A legacy single-profile install (`'current'` key) is migrated to the id-keyed layout on first read. `getDeviceKey()` generates and persists a random per-install id used as `userKey` to scope server-side favourites (no auth system exists).

**Models:** plain Dart classes with `fromJson`/`toJson` for API models; `UserProfile` is the only Hive-persisted model (`@HiveType(typeId: 0)` in [lib/models/user_profile.dart](lib/models/user_profile.dart), generated adapter in `user_profile.g.dart`). New `@HiveField` additions must default sensibly for older persisted rows (see the `timezone`/`topics` field comments) since there's no migration system beyond that convention.

**Timezone convention:** `timezone` is always a numeric UTC offset in hours (e.g. `7`, `-5`), not an IANA name — the backend resolver maps it to a fixed-offset zone.
