/// Weekly multi-investor speculative-market signal.
///
/// Mirrors the backend response from /api/market-signal-weekly. The signal
/// is derived from running the SuddenGainSigns / SuddenLossesSigns Vedic
/// rule sets against the bundled Druckenmiller / Ackman / Soros charts and
/// aggregating per-investor verdicts into a single market posture.
library;

enum MarketVerdict { favourable, cautious, normal }

MarketVerdict _parseVerdict(String? raw) {
  switch ((raw ?? '').toLowerCase()) {
    case 'favourable':
    case 'favorable':
      return MarketVerdict.favourable;
    case 'cautious':
      return MarketVerdict.cautious;
    default:
      return MarketVerdict.normal;
  }
}

class MarketInvestor {
  final String key;
  final String name;
  final String style;
  final bool birthTimeKnown;
  final String birthTimeSource;

  MarketInvestor({
    required this.key,
    required this.name,
    required this.style,
    required this.birthTimeKnown,
    required this.birthTimeSource,
  });

  factory MarketInvestor.fromJson(Map<String, dynamic> json) => MarketInvestor(
        key: (json['key'] ?? '') as String,
        name: (json['name'] ?? '') as String,
        style: (json['style'] ?? '') as String,
        birthTimeKnown: (json['birthTimeKnown'] ?? false) as bool,
        birthTimeSource: (json['birthTimeSource'] ?? 'unknown') as String,
      );
}

class MarketSign {
  final String id;
  final String label;
  final int weight;
  final String? description;

  MarketSign({
    required this.id,
    required this.label,
    required this.weight,
    this.description,
  });

  factory MarketSign.fromJson(Map<String, dynamic> json) => MarketSign(
        id: (json['id'] ?? '') as String,
        label: (json['label'] ?? '') as String,
        weight: (json['weight'] is num) ? (json['weight'] as num).toInt() : 0,
        description: json['description'] as String?,
      );
}

class MarketInvestorVerdict {
  final String profileKey;
  final String profileName;
  final MarketVerdict verdict;
  final int gainScore;
  final int lossScore;
  final int netScore;
  final List<MarketSign> gainSigns;
  final List<MarketSign> lossSigns;

  MarketInvestorVerdict({
    required this.profileKey,
    required this.profileName,
    required this.verdict,
    required this.gainScore,
    required this.lossScore,
    required this.netScore,
    required this.gainSigns,
    required this.lossSigns,
  });

  factory MarketInvestorVerdict.fromJson(Map<String, dynamic> json) {
    List<MarketSign> parseSigns(dynamic raw) =>
        ((raw as List?) ?? const [])
            .map((e) => MarketSign.fromJson(e as Map<String, dynamic>))
            .toList();
    int asInt(dynamic v) => v is num ? v.toInt() : 0;
    return MarketInvestorVerdict(
      profileKey: (json['profileKey'] ?? '') as String,
      profileName: (json['profileName'] ?? '') as String,
      verdict: _parseVerdict(json['verdict'] as String?),
      gainScore: asInt(json['gainScore']),
      lossScore: asInt(json['lossScore']),
      netScore: asInt(json['netScore']),
      gainSigns: parseSigns(json['gainSigns']),
      lossSigns: parseSigns(json['lossSigns']),
    );
  }
}

class MarketSignalDay {
  final String date;
  final MarketVerdict verdict;
  final String confidence; // 'low' | 'medium' | 'high'
  final String summary;
  final List<MarketInvestorVerdict> perInvestor;

  MarketSignalDay({
    required this.date,
    required this.verdict,
    required this.confidence,
    required this.summary,
    required this.perInvestor,
  });

  factory MarketSignalDay.fromJson(Map<String, dynamic> json) => MarketSignalDay(
        date: (json['date'] ?? '') as String,
        verdict: _parseVerdict(json['verdict'] as String?),
        confidence: (json['confidence'] ?? 'low') as String,
        summary: (json['summary'] ?? '') as String,
        perInvestor: ((json['perInvestor'] as List?) ?? const [])
            .map((e) =>
                MarketInvestorVerdict.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class WeeklyMarketSignal {
  final String weekStart;
  final String weekEnd;
  final List<MarketInvestor> investors;
  final List<MarketSignalDay> days;

  WeeklyMarketSignal({
    required this.weekStart,
    required this.weekEnd,
    required this.investors,
    required this.days,
  });

  factory WeeklyMarketSignal.fromJson(Map<String, dynamic> json) =>
      WeeklyMarketSignal(
        weekStart: (json['weekStart'] ?? '') as String,
        weekEnd: (json['weekEnd'] ?? '') as String,
        investors: ((json['investors'] as List?) ?? const [])
            .map((e) => MarketInvestor.fromJson(e as Map<String, dynamic>))
            .toList(),
        days: ((json['days'] as List?) ?? const [])
            .map((e) => MarketSignalDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
