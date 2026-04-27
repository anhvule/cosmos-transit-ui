import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import '../../models/prediction_reading.dart';
import '../../services/prediction_api_service.dart';
import '../../services/storage_service.dart';
import '../investment_forecast/investment_forecast_screen.dart';
import '../dasha/dasha_screen.dart';
import '../essence_cycle/essence_cycle_screen.dart';
import '../../widgets/cosmic_loader.dart';

class PredictionsScreen extends StatefulWidget {
  const PredictionsScreen({super.key});

  @override
  State<PredictionsScreen> createState() => _PredictionsScreenState();
}

class _PredictionsScreenState extends State<PredictionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Default inputs per spec
  final _nameController = TextEditingController(text: 'Astrologer');
  DateTime _birthDate = DateTime(1991, 12, 29);
  TimeOfDay _birthTime = const TimeOfDay(hour: 13, minute: 30);
  final _cityController = TextEditingController();
  final _latitudeController = TextEditingController(text: '10.7765713');
  final _longitudeController = TextEditingController(text: '106.7012093');
  final _timezoneController = TextEditingController(text: 'Asia/Ho_Chi_Minh');
  DateTime _transitDate = _todayDateOnly();

  // City → lat/lng geocoding state. `_lastGeocodedCity` lets us avoid
  // re-running the lookup on every fetch when the city hasn't changed.
  bool _geocoding = false;
  String? _cityError;
  String _lastGeocodedCity = '';

  static DateTime _todayDateOnly() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  // Per-tab state
  final Map<PredictionArea, PredictionReading?> _results = {};
  final Map<PredictionArea, String?> _errors = {};
  final Map<PredictionArea, bool> _loading = {};

  // Collapsible panel state — default expanded so user sees inputs on first run
  bool _formExpanded = true;

  @override
  void initState() {
    super.initState();
    _tabController =
        TabController(length: PredictionArea.values.length, vsync: this);
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
      // Profile doesn't store timezone yet; keep the existing default.
    }
    // Auto-fetch once on first load
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _cityController.dispose();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _geocoding = false;
        _cityError = 'Lookup failed: ${e.toString()}';
      });
    }
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
    if (_timezoneController.text.trim().isEmpty) return null;
    return PredictionRequest(
      name: _nameController.text.trim(),
      birthDate: _formatDate(_birthDate),
      birthTime: _formatTime(_birthTime),
      latitude: lat,
      longitude: lng,
      timezone: _timezoneController.text.trim(),
      transitDate: _formatDate(_transitDate),
    );
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
      for (final a in PredictionArea.values) {
        _loading[a] = true;
        _errors[a] = null;
      }
    });

    // The free Heroku dyno runs a single Node.js worker that spawns a
    // Python ephemeris process per request. Firing all 7 prediction calls
    // at once queues them on the dyno; the slowest miss Heroku's 30s H12
    // router timeout and all return 503. Cap concurrency so the dyno can
    // finish each request within its router budget.
    const concurrency = 2;
    final queue =
        List<PredictionArea>.from(PredictionArea.values);
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final area = queue.removeAt(0);
        await _fetchOne(area, req,
            forceRefresh: forceRefresh, markLoading: false);
      }
    }
    await Future.wait(List.generate(concurrency, (_) => worker()));
  }

  IconData _iconFor(PredictionArea a) {
    switch (a) {
      case PredictionArea.career:
        return Icons.work_outline;
      case PredictionArea.relationship:
        return Icons.favorite_outline;
      case PredictionArea.investment:
        return Icons.account_balance_wallet_outlined;
      case PredictionArea.advice:
        return Icons.lightbulb_outline;
      case PredictionArea.gain:
        return Icons.trending_up;
      case PredictionArea.loss:
        return Icons.trending_down;
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
              tabs: PredictionArea.values
                  .map((a) => Tab(
                        height: 48,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(_iconFor(a), size: 16),
                            const SizedBox(width: 6),
                            Text(a.label),
                          ],
                        ),
                      ))
                  .toList(),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: PredictionArea.values
                    .map((a) => _buildTab(a))
                    .toList(),
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
                      'Transit Inputs',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _textField('Name', _nameController)),
              const SizedBox(width: 8),
              Expanded(child: _textField('Timezone', _timezoneController)),
            ],
          ),
          const SizedBox(height: 8),
          // Birth City row — lat/lng are derived via geocoding (`_lookupCity`)
          // and kept in hidden controllers, so the user only sees the city.
          Row(
            children: [
              Expanded(
                child: _textField(
                  'Birth City',
                  _cityController,
                  errorText: _cityError,
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
enum _NavTarget { essenceCycle, dasha, investmentForecast }

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
