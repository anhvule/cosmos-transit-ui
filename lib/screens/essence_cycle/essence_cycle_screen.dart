import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/essence_cycle.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

class EssenceCycleScreen extends StatefulWidget {
  /// Initial values pre-filled from the predictions screen. The user can
  /// edit any of them on this page (full name often differs from the
  /// "natal chart name" used elsewhere — numerology cares about the
  /// full birth name).
  final String initialFullName;
  final String initialDob; // YYYY-MM-DD
  final int? initialStartYear;

  const EssenceCycleScreen({
    super.key,
    required this.initialFullName,
    required this.initialDob,
    this.initialStartYear,
  });

  @override
  State<EssenceCycleScreen> createState() => _EssenceCycleScreenState();
}

class _EssenceCycleScreenState extends State<EssenceCycleScreen> {
  late final TextEditingController _nameController;
  late DateTime _dob;
  late int _startYear;

  EssenceCycle? _cycle;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialFullName);
    _dob = _parseDob(widget.initialDob);
    _startYear = widget.initialStartYear ?? DateTime.now().year;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static DateTime _parseDob(String s) {
    try {
      final parts = s.split('-');
      return DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
    } catch (_) {
      return DateTime(1990, 1, 1);
    }
  }

  String _fmtDob(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch({bool forceRefresh = false}) async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Full name is required.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PredictionApiService.fetchEssenceCycle(
        fullName: name,
        dob: _fmtDob(_dob),
        startYear: _startYear,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _cycle = result;
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
        title: const Text('Essence Cycle'),
        actions: [
          // GestureDetector with opaque hit-test so long-press registers on
          // the full padded area (not only the opaque icon pixels). InkWell
          // is wrapped to give visual ripple feedback on tap.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading ? null : () => _fetch(),
            onLongPress: _loading ? null : () {
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
      body: SafeArea(top: false, bottom: false, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildInputs(),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildInputs() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: const Color(0xFF1A1745),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              labelText: 'Full Name',
              labelStyle:
                  const TextStyle(color: Colors.white70, fontSize: 12),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF7C4DFF)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _dob,
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) setState(() => _dob = d);
                  },
                  child: _tile('Date of Birth', _fmtDob(_dob)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime(_startYear),
                      firstDate: DateTime(1900),
                      lastDate: DateTime(2100),
                      helpText: 'Pick any date in the start year',
                    );
                    if (d != null) setState(() => _startYear = d.year);
                  },
                  child: _tile('Start Year', _startYear.toString()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 40,
            // Compute is an explicit user action ⇒ always bypass the cache.
            // Auto-fetch on screen open (initState) still uses the cache.
            child: ElevatedButton(
              onPressed: _loading ? null : () => _fetch(forceRefresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C4DFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: const Text('Compute Essence Cycle',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(String label, String value) {
    return Container(
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
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CosmicLoader(message: 'Computing your essence cycle...'),
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
    final c = _cycle;
    if (c == null) {
      return const Center(
        child: Text('Tap "Compute Essence Cycle" to load.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Reserve item count: years + 1 debug section header.
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      itemCount: c.essenceTable.length + 1,
      itemBuilder: (_, i) {
        if (i == c.essenceTable.length) {
          return const _DebugRawResponseTile();
        }
        return _YearCard(year: c.essenceTable[i]);
      },
    );
  }
}

/// Debug overlay — collapsible card at the bottom of the year list that
/// shows the raw API response (or cache snapshot) the screen is rendering.
/// Useful for confirming the wire payload matches what `curl` returns.
class _DebugRawResponseTile extends StatelessWidget {
  const _DebugRawResponseTile();

  @override
  Widget build(BuildContext context) {
    final raw = PredictionApiService.lastEssenceCycleRawBody;
    final source = PredictionApiService.lastEssenceCycleSource ?? '?';
    if (raw == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(
          dividerColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(primary: Colors.amber),
        ),
        child: ExpansionTile(
          iconColor: Colors.amber.shade200,
          collapsedIconColor: Colors.amber.shade200,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Icon(Icons.bug_report,
                  color: Colors.amber.shade200, size: 18),
              const SizedBox(width: 8),
              Text('Debug: raw response ($source)',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('Copy raw JSON'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: raw));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Raw JSON copied to clipboard'),
                          duration: Duration(seconds: 1)),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber.shade700,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(0, 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                raw.length > 8000
                    ? '${raw.substring(0, 8000)}\n…(truncated, copy for full)'
                    : raw,
                style: const TextStyle(
                  color: Colors.white70,
                  fontFamily: 'Menlo',
                  fontSize: 10,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YearCard extends StatelessWidget {
  final EssenceYear year;
  const _YearCard({required this.year});

  static const Color _accent = Color(0xFF7C4DFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(
          dividerColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(primary: _accent),
        ),
        child: ExpansionTile(
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              _bigNumberBadge(year.essenceNumber),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${year.year} · Age ${year.age}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(year.keyword,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip('PY ${year.personalYear}'),
                if (year.transits.physical != null)
                  _chip('P ${year.transits.physical!.letter}'),
                if (year.transits.mental != null)
                  _chip('M ${year.transits.mental!.letter}'),
                if (year.transits.spiritual != null)
                  _chip('S ${year.transits.spiritual!.letter}'),
              ],
            ),
          ),
          children: [
            if (year.meaning.isNotEmpty) ...[
              _sectionLabel('Meaning'),
              Text(
                year.meaning,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                    height: 1.4),
              ),
              const SizedBox(height: 12),
            ],
            if (year.detailedMeaning.isNotEmpty) ...[
              _sectionLabel('Detailed Meaning'),
              Text(
                year.detailedMeaning,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.5),
              ),
              const SizedBox(height: 12),
            ],
            if (year.transits.physical != null ||
                year.transits.mental != null ||
                year.transits.spiritual != null) ...[
              _sectionLabel('Transits'),
              if (year.transits.physical != null)
                _transitCard(year.transits.physical!),
              if (year.transits.mental != null)
                _transitCard(year.transits.mental!),
              if (year.transits.spiritual != null)
                _transitCard(year.transits.spiritual!),
            ],
            // Render all dualities the API returns:
            //   * before_birthday + after_birthday  → both cards
            //   * full_year                         → one "Full year" card
            // (years where essence/PY don't flip across the birthday only
            // come back as full_year — splitting them would be wrong.)
            if (year.dualities.isNotEmpty) ...[
              _sectionLabel(
                  year.dualities.length == 1 ? 'Year Detail' : 'Dualities'),
              ...year.dualities.map(_dualityCard),
            ],
          ],
        ),
      ),
    );
  }

  static Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1),
        ),
      );

  static Widget _bigNumberBadge(int n) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _accent.withValues(alpha: 0.18),
        border: Border.all(color: _accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        '$n',
        style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  static Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          style: const TextStyle(color: Colors.white70, fontSize: 11)),
    );
  }

  /// Per-stream transit card: header with letter + value + plane + duration,
  /// short `meaning`, and an expandable `detailed_meaning` (only if present).
  static Widget _transitCard(EssenceTransit t) {
    final hasMeaning = t.meaning.isNotEmpty;
    final hasDetail = t.detailedMeaning.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _letterBadge(t.letter, t.value),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${t.plane} Transit',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.durationYears > 0
                          ? 'Letter ${t.letter} · Value ${t.value} · ${t.durationYears} ${t.durationYears == 1 ? "year" : "years"}'
                          : 'Letter ${t.letter}',
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (hasMeaning) ...[
            const SizedBox(height: 8),
            Text(
              t.meaning,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 12,
                  height: 1.45),
            ),
          ],
          if (hasDetail) ...[
            const SizedBox(height: 8),
            Theme(
              data: ThemeData.dark().copyWith(
                dividerColor: Colors.transparent,
                colorScheme: const ColorScheme.dark(primary: _accent),
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
                iconColor: Colors.white54,
                collapsedIconColor: Colors.white54,
                title: const Text(
                  'Read more',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
                children: [
                  Text(
                    t.detailedMeaning,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget _letterBadge(String letter, int value) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _accent.withValues(alpha: 0.18),
        border: Border.all(color: _accent.withValues(alpha: 0.55)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            letter,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.0,
                fontWeight: FontWeight.bold),
          ),
          if (value > 0)
            Text(
              '$value',
              style: const TextStyle(
                  color: Colors.white70, fontSize: 9, height: 1.2),
            ),
        ],
      ),
    );
  }

  static Widget _dualityCard(EssenceDuality d) {
    // The API returns three period values:
    //   * before_birthday — Jan 1 to the day before birthday
    //   * after_birthday  — birthday to Dec 31
    //   * full_year       — Jan 1 to Dec 31 (years where essence/PY don't
    //                        flip across the birthday, so a single block
    //                        covers the whole calendar year)
    final String periodLabel;
    switch (d.period) {
      case 'before_birthday':
        periodLabel = 'Before birthday';
        break;
      case 'after_birthday':
        periodLabel = 'After birthday';
        break;
      case 'full_year':
        periodLabel = 'Full year';
        break;
      default:
        periodLabel = d.period.isEmpty
            ? 'Period'
            : d.period.replaceAll('_', ' ');
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  periodLabel,
                  style: const TextStyle(
                      color: Color(0xFF7C4DFF), fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${d.startDate} → ${d.endDate}',
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('E ${d.essenceNumber}'),
              const SizedBox(width: 4),
              _chip('PY ${d.personalYear}'),
              const SizedBox(width: 4),
              _chip('Duality ${d.dualityNumber}'),
            ],
          ),
          if (d.keyword.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(d.keyword,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
          if (d.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              d.description,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}
