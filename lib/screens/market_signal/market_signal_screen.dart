import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/market_signal.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

/// Weekly speculative-market posture screen.
///
/// Pulls from /api/market-signal-weekly which runs the SuddenGainSigns and
/// SuddenLossesSigns rule sets against a verified-time-only panel of
/// famous-investor natal charts (Buffett, Ackman, Bloomberg — birth times
/// attested by AstroDatabank Rodden A/AA or comparable journalistic
/// citation) and aggregates per-investor verdicts into a single
/// favourable / cautious / normal market signal per day.
///
/// Unlike InvestmentForecastScreen this screen takes no inputs — the three
/// celebrity natal charts are server-bundled, so the only knob is which
/// Mon–Sun window to read.
class MarketSignalScreen extends StatefulWidget {
  const MarketSignalScreen({super.key});

  @override
  State<MarketSignalScreen> createState() => _MarketSignalScreenState();
}

class _MarketSignalScreenState extends State<MarketSignalScreen> {
  DateTime _weekStart = _defaultWeekStart();
  WeeklyMarketSignal? _signal;
  bool _loading = false;
  String? _error;

  static DateTime _defaultWeekStart() {
    final now = DateTime.now();
    return now.subtract(Duration(days: now.weekday - 1));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _fetch({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await PredictionApiService.fetchMarketSignalWeekly(
        weekStart: _fmt(_weekStart),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _signal = result;
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
        title: const Text('Market Signal — Weekly'),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _buildWeekPicker(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
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
                  setState(() => _weekStart =
                      picked.subtract(Duration(days: picked.weekday - 1)));
                  _fetch();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Week (Mon–Sun)',
                        style:
                            TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmt(_weekStart)}  →  ${_fmt(end)}',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _loading ? null : () => _fetch(),
            onLongPress: _loading ? null : () => _fetch(forceRefresh: true),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.refresh, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CosmicLoader(message: 'Reading the speculative tape...'),
            SizedBox(height: 6),
            Text('Aggregating verified-time investor charts',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
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
                onPressed: _fetch,
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
    final signal = _signal;
    if (signal == null) {
      return const Center(
        child: Text('Pick a week to load.',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return _SignalContent(signal: signal);
  }
}

class _SignalContent extends StatelessWidget {
  final WeeklyMarketSignal signal;
  const _SignalContent({required this.signal});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      children: [
        _headerCard(),
        const SizedBox(height: 16),
        _investorsCard(),
        const SizedBox(height: 20),
        _sectionHeader('Daily Market Posture'),
        ...signal.days.map(_dayCard),
      ],
    );
  }

  Widget _headerCard() {
    final favCount =
        signal.days.where((d) => d.verdict == MarketVerdict.favourable).length;
    final cauCount =
        signal.days.where((d) => d.verdict == MarketVerdict.cautious).length;
    final normCount = signal.days.length - favCount - cauCount;

    return Container(
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
            'WEEK',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${signal.weekStart}  →  ${signal.weekEnd}',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _countPill('Favourable', favCount, _favColor),
              _countPill('Cautious', cauCount, _cauColor),
              _countPill('Normal', normCount, _normColor),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Speculative-market signal aggregated from a ${signal.investors.length}-chart panel of '
            'famous investors with publicly attested birth times '
            '(AstroDatabank Rodden A/AA or comparable journalistic source) '
            'via the SuddenGain / SuddenLoss Vedic rule sets. A strong '
            'majority on the same side, with at most one dissenter, fires '
            'a favourable or cautious verdict.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 12,
                height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _investorsCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BUNDLED CHARTS',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          ...signal.investors.map((inv) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(inv.birthTimeKnown ? '✓' : '⚠',
                        style: TextStyle(
                            color: inv.birthTimeKnown
                                ? const Color(0xFF4ADE80)
                                : const Color(0xFFFBBF24),
                            fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              children: [
                                TextSpan(
                                    text: inv.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                TextSpan(
                                    text: '  ·  ${inv.style}',
                                    style: TextStyle(
                                        color: Colors.white
                                            .withValues(alpha: 0.6),
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                          if (inv.birthTimeSource.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                inv.birthTimeSource,
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.45),
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _countPill(String label, int n, Color c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Text(
        '$label · $n',
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
      ),
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

  Widget _dayCard(MarketSignalDay day) {
    final c = _verdictColor(day.verdict);
    final dayLabel = _formatDayLabel(day.date);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.45)),
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
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dayLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      day.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                          height: 1.35),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _verdictBadge(day.verdict, day.confidence),
            ],
          ),
          children: [
            const SizedBox(height: 2),
            Text(
              day.summary,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  height: 1.45),
            ),
            const SizedBox(height: 12),
            ...day.perInvestor.map(_perInvestorBlock),
          ],
        ),
      ),
    );
  }

  Widget _verdictBadge(MarketVerdict v, String confidence) {
    final c = _verdictColor(v);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _verdictLabel(v).toUpperCase(),
            style: TextStyle(
                color: c, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          Text(
            confidence,
            style:
                TextStyle(color: c.withValues(alpha: 0.85), fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _perInvestorBlock(MarketInvestorVerdict pi) {
    final c = _verdictColor(pi.verdict);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  pi.profileName,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _verdictLabel(pi.verdict),
                  style: TextStyle(
                      color: c,
                      fontSize: 10,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Gain ${pi.gainScore}  ·  Loss ${pi.lossScore}  ·  Net ${pi.netScore >= 0 ? '+' : ''}${pi.netScore}',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 11,
                fontFamily: 'monospace'),
          ),
          if (pi.gainSigns.isNotEmpty) ...[
            const SizedBox(height: 6),
            _signList('Gain triggers', pi.gainSigns, _favColor),
          ],
          if (pi.lossSigns.isNotEmpty) ...[
            const SizedBox(height: 6),
            _signList('Loss triggers', pi.lossSigns, _cauColor),
          ],
        ],
      ),
    );
  }

  Widget _signList(String header, List<MarketSign> signs, Color c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          header.toUpperCase(),
          style: TextStyle(
              color: c.withValues(alpha: 0.85),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1),
        ),
        const SizedBox(height: 4),
        ...signs.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 3, left: 6),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.35),
                  children: [
                    TextSpan(
                        text: '• ${s.label}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85))),
                    if ((s.description ?? '').isNotEmpty)
                      TextSpan(
                        text: '  — ${s.description}',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 11),
                      ),
                  ],
                ),
              ),
            )),
      ],
    );
  }

  static String _formatDayLabel(String dateStr) {
    try {
      final d = DateTime.parse(dateStr);
      return '${DateFormat('EEE, MMM d').format(d)}  ·  $dateStr';
    } catch (_) {
      return dateStr;
    }
  }

  static String _verdictLabel(MarketVerdict v) {
    switch (v) {
      case MarketVerdict.favourable:
        return 'Favourable';
      case MarketVerdict.cautious:
        return 'Cautious';
      case MarketVerdict.normal:
        return 'Normal';
    }
  }

  static Color _verdictColor(MarketVerdict v) {
    switch (v) {
      case MarketVerdict.favourable:
        return _favColor;
      case MarketVerdict.cautious:
        return _cauColor;
      case MarketVerdict.normal:
        return _normColor;
    }
  }

  static const Color _favColor = Color(0xFF4ADE80); // green-400
  static const Color _cauColor = Color(0xFFF87171); // red-400
  static const Color _normColor = Color(0xFF94A3B8); // slate-400
}
