class MindEnergyDriver {
  final String metric; // 'overthinking' | 'vitality'
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

class MindEnergyDay {
  final String date; // YYYY-MM-DD
  final double overthinking;
  final double vitality;
  final List<MindEnergyDriver> drivers;

  MindEnergyDay({
    required this.date,
    required this.overthinking,
    required this.vitality,
    required this.drivers,
  });

  factory MindEnergyDay.fromJson(Map<String, dynamic> json) => MindEnergyDay(
    date: (json['date'] ?? '') as String,
    overthinking: (json['overthinking'] as num?)?.toDouble() ?? 0,
    vitality: (json['vitality'] as num?)?.toDouble() ?? 0,
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
