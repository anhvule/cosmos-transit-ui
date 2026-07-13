import 'package:flutter/material.dart';

import '../../models/wealth_analysis.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/cosmic_loader.dart';

/// Vedic wealth analysis page — wraps /api/wealth-analysis.
///
/// Mirrors the structure of the Wealth.docx reference report:
///   1. Lagna-based prediction
///   2. Nakshatra-based prediction (Moon, Jupiter, Venus)
///   3. House analysis (2nd, 4th, 9th, 11th)
///   4. Hora chart (D2)
///   5. Wealth yogas
class WealthAnalysisScreen extends StatefulWidget {
  final PredictionRequest request;

  const WealthAnalysisScreen({super.key, required this.request});

  @override
  State<WealthAnalysisScreen> createState() => _WealthAnalysisScreenState();
}

class _WealthAnalysisScreenState extends State<WealthAnalysisScreen> {
  WealthAnalysis? _analysis;
  String? _error;
  bool _loading = false;

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
      final result = await PredictionApiService.fetchWealthAnalysis(
        name: widget.request.name,
        birthDate: widget.request.birthDate,
        birthTime: widget.request.birthTime,
        latitude: widget.request.latitude,
        longitude: widget.request.longitude,
        timezone: widget.request.timezone,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        _analysis = result;
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
        title: const Text('Wealth Analysis'),
        actions: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _fetch(),
            onLongPress: () {
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
    if (_loading) {
      return const Center(child: CosmicLoader(message: 'Reading your natal chart…'));
    }
    if (_error != null) {
      return _ErrorRetry(message: _error!, onRetry: () => _fetch(forceRefresh: true));
    }
    final a = _analysis;
    if (a == null) {
      return const Center(
        child: Text('No data.', style: TextStyle(color: Colors.white70)),
      );
    }

    final bottomInset = MediaQuery.of(context).padding.bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
      children: [
        _OverallBanner(effect: a.overallEffect, yogaCount: a.yogaCount),
        const SizedBox(height: 16),
        const _SectionHeader('Lagna based prediction'),
        _LagnaCard(lagna: a.lagna),
        const SizedBox(height: 16),
        const _SectionHeader('Nakshatra based prediction'),
        _NakshatraCard(section: a.nakshatra),
        const SizedBox(height: 16),
        const _SectionHeader('House analysis for wealth'),
        for (final h in a.houseAnalysis.all) ...[
          _HouseCard(entry: h),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const _SectionHeader('Wealth Overview — Hora chart'),
        _HoraCard(section: a.hora),
        const SizedBox(height: 16),
        const _SectionHeader('Wealth Yogas'),
        _YogasCard(yogas: a.yogas),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

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
  final int yogaCount;
  const _OverallBanner({required this.effect, required this.yogaCount});

  @override
  Widget build(BuildContext context) {
    final color = effect.contains('Strongly')
        ? const Color(0xFF4CAF50)
        : effect == 'Favourable'
            ? const Color(0xFF7C4DFF)
            : const Color(0xFFFF9800);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.25),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('💎', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  effect,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$yogaCount wealth ${yogaCount == 1 ? "yoga" : "yogas"} detected',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
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

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1745).withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

TextStyle _bodyStyle() => TextStyle(
      color: Colors.white.withValues(alpha: 0.85),
      fontSize: 14.5,
      height: 1.55,
    );

TextStyle _subStyle() => const TextStyle(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w600,
    );

Widget _para(String text) {
  if (text.isEmpty) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: _bodyStyle()),
  );
}

Widget _subhead(String text) {
  return Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Text(text, style: _subStyle()),
  );
}

class _LagnaCard extends StatelessWidget {
  final LagnaSection lagna;
  const _LagnaCard({required this.lagna});

  @override
  Widget build(BuildContext context) {
    final ascendant = lagna.signVedic != null && lagna.signVedic!.isNotEmpty
        ? '${lagna.sign} (${lagna.signVedic})'
        : lagna.sign;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ascendant: $ascendant',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              )),
          const SizedBox(height: 10),
          _para(lagna.personalityPrediction),
          if (lagna.lordHouse != null)
            _subhead('Lagna Lord — ${lagna.lord} in ${lagna.lordHouse}th house'),
          _para(lagna.lordPrediction),
        ],
      ),
    );
  }
}

class _NakshatraCard extends StatelessWidget {
  final NakshatraSection section;
  const _NakshatraCard({required this.section});

  @override
  Widget build(BuildContext context) {
    final entries = [section.moon, section.jupiter, section.venus]
        .whereType<NakshatraEntry>()
        .toList();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in entries) ...[
            _subhead('${e.planet} — ${e.nakshatra} (pada ${e.pada})'),
            _para(e.prediction),
            if (e.padaNote.isNotEmpty) _para(e.padaNote),
          ],
        ],
      ),
    );
  }
}

class _HouseCard extends StatelessWidget {
  final HouseEntry entry;
  const _HouseCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              entry.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 10),
          _para(entry.preamble),
          if (entry.lordHouse != null)
            _subhead('${entry.lord} (lord) in ${entry.lordHouse}th house'),
          _para(entry.lordPrediction),
          if (entry.aspects.isNotEmpty) ...[
            _subhead('Aspects on this house'),
            for (final a in entry.aspects)
              if (a.prediction.isNotEmpty) _para(a.prediction),
          ],
        ],
      ),
    );
  }
}

class _HoraCard extends StatelessWidget {
  final HoraSection section;
  const _HoraCard({required this.section});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _para(section.preamble),
          if (section.ascendantNote.isNotEmpty) _para(section.ascendantNote),
          for (final p in section.placements) ...[
            _subhead('${p.planet} → ${p.hora} hora'),
            _para(p.prediction),
          ],
        ],
      ),
    );
  }
}

class _YogasCard extends StatelessWidget {
  final List<YogaEntry> yogas;
  const _YogasCard({required this.yogas});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (yogas.isEmpty)
            _para(
              'No classical wealth-forming combinations were detected in your chart. Wealth in your life will primarily come through dasha periods, transits, and personal effort rather than from natal yogas.',
            ),
          for (final y in yogas) _YogaTile(yoga: y),
        ],
      ),
    );
  }
}

class _YogaTile extends StatelessWidget {
  final YogaEntry yoga;
  const _YogaTile({required this.yoga});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            yoga.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Logic: ${yoga.logic}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
          if (yoga.detail != null) ...[
            const SizedBox(height: 4),
            Text(
              yoga.detail!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12.5,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(yoga.description, style: _bodyStyle()),
        ],
      ),
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
