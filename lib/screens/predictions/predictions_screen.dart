import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../../models/prediction_reading.dart';
import '../../models/dasha_reading.dart';
import '../../services/prediction_api_service.dart';
import '../../services/storage_service.dart';
import '../investment_forecast/investment_forecast_screen.dart';
import '../market_signal/market_signal_screen.dart';
import '../dasha/dasha_screen.dart';
import '../essence_cycle/essence_cycle_screen.dart';
import '../yearly/yearly_screen.dart';
import '../wealth/wealth_analysis_screen.dart';
import '../favourites/favourites_screen.dart';
import '../profiles/profiles_screen.dart';
import '../../widgets/cosmic_loader.dart';

/// One autocomplete suggestion returned by the Photon (OpenStreetMap) API.
/// Carries the coordinates inline so selecting a suggestion populates the
/// hidden lat/lng controllers without a second network round-trip.
class _PlaceSuggestion {
  final String displayName;
  final double latitude;
  final double longitude;

  const _PlaceSuggestion(this.displayName, this.latitude, this.longitude);

  @override
  String toString() => displayName;
}

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen>
    with TickerProviderStateMixin {
  // Mutable so we can recreate the controller when the active profile's
  // topic set changes (different number of tabs).
  late TabController _tabController;
  // Tabs/tab views derive from this filtered list — defaults to every
  // PredictionArea but trimmed when the active profile picks a subset.
  late List<PredictionArea> _visibleAreas;

  // Default inputs per spec
  final _nameController = TextEditingController(text: 'Astrologer');
  DateTime _birthDate = DateTime(1991, 12, 29);
  TimeOfDay _birthTime = const TimeOfDay(hour: 13, minute: 30);
  final _cityController = TextEditingController(text: 'Ho Chi Minh City');
  final _latitudeController = TextEditingController(text: '10.7765713');
  final _longitudeController = TextEditingController(text: '106.7012093');
  // Timezone is a numeric UTC offset in hours (e.g. 7 for Vietnam, -5 for
  // US Eastern). Backend accepts integers in [-12, 14]; fractional offsets
  // are not supported yet.
  final _timezoneController = TextEditingController(text: '7');
  String? _timezoneError;
  DateTime _transitDate = _todayDateOnly();

  // City → lat/lng geocoding state. `_lastGeocodedCity` lets us avoid
  // re-running the lookup on every fetch when the city hasn't changed.
  // Initialized to the default city above so the first fetch doesn't try
  // to re-geocode "Ho Chi Minh City" (lat/lng already match it).
  bool _geocoding = false;
  String? _cityError;
  String _lastGeocodedCity = 'Ho Chi Minh City';

  // Latest in-flight autocomplete query — when the user keeps typing, we
  // discard stale Photon responses by checking that the query for which a
  // result arrived still matches the one the user is on.
  String _latestSearchQuery = '';

  // External controller + focus node so RawAutocomplete uses our existing
  // _cityController. (The basic Autocomplete widget owns its own controller
  // internally, which makes pre-fill from saved profile awkward to keep
  // in sync.)
  late final FocusNode _cityFocusNode;

  static DateTime _todayDateOnly() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// Derive the list of PredictionAreas this screen should render tabs
  /// for, based on the active profile's topic preferences. An empty
  /// `topics` list (legacy default) means "show everything".
  List<PredictionArea> _computeVisibleAreas() {
    final profile = StorageService.getProfile();
    final picks = profile?.topics ?? const <String>[];
    if (picks.isEmpty) return PredictionArea.values;
    final pickSet = picks.toSet();
    final filtered = PredictionArea.values
        .where((a) => pickSet.contains(a.name))
        .toList();
    // Defensive: never present zero tabs — fall back to all if a profile
    // somehow ended up with an empty-but-explicit selection.
    return filtered.isEmpty ? PredictionArea.values : filtered;
  }

  /// Recompute visible tabs after the active profile changes and rebuild
  /// the TabController to match the new length. Discards per-tab state
  /// for areas that are no longer visible.
  void _rebuildTabsForActiveProfile() {
    final next = _computeVisibleAreas();
    final sameSet = next.length == _visibleAreas.length &&
        next.every((a) => _visibleAreas.contains(a));
    if (sameSet) return;
    _tabController.dispose();
    setState(() {
      _visibleAreas = next;
      // +1 for the trailing "Current Dasha" tab, which is always present.
      _tabController = TabController(length: next.length + 1, vsync: this);
      // Drop cached results/errors for areas the user no longer wants —
      // saves memory and avoids surfacing stale data if they re-enable.
      final keep = next.toSet();
      _results.removeWhere((k, _) => !keep.contains(k));
      _errors.removeWhere((k, _) => !keep.contains(k));
      _loading.removeWhere((k, _) => !keep.contains(k));
    });
  }

  // Per-tab state
  final Map<PredictionArea, PredictionReading?> _results = {};
  final Map<PredictionArea, String?> _errors = {};
  final Map<PredictionArea, bool> _loading = {};

  // ── Dasha tab state ────────────────────────────────────────────────────
  // The "Current Dasha" tab lives alongside the PredictionArea tabs but
  // pulls from /api/dasha (different shape — not a PredictionReading), so
  // we keep its loading/result/error state in dedicated fields rather than
  // trying to wedge it into the PredictionArea-keyed maps.
  DashaReading? _dashaResult;
  String? _dashaError;
  bool _dashaLoading = false;

  // Collapsible panel state — default expanded so user sees inputs on first run
  bool _formExpanded = true;

  @override
  void initState() {
    super.initState();
    _visibleAreas = _computeVisibleAreas();
    // +1 for the trailing "Current Dasha" tab.
    _tabController =
        TabController(length: _visibleAreas.length + 1, vsync: this);
    _cityFocusNode = FocusNode();
    // Pre-fill fields from the saved profile (set during onboarding) so the
    // user doesn't have to re-type their birth details on every launch.
    // Falls back to the hardcoded defaults if onboarding hasn't run.
    final profile = StorageService.getProfile();
    if (profile != null) {
      _nameController.text = profile.name;
      _birthDate = profile.birthDate;
      // birthTime is stored as "HH:mm" — parse it back into a TimeOfDay.
      final parts = profile.birthTime.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          _birthTime = TimeOfDay(hour: h, minute: m);
        }
      }
      _cityController.text = profile.birthCity;
      _latitudeController.text = profile.latitude.toStringAsFixed(7);
      _longitudeController.text = profile.longitude.toStringAsFixed(7);
      // Treat the profile's city as already geocoded so we don't re-lookup
      // on first fetch.
      _lastGeocodedCity = profile.birthCity;
      // Profile carries its own UTC offset — preload it so the user
      // doesn't have to reset it for every saved chart.
      _timezoneController.text = profile.timezone.toString();
    }
    // Auto-fetch once on first load
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _cityController.dispose();
    _cityFocusNode.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  /// Geocode the user-entered city to latitude/longitude using the
  /// `geocoding` package and write the result back into the lat/lng
  /// controllers. Same approach the onboarding screen uses.
  Future<void> _lookupCity() async {
    final city = _cityController.text.trim();
    if (city.isEmpty) {
      setState(() => _cityError = 'Enter a city name first.');
      return;
    }
    setState(() {
      _geocoding = true;
      _cityError = null;
    });
    try {
      final locations = await locationFromAddress(city);
      if (!mounted) return;
      if (locations.isEmpty) {
        setState(() {
          _geocoding = false;
          _cityError = 'City not found. Try a different spelling.';
        });
        return;
      }
      final loc = locations.first;
      setState(() {
        _latitudeController.text = loc.latitude.toStringAsFixed(7);
        _longitudeController.text = loc.longitude.toStringAsFixed(7);
        _geocoding = false;
        _lastGeocodedCity = city;
      });
      _showCoordinatesAlert(city, loc.latitude, loc.longitude);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geocoding = false;
        _cityError = 'Lookup failed: ${e.toString()}';
      });
    }
  }

  /// Query Photon (https://photon.komoot.io) for city/place suggestions
  /// matching `query`. Free, no API key, returns coordinates inline. Returns
  /// an empty list for short queries, network errors, or stale results
  /// (when the user has typed more characters since this call started).
  Future<Iterable<_PlaceSuggestion>> _searchPlaces(String query) async {
    final q = query.trim();
    _latestSearchQuery = q;
    if (q.length < 2) return const [];
    // Small debounce — with the per-keystroke optionsBuilder calls Flutter
    // makes, this collapses bursts into one in-flight request.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (q != _latestSearchQuery) return const [];
    try {
      final url = Uri.parse(
        'https://photon.komoot.io/api/'
        '?q=${Uri.encodeQueryComponent(q)}'
        '&limit=8&lang=en',
      );
      // Komoot's Photon blocks requests sent with the default Dart
      // User-Agent (Dart/x.y (dart:io)) — they require a meaningful UA per
      // their fair-use policy. Identify the app explicitly.
      final res = await http.get(
        url,
        headers: const {
          'User-Agent':
              'CosmicTransit/1.0 (https://github.com/anhvule/cosmos-transit-ui)',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));
      if (q != _latestSearchQuery) return const [];
      if (res.statusCode != 200) return const [];
      final body = jsonDecode(res.body);
      final features = (body is Map && body['features'] is List)
          ? body['features'] as List
          : const [];
      // Filter to actual place-type results (city/town/village/county/
      // state/country). Photon's "office", "amenity", "house", etc. matches
      // are noisy for a birth-city picker.
      const placeKeys = {'place', 'boundary'};
      const placeTypes = {
        'city',
        'town',
        'village',
        'hamlet',
        'municipality',
        'county',
        'state',
        'region',
        'province',
        'country',
        'administrative',
      };
      final results = <_PlaceSuggestion>[];
      for (final f in features) {
        if (f is! Map) continue;
        final geometry = f['geometry'];
        final properties = f['properties'];
        if (geometry is! Map || properties is! Map) continue;
        final osmKey = (properties['osm_key'] ?? '').toString();
        final type = (properties['type'] ?? '').toString();
        // Reject non-place results.
        if (!placeKeys.contains(osmKey) && !placeTypes.contains(type)) {
          continue;
        }
        final coords = geometry['coordinates'];
        if (coords is! List || coords.length < 2) continue;
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lng == null || lat == null) continue;
        // Build a friendly display name: "Name, State, Country".
        final name = (properties['name'] ?? '').toString();
        if (name.isEmpty) continue;
        final state = (properties['state'] ?? '').toString();
        final country = (properties['country'] ?? '').toString();
        final parts = <String>[name];
        if (state.isNotEmpty && state != name) parts.add(state);
        if (country.isNotEmpty) parts.add(country);
        results.add(_PlaceSuggestion(parts.join(', '), lat, lng));
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Pop a confirmation dialog after a successful geocode so the user can
  /// see the coordinates that will be sent to the API.
  void _showCoordinatesAlert(String city, double lat, double lng) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1745),
        title: const Text(
          'Coordinates updated',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              city,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Latitude:  ${lat.toStringAsFixed(7)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'Longitude: ${lng.toStringAsFixed(7)}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF7C4DFF),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  PredictionRequest? _buildRequest() {
    final lat = double.tryParse(_latitudeController.text.trim());
    final lng = double.tryParse(_longitudeController.text.trim());
    if (lat == null || lng == null) return null;
    if (_nameController.text.trim().isEmpty) return null;
    final tz = _parseTimezone(_timezoneController.text);
    if (tz == null) return null;
    return PredictionRequest(
      name: _nameController.text.trim(),
      birthDate: _formatDate(_birthDate),
      birthTime: _formatTime(_birthTime),
      latitude: lat,
      longitude: lng,
      timezone: tz,
      transitDate: _formatDate(_transitDate),
    );
  }

  /// Parse the timezone field as a signed integer UTC offset in [-12, 14].
  /// Strips a leading '+' so "+7" works. Updates `_timezoneError` for the
  /// form to render; returns null on invalid input.
  int? _parseTimezone(String raw) {
    final trimmed = raw.trim().replaceFirst(RegExp(r'^\+'), '');
    if (trimmed.isEmpty) {
      _timezoneError = 'Required';
      return null;
    }
    final n = int.tryParse(trimmed);
    if (n == null) {
      _timezoneError = 'Whole number only (e.g. 7)';
      return null;
    }
    if (n < -12 || n > 14) {
      _timezoneError = 'Range -12 to 14';
      return null;
    }
    _timezoneError = null;
    return n;
  }

  void _openDasha() {
    final req = _buildRequest();
    if (req == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DashaScreen(request: req)),
    );
  }

  void _openEssenceCycle() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EssenceCycleScreen(
        initialFullName: _nameController.text.trim(),
        initialDob: _formatDate(_birthDate),
        initialStartYear: DateTime.now().year,
      ),
    ));
  }

  void _openYearly() {
    final req = _buildRequest();
    if (req == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => YearlyScreen(
        request: req,
        // Default to the current year — the screen has its own year stepper.
        initialYear: DateTime.now().year,
      ),
    ));
  }

  void _openForecast() {
    final req = _buildRequest();
    if (req == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InvestmentForecastScreen(
        initialInputs: ForecastInputs(
          name: req.name,
          birthDate: req.birthDate,
          birthTime: req.birthTime,
          latitude: req.latitude,
          longitude: req.longitude,
          timezone: req.timezone,
        ),
      ),
    ));
  }

  void _openMarketSignal() {
    // Takes no user inputs — three celebrity natal charts are server-bundled.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MarketSignalScreen()),
    );
  }

  void _openWealth() {
    final req = _buildRequest();
    if (req == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WealthAnalysisScreen(request: req)),
    );
  }

  /// Quick-save the active transit date as a favourite without navigating
  /// away. Pops a tiny dialog for an optional title + a required memory note,
  /// POSTs to /api/favourites with the current `_transitDate`, and confirms
  /// via snackbar. Errors surface inline.
  Future<void> _saveCurrentDateToFavourites() async {
    final entered = await showDialog<_QuickFav>(
      context: context,
      builder: (_) => _QuickSaveFavouriteDialog(date: _transitDate),
    );
    if (!mounted || entered == null) return;
    try {
      await PredictionApiService.createFavourite(
        userKey: StorageService.getDeviceKey(),
        transitDate: _formatDate(_transitDate),
        title: entered.title,
        description: entered.description,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('★ Saved ${_formatDate(_transitDate)} to favourites'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  /// Open the saved-profiles manager. After it returns, reload the form
  /// fields from whichever profile is now active so the user sees the
  /// switch reflected immediately and can fetch predictions for it.
  void _openProfiles() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfilesScreen()),
    );
    if (!mounted) return;
    final profile = StorageService.getProfile();
    if (profile == null) return;
    setState(() {
      _nameController.text = profile.name;
      _birthDate = profile.birthDate;
      final parts = profile.birthTime.split(':');
      if (parts.length == 2) {
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          _birthTime = TimeOfDay(hour: h, minute: m);
        }
      }
      _cityController.text = profile.birthCity;
      _latitudeController.text = profile.latitude.toStringAsFixed(7);
      _longitudeController.text = profile.longitude.toStringAsFixed(7);
      _lastGeocodedCity = profile.birthCity;
      _timezoneController.text = profile.timezone.toString();
      _timezoneError = null;
    });
    // Active profile may have a different topic set — recreate the tab
    // controller / visible areas to match before refetching.
    _rebuildTabsForActiveProfile();
    _fetchAll();
  }

  void _openFavourites() async {
    // Favourites screen returns the picked transit date (YYYY-MM-DD) when
    // the user taps a row — null when they just back out. We then load that
    // date as the active transit date and refetch all 7 prediction tabs.
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FavouritesScreen()),
    );
    if (!mounted || picked == null) return;
    final parts = picked.split('-');
    if (parts.length != 3) return;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return;
    setState(() {
      _transitDate = DateTime(y, m, d);
      // Clear any stale results so the loading indicators show on each tab
      // while the new date's predictions stream in.
      _results.clear();
      _errors.clear();
      _formExpanded = true; // surface the inputs panel so the user sees the date
    });
    await _fetchAll();
  }

  Future<void> _fetchAll({bool forceRefresh = false}) async {
    // If the user typed a new city since the last geocode, derive lat/lng
    // first so they don't have to remember to tap the Find button.
    final city = _cityController.text.trim();
    if (city.isNotEmpty && city != _lastGeocodedCity) {
      await _lookupCity();
      if (_cityError != null) return;
    }
    final req = _buildRequest();
    if (req == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields correctly.')),
      );
      return;
    }
    // Auto-collapse the form after submitting so the reading gets screen space
    // and pre-mark every tab as loading so the user gets immediate feedback
    // (workers below process the queue with bounded concurrency).
    setState(() {
      _formExpanded = false;
      // Only mark the visible tabs as loading — there's no point fetching
      // areas the active profile has filtered out.
      for (final a in _visibleAreas) {
        _loading[a] = true;
        _errors[a] = null;
      }
      _dashaLoading = true;
      _dashaError = null;
    });

    // The free Heroku dyno runs a single Node.js worker that spawns a
    // Python ephemeris process per request. Firing all 7 prediction calls
    // at once queues them on the dyno; the slowest miss Heroku's 30s H12
    // router timeout and all return 503. Cap concurrency so the dyno can
    // finish each request within its router budget.
    const concurrency = 2;
    // Only fetch the topics this profile cares about.
    final queue = List<PredictionArea>.from(_visibleAreas);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final area = queue.removeAt(0);
        await _fetchOne(area, req,
            forceRefresh: forceRefresh, markLoading: false);
      }
    }
    // Run the area workers and the single dasha fetch in parallel — the
    // dasha endpoint runs its own kerykeion call so it doesn't compete
    // for the 2-slot worker pool.
    await Future.wait([
      ...List.generate(concurrency, (_) => worker()),
      _fetchDasha(req, forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _fetchDasha(PredictionRequest req,
      {bool forceRefresh = false}) async {
    try {
      final result =
          await PredictionApiService.fetchDasha(req, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _dashaResult = result;
        _dashaLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dashaError = e.toString();
        _dashaLoading = false;
      });
    }
  }

  IconData _iconFor(PredictionArea a) {
    switch (a) {
      case PredictionArea.career:
        return Icons.work_outline;
      case PredictionArea.relationship:
        return Icons.favorite_outline;
      case PredictionArea.advice:
        return Icons.lightbulb_outline;
      case PredictionArea.food:
        return Icons.restaurant_menu;
    }
  }

  Future<void> _fetchOne(PredictionArea area, PredictionRequest req,
      {bool forceRefresh = false, bool markLoading = true}) async {
    if (markLoading) {
      setState(() {
        _loading[area] = true;
        _errors[area] = null;
      });
    }
    try {
      final result =
          await PredictionApiService.fetch(area, req, forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _results[area] = result;
        _loading[area] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[area] = e.toString();
        _loading[area] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      // SafeArea on all edges so the notch / Dynamic Island (iPhone 16 Pro Max)
      // and the home indicator don't cover content. maintainBottomViewPadding
      // keeps layout stable when the keyboard pushes up.
      // No SafeArea on top/bottom — the form background extends under the
      // Dynamic Island and the ListView scrolls past the home indicator.
      // Top inset is added back as padding inside the collapsible form, and
      // each tab's ListView pads its bottom by the system bottom inset.
      body: SafeArea(
        top: false,
        bottom: false,
        left: true,
        right: true,
        maintainBottomViewPadding: true,
        child: Column(
          children: [
            _buildCollapsibleForm(),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorColor: const Color(0xFF7C4DFF),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white54,
              labelPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              tabs: [
                ..._visibleAreas.map((a) => Tab(
                      height: 48,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_iconFor(a), size: 16),
                          const SizedBox(width: 6),
                          Text(a.label),
                        ],
                      ),
                    )),
                // Trailing "Current Dasha" tab — always shown, lives outside
                // the topic-filterable PredictionArea set because it has its
                // own data shape (Vimshottari MD/AD/PD/SD).
                const Tab(
                  height: 48,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome, size: 16),
                      SizedBox(width: 6),
                      Text('Current Dasha'),
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  ..._visibleAreas.map((a) => _buildTab(a)),
                  _buildDashaTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollapsibleForm() {
    final topInset = MediaQuery.of(context).padding.top;
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1745),
      padding: EdgeInsets.only(top: topInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderBar(),
          // AnimatedCrossFade gives a smooth expand/collapse transition.
          AnimatedCrossFade(
            firstChild: _buildFormBody(),
            secondChild: const SizedBox(
                width: double.infinity, height: 0),
            crossFadeState: _formExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar() {
    // Compact summary shown when collapsed; full label when expanded.
    return InkWell(
      onTap: () => setState(() => _formExpanded = !_formExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.tune, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: _formExpanded
                  ? const Text(
                      'Hello Dear',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    )
                  : Text(
                      '${_nameController.text.trim().isEmpty ? "—" : _nameController.text.trim()} · ${_formatDate(_transitDate)}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
            ),
            // Quick-save the active transit date to favourites without leaving
            // the predictions screen — opens a small dialog for title + memory.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _saveCurrentDateToFavourites,
              child: const Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Icon(Icons.star_border,
                    color: Colors.white70, size: 22),
              ),
            ),
            if (!_formExpanded)
              // Tap = use cache if fresh; long-press = force refresh.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _fetchAll(),
                onLongPress: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Bypassing cache — refetching…'),
                        duration: Duration(seconds: 1)),
                  );
                  _fetchAll(forceRefresh: true);
                },
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Icon(Icons.refresh,
                      color: Colors.white70, size: 20),
                ),
              ),
            PopupMenuButton<_NavTarget>(
              tooltip: 'More',
              icon: const Icon(Icons.more_vert,
                  color: Colors.white70, size: 20),
              padding: EdgeInsets.zero,
              color: const Color(0xFF1F1B4F),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12)),
              ),
              onSelected: (target) {
                switch (target) {
                  case _NavTarget.essenceCycle:
                    _openEssenceCycle();
                    break;
                  case _NavTarget.dasha:
                    _openDasha();
                    break;
                  case _NavTarget.investmentForecast:
                    _openForecast();
                    break;
                  case _NavTarget.marketSignal:
                    _openMarketSignal();
                    break;
                  case _NavTarget.varshaphal:
                    _openYearly();
                    break;
                  case _NavTarget.wealth:
                    _openWealth();
                    break;
                  case _NavTarget.favourites:
                    _openFavourites();
                    break;
                  case _NavTarget.profiles:
                    _openProfiles();
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _NavTarget.essenceCycle,
                  child: _MenuRow(
                      icon: Icons.timeline, label: 'Essence Cycle'),
                ),
                PopupMenuItem(
                  value: _NavTarget.dasha,
                  child: _MenuRow(
                      icon: Icons.auto_awesome,
                      label: 'Vimshottari Dasha'),
                ),
                PopupMenuItem(
                  value: _NavTarget.investmentForecast,
                  child: _MenuRow(
                      icon: Icons.insights,
                      label: 'Investment Forecast'),
                ),
                PopupMenuItem(
                  value: _NavTarget.marketSignal,
                  child: _MenuRow(
                      icon: Icons.show_chart,
                      label: 'Market Signal (Weekly)'),
                ),
                PopupMenuItem(
                  value: _NavTarget.varshaphal,
                  child: _MenuRow(
                      icon: Icons.calendar_today_outlined,
                      label: 'Varshaphal (Yearly)'),
                ),
                PopupMenuItem(
                  value: _NavTarget.wealth,
                  child: _MenuRow(
                      icon: Icons.diamond_outlined,
                      label: 'Wealth Analysis'),
                ),
                PopupMenuItem(
                  value: _NavTarget.favourites,
                  child: _MenuRow(
                      icon: Icons.favorite_outline,
                      label: 'Favourites'),
                ),
                PopupMenuItem(
                  value: _NavTarget.profiles,
                  child: _MenuRow(
                      icon: Icons.people_outline,
                      label: 'Saved Profiles'),
                ),
              ],
            ),
            AnimatedRotation(
              turns: _formExpanded ? 0.5 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: const Icon(Icons.expand_more, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormBody() {
    // Top padding gives the floating Material labels (Name / UTC offset)
    // room above the field so they aren't clipped by the header bar
    // sitting directly above.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _textField('Name', _nameController)),
              const SizedBox(width: 8),
              Expanded(
                child: _textField(
                  'UTC offset (h)',
                  _timezoneController,
                  keyboard: const TextInputType.numberWithOptions(signed: true),
                  errorText: _timezoneError,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Birth City row — autocomplete pulls suggestions from Photon
          // (OpenStreetMap) so the user can type "Ho" and pick "Ho Chi Minh
          // City, Vietnam" from a dropdown. Selecting a suggestion fills the
          // hidden lat/lng controllers from the response, no second call.
          // The "Find" button stays as a fallback for arbitrary text input.
          Row(
            children: [
              Expanded(
                child: RawAutocomplete<_PlaceSuggestion>(
                  textEditingController: _cityController,
                  focusNode: _cityFocusNode,
                  displayStringForOption: (s) => s.displayName,
                  optionsBuilder: (tev) => _searchPlaces(tev.text),
                  onSelected: (s) {
                    setState(() {
                      _latitudeController.text = s.latitude.toStringAsFixed(7);
                      _longitudeController.text =
                          s.longitude.toStringAsFixed(7);
                      _lastGeocodedCity = s.displayName;
                      _cityError = null;
                    });
                    _showCoordinatesAlert(
                        s.displayName, s.latitude, s.longitude);
                  },
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController controller,
                    FocusNode focusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onSubmitted: (_) => onFieldSubmitted(),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Birth City',
                        labelStyle: const TextStyle(
                            color: Colors.white70, fontSize: 12),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        errorText: _cityError,
                        errorStyle: const TextStyle(fontSize: 11),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: Color(0xFF7C4DFF)),
                        ),
                      ),
                    );
                  },
                  optionsViewBuilder: (context, onSelected, options) {
                    // Darker than the form panel (which sits on 0xFF1A1745)
                    // plus a thin purple border so the dropdown reads as a
                    // distinct floating surface, not a flat continuation of
                    // the field below it.
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        color: const Color(0xFF06041A),
                        elevation: 8,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF7C4DFF)
                                  .withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                          constraints: const BoxConstraints(maxHeight: 240),
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            shrinkWrap: true,
                            itemCount: options.length,
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                            itemBuilder: (context, i) {
                              final s = options.elementAt(i);
                              return InkWell(
                                onTap: () => onSelected(s),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  child: Text(
                                    s.displayName,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _geocoding ? null : _lookupCity,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF7C4DFF).withValues(alpha: 0.85),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _geocoding
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.travel_explore, size: 16),
                  label: const Text('Find',
                      style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'Birth Date',
                  value: DateFormat('yyyy-MM-dd').format(_birthDate),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _birthDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _birthDate = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateTile(
                  label: 'Birth Time',
                  value: _formatTime(_birthTime),
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: _birthTime,
                    );
                    if (t != null) setState(() => _birthTime = t);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _dateTile(
                  label: 'Transit Date',
                  value: DateFormat('yyyy-MM-dd').format(_transitDate),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _transitDate,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _transitDate = d);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _fetchAll,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22)),
              ),
              child: const Text('Get Predictions',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    String? errorText,
  }) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 12),
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        errorText: errorText,
        errorStyle: const TextStyle(fontSize: 11),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
        ),
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(PredictionArea area) {
    final loading = _loading[area] ?? false;
    final error = _errors[area];
    final result = _results[area];

    if (loading) {
      return const Center(
        child: CosmicLoader(message: 'Reading the cosmos...'),
      );
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final req = _buildRequest();
                  if (req != null) _fetchOne(area, req);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (result == null) {
      return const Center(
        child: Text('Tap "Get Predictions" to load.',
            style: TextStyle(color: Colors.white70)),
      );
    }

    if (result.aspects.isEmpty && result.rulers.isEmpty) {
      return Center(
        child: Text(
          'No ${area.label.toLowerCase()} transits on ${result.date}.',
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      children: [
        Text(
          '${area.label} — ${result.date}',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (result.aspects.isNotEmpty) ...[
          const _SectionHeader('Transits'),
          ...result.aspects.map(_buildAspectCard),
          const SizedBox(height: 16),
        ],
        if (result.rulers.isNotEmpty) ...[
          const _SectionHeader('Rulers'),
          ...result.rulers.map(_buildRulerCard),
        ],
      ],
    );
  }

  /// "Current Dasha" tab — renders the active MD/AD/PD/SD plus the
  /// investment-favorable sub-period highlights. Lighter than the dedicated
  /// Vimshottari Dasha screen — no nakshatra header, no progress bars on
  /// individual cards, just the four active periods and a green-flagged
  /// list of upcoming favorable PDs/SDs.
  Widget _buildDashaTab() {
    if (_dashaLoading) {
      return const Center(
        child: CosmicLoader(message: 'Reading the cosmos...'),
      );
    }
    if (_dashaError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(_dashaError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  final req = _buildRequest();
                  if (req != null) _fetchDasha(req);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C4DFF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    final r = _dashaResult;
    if (r == null) {
      return const Center(
        child: Text('Tap "Get Predictions" to load.',
            style: TextStyle(color: Colors.white70)),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      children: [
        Text(
          'Current Dasha — ${r.date}',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          'Nakshatra ${r.nakshatra.name} · Lord ${r.nakshatra.lord}',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
        ),
        const SizedBox(height: 16),
        _DashaTabRow(
            label: 'Mahadasha', sublabel: 'Major', period: r.mahadasha),
        _DashaTabRow(
            label: 'Antardasha', sublabel: 'Sub', period: r.antardasha),
        _DashaTabRow(
            label: 'Pratyantardasha',
            sublabel: 'Sub-sub',
            period: r.pratyantardasha),
        if (r.sookshmadasha != null)
          _DashaTabRow(
              label: 'Sookshmadasha',
              sublabel: 'Sub-sub-sub',
              period: r.sookshmadasha!),
        if (!r.investmentFavorable.isEmpty) ...[
          const SizedBox(height: 16),
          // Empirical-accuracy disclaimer — same framing as the
          // dedicated Vimshottari Dasha screen. Backtests against
          // AMZN and S&P 500 show this model is for personal
          // capital-deployment timing, not market direction.
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Colors.amberAccent.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 1, right: 6),
                  child: Icon(Icons.info_outline,
                      color: Colors.amberAccent, size: 13),
                ),
                Expanded(
                  child: Text(
                    'Personal capital-deployment guidance — backtested at '
                    '~40% market-direction accuracy (AMZN + S&P 500). '
                    'Tracks YOUR fortune cycle, not the index.',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 11,
                        height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _SectionHeader('Favorable Personal Windows'),
          ..._dashaTabFavorables(
              'Antardashas', r.investmentFavorable.antardashas),
          ..._dashaTabFavorables(
              'Pratyantardashas', r.investmentFavorable.pratyantardashas),
          ..._dashaTabFavorables(
              'Sookshmadashas', r.investmentFavorable.sookshmadashas),
        ],
      ],
    );
  }

  List<Widget> _dashaTabFavorables(
      String groupLabel, List<DashaPeriodAnnotated> periods) {
    if (periods.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(
          groupLabel,
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6),
        ),
      ),
      ...periods.map((p) => _FavorableTabCard(period: p)),
    ];
  }

  Widget _buildAspectCard(PredictionAspect a) {
    // Map impact level to visual weight:
    //   * Impactful          → bright orange, thicker/stronger border,
    //                           tinted card background (highest attention).
    //   * Slightly impactful → soft purple, thin/subtle border, neutral bg.
    //   * Positive / Negative → retained legacy semantics if ever returned.
    final impact = (a.impact ?? '').toLowerCase();
    Color impactColor;
    double borderAlpha;
    double borderWidth;
    Color bgColor;
    switch (impact) {
      case 'impactful':
        impactColor = Colors.orangeAccent;
        borderAlpha = 0.65;
        borderWidth = 1.8;
        bgColor = Colors.orangeAccent.withValues(alpha: 0.10);
        break;
      case 'slightly impactful':
        impactColor = const Color(0xFF7C4DFF);
        borderAlpha = 0.30;
        borderWidth = 1.0;
        bgColor = Colors.white.withValues(alpha: 0.04);
        break;
      case 'positive':
      case 'good':
        impactColor = Colors.greenAccent;
        borderAlpha = 0.5;
        borderWidth = 1.2;
        bgColor = Colors.greenAccent.withValues(alpha: 0.08);
        break;
      case 'negative':
      case 'caution':
      case 'bad':
        impactColor = Colors.redAccent;
        borderAlpha = 0.6;
        borderWidth = 1.5;
        bgColor = Colors.redAccent.withValues(alpha: 0.08);
        break;
      default:
        impactColor = const Color(0xFF7C4DFF);
        borderAlpha = 0.4;
        borderWidth = 1.0;
        bgColor = Colors.white.withValues(alpha: 0.05);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: impactColor.withValues(alpha: borderAlpha),
            width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a.description,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
              ),
              if (a.impact != null && a.impact!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: impactColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    a.impact!,
                    style: TextStyle(color: impactColor, fontSize: 11),
                  ),
                ),
            ],
          ),
          if (a.interpretation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              a.interpretation,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRulerCard(PredictionRuler r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.description,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          if (r.interpretation.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              r.interpretation,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Targets for the header-bar overflow menu.
enum _NavTarget {
  essenceCycle,
  dasha,
  investmentForecast,
  marketSignal,
  varshaphal,
  wealth,
  favourites,
  profiles,
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

/// Compact row inside the "Current Dasha" tab — one MD/AD/PD/SD level
/// each. Renders glyph + planet + date range without the heavy progress
/// chrome the dedicated Dasha screen uses.
class _DashaTabRow extends StatelessWidget {
  final String label;
  final String sublabel;
  final DashaPeriod period;

  const _DashaTabRow({
    required this.label,
    required this.sublabel,
    required this.period,
  });

  static const Map<String, String> _glyph = {
    'Sun': '☉',
    'Moon': '☽',
    'Mars': '♂',
    'Mercury': '☿',
    'Jupiter': '♃',
    'Venus': '♀',
    'Saturn': '♄',
    'Rahu': '☊',
    'Ketu': '☋',
  };

  static const Map<String, Color> _color = {
    'Sun': Color(0xFFFFB347),
    'Moon': Color(0xFFB0C4DE),
    'Mars': Color(0xFFFF6B6B),
    'Mercury': Color(0xFF7DD3C0),
    'Jupiter': Color(0xFFFFD700),
    'Venus': Color(0xFFFFB6C1),
    'Saturn': Color(0xFF8B7CB6),
    'Rahu': Color(0xFF6B5B95),
    'Ketu': Color(0xFFB565A7),
  };

  String _fmt(DateTime d) => DateFormat('MMM d, yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4CD27E);
    final color = _color[period.planet] ?? const Color(0xFF7C4DFF);
    final glyph = _glyph[period.planet] ?? '✦';
    final fav = period.favorable;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fav
            ? green.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: fav ? green.withValues(alpha: 0.55) : color.withValues(alpha: 0.4),
            width: fav ? 1.4 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child:
                    Text(glyph, style: TextStyle(color: color, fontSize: 18)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          sublabel,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 10),
                        ),
                        if (fav) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: green.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'GOOD',
                              style: TextStyle(
                                  color: green,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      period.planet,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${_fmt(period.startDate)}  →  ${_fmt(period.endDate)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Surface the first reason inline so the Current Dasha tab is
          // self-contained — users don't need to scroll the dedicated
          // Vimshottari Dasha screen to learn why a period is flagged.
          if (period.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3, right: 6),
                    child: Icon(Icons.check_circle, color: green, size: 12),
                  ),
                  Expanded(
                    child: Text(
                      period.reasons.first,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (period.warnings.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3, right: 6),
                    child: Icon(Icons.warning_amber_rounded,
                        color: Colors.amberAccent, size: 12),
                  ),
                  Expanded(
                    child: Text(
                      period.warnings.first,
                      style: TextStyle(
                          color: Colors.amberAccent.withValues(alpha: 0.92),
                          fontSize: 11.5,
                          height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact favorable-period card for the "Current Dasha" tab — shows the
/// planet, date range, and a bullet list of why the period was flagged.
class _FavorableTabCard extends StatelessWidget {
  final DashaPeriodAnnotated period;
  const _FavorableTabCard({required this.period});

  String _fmt(DateTime d) => DateFormat('MMM d, yyyy').format(d.toLocal());

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF4CD27E);
    final active = period.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: green.withValues(alpha: active ? 0.7 : 0.35),
            width: active ? 1.5 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  period.planet,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold),
                ),
              ),
              if (active)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: green.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'NOW',
                    style: TextStyle(
                        color: green,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${_fmt(period.startDate)}  →  ${_fmt(period.endDate)}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
          ),
          if (period.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...period.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 6),
                        child: Icon(Icons.check_circle,
                            color: green, size: 12),
                      ),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (period.warnings.isNotEmpty)
            ...period.warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 6),
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.amberAccent, size: 12),
                      ),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                              color: Colors.amberAccent.withValues(alpha: 0.95),
                              fontSize: 12,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

/// Lightweight payload returned by the quick-save favourite dialog so the
/// caller (PredictionsScreen) doesn't need to crack open a Map.
class _QuickFav {
  final String? title;
  final String description;
  _QuickFav({required this.title, required this.description});
}

/// Compact "save to favourites" dialog shown when the user taps the star on
/// the Transit Inputs header. The transit date is fixed (passed in) — only
/// title (optional) and memory (required) are collected here.
class _QuickSaveFavouriteDialog extends StatefulWidget {
  final DateTime date;
  const _QuickSaveFavouriteDialog({required this.date});

  @override
  State<_QuickSaveFavouriteDialog> createState() =>
      _QuickSaveFavouriteDialogState();
}

class _QuickSaveFavouriteDialogState extends State<_QuickSaveFavouriteDialog> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _label(DateTime d) => DateFormat('EEE, MMM d, yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1745),
      titleTextStyle: const TextStyle(
          color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      title: Text('Save ${_label(widget.date)}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Title (optional)',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _titleController,
              maxLength: 200,
              style: const TextStyle(color: Colors.white),
              decoration: _decoration(hint: 'e.g. Saturn return exact'),
            ),
            const SizedBox(height: 6),
            const Text('Memory',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: _descriptionController,
              maxLines: 5,
              minLines: 3,
              maxLength: 4000,
              style: const TextStyle(color: Colors.white),
              decoration:
                  _decoration(hint: 'What happened? How did it feel?'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final desc = _descriptionController.text.trim();
            if (desc.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Memory cannot be empty')),
              );
              return;
            }
            Navigator.of(context).pop(_QuickFav(
              title: _titleController.text.trim().isEmpty
                  ? null
                  : _titleController.text.trim(),
              description: desc,
            ));
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C4DFF),
            foregroundColor: Colors.white,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }

  InputDecoration _decoration({required String hint}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        counterStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: Color(0xFF7C4DFF), width: 1.4),
        ),
      );
}
