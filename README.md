# CosmicTransit

A Flutter (iOS-only) app delivering Vedic-astrology readings and a speculative-market-signal feature built on famous investors' natal charts.

## Features

- Daily/monthly/yearly astrological predictions (career, relationship, advice, food)
- Investment forecasts (weekly/monthly) and a Vimshottari Dasha timeline with a yearly caution forecast
- Weekly market signal aggregated across bundled investor charts (Druckenmiller / Ackman / Soros)
- Vedic wealth analysis (lagna, nakshatra, house analysis, hora, yogas)
- Numerology "essence cycle" reports
- Multiple saved profiles per device, with per-profile topic filtering
- Favourites — bookmarkable transit dates with notes, synced per-device via a server-side key

## Getting started

```bash
flutter pub get
flutter run
```

The app talks to an external prediction API (see `PredictionApiService` in [lib/services/prediction_api_service.dart](lib/services/prediction_api_service.dart)); there's no local backend to stand up.

## Project structure

```
lib/
  main.dart            # entry point; home screen is PredictionsScreen
  models/               # data models (API DTOs + the one Hive-persisted model, UserProfile)
  providers/             # ReadingProvider (legacy daily-reading state)
  services/              # API clients, local cache, Hive storage, notifications
  screens/                # one directory per feature screen
  widgets/                # shared widgets
```

See [CLAUDE.md](CLAUDE.md) for a deeper architecture overview (caching scheme, dual-backend setup, storage/profile model) aimed at AI coding assistants working in this repo.
