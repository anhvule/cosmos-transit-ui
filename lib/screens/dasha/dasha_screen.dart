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

class _DashaScreenState extends State<DashaScreen> {
  DashaReading? _reading;
  String? _error;
  bool _loading = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PredictionApiService.fetchDasha(
        widget.request,
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
        _buildHeader(r),
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
        // ── Investment-favorable sub-period highlights ──
        // Server flags each AD/PD/SD against the SuddenGainSigns ruleset
        // (5L/8L/11L lordship, wealth-house placement, speculation planets).
        // We render them as collapsible sections so users can scan the full
        // landscape of upcoming favorable windows at a glance.
        ..._buildFavorableSection(
          title: 'Favorable Antardashas',
          sublabel: 'Within current Mahadasha',
          periods: r.investmentFavorable.antardashas,
        ),
        ..._buildFavorableSection(
          title: 'Favorable Pratyantardashas',
          sublabel: 'Within current Antardasha',
          periods: r.investmentFavorable.pratyantardashas,
        ),
        ..._buildFavorableSection(
          title: 'Favorable Sookshmadashas',
          sublabel: 'Within current Pratyantardasha',
          periods: r.investmentFavorable.sookshmadashas,
        ),
      ],
    );
  }

  /// Render a header + list of favorable periods. Returns an empty list if
  /// there are none — callers spread it into a ListView's children.
  List<Widget> _buildFavorableSection({
    required String title,
    required String sublabel,
    required List<DashaPeriodAnnotated> periods,
  }) {
    if (periods.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      _SectionHeader(label: title, sublabel: sublabel, accent: _favorableGreen),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
        child: Text(
          'Speculative-investment windows per SuddenGainSigns + Dasha.docx rules.',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontStyle: FontStyle.italic),
        ),
      ),
      ...periods.map((p) => _FavorablePeriodCard(
            period: p,
            color: _colorFor(p.planet),
            glyph: _glyphFor(p.planet),
          )),
    ];
  }

  Color _colorFor(String planet) =>
      _planetColor[planet] ?? const Color(0xFF7C4DFF);

  String _glyphFor(String planet) => _planetGlyph[planet] ?? '✦';

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
  final Color? accent;
  const _SectionHeader({
    required this.label,
    required this.sublabel,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 2),
      child: Row(
        children: [
          if (accent != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: accent ?? Colors.white,
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

/// Card for an investment-favorable AD/PD/SD: glyph + planet name + date
/// range + green "favorable" badge + bulleted reasons + amber warnings.
class _FavorablePeriodCard extends StatelessWidget {
  final DashaPeriodAnnotated period;
  final Color color;
  final String glyph;

  const _FavorablePeriodCard({
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
    final activeBadge = period.isActive;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _favorableGreen.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _favorableGreen.withValues(alpha: activeBadge ? 0.7 : 0.4),
            width: activeBadge ? 1.6 : 1.0),
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
                        if (activeBadge)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _favorableGreen.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'NOW',
                              style: TextStyle(
                                  color: _favorableGreen,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8),
                            ),
                          ),
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
                  color: _favorableGreen.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _humanDuration(period.totalDuration),
                  style: const TextStyle(
                      color: _favorableGreen,
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
