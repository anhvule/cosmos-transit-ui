class Nakshatra {
  final int index;
  final String name;
  final String lord;
  final double fractionElapsed;
  final int pada;

  Nakshatra({
    required this.index,
    required this.name,
    required this.lord,
    required this.fractionElapsed,
    required this.pada,
  });

  factory Nakshatra.fromJson(Map<String, dynamic> json) => Nakshatra(
        index: (json['index'] as num?)?.toInt() ?? 0,
        name: (json['name'] ?? '') as String,
        lord: (json['lord'] ?? '') as String,
        fractionElapsed: ((json['fractionElapsed'] ?? 0) as num).toDouble(),
        pada: (json['pada'] as num?)?.toInt() ?? 0,
      );
}

/// One dasha level (MD/AD/PD/SD). The backend now merges the period
/// definition (planet/start/end/description) with the investment
/// favorability annotation (favorable/reasons/warnings), so the Vimshottari
/// Dasha screen can show "you're in a good window right now" inline on the
/// active card without filtering against a separate list.
class DashaPeriod {
  final String planet;
  final DateTime startDate;
  final DateTime endDate;
  final String description;
  final bool favorable;
  final List<String> reasons;
  final List<String> warnings;

  DashaPeriod({
    required this.planet,
    required this.startDate,
    required this.endDate,
    required this.description,
    this.favorable = false,
    this.reasons = const [],
    this.warnings = const [],
  });

  factory DashaPeriod.fromJson(Map<String, dynamic> json) => DashaPeriod(
        planet: (json['planet'] ?? '') as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        description: (json['description'] ?? '') as String,
        favorable: (json['favorable'] ?? false) as bool,
        reasons: ((json['reasons'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        warnings: ((json['warnings'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Duration get totalDuration => endDate.difference(startDate);
  Duration get elapsed {
    final now = DateTime.now();
    if (now.isBefore(startDate)) return Duration.zero;
    if (now.isAfter(endDate)) return totalDuration;
    return now.difference(startDate);
  }

  /// 0..1 fraction of period elapsed (for progress bars).
  double get progress {
    final t = totalDuration.inSeconds;
    if (t <= 0) return 0;
    return (elapsed.inSeconds / t).clamp(0.0, 1.0);
  }
}

/// Sub-period (AD/PD/SD) flagged as favorable for investment. Same fields
/// as a `DashaPeriod` but without `description` (the backend doesn't ship
/// per-sub-period descriptions for the favorable lists).
class DashaPeriodAnnotated {
  final String planet;
  final DateTime startDate;
  final DateTime endDate;
  final bool favorable;
  final List<String> reasons;
  final List<String> warnings;

  DashaPeriodAnnotated({
    required this.planet,
    required this.startDate,
    required this.endDate,
    required this.favorable,
    required this.reasons,
    required this.warnings,
  });

  factory DashaPeriodAnnotated.fromJson(Map<String, dynamic> json) =>
      DashaPeriodAnnotated(
        planet: (json['planet'] ?? '') as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        favorable: (json['favorable'] ?? false) as bool,
        reasons: ((json['reasons'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        warnings: ((json['warnings'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Duration get totalDuration => endDate.difference(startDate);

  /// Whether `now` falls inside this period — used by the UI to highlight
  /// the row that matches the active dasha lord.
  bool get isActive {
    final now = DateTime.now();
    return !now.isBefore(startDate) && now.isBefore(endDate);
  }
}

/// Bundle of investment-favorable AD/PD/SD periods (server-filtered to
/// `favorable: true`). Used by the Vimshottari Dasha screen's "Best for
/// investment" highlights section.
class InvestmentFavorablePeriods {
  final List<DashaPeriodAnnotated> antardashas;
  final List<DashaPeriodAnnotated> pratyantardashas;
  final List<DashaPeriodAnnotated> sookshmadashas;

  InvestmentFavorablePeriods({
    required this.antardashas,
    required this.pratyantardashas,
    required this.sookshmadashas,
  });

  static List<DashaPeriodAnnotated> _list(dynamic raw) =>
      ((raw as List?) ?? const [])
          .map((e) =>
              DashaPeriodAnnotated.fromJson(e as Map<String, dynamic>))
          .toList();

  factory InvestmentFavorablePeriods.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return InvestmentFavorablePeriods(
          antardashas: const [],
          pratyantardashas: const [],
          sookshmadashas: const []);
    }
    return InvestmentFavorablePeriods(
      antardashas: _list(json['antardashas']),
      pratyantardashas: _list(json['pratyantardashas']),
      sookshmadashas: _list(json['sookshmadashas']),
    );
  }

  bool get isEmpty =>
      antardashas.isEmpty &&
      pratyantardashas.isEmpty &&
      sookshmadashas.isEmpty;
}

class DashaReading {
  final String date;
  final double moonLongitude;
  final Nakshatra nakshatra;
  final DashaPeriod mahadasha;
  final DashaPeriod antardasha;
  final DashaPeriod pratyantardasha;
  final DashaPeriod? sookshmadasha;
  // Full sub-period lists with favorable/reasons/warnings tags on EACH
  // entry. The UI renders these as color-coded rows (green = favorable,
  // amber = warning) so users see both good and cautious windows side
  // by side. `investmentFavorable.*` is the pre-filtered "green only"
  // subset for headline highlight sections.
  final List<DashaPeriodAnnotated> antardashas;
  final List<DashaPeriodAnnotated> pratyantardashas;
  final List<DashaPeriodAnnotated> sookshmadashas;
  final InvestmentFavorablePeriods investmentFavorable;

  DashaReading({
    required this.date,
    required this.moonLongitude,
    required this.nakshatra,
    required this.mahadasha,
    required this.antardasha,
    required this.pratyantardasha,
    required this.sookshmadasha,
    required this.antardashas,
    required this.pratyantardashas,
    required this.sookshmadashas,
    required this.investmentFavorable,
  });

  static List<DashaPeriodAnnotated> _annotatedList(dynamic raw) =>
      ((raw as List?) ?? const [])
          .map((e) =>
              DashaPeriodAnnotated.fromJson(e as Map<String, dynamic>))
          .toList();

  factory DashaReading.fromJson(Map<String, dynamic> json) => DashaReading(
        date: (json['date'] ?? '') as String,
        moonLongitude:
            ((json['moonLongitude'] ?? 0) as num).toDouble(),
        nakshatra:
            Nakshatra.fromJson(json['nakshatra'] as Map<String, dynamic>),
        mahadasha:
            DashaPeriod.fromJson(json['mahadasha'] as Map<String, dynamic>),
        antardasha:
            DashaPeriod.fromJson(json['antardasha'] as Map<String, dynamic>),
        pratyantardasha: DashaPeriod.fromJson(
            json['pratyantardasha'] as Map<String, dynamic>),
        sookshmadasha: json['sookshmadasha'] is Map
            ? DashaPeriod.fromJson(
                json['sookshmadasha'] as Map<String, dynamic>)
            : null,
        antardashas: _annotatedList(json['antardashas']),
        pratyantardashas: _annotatedList(json['pratyantardashas']),
        sookshmadashas: _annotatedList(json['sookshmadashas']),
        investmentFavorable: InvestmentFavorablePeriods.fromJson(
          json['investmentFavorable'] as Map<String, dynamic>?,
        ),
      );
}
