import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/dasha_reading.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

class DashaScreen extends StatefulWidget {
  final PredictionRequest request;

  const DashaScreen({super.key, required this.request});

  @override
  State<DashaScreen> createState() => _DashaScreenState();
}

/// Comparison profiles bundled with the Vimshottari Dasha screen so the
/// user can flip between their own chart and famous investors' charts
/// to see how the dasha favorability landscape looks for each. Useful
/// for empirical sanity-checking ("what does Burry's chart say about
/// 2008? does it match what he actually did?") and for understanding
/// the chart-relativity of the personal-fortune model.
///
/// Birth times for celebrities are noon-default (real birth times are
/// not in the public record); MD ladder is insensitive to ±2h shifts.
class DashaProfileOption {
  final String label;
  final String shortLabel;
  final PredictionRequest request;
  const DashaProfileOption({
    required this.label,
    required this.shortLabel,
    required this.request,
  });
}

const _burryProfile = DashaProfileOption(
  label: 'Michael Burry (1971-06-19, San Jose)',
  shortLabel: 'Burry',
  request: PredictionRequest(
    name: 'Michael Burry',
    birthDate: '1971-06-19',
    birthTime: '12:00',
    latitude: 37.3382,
    longitude: -121.8863,
    timezone: -7, // PDT in June
    transitDate: '',
  ),
);

const _ackmanProfile = DashaProfileOption(
  label: 'Bill Ackman (1966-05-11, Chappaqua NY)',
  shortLabel: 'Ackman',
  request: PredictionRequest(
    name: 'Bill Ackman',
    birthDate: '1966-05-11',
    birthTime: '12:00',
    latitude: 41.1570,
    longitude: -73.7660,
    timezone: -4, // EDT in May
    transitDate: '',
  ),
);

class _DashaScreenState extends State<DashaScreen> {
  DashaReading? _reading;
  String? _error;
  bool _loading = false;
  // Active profile for /api/dasha + /api/dasha-range. Defaults to the
  // user's chart (passed via widget.request); can be swapped to Burry
  // or Ackman from the chip selector at the top.
  late PredictionRequest _activeRequest;
  late String _activeProfileKey; // 'self' | 'burry' | 'ackman'

  // ── Range-search state ────────────────────────────────────────────
  // The "Search dashas in date range" panel expands inline. From defaults
  // to today; To defaults to today + 1 year. _level limits results to a
  // single dasha level (mahadasha / antardasha / pratyantardasha /
  // sookshmadasha) so users aren't drowned in 100+ SDs by default.
  bool _searchExpanded = false;
  bool _searchLoading = false;
  String? _searchError;
  DashaRange? _searchResult;
  late DateTime _searchFrom;
  late DateTime _searchTo;
  String _searchLevel = 'pratyantardasha';
  static const _searchLevels = <String, String>{
    'mahadasha': 'Mahadasha',
    'antardasha': 'Antardasha',
    'pratyantardasha': 'Pratyantardasha',
    'sookshmadasha': 'Sookshmadasha',
  };

