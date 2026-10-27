import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/mind_energy.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

const _overthinkingColor = Color(0xFFFBBF24);
const _vitalityColor = Color(0xFF4ADE80);

/// Monthly line chart of daily overthinking and vitality scores (0–100) —
/// wraps /api/mind-energy-monthly. Tap a day to see its top drivers.
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
        const _Legend(),
        const SizedBox(height: 12),
        SizedBox(
          height: 260,
          child: _Chart(
            data: data,
            month: _month,
            selectedDay: _selectedDay,
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
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 4,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      children: [
        item(_overthinkingColor, 'Overthinking'),
        item(_vitalityColor, 'Vitality'),
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
  final ValueChanged<int> onSelect;
  const _Chart({
    required this.data,
    required this.month,
    required this.selectedDay,
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
            if (event is FlTapUpEvent || event is FlPanEndEvent) {
              onSelect(spots.first.x.toInt());
            }
          },
        ),
        lineBarsData: [
          _line(_overthinkingColor, (d) => d.overthinking),
          _line(_vitalityColor, (d) => d.vitality),
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
    final drivers = day.drivers.take(3).toList();
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
          Row(
            children: [
              Expanded(
                child: _Score(
                  label: 'Overthinking',
                  value: day.overthinking,
                  color: _overthinkingColor,
                ),
              ),
              Expanded(
                child: _Score(
                  label: 'Vitality',
                  value: day.vitality,
                  color: _vitalityColor,
                ),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          value.round().toString(),
          style: TextStyle(
            color: color,
            fontSize: 28,
            fontWeight: FontWeight.w800,
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
    final color = driver.metric == 'vitality'
        ? _vitalityColor
        : _overthinkingColor;
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
          'Vitality combines mental stamina and physical energy. Both are '
          'scored 0–100 each day from the transits against your birth chart.',
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
