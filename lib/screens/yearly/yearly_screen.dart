import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/yearly_summary.dart';
import '../../models/monthly_prediction.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

/// Tajika Varshaphal page — wraps the /api/yearly-summary and
/// /api/monthly-prediction endpoints in two tabs.
class YearlyScreen extends StatefulWidget {
  final PredictionRequest request;
  final int initialYear;

  const YearlyScreen({
    super.key,
    required this.request,
    required this.initialYear,
  });

  @override
  State<YearlyScreen> createState() => _YearlyScreenState();
}

class _YearlyScreenState extends State<YearlyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late int _year;

  YearlySummary? _summary;
  MonthlyPrediction? _monthly;
  String? _summaryError;
  String? _monthlyError;
  bool _summaryLoading = false;
  bool _monthlyLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _year = widget.initialYear;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchAll());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _fetchAll({bool forceRefresh = false}) async {
    // Run both calls in parallel — they hit different backend code paths and
    // share the cache by year so the second call is usually instant.
    await Future.wait([
      _fetchSummary(forceRefresh: forceRefresh),
      _fetchMonthly(forceRefresh: forceRefresh),
    ]);
  }

  Future<void> _fetchSummary({bool forceRefresh = false}) async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final result = await PredictionApiService.fetchYearlySummary(
        name: widget.request.name,
        birthDate: widget.request.birthDate,
        birthTime: widget.request.birthTime,
        latitude: widget.request.latitude,
        longitude: widget.request.longitude,
        timezone: widget.request.timezone,
        year: _year,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _summary = result;
        _summaryLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.toString();
        _summaryLoading = false;
      });
    }
  }

  Future<void> _fetchMonthly({bool forceRefresh = false}) async {
    setState(() {
      _monthlyLoading = true;
      _monthlyError = null;
    });
    try {
      final result = await PredictionApiService.fetchMonthlyPrediction(
        name: widget.request.name,
        birthDate: widget.request.birthDate,
        birthTime: widget.request.birthTime,
        latitude: widget.request.latitude,
        longitude: widget.request.longitude,
        timezone: widget.request.timezone,
        year: _year,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _monthly = result;
        _monthlyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _monthlyError = e.toString();
        _monthlyLoading = false;
      });
    }
  }

  void _shiftYear(int delta) {
    setState(() {
      _year += delta;
      _summary = null;
      _monthly = null;
    });
    _fetchAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1745),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Varshaphal'),
        actions: [
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
              padding: EdgeInsets.all(12),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              _buildYearStepper(),
              TabBar(
                controller: _tabs,
                indicatorColor: const Color(0xFF7C4DFF),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                tabs: const [
                  Tab(
                      icon: Icon(Icons.assessment_outlined, size: 18),
                      text: 'Combined Effect'),
                  Tab(
                      icon: Icon(Icons.calendar_view_month, size: 18),
                      text: 'Monthly'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            _buildSummaryTab(),
            _buildMonthlyTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildYearStepper() {
    return Container(
      color: const Color(0xFF1A1745),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70),
            onPressed: () => _shiftYear(-1),
            tooltip: 'Previous year',
          ),
          Expanded(
            child: Center(
              child: Column(
                children: [
                  Text(
                    'Year $_year',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (_summary != null)
                    Text(
                      'Tajika year ${_summary!.tajikaYear} · Pravesh ${_summary!.varshapravesh.split('T').first}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white70),
            onPressed: () => _shiftYear(1),
            tooltip: 'Next year',
          ),
        ],
      ),
    );
  }

  // ─── Combined-effect tab ──────────────────────────────────────────────────

  Widget _buildSummaryTab() {
    if (_summaryLoading) {
      return const Center(child: CosmicLoader(message: 'Casting annual chart…'));
    }
    if (_summaryError != null) {
      return _ErrorRetry(
        message: _summaryError!,
        onRetry: () => _fetchSummary(forceRefresh: true),
      );
    }
    final s = _summary;
    if (s == null) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: Colors.white70)),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
        _OverallBanner(effect: s.overallEffect),
        const SizedBox(height: 16),
        _SectionHeader('Combined Effect of Factors Analysed'),
        ...s.factors.map((f) => _FactorCard(factor: f)),
        const SizedBox(height: 16),
        _SectionHeader('Annual Chart'),
        _AnnualChartCard(chart: s.annualChart, muntha: s.muntha),
        const SizedBox(height: 16),
        _SectionHeader('Sarvashtavarga Points'),
        _SarvashtaGrid(points: s.sarvashtavarga),
        const SizedBox(height: 16),
        _SectionHeader('Varsheshwara — Lord of the Year'),
        _VarsheshwaraCard(info: s.varsheshwara),
      ],
    );
  }

  // ─── Monthly tab ──────────────────────────────────────────────────────────

  Widget _buildMonthlyTab() {
    if (_monthlyLoading) {
      return const Center(child: CosmicLoader(message: 'Tracking the Sun…'));
    }
    if (_monthlyError != null) {
      return _ErrorRetry(
        message: _monthlyError!,
        onRetry: () => _fetchMonthly(forceRefresh: true),
      );
    }
    final m = _monthly;
    if (m == null) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: Colors.white70)),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.nightlight_round,
                  color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Predictions counted from your natal Moon in ${m.natalMoonSignVedic}.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...m.periods.map((p) => _MonthlyPeriodCard(period: p)),
      ],
    );
  }
}

// ─── Sub-widgets ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
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

class _OverallBanner extends StatelessWidget {
  final String effect;
  const _OverallBanner({required this.effect});