  // Planet → glyph (Vedic / Western mix)
  static const Map<String, String> _planetGlyph = {
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

  // Planet → accent color
  static const Map<String, Color> _planetColor = {
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

  @override
  void initState() {
    super.initState();
    _activeRequest = widget.request;
    _activeProfileKey = 'self';
    final today = DateTime.now();
    _searchFrom = DateTime(today.year, today.month, today.day);
    _searchTo = _searchFrom.add(const Duration(days: 365));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  /// Switch the active chart between the user's own and the bundled
  /// celebrity profiles (Burry / Ackman). Refetches /api/dasha for the
  /// new chart and clears any prior search results so the screen
  /// doesn't show mixed data.
  void _selectProfile(String key) {
    if (key == _activeProfileKey) return;
    PredictionRequest req;
    switch (key) {
      case 'burry':
        // Use the user's transit date so we compare apples-to-apples
        // (the celebrity's chart, but the user's "as-of" moment).
        req = _withTransitDate(_burryProfile.request, widget.request.transitDate);
        break;
      case 'ackman':
        req = _withTransitDate(_ackmanProfile.request, widget.request.transitDate);
        break;
      case 'self':
      default:
        req = widget.request;
    }
    setState(() {
      _activeProfileKey = key;
      _activeRequest = req;
      _reading = null;
      _searchResult = null;
      _searchError = null;
    });
    _fetch();
  }

  PredictionRequest _withTransitDate(PredictionRequest base, String transitDate) {
    return PredictionRequest(
      name: base.name,
      birthDate: base.birthDate,
      birthTime: base.birthTime,
      latitude: base.latitude,
      longitude: base.longitude,
      timezone: base.timezone,
      transitDate: transitDate,
    );
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _runSearch({bool forceRefresh = false}) async {
    if (!_searchFrom.isBefore(_searchTo)) {
      setState(() => _searchError = 'From date must be before To date.');
      return;
    }
    setState(() {
      _searchLoading = true;
      _searchError = null;
    });
    try {
      final r = await PredictionApiService.fetchDashaRange(
        name: _activeRequest.name,
        birthDate: _activeRequest.birthDate,
        birthTime: _activeRequest.birthTime,
        latitude: _activeRequest.latitude,
        longitude: _activeRequest.longitude,
        timezone: _activeRequest.timezone,
        fromDate: _ymd(_searchFrom),
        toDate: _ymd(_searchTo),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _searchResult = r;
        _searchLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.toString();
        _searchLoading = false;
      });
    }
  }

  Future<void> _pickSearchDate({required bool isFrom}) async {
    final initial = isFrom ? _searchFrom : _searchTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _searchFrom = picked;
        if (!_searchFrom.isBefore(_searchTo)) {
          _searchTo = _searchFrom.add(const Duration(days: 1));
        }
      } else {
        _searchTo = picked;
      }
    });
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PredictionApiService.fetchDasha(
        _activeRequest,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _reading = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1745),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Vimshottari Dasha'),
        actions: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading ? null : () => _fetch(),
            onLongPress: _loading
                ? null
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Bypassing cache — refetching…'),
                          duration: Duration(seconds: 1)),
                    );
                    _fetch(forceRefresh: true);
                  },
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
      ),
      // Top handled by AppBar. Bottom disabled so list scrolls past home
      // indicator; added back as ListView bottom padding below.
      body: SafeArea(top: false, bottom: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CosmicLoader(message: 'Reading the cosmos...'),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('🌌', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _fetch(forceRefresh: true),
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
    final r = _reading;
    if (r == null) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: Colors.white70)),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final sd = r.sookshmadasha;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
        _buildProfileSelector(),
        const SizedBox(height: 12),
        _buildHeader(r),
        const SizedBox(height: 12),
        const _CalibrationBanner(),
        const SizedBox(height: 16),
        _buildSearchPanel(),
        if (_searchResult != null) ..._buildSearchResults(_searchResult!),
        const SizedBox(height: 20),
        _SectionHeader(label: 'Mahadasha', sublabel: 'Major period'),
        _DashaCard(
          period: r.mahadasha,
          color: _colorFor(r.mahadasha.planet),
          glyph: _glyphFor(r.mahadasha.planet),
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Antardasha', sublabel: 'Sub-period'),
        _DashaCard(
          period: r.antardasha,
          color: _colorFor(r.antardasha.planet),
          glyph: _glyphFor(r.antardasha.planet),
        ),
        const SizedBox(height: 16),
        _SectionHeader(label: 'Pratyantardasha', sublabel: 'Sub-sub-period'),
        _DashaCard(
          period: r.pratyantardasha,
          color: _colorFor(r.pratyantardasha.planet),
          glyph: _glyphFor(r.pratyantardasha.planet),
        ),
        if (sd != null) ...[
          const SizedBox(height: 16),
          _SectionHeader(
              label: 'Sookshmadasha', sublabel: 'Sub-sub-sub-period'),
          _DashaCard(
            period: sd,
            color: _colorFor(sd.planet),
            glyph: _glyphFor(sd.planet),
          ),
        ],
        // ── Personal capital-deployment sub-period landscape ──
        // Every AD/PD/SD is shown with its tag — green when favorable
        // for YOUR personal capital deployment, amber when caution
        // applies, neutral when neither. Empirically these tags
        // correlate with personal-fortune cycles, NOT broad-market
        // direction (see calibration banner above).
        ..._buildTaggedSection(
          title: 'Antardashas',
          sublabel: 'Your sub-periods within current Mahadasha',
          periods: r.antardashas,
        ),
        ..._buildTaggedSection(
          title: 'Pratyantardashas',
          sublabel: 'Your sub-periods within current Antardasha',
          periods: r.pratyantardashas,
        ),
        ..._buildTaggedSection(
          title: 'Sookshmadashas',
          sublabel: 'Your sub-periods within current Pratyantardasha',
          periods: r.sookshmadashas,
        ),
      ],
    );
  }

  /// Render a header + the full list of sub-periods, each colored by its
  /// favorable/warnings tag. Returns an empty list if there are no periods
  /// (caller spreads into a ListView's children).
  List<Widget> _buildTaggedSection({
    required String title,
    required String sublabel,
    required List<DashaPeriodAnnotated> periods,
  }) {
    if (periods.isEmpty) return const [];
    final favCount = periods.where((p) => p.favorable).length;
    final warnCount =
        periods.where((p) => !p.favorable && p.warnings.isNotEmpty).length;
    return [
      const SizedBox(height: 20),
      _SectionHeader(label: title, sublabel: sublabel),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
        child: Row(
          children: [
            _CountChip(
                label: '$favCount favorable',
                color: _favorableGreen,
                icon: Icons.check_circle),
            const SizedBox(width: 6),
            if (warnCount > 0)
              _CountChip(
                  label: '$warnCount caution',
                  color: Colors.amberAccent,
                  icon: Icons.warning_amber_rounded),
          ],
        ),
      ),
      ...periods.map((p) => _TaggedPeriodCard(
            period: p,
            color: _colorFor(p.planet),
            glyph: _glyphFor(p.planet),
          )),
    ];
  }

  Color _colorFor(String planet) =>
      _planetColor[planet] ?? const Color(0xFF7C4DFF);

  String _glyphFor(String planet) => _planetGlyph[planet] ?? '✦';

  /// Profile selector at the top of the screen — chips for the user's
  /// own chart and the bundled celebrity profiles. Tapping a chip
  /// reloads the screen with that chart's dasha view. Useful for
  /// comparing how the favorability landscape looks across different
  /// natal charts (e.g. Burry's hyper-favored late-2000s vs Jack's).
  Widget _buildProfileSelector() {
    final selfLabel = widget.request.name.isEmpty
        ? 'Your chart'
        : '${widget.request.name} (you)';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              Text(
                'View dasha for…',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _profileChip('self', selfLabel),
              _profileChip('burry', _burryProfile.shortLabel,
                  tooltip: _burryProfile.label),
              _profileChip('ackman', _ackmanProfile.shortLabel,
                  tooltip: _ackmanProfile.label),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileChip(String key, String label, {String? tooltip}) {
    final selected = _activeProfileKey == key;
    final chip = ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _selectProfile(key),
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      selectedColor: const Color(0xFF7C4DFF).withValues(alpha: 0.4),
      labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: selected
                  ? const Color(0xFF7C4DFF)
                  : Colors.white.withValues(alpha: 0.15))),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: chip) : chip;
  }

  /// Collapsible "Search dashas in date range" panel. Header shows the
  /// active range + level; tapping the header expands the controls
  /// (from / to date pickers, level selector, Search button).
  Widget _buildSearchPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () =>
                setState(() => _searchExpanded = !_searchExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.search,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _searchExpanded
                        ? const Text(
                            'Search Personal Capital-Deployment Windows',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700),
                          )
                        : Text(
                            'Search ${_searchLevels[_searchLevel]}: ${_ymd(_searchFrom)} → ${_ymd(_searchTo)}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                  AnimatedRotation(
                    turns: _searchExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more,
                        color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: _buildSearchControls(),
            secondChild: const SizedBox(width: double.infinity, height: 0),
            crossFadeState: _searchExpanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            duration: const Duration(milliseconds: 220),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _searchDateTile(
                    label: 'From',
                    value: _ymd(_searchFrom),
                    onTap: () => _pickSearchDate(isFrom: true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _searchDateTile(
                    label: 'To',
                    value: _ymd(_searchTo),
                    onTap: () => _pickSearchDate(isFrom: false)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Level selector — search per-level keeps response sizes
          // sane (a 5-year range can be ~500 SDs).
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _searchLevels.entries.map((e) {
              final selected = e.key == _searchLevel;
              return ChoiceChip(
                label: Text(e.value),
                selected: selected,
                onSelected: (_) =>
                    setState(() => _searchLevel = e.key),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                selectedColor:
                    const Color(0xFF7C4DFF).withValues(alpha: 0.4),
                labelStyle: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: selected
                            ? const Color(0xFF7C4DFF)
                            : Colors.white.withValues(alpha: 0.12))),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          if (_searchError != null) ...[
            Text(_searchError!,
                style: const TextStyle(
                    color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _searchLoading ? null : () => _runSearch(),
              icon: _searchLoading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.search, size: 16),
              label: Text(_searchLoading ? 'Searching…' : 'Search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchDateTile({
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
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 11)),
            const SizedBox(height: 2),
            Text(value,
                style:
                    const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  /// Render the results section based on the selected level. Each row is
  /// a `_RangeEntryCard` (similar to `_TaggedPeriodCard` but compact and
  /// shows the parent lineage for sub-periods).
  List<Widget> _buildSearchResults(DashaRange r) {
    final List<DashaRangeEntry> entries = switch (_searchLevel) {
      'mahadasha' => r.mahadashas,
      'antardasha' => r.antardashas,
      'pratyantardasha' => r.pratyantardashas,
      'sookshmadasha' => r.sookshmadashas,
      _ => const [],
    };
    final levelLabel = _searchLevels[_searchLevel] ?? '';
    final favCount = entries.where((e) => e.favorable).length;
    final warnCount = entries
        .where((e) => !e.favorable && e.warnings.isNotEmpty)
        .length;
    return [
      const SizedBox(height: 14),
      _SectionHeader(
        label: 'Search Results',
        sublabel: '$levelLabel · ${r.fromDate} → ${r.toDate}',
      ),
      if (entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No $levelLabel periods in this range.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic),
          ),
        )
      else ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              _CountChip(
                  label: '${entries.length} total',
                  color: const Color(0xFF7C4DFF),
                  icon: Icons.list_alt),
              const SizedBox(width: 6),
              _CountChip(
                  label: '$favCount favorable',
                  color: _favorableGreen,
                  icon: Icons.check_circle),
              if (warnCount > 0) ...[
                const SizedBox(width: 6),
                _CountChip(
                    label: '$warnCount caution',
                    color: Colors.amberAccent,
                    icon: Icons.warning_amber_rounded),
              ],
            ],
          ),
        ),
        ...entries.map((e) => _RangeEntryCard(
              entry: e,
              color: _colorFor(e.planet),
              glyph: _glyphFor(e.planet),
            )),
      ],
    ];
  }

  Widget _buildHeader(DashaReading r) {
    final n = r.nakshatra;
    final padaText = n.pada > 0 ? ' · Pada ${n.pada}' : '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AS OF ${r.date}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                _glyphFor(n.lord),
                style: TextStyle(
                    color: _colorFor(n.lord), fontSize: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nakshatra ${n.name}$padaText',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Lord: ${n.lord} · Moon ${r.moonLongitude.toStringAsFixed(2)}°',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: n.fractionElapsed.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(_colorFor(n.lord)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nakshatra elapsed: ${(n.fractionElapsed * 100).toStringAsFixed(1)}%',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

const Color _favorableGreen = Color(0xFF4CD27E);

class _SectionHeader extends StatelessWidget {
  final String label;
  final String sublabel;
  const _SectionHeader({
    required this.label,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              sublabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashaCard extends StatelessWidget {
  final DashaPeriod period;
  final Color color;
  final String glyph;

  const _DashaCard({
    required this.period,
    required this.color,
    required this.glyph,
  });

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    return DateFormat('MMM d, yyyy').format(local);
  }

  String _humanDuration(Duration d) {
    final days = d.inDays;
    if (days >= 365) {
      final years = days / 365.25;
      final whole = years.floor();
      final months = ((years - whole) * 12).round();
      if (months == 0) return '$whole yr';
      return '$whole yr $months mo';
    }
    if (days >= 30) {
      final months = (days / 30.4375).floor();
      final remDays = days - (months * 30.4375).round();
      if (remDays <= 0) return '$months mo';
      return '$months mo $remDays d';
    }
    return '$days d';
  }

  @override
  Widget build(BuildContext context) {
    final progress = period.progress;
    // When the active period is investment-favorable, swap the planet
    // accent color for the green favorable accent on the card border so
    // the user immediately sees "you're in a good window right now".
    // Falls back to the planet color otherwise.
    final borderColor = period.favorable
        ? _favorableGreen
        : color.withValues(alpha: 0.4);
    final borderWidth = period.favorable ? 1.6 : 1.0;
    final cardBg = period.favorable
        ? _favorableGreen.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.05);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child: Text(glyph,
                    style: TextStyle(color: color, fontSize: 22)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            period.planet,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (period.favorable) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _favorableGreen.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'FAVORABLE',
                              style: TextStyle(
                                  color: _favorableGreen,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtDate(period.startDate)}  →  ${_fmtDate(period.endDate)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _humanDuration(period.totalDuration),
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${(progress * 100).toStringAsFixed(1)}% elapsed',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11),
              ),
              const Spacer(),
              Text(
                '${_humanDuration(period.totalDuration - period.elapsed)} left',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11),
              ),
            ],
          ),
          if (period.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              period.description,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.45),
            ),
          ],
          // Inline favorability rationale on the active card. Lets the user
          // see WHY the current MD/AD/PD/SD is flagged as favorable
          // (e.g. "Jupiter–Venus antardasha — Dasha.docx flags this pair as
          // favorable for property appreciation") without scrolling to the
          // dedicated highlights section below.
          if (period.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...period.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4, right: 8),
                        child: Icon(Icons.check_circle,
                            color: _favorableGreen, size: 13),
                      ),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (period.warnings.isNotEmpty) ...[
            if (period.reasons.isEmpty) const SizedBox(height: 10),
            ...period.warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4, right: 8),
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.amberAccent, size: 13),
                      ),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                              color: Colors.amberAccent.withValues(alpha: 0.95),
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// Empirical-accuracy banner shown above the dasha results. Backtests
/// against AMZN (10 milestones) and S&P 500 (20 milestones) showed
/// ~40% market-direction accuracy — no better than the always-bullish
/// baseline. The dasha API tracks the user's PERSONAL capital-
/// deployment fortune, not broad-market timing. This banner makes that
/// limitation legible so users don't over-trust the FAVORABLE flags
/// as buy signals.
class _CalibrationBanner extends StatelessWidget {
  const _CalibrationBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.amberAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1, right: 8),
            child: Icon(Icons.info_outline,
                color: Colors.amberAccent, size: 16),
          ),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    height: 1.4),
                children: const [
                  TextSpan(
                    text: 'Personal capital-deployment guidance, not market timing.\n',
                    style: TextStyle(
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        'Backtested against AMZN and S&P 500 milestones, '
                        'this dasha-only model lands ~40% market-direction '
                        'accuracy — no better than always saying bullish. '
                        'It tracks YOUR fortune cycle, not the index. Treat '
                        '"FAVORABLE" as "OK to deploy capital this period," '
                        'not "the market will rise."',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tiny inline status badge (FAVORABLE / CAUTION / NOW) used on the
/// tagged-period cards. Color is supplied by the caller so the same pill
/// renders green / amber / planet-tinted depending on context.
class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8),
        ),
      ),
    );
  }
}

