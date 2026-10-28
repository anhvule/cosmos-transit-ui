import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mind_energy.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

class _Metric {
  final String key; // matches MindEnergyDriver.metric
  final String label;
  final Color color;
  final double Function(MindEnergyDay) pick;
  const _Metric(this.key, this.label, this.color, this.pick);
}

final _metrics = <_Metric>[
  _Metric(
    'overthinking',
    'Overthinking',
    const Color(0xFFFBBF24),
    (d) => d.overthinking,
  ),
  _Metric('vitality', 'Vitality', const Color(0xFF4ADE80), (d) => d.vitality),
  _Metric('focus', 'Focus', const Color(0xFF60A5FA), (d) => d.focus),
  _Metric(
    'irritability',
    'Irritability',
    const Color(0xFFF87171),
    (d) => d.irritability,
  ),
  _Metric(
    'steadiness',
    'Steadiness',
    const Color(0xFFC084FC),
    (d) => d.steadiness,
  ),
];

Color _colorFor(String key) => _metrics
    .firstWhere((m) => m.key == key, orElse: () => _metrics.first)
    .color;

/// Monthly line chart of daily Mind & Energy scores (0–100) — wraps
/// /api/mind-energy-monthly. Also fetches the previous month so each metric's
/// monthly average can be compared, since the Moon's daily swings hide slower
/// shifts (sub-periods, Saturn). Tap a legend chip to show/hide a metric's
/// line; tap a day to see all five scores and its top drivers.
class MindEnergyScreen extends StatefulWidget {
  final PredictionRequest request;

  const MindEnergyScreen({super.key, required this.request});

  @override
  State<MindEnergyScreen> createState() => _MindEnergyScreenState();
}

class _MindEnergyScreenState extends State<MindEnergyScreen> {
  late DateTime _month; // first day of the displayed month
  MindEnergyMonth? _data;
  MindEnergyMonth? _previous; // month before, for the averages comparison
  String? _error;
  bool _loading = false;
  String? _selectedDate; // YYYY-MM-DD
  // Two lines by default so the chart isn't crowded; the rest are a tap away.
  final Set<String> _visible = {'overthinking', 'vitality'};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  String get _monthKey => DateFormat('yyyy-MM').format(_month);

  Future<MindEnergyMonth> _fetchMonth(DateTime month, bool forceRefresh) =>
      PredictionApiService.fetchMindEnergyMonthly(
        name: widget.request.name,
        birthDate: widget.request.birthDate,
        birthTime: widget.request.birthTime,
        latitude: widget.request.latitude,
        longitude: widget.request.longitude,
        timezone: widget.request.timezone,
        month: DateFormat('yyyy-MM').format(month),
        forceRefresh: forceRefresh,
      );