  @override
  Widget build(BuildContext context) {
    final fav = effect == 'Favourable';
    final color = fav ? Colors.greenAccent : Colors.orangeAccent;
    final icon = fav ? Icons.check_circle : Icons.warning_amber_rounded;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1.4),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Overall outlook',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  effect,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FactorCard extends StatelessWidget {
  final FactorRow factor;
  const _FactorCard({required this.factor});

  @override
  Widget build(BuildContext context) {
    final fav = factor.effect == 'Favourable';
    final color = fav ? Colors.greenAccent : Colors.orangeAccent;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  factor.factor,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  factor.effect,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (factor.detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              factor.detail,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
          if (factor.rows != null && factor.rows!.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...factor.rows!.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 70,
                        child: Text(
                          r.planet,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'h${r.house} · ${r.sign}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Text(
                        r.effect,
                        style: TextStyle(
                          color: r.effect == 'Favourable'
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
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

class _AnnualChartCard extends StatelessWidget {
  final AnnualChart chart;
  final MunthaInfo muntha;
  const _AnnualChartCard({required this.chart, required this.muntha});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv('Varsha Lagna', '${chart.lagnaVedic} (lord ${chart.lagnaLord})'),
          _kv('Birth Lagna',
              '${chart.birthLagnaVedic} → ${_ordinal(chart.birthLagnaHouseInAnnual)} house'),
          _kv('Muntha',
              '${muntha.signVedic} → ${_ordinal(muntha.house)} house'),
          if (muntha.lordHouseInAnnual != null)
            _kv('Muntha Lord',
                '${muntha.lord} → ${_ordinal(muntha.lordHouseInAnnual!)} house'),
          const Divider(color: Colors.white24, height: 20),
          ...chart.planets.map(_planetRow),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                k,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
            Expanded(
              child: Text(
                v,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _planetRow(AnnualPlanet p) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(
                p.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                '${p.signVedic} · ${_ordinal(p.house)} house',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
}

class _SarvashtaGrid extends StatelessWidget {
  final Map<String, int> points;
  const _SarvashtaGrid({required this.points});

  @override
  Widget build(BuildContext context) {
    // Keep canonical Vedic sign order so the grid reads consistently across
    // charts and matches the Yearly.docx reference.
    const order = [
      'Mesha', 'Vrishabha', 'Mithuna', 'Karkata',
      'Simha', 'Kanya', 'Tula', 'Vrischika',
      'Dhanu', 'Makara', 'Kumbha', 'Meena',
    ];
    final entries = order
        .where(points.containsKey)
        .map((k) => MapEntry(k, points[k]!))
        .toList();

    int maxPoints = 0;
    for (final e in entries) {
      if (e.value > maxPoints) maxPoints = e.value;
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      childAspectRatio: 1.6,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: entries.map((e) {
        final isMax = e.value == maxPoints;
        final color = isMax
            ? const Color(0xFFFFD700)
            : (e.value >= 30
                ? Colors.greenAccent
                : (e.value < 25 ? Colors.orangeAccent : Colors.white70));
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                e.key,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${e.value}',
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _VarsheshwaraCard extends StatelessWidget {
  final VarsheshwaraInfo info;
  const _VarsheshwaraCard({required this.info});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFD700).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFFFFD700).withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome,
              color: Color(0xFFFFD700), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.planet,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${info.role}${info.house != null ? " · ${_ordinal(info.house!)} house" : ""}${info.sign != null ? " (${info.sign})" : ""}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthlyPeriodCard extends StatelessWidget {
  final MonthlyPeriod period;
  const _MonthlyPeriodCard({required this.period});

  Color _bandColor() {
    switch (period.band) {
      case 'high':
        return Colors.greenAccent;
      case 'low':
        return Colors.orangeAccent;
      default:
        return const Color(0xFF7C4DFF);
    }
  }

  String _formatRange() {
    DateTime? from = DateTime.tryParse(period.fromDate);
    DateTime? to = DateTime.tryParse(period.toDate);
    if (from == null || to == null) {
      return '${period.fromDate} → ${period.toDate}';
    }
    final fmt = DateFormat('MMM d');
    final yfmt = DateFormat('MMM d, yyyy');
    return '${fmt.format(from)} → ${yfmt.format(to)}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _bandColor();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatRange(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${period.sarvashtavargaPoints} bindus',
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _miniChip('☉ Sun', '${period.sunSignVedic} · h${period.sunHouseFromMoon}'),
              _miniChip('♃ Jupiter', '${period.jupiterSignVedic} · h${period.jupiterHouseFromMoon}'),
            ],
          ),
          if (period.theme.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              period.theme,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
          if (!period.prediction.isEmpty) ...[
            const SizedBox(height: 8),
            _categoryRow(
              icon: Icons.work_outline,
              label: 'Work',
              text: period.prediction.work,
              color: color,
            ),
            _categoryRow(
              icon: Icons.favorite_border,
              label: 'Health',
              text: period.prediction.health,
              color: color,
            ),
            _categoryRow(
              icon: Icons.people_outline,
              label: 'Relationship',
              text: period.prediction.relationship,
              color: color,
            ),
            _categoryRow(
              icon: Icons.account_balance_wallet_outlined,
              label: 'Investment',
              text: period.prediction.investment,
              color: color,
            ),
          ],
        ],
      ),
    );
  }

  Widget _categoryRow({
    required IconData icon,
    required String label,
    required String text,
    required Color color,
  }) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.85)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🌌', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
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
}

String _ordinal(int n) {
  final v = n % 100;
  if (v >= 11 && v <= 13) return '${n}th';
  switch (n % 10) {
    case 1:
      return '${n}st';
    case 2:
      return '${n}nd';
    case 3:
      return '${n}rd';
    default:
      return '${n}th';
  }
}