/// Compact count chip used in section headers ("3 favorable | 1 caution").
class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _CountChip(
      {required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
                color: color, fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Card for any AD/PD/SD with its tag visible. Three visual states:
///   • favorable        → green border + tinted bg + FAVORABLE badge,
///                        all reasons + warnings rendered
///   • warning-only     → amber border + tinted bg + CAUTION badge, only
///                        warnings rendered
///   • neutral          → faint planet-color border, no badge, no extras
class _TaggedPeriodCard extends StatelessWidget {
  final DashaPeriodAnnotated period;
  final Color color;
  final String glyph;

  const _TaggedPeriodCard({
    required this.period,
    required this.color,
    required this.glyph,
  });

  String _fmtDate(DateTime d) {
    final local = d.toLocal();
    return DateFormat('MMM d, yyyy').format(local);
  }

  String _humanDuration(Duration d) {
    final days = d.inDays;
    if (days >= 365) {
      final years = days / 365.25;
      final whole = years.floor();
      final months = ((years - whole) * 12).round();
      if (months == 0) return '$whole yr';
      return '$whole yr $months mo';
    }
    if (days >= 30) {
      final months = (days / 30.4375).floor();
      final remDays = days - (months * 30.4375).round();
      if (remDays <= 0) return '$months mo';
      return '$months mo $remDays d';
    }
    return '$days d';
  }

  @override
  Widget build(BuildContext context) {
    final isActive = period.isActive;
    final favorable = period.favorable;
    final hasOnlyWarnings = !favorable && period.warnings.isNotEmpty;
    final tagColor = favorable
        ? _favorableGreen
        : hasOnlyWarnings
            ? Colors.amberAccent
            : color;
    final cardBg = favorable
        ? _favorableGreen.withValues(alpha: 0.06)
        : hasOnlyWarnings
            ? Colors.amberAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.03);
    final borderAlpha = favorable || hasOnlyWarnings
        ? (isActive ? 0.7 : 0.4)
        : (isActive ? 0.5 : 0.18);
    final borderWidth = isActive ? 1.6 : 1.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: tagColor.withValues(alpha: borderAlpha),
            width: borderWidth),
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
                child: Text(glyph,
                    style: TextStyle(color: color, fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          period.planet,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        if (favorable)
                          _StatusPill(
                              label: 'FAVORABLE', color: _favorableGreen),
                        if (hasOnlyWarnings)
                          _StatusPill(
                              label: 'CAUTION', color: Colors.amberAccent),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          _StatusPill(
                              label: 'NOW', color: tagColor),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtDate(period.startDate)}  →  ${_fmtDate(period.endDate)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _humanDuration(period.totalDuration),
                  style: TextStyle(
                      color: tagColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (period.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...period.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4, right: 8),
                        child: Icon(Icons.check_circle,
                            color: _favorableGreen, size: 14),
                      ),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          if (period.warnings.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...period.warnings.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 4, right: 8),
                        child: Icon(Icons.warning_amber_rounded,
                            color: Colors.amberAccent, size: 14),
                      ),
                      Expanded(
                        child: Text(
                          w,
                          style: TextStyle(
                              color: Colors.amberAccent.withValues(alpha: 0.95),
                              fontSize: 12.5,
                              height: 1.4),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// One row in the dasha-range search results. Compact layout: planet
/// glyph + name + date range + status pill. Reasons / warnings are
/// rendered when present so users can scan why a window is flagged.
/// `parent` is shown next to the planet name as "Saturn AD → Mercury PD"
/// breadcrumb so users see the lineage at a glance.
class _RangeEntryCard extends StatelessWidget {
  final DashaRangeEntry entry;
  final Color color;
  final String glyph;

  const _RangeEntryCard({
    required this.entry,
    required this.color,
    required this.glyph,
  });

  String _fmtDate(DateTime d) =>
      DateFormat('MMM d, yyyy').format(d.toLocal());

  String _humanDuration(Duration d) {
    final days = d.inDays;
    if (days >= 365) {
      final years = days / 365.25;
      final whole = years.floor();
      final months = ((years - whole) * 12).round();
      if (months == 0) return '$whole yr';
      return '$whole yr $months mo';
    }
    if (days >= 30) {
      final months = (days / 30.4375).floor();
      final remDays = days - (months * 30.4375).round();
      if (remDays <= 0) return '$months mo';
      return '$months mo $remDays d';
    }
    return '$days d';
  }

  @override
  Widget build(BuildContext context) {
    final favorable = entry.favorable;
    final hasWarning = !favorable && entry.warnings.isNotEmpty;
    final tagColor = favorable
        ? _favorableGreen
        : hasWarning
            ? Colors.amberAccent
            : color;
    final cardBg = favorable
        ? _favorableGreen.withValues(alpha: 0.06)
        : hasWarning
            ? Colors.amberAccent.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.03);
    final isActive = entry.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: tagColor.withValues(alpha: isActive ? 0.7 : 0.35),
          width: isActive ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                alignment: Alignment.center,
                child:
                    Text(glyph, style: TextStyle(color: color, fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          entry.planet,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                        ),
                        if (entry.parent != null && entry.parent!.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '· in ${entry.parent}',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11),
                          ),
                        ],
                        const SizedBox(width: 6),
                        if (favorable)
                          _StatusPill(label: 'FAVORABLE', color: _favorableGreen),
                        if (hasWarning)
                          _StatusPill(label: 'CAUTION', color: Colors.amberAccent),
                        if (isActive)
                          _StatusPill(label: 'NOW', color: tagColor),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtDate(entry.startDate)}  →  ${_fmtDate(entry.endDate)}',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _humanDuration(entry.totalDuration),
                  style: TextStyle(
                      color: tagColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (entry.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...entry.reasons.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 3, right: 6),
                        child: Icon(Icons.check_circle,
                            color: _favorableGreen, size: 12),
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
          if (entry.warnings.isNotEmpty) ...[
            if (entry.reasons.isEmpty) const SizedBox(height: 6),
            ...entry.warnings.map((w) => Padding(
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
        ],
      ),
    );
  }
}
