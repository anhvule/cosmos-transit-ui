class FocusArea {
  final String label;
  final String icon;
  final String level; // "positive", "neutral", "caution"

  FocusArea({
    required this.label,
    required this.icon,
    required this.level,
  });

  factory FocusArea.fromJson(Map<String, dynamic> json) => FocusArea(
        label: json['label'] as String,
        icon: json['icon'] as String,
        level: json['level'] as String,
      );
}

class DailyReading {
  final String date;
  final String reading;
  final List<FocusArea> focusAreas;
  final String transitSummary;

  DailyReading({
    required this.date,
    required this.reading,
    required this.focusAreas,
    required this.transitSummary,
  });

  factory DailyReading.fromJson(Map<String, dynamic> json) => DailyReading(
        date: json['date'] as String,
        reading: json['reading'] as String,
        focusAreas: (json['focusAreas'] as List)
            .map((e) => FocusArea.fromJson(e as Map<String, dynamic>))
            .toList(),
        transitSummary: json['transitSummary'] as String,
      );
}