  Future<void> _fetch({bool forceRefresh = false}) async {
    final requested = _monthKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // The previous month only feeds the comparison, so its failure is not fatal.
      final previous = _fetchMonth(
        DateTime(_month.year, _month.month - 1),
        forceRefresh,
      ).then<MindEnergyMonth?>((m) => m, onError: (_) => null);
      final result = await _fetchMonth(_month, forceRefresh);
      final prev = await previous;
      if (!mounted || requested != _monthKey) return;
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      setState(() {
        _data = result;
        _previous = prev;
        _loading = false;
        _selectedDate = result.days.any((d) => d.date == today) ? today : null;
      });
    } catch (e) {
      if (!mounted || requested != _monthKey) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _data = null;
      _previous = null;
      _selectedDate = null;
    });
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0B2E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1745),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Mind & Energy'),
        actions: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _fetch(),
            onLongPress: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Bypassing cache — refetching…'),
                  duration: Duration(seconds: 1),
                ),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      children: [
        _MonthHeader(
          month: _month,
          onPrev: () => _shiftMonth(-1),
          onNext: () => _shiftMonth(1),
        ),
        const SizedBox(height: 12),
        _buildChartArea(),
        const SizedBox(height: 16),
        const _Explainer(),
      ],
    );
  }

  Widget _buildChartArea() {
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CosmicLoader(message: 'Reading your chart…')),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 300,
        child: _ErrorRetry(
          message: _error!,
          onRetry: () => _fetch(forceRefresh: true),
        ),
      );
    }
    final data = _data;
    final days = [
      for (final d in data?.days ?? const <MindEnergyDay>[])
        if (d.dayOfMonth > 0) d,
    ];
    if (days.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('No data.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    MindEnergyDay? selected;
    for (final d in days) {
      if (d.date == _selectedDate) selected = d;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Legend(
          visible: _visible,
          onToggle: (key) => setState(() {
            // Keep at least one line on the chart.
            if (_visible.contains(key)) {
              if (_visible.length > 1) _visible.remove(key);
            } else {
              _visible.add(key);
            }
          }),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: _Chart(
            days: days,
            selectedDate: _selectedDate,
            visible: _visible,
            onSelect: (date) => setState(() => _selectedDate = date),
          ),
        ),
        const SizedBox(height: 12),
        _PeriodStrip(days: days),
        const SizedBox(height: 12),
        _MonthAverages(month: data!, previous: _previous, visible: _visible),
        const SizedBox(height: 16),
        if (selected != null)
          _DayCard(day: selected)
        else
          Text(
            'Tap a point on the chart to see what shaped that day.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _MonthHeader extends StatelessWidget {
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left, color: Colors.white70),
          tooltip: 'Previous month',
        ),
        Text(
          DateFormat('MMMM yyyy').format(month),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right, color: Colors.white70),
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Set<String> visible;
  final ValueChanged<String> onToggle;
  const _Legend({required this.visible, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    Widget item(_Metric m) {
      final on = visible.contains(m.key);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggle(m.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: on ? m.color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: on ? m.color : Colors.white.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 4,
                decoration: BoxDecoration(
                  color: on ? m.color : Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                m.label,
                style: TextStyle(
                  color: on ? Colors.white : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final m in _metrics) item(m),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '┆',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Today',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class _Chart extends StatelessWidget {
  final List<MindEnergyDay> days; // one month, oldest first
  final String? selectedDate;
  final Set<String> visible;
  final ValueChanged<String> onSelect;
  const _Chart({
    required this.days,
    required this.selectedDate,
    required this.visible,
    required this.onSelect,
  });

  LineChartBarData _line(Color color, double Function(MindEnergyDay) pick) {
    return LineChartBarData(
      spots: [
        for (var i = 0; i < days.length; i++)
          FlSpot(i.toDouble(), pick(days[i])),
      ],
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => days[spot.x.toInt()].date == selectedDate,
        getDotPainter: (spot, a, b, c) => FlDotCirclePainter(
          radius: 5,
          color: color,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
    );
  }

  /// Indexes where the sub-period lord changes from the previous day.
  List<int> _periodChanges() => [
    for (var i = 1; i < days.length; i++)
      if (days[i].period?.pratyantardasha != null &&
          days[i - 1].period?.pratyantardasha != null &&
          days[i].period!.pratyantardasha !=
              days[i - 1].period!.pratyantardasha)
        i,
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayIdx = days.indexWhere((d) => d.date == today);
    final selectedIdx = days.indexWhere((d) => d.date == selectedDate);
    final gridColor = Colors.white.withValues(alpha: 0.08);
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 10);

    String? bottomLabel(int i) {
      final d = days[i];
      final last = days.length;
      final show =
          d.dayOfMonth == 1 ||
          d.dayOfMonth == last ||
          (d.dayOfMonth % 5 == 0 && d.dayOfMonth <= last - 2);
      return show ? '${d.dayOfMonth}' : null;
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (days.length - 1).toDouble(),
        minY: 0,
        maxY: 100,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 25,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: gridColor, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 25,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(v.toInt().toString(), style: labelStyle),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                final label = v == i.toDouble() && i >= 0 && i < days.length
                    ? bottomLabel(i)
                    : null;
                if (label == null) return const SizedBox.shrink();
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(label, style: labelStyle),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          // Each visible metric's monthly average, so the month's overall
          // level reads at a glance under the daily swings.
          horizontalLines: [
            for (final m in _metrics)
              if (visible.contains(m.key))
                HorizontalLine(
                  y: days.map(m.pick).reduce((a, b) => a + b) / days.length,
                  color: m.color.withValues(alpha: 0.55),
                  strokeWidth: 1,
                  dashArray: [6, 4],
                ),
          ],
          verticalLines: [
            for (final i in _periodChanges())
              VerticalLine(
                x: i.toDouble(),
                color: const Color(0xFFB39DDB).withValues(alpha: 0.7),
                strokeWidth: 1.2,
                dashArray: [2, 3],
                label: VerticalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  style: const TextStyle(
                    color: Color(0xFFB39DDB),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                  labelResolver: (_) => days[i].period!.pratyantardasha!,
                ),
              ),
            if (selectedIdx >= 0)
              VerticalLine(
                x: selectedIdx.toDouble(),
                color: Colors.white.withValues(alpha: 0.25),
                strokeWidth: 1,
              ),
            if (todayIdx >= 0)
              VerticalLine(
                x: todayIdx.toDouble(),
                color: Colors.white.withValues(alpha: 0.6),
                strokeWidth: 1.2,
                dashArray: [4, 4],
              ),
          ],
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchSpotThreshold: 24,
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((_) => null).toList(),
          ),
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions) return;
            final spots = response?.lineBarSpots;
            if (spots == null || spots.isEmpty) return;
            // Select on tap and while dragging, so the marker follows the finger.
            onSelect(days[spots.first.x.toInt()].date);
          },
        ),
        lineBarsData: [
          for (final m in _metrics)
            if (visible.contains(m.key)) _line(m.color, m.pick),
        ],
      ),
    );
  }
}

/// The dasha sub-periods (pratyantardasha) covering the shown days, with
/// their full date spans — these are the slow backdrop behind the daily lines.
class _PeriodStrip extends StatelessWidget {
  final List<MindEnergyDay> days;
  const _PeriodStrip({required this.days});

  static String _fmt(String? iso) {
    final dt = iso == null ? null : DateTime.tryParse(iso);
    return dt == null ? '?' : DateFormat('d MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final periods = <MindEnergyPeriod>[];
    for (final d in days) {
      final p = d.period;
      if (p?.pratyantardasha == null) continue;
      if (periods.isEmpty ||
          periods.last.pratyantardasha != p!.pratyantardasha ||
          periods.last.pratyantardashaStart != p.pratyantardashaStart) {
        periods.add(p!);
      }
    }
    if (periods.isEmpty) return const SizedBox.shrink();
    final muted = Colors.white.withValues(alpha: 0.6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SUB-PERIODS (${periods.first.mahadasha} › ${periods.first.antardasha})',
          style: TextStyle(
            color: muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in periods)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1745),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFFB39DDB).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '${p.pratyantardasha} · ${_fmt(p.pratyantardashaStart)} – ${_fmt(p.pratyantardashaEnd)}',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Average of each visible metric for this month next to the month before,
/// with the change — the direct month-to-month comparison.
class _MonthAverages extends StatelessWidget {
  final MindEnergyMonth month;
  final MindEnergyMonth? previous;
  final Set<String> visible;
  const _MonthAverages({
    required this.month,
    required this.previous,
    required this.visible,
  });

  static double? _avg(MindEnergyMonth? m, double Function(MindEnergyDay) pick) {
    final days = (m?.days ?? const <MindEnergyDay>[])
        .where((d) => d.dayOfMonth > 0)
        .toList();
    if (days.isEmpty) return null;
    return days.map(pick).reduce((a, b) => a + b) / days.length;
  }

  static String _name(String yyyyMm, String fallback) {
    final dt = DateTime.tryParse('$yyyyMm-01');
    return dt == null ? fallback : DateFormat('MMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics.where((m) => visible.contains(m.key)).toList();
    final headStyle = TextStyle(
      color: Colors.white.withValues(alpha: 0.6),
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    final prevName = previous == null
        ? 'Last month'
        : _name(previous!.month, 'Last month');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1745),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1.6)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              Text('MONTHLY AVERAGE', style: headStyle),
              Text(prevName, textAlign: TextAlign.right, style: headStyle),
              Text(
                _name(month.month, 'This month'),
                textAlign: TextAlign.right,
                style: headStyle,
              ),
            ],
          ),
          for (final metric in metrics)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    metric.label,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _AvgCell(
                    value: _avg(previous, metric.pick),
                    color: metric.color.withValues(alpha: 0.6),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _AvgCell(
                    value: _avg(month, metric.pick),
                    previous: _avg(previous, metric.pick),
                    color: metric.color,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _AvgCell extends StatelessWidget {
  final double? value;
  final double? previous;
  final Color color;
  const _AvgCell({required this.value, this.previous, required this.color});

  @override
  Widget build(BuildContext context) {
    if (value == null) {
      return const Text(
        '–',
        textAlign: TextAlign.right,
        style: TextStyle(color: Colors.white54),
      );
    }
    final diff = previous == null ? null : (value! - previous!).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value!.round().toString(),
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (diff != null && diff != 0)
          Text(
            diff > 0 ? '+$diff' : '−${-diff}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 10,
            ),
          ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  final MindEnergyDay day;
  const _DayCard({required this.day});

  static String _heading(String iso) {
    final dt = DateTime.tryParse(iso);
    return dt == null ? iso : DateFormat('EEEE, d MMMM').format(dt);
  }

  @override
  Widget build(BuildContext context) {
    final drivers = day.drivers.take(5).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1745),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _heading(day.date),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (day.period?.pratyantardasha != null) ...[
            const SizedBox(height: 2),
            Text(
              'Dasha ${day.period!.mahadasha} › ${day.period!.antardasha} › ${day.period!.pratyantardasha}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              runSpacing: 14,
              children: [
                for (final m in _metrics)
                  SizedBox(
                    width: constraints.maxWidth / 2,
                    child: _Score(
                      label: m.label,
                      value: m.pick(day),
                      color: m.color,
                    ),
                  ),
              ],
            ),
          ),
          if (drivers.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'TOP DRIVERS',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            for (final d in drivers) _DriverRow(driver: d),
          ],
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _Score({required this.label, required this.value, required this.color});

  static String _level(double v) {
    if (v < 25) return 'Very low';
    if (v < 45) return 'Low';
    if (v < 60) return 'Moderate';
    if (v < 80) return 'High';
    return 'Very high';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value.round().toString(),
              style: TextStyle(
                color: color,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              ' / 100',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
        Text(
          _level(value),
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 6,
              color: color,
              backgroundColor: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
      ],
    );
  }
}

class _DriverRow extends StatelessWidget {
  final MindEnergyDriver driver;
  const _DriverRow({required this.driver});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(driver.metric);
    final sign = driver.delta > 0 ? '+' : (driver.delta < 0 ? '−' : '');
    final value = driver.delta.abs();
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              '$sign$text',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              driver.label,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _Explainer extends StatelessWidget {
  const _Explainer();

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(
      color: Colors.white.withValues(alpha: 0.65),
      fontSize: 13,
      height: 1.4,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overthinking estimates how busy and restless the mind may feel. '
          'Vitality combines mental stamina and physical energy. '
          'Focus reflects mental clarity and concentration. '
          'Irritability shows how short your temper may run. '
          'Steadiness reflects how emotionally settled you may feel. All are '
          'scored 0–100 each day from the transits against your birth chart: under 25 is very low, 25–44 low, 45–59 moderate, 60–79 high, 80+ very high. '
          'The Moon moves the daily line; slower factors — your dasha sub-period and Saturn — '
          'set the backdrop for weeks at a time. The dashed lines mark each '
          "month's average; compare it with last month in the table below the chart.",
          style: muted,
        ),
        const SizedBox(height: 8),
        Text(
          'For reflection, not medical advice.',
          style: muted.copyWith(fontStyle: FontStyle.italic),
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
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
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
