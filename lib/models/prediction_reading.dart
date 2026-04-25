class PredictionAspect {
  final String? impact;
  final String description;
  final String interpretation;

  PredictionAspect({
    required this.impact,
    required this.description,
    required this.interpretation,
  });

  factory PredictionAspect.fromJson(Map<String, dynamic> json) =>
      PredictionAspect(
        impact: json['impact'] as String?,
        description: (json['description'] ?? '') as String,
        interpretation: (json['interpretation'] ?? '') as String,
      );
}

class PredictionRuler {
  final String description;
  final String interpretation;

  PredictionRuler({
    required this.description,
    required this.interpretation,
  });

  factory PredictionRuler.fromJson(Map<String, dynamic> json) => PredictionRuler(
        description: (json['description'] ?? '') as String,
        interpretation: (json['interpretation'] ?? '') as String,
      );
}

class PredictionReading {
  final String date;
  final List<PredictionAspect> aspects;
  final List<PredictionRuler> rulers;

  PredictionReading({
    required this.date,
    required this.aspects,
    required this.rulers,
  });

  factory PredictionReading.fromJson(Map<String, dynamic> json) =>
      PredictionReading(
        date: (json['date'] ?? '') as String,
        aspects: ((json['aspects'] as List?) ?? const [])
            .map((e) => PredictionAspect.fromJson(e as Map<String, dynamic>))
            .toList(),
        rulers: ((json['rulers'] as List?) ?? const [])
            .map((e) => PredictionRuler.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
