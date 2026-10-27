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
/// /api/mind-energy-monthly. Tap a legend chip to show/hide a metric's line;
/// tap a day to see all five scores and its top drivers.
class MindEnergyScreen extends StatefulWidget {
  final PredictionRequest request;

  const MindEnergyScreen({super.key, required this.request});

  @override
  State<MindEnergyScreen> createState() => _MindEnergyScreenState();
}

class _MindEnergyScreenState extends State<MindEnergyScreen> {
  late DateTime _month; // first day of the displayed month
  MindEnergyMonth? _data;
  String? _error;
  bool _loading = false;
  int? _selectedDay;
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

  Future<void> _fetch({bool forceRefresh = false}) async {
    final requested = _monthKey;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PredictionApiService.fetchMindEnergyMonthly(
        name: widget.request.name,
        birthDate: widget.request.birthDate,
        birthTime: widget.request.birthTime,
        latitude: widget.request.latitude,
        longitude: widget.request.longitude,
        timezone: widget.request.timezone,
        month: requested,
        forceRefresh: forceRefresh,
      );
      if (!mounted || requested != _monthKey) return;
      final now = DateTime.now();
      final isCurrent = _month.year == now.year && _month.month == now.month;
      setState(() {
        _data = result;
        _loading = false;
        _selectedDay =
            isCurrent && result.days.any((d) => d.dayOfMonth == now.day)
            ? now.day
            : null;
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
      _selectedDay = null;
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
    if (data == null || data.days.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('No data.', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    MindEnergyDay? selected;
    for (final d in data.days) {
      if (d.dayOfMonth == _selectedDay) selected = d;
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
            data: data,
            month: _month,
            selectedDay: _selectedDay,
            visible: _visible,
            onSelect: (day) => setState(() => _selectedDay = day),
          ),
        ),
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
  final MindEnergyMonth data;
  final DateTime month;
  final int? selectedDay;
  final Set<String> visible;
  final ValueChanged<int> onSelect;
  const _Chart({
    required this.data,
    required this.month,
    required this.selectedDay,
    required this.visible,
    required this.onSelect,
  });

  List<FlSpot> _spots(double Function(MindEnergyDay) pick) => [
    for (final d in data.days)
      if (d.dayOfMonth > 0) FlSpot(d.dayOfMonth.toDouble(), pick(d)),
  ];

  LineChartBarData _line(Color color, double Function(MindEnergyDay) pick) {
    final spots = _spots(pick);
    return LineChartBarData(
      spots: spots,
      isCurved: true,
      curveSmoothness: 0.2,
      preventCurveOverShooting: true,
      color: color,
      barWidth: 2.5,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.x.toInt() == selectedDay,
        getDotPainter: (spot, a, b, c) => FlDotCirclePainter(
          radius: 5,
          color: color,
          strokeWidth: 2,
          strokeColor: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final now = DateTime.now();
    final isCurrent = month.year == now.year && month.month == now.month;
    final gridColor = Colors.white.withValues(alpha: 0.08);
    const labelStyle = TextStyle(color: Colors.white54, fontSize: 10);

    return LineChart(
      LineChartData(
        minX: 1,
        maxX: daysInMonth.toDouble(),
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
                final day = v.toInt();
                final show =
                    day == 1 ||
                    day == daysInMonth ||
                    (day % 5 == 0 && day <= daysInMonth - 2);
                if (!show || v != day.toDouble()) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text('$day', style: labelStyle),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          verticalLines: [
            if (selectedDay != null)
              VerticalLine(
                x: selectedDay!.toDouble(),
                color: Colors.white.withValues(alpha: 0.25),
                strokeWidth: 1,
              ),
            if (isCurrent)
              VerticalLine(
                x: now.day.toDouble(),
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
            onSelect(spots.first.x.toInt());
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
          'scored 0–100 each day from the transits against your birth chart: under 25 is very low, 25–44 low, 45–59 moderate, 60–79 high, 80+ very high.',
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
