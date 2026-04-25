import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/investment_forecast.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

/// Inputs the caller must provide — re-used natal chart data.
class ForecastInputs {
  final String name;
  final String birthDate; // YYYY-MM-DD
  final String birthTime; // HH:mm
  final double latitude;
  final double longitude;
  final String timezone;

  ForecastInputs({
    required this.name,
    required this.birthDate,
    required this.birthTime,
    required this.latitude,
    required this.longitude,
    required this.timezone,
  });
}

class InvestmentForecastScreen extends StatefulWidget {
  final ForecastInputs initialInputs;

  const InvestmentForecastScreen({
    super.key,
    required this.initialInputs,
  });

  @override
  State<InvestmentForecastScreen> createState() =>
      _InvestmentForecastScreenState();
}

class _InvestmentForecastScreenState extends State<InvestmentForecastScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Monday-of-current-week for weekStart default
  DateTime _weekStart = _defaultWeekStart();
  // YYYY-MM of current month
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  InvestmentForecast? _weekly;
  InvestmentForecast? _monthly;
  bool _loadingWeekly = false;
  bool _loadingMonthly = false;
  String? _weeklyError;
  String? _monthlyError;

  static DateTime _defaultWeekStart() {
    final now = DateTime.now();
    // Monday of this week (ISO week). weekday: 1 = Mon, 7 = Sun.
    return now.subtract(Duration(days: now.weekday - 1));
  }

  bool _monthlyFetchedOnce = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Only auto-fetch weekly on open. Monthly is heavy (Heroku H12 risk) —
    // fire it lazily the first time the user switches to the Monthly tab.
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchWeekly());
  }

  void _onTabChanged() {
    if (_tabController.index == 1 && !_monthlyFetchedOnce) {
      _monthlyFetchedOnce = true;
      _fetchMonthly();
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _monthStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  Future<void> _fetchWeekly({bool forceRefresh = false}) async {
    setState(() {
      _loadingWeekly = true;
      _weeklyError = null;
    });
    try {
      final i = widget.initialInputs;
      final result = await PredictionApiService.fetchInvestmentWeekly(
        name: i.name,
        birthDate: i.birthDate,
        birthTime: i.birthTime,
        latitude: i.latitude,
        longitude: i.longitude,
        timezone: i.timezone,
        weekStart: _fmt(_weekStart),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _weekly = result;
        _loadingWeekly = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _weeklyError = e.toString();
        _loadingWeekly = false;
      });
    }
  }

  Future<void> _fetchMonthly({bool forceRefresh = false}) async {
    setState(() {
      _loadingMonthly = true;
      _monthlyError = null;
    });
    try {
      final i = widget.initialInputs;
      final result = await PredictionApiService.fetchInvestmentMonthly(
        name: i.name,
        birthDate: i.birthDate,
        birthTime: i.birthTime,
        latitude: i.latitude,
        longitude: i.longitude,
        timezone: i.timezone,
        month: _monthStr(_month),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _monthly = result;
        _loadingMonthly = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _monthlyError = e.toString();
        _loadingMonthly = false;
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
        title: const Text('Investment Forecast'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7C4DFF),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      // Top is handled by the AppBar. Disable bottom so the list can scroll
      // past the home indicator; we add that inset as bottom padding inside
      // the ListView so the last item stays reachable.
      body: SafeArea(
        top: false,
        bottom: false,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildWeeklyTab(),
            _buildMonthlyTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyTab() {
    return Column(
      children: [
        _buildWeekPicker(),
        Expanded(child: _buildForecastBody(
          loading: _loadingWeekly,
          error: _weeklyError,
          forecast: _weekly,
          onRetry: _fetchWeekly,
          emptyLabel: 'Pick a week to load.',
        )),
      ],
    );
  }

  Widget _buildMonthlyTab() {
    return Column(
      children: [
        _buildMonthPicker(),
        Expanded(child: _buildForecastBody(
          loading: _loadingMonthly,
          error: _monthlyError,
          forecast: _monthly,
          onRetry: _fetchMonthly,
          emptyLabel: 'Pick a month to load.',
        )),
      ],
    );
  }

  Widget _buildWeekPicker() {
    final end = _weekStart.add(const Duration(days: 6));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1A1745),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _weekStart,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Pick any day of the target week',
                );
                if (picked != null) {
                  setState(() =>
                      _weekStart = picked.subtract(
                          Duration(days: picked.weekday - 1)));
                  _fetchWeekly();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Week (Mon–Sun)',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmt(_weekStart)}  →  ${_fmt(end)}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadingWeekly ? null : () => _fetchWeekly(),
            onLongPress: _loadingWeekly
                ? null
                : () => _fetchWeekly(forceRefresh: true),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFF1A1745),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _month,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  helpText: 'Pick any day of the target month',
                );
                if (picked != null) {
                  setState(() =>
                      _month = DateTime(picked.year, picked.month));
                  _fetchMonthly();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Month',
                        style: TextStyle(
                            color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy').format(_month),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _loadingMonthly ? null : () => _fetchMonthly(),
            onLongPress: _loadingMonthly
                ? null
                : () => _fetchMonthly(forceRefresh: true),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildForecastBody({
    required bool loading,
    required String? error,
    required InvestmentForecast? forecast,
    required VoidCallback onRetry,
    required String emptyLabel,
  }) {
    if (loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CosmicLoader(message: 'Crunching the cosmos...'),
            SizedBox(height: 6),
            Text('Monthly can take up to ~4 min.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
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
    if (forecast == null) {
      return Center(
        child: Text(emptyLabel,
            style: const TextStyle(color: Colors.white70)),
      );
    }
    return _ForecastContent(forecast: forecast);
  }
}

class _ForecastContent extends StatelessWidget {
  final InvestmentForecast forecast;

  const _ForecastContent({required this.forecast});

  Color _impactColor(String? impact) {
    switch ((impact ?? '').toLowerCase()) {
      case 'impactful':
        return Colors.orangeAccent;
      case 'slightly impactful':
        return const Color(0xFF7C4DFF);
      case 'positive':
      case 'good':
        return Colors.greenAccent;
      case 'negative':
      case 'caution':
      case 'bad':
        return Colors.redAccent;
      default:
        return const Color(0xFF7C4DFF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
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
                forecast.period.toUpperCase(),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${forecast.startDate}  →  ${forecast.endDate}',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '${forecast.days.length} day${forecast.days.length == 1 ? '' : 's'} · '
                '${forecast.aggregatedAspects.length} aspect${forecast.aggregatedAspects.length == 1 ? '' : 's'} · '
                '${forecast.aggregatedRulers.length} ruler${forecast.aggregatedRulers.length == 1 ? '' : 's'}',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (forecast.aggregatedAspects.isNotEmpty) ...[
          _sectionHeader('Period Highlights — Aspects'),
          ...forecast.aggregatedAspects
              .map((a) => _aggregatedAspectCard(a)),
          const SizedBox(height: 20),
        ],
        if (forecast.aggregatedRulers.isNotEmpty) ...[
          _sectionHeader('Period Highlights — Rulers'),
          ...forecast.aggregatedRulers.map(_aggregatedRulerCard),
          const SizedBox(height: 20),
        ],
        if (forecast.days.isNotEmpty) ...[
          _sectionHeader('Daily Breakdown'),
          ...forecast.days.map(_dayTile),
        ],
      ],
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _aggregatedAspectCard(AggregatedAspect a) {
    final c = _impactColor(a.impact);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.4)),
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
              if ((a.impact ?? '').isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(a.impact!,
                      style: TextStyle(color: c, fontSize: 11)),
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
                  height: 1.4),
            ),
          ],
          if (a.dates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _dateChips(a.dates),
          ],
        ],
      ),
    );
  }

  Widget _aggregatedRulerCard(AggregatedRuler r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.3)),
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
                  height: 1.4),
            ),
          ],
          if (r.dates.isNotEmpty) ...[
            const SizedBox(height: 10),
            _dateChips(r.dates),
          ],
        ],
      ),
    );
  }

  Widget _dateChips(List<String> dates) {
    final uniqueDates = dates.toSet().toList()..sort();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: uniqueDates
          .map((d) => Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(d,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 11)),
              ))
          .toList(),
    );
  }

  Widget _dayTile(InvestmentDay day) {
    final hasContent = day.aspects.isNotEmpty || day.rulers.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Theme(
        data: ThemeData.dark().copyWith(
          dividerColor: Colors.transparent,
          colorScheme: const ColorScheme.dark(primary: Color(0xFF7C4DFF)),
        ),
        child: ExpansionTile(
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding:
              const EdgeInsets.fromLTRB(14, 0, 14, 12),
          title: Row(
            children: [
              Text(
                day.date,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              Text(
                '${day.aspects.length}a · ${day.rulers.length}r',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          children: hasContent
              ? [
                  if (day.aspects.isNotEmpty) ...[
                    _miniHeader('Aspects'),
                    ...day.aspects.map((a) => _miniAspect(a)),
                  ],
                  if (day.rulers.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _miniHeader('Rulers'),
                    ...day.rulers.map((r) => _miniRuler(r)),
                  ],
                ]
              : const [
                  Padding(
                    padding: EdgeInsets.only(top: 4, bottom: 8),
                    child: Text('No events.',
                        style: TextStyle(color: Colors.white54)),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _miniHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
              color: Colors.white54,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1),
        ),
      );

  Widget _miniAspect(dynamic a) {
    final c = _impactColor(a.impact as String?);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  a.description as String,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (((a.impact as String?) ?? '').isNotEmpty)
                Text(
                  a.impact as String,
                  style: TextStyle(color: c, fontSize: 11),
                ),
            ],
          ),
          if (((a.interpretation as String?) ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                a.interpretation as String,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.35),
              ),
            ),
        ],
      ),
    );
  }

  Widget _miniRuler(dynamic r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.description as String,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          if (((r.interpretation as String?) ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                r.interpretation as String,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.35),
              ),
            ),
        ],
      ),
    );
  }
}
