class MindEnergyDriver {
  final String
  metric; // 'overthinking' | 'vitality' | 'focus' | 'irritability' | 'steadiness'
  final String label;
  final double delta;

  MindEnergyDriver({
    required this.metric,
    required this.label,
    required this.delta,
  });

  factory MindEnergyDriver.fromJson(Map<String, dynamic> json) =>
      MindEnergyDriver(
        metric: (json['metric'] ?? '') as String,
        label: (json['label'] ?? '') as String,
        delta: (json['delta'] as num?)?.toDouble() ?? 0,
      );
}

/// Active Vimshottari dasha lords for a day. The sub-period (pratyantardasha)
/// lasts weeks to months, so it is what makes one month differ from the next.
class MindEnergyPeriod {
  final String? mahadasha;
  final String? antardasha;
  final String? pratyantardasha;
  final String? pratyantardashaStart; // YYYY-MM-DD
  final String? pratyantardashaEnd;

  MindEnergyPeriod({
    this.mahadasha,
    this.antardasha,
    this.pratyantardasha,
    this.pratyantardashaStart,
    this.pratyantardashaEnd,
  });

  factory MindEnergyPeriod.fromJson(Map<String, dynamic> json) =>
      MindEnergyPeriod(
        mahadasha: json['mahadasha'] as String?,
        antardasha: json['antardasha'] as String?,
        pratyantardasha: json['pratyantardasha'] as String?,
        pratyantardashaStart: json['pratyantardashaStart'] as String?,
        pratyantardashaEnd: json['pratyantardashaEnd'] as String?,
      );
}

class MindEnergyDay {
  final String date; // YYYY-MM-DD
  final double overthinking;
  final double vitality;
  final double focus;
  final double irritability;
  final double steadiness;
  final MindEnergyPeriod? period; // null on older backends
  final List<MindEnergyDriver> drivers;

  MindEnergyDay({
    required this.date,
    required this.overthinking,
    required this.vitality,
    required this.focus,
    required this.irritability,
    required this.steadiness,
    this.period,
    required this.drivers,
  });

  factory MindEnergyDay.fromJson(Map<String, dynamic> json) => MindEnergyDay(
    date: (json['date'] ?? '') as String,
    overthinking: (json['overthinking'] as num?)?.toDouble() ?? 0,
    vitality: (json['vitality'] as num?)?.toDouble() ?? 0,
    focus: (json['focus'] as num?)?.toDouble() ?? 0,
    irritability: (json['irritability'] as num?)?.toDouble() ?? 0,
    steadiness: (json['steadiness'] as num?)?.toDouble() ?? 0,
    period: json['period'] is Map<String, dynamic>
        ? MindEnergyPeriod.fromJson(json['period'] as Map<String, dynamic>)
        : null,
    drivers: ((json['drivers'] as List?) ?? const [])
        .map((e) => MindEnergyDriver.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  /// Day of month parsed from [date]; 0 when malformed.
  int get dayOfMonth {
    final parts = date.split('-');
    return parts.length == 3 ? int.tryParse(parts[2]) ?? 0 : 0;
  }
}

class MindEnergyMonth {
  final String month; // YYYY-MM
  final List<MindEnergyDay> days;

  MindEnergyMonth({required this.month, required this.days});

  factory MindEnergyMonth.fromJson(Map<String, dynamic> json) =>
      MindEnergyMonth(
        month: (json['month'] ?? '') as String,
        days: ((json['days'] as List?) ?? const [])
            .map((e) => MindEnergyDay.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
