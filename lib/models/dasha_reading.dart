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

class DashaPeriod {
  final String planet;
  final DateTime startDate;
  final DateTime endDate;
  final String description;

  DashaPeriod({
    required this.planet,
    required this.startDate,
    required this.endDate,
    required this.description,
  });

  factory DashaPeriod.fromJson(Map<String, dynamic> json) => DashaPeriod(
        planet: (json['planet'] ?? '') as String,
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        description: (json['description'] ?? '') as String,
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

class DashaReading {
  final String date;
  final double moonLongitude;
  final Nakshatra nakshatra;
  final DashaPeriod mahadasha;
  final DashaPeriod antardasha;
  final DashaPeriod pratyantardasha;

  DashaReading({
    required this.date,
    required this.moonLongitude,
    required this.nakshatra,
    required this.mahadasha,
    required this.antardasha,
    required this.pratyantardasha,
  });

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
      );
}
