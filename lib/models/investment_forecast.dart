import 'prediction_reading.dart';

class AggregatedAspect {
  final String description;
  final String interpretation;
  final String? impact;
  final List<String> dates;

  AggregatedAspect({
    required this.description,
    required this.interpretation,
    required this.impact,
    required this.dates,
  });

  factory AggregatedAspect.fromJson(Map<String, dynamic> json) =>
      AggregatedAspect(
        description: (json['description'] ?? '') as String,
        interpretation: (json['interpretation'] ?? '') as String,
        impact: json['impact'] as String?,
        dates: ((json['dates'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class AggregatedRuler {
  final String description;
  final String interpretation;
  final List<String> dates;

  AggregatedRuler({
    required this.description,
    required this.interpretation,
    required this.dates,
  });

  factory AggregatedRuler.fromJson(Map<String, dynamic> json) =>
      AggregatedRuler(
        description: (json['description'] ?? '') as String,
        interpretation: (json['interpretation'] ?? '') as String,
        dates: ((json['dates'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}

class InvestmentDay {
  final String date;
  final List<PredictionAspect> aspects;
  final List<PredictionRuler> rulers;

  InvestmentDay({
    required this.date,
    required this.aspects,
    required this.rulers,
  });

  factory InvestmentDay.fromJson(Map<String, dynamic> json) => InvestmentDay(
        date: (json['date'] ?? '') as String,
        aspects: ((json['aspects'] as List?) ?? const [])
            .map((e) => PredictionAspect.fromJson(e as Map<String, dynamic>))
            .toList(),
        rulers: ((json['rulers'] as List?) ?? const [])
            .map((e) => PredictionRuler.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class InvestmentForecast {
  final String period; // "week" or "month"
  final String startDate;
  final String endDate;
  final List<InvestmentDay> days;
  final List<AggregatedAspect> aggregatedAspects;
  final List<AggregatedRuler> aggregatedRulers;

  InvestmentForecast({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.aggregatedAspects,
    required this.aggregatedRulers,
  });

  factory InvestmentForecast.fromJson(Map<String, dynamic> json) =>
      InvestmentForecast(
        period: (json['period'] ?? '') as String,
        startDate: (json['startDate'] ?? '') as String,
        endDate: (json['endDate'] ?? '') as String,
        days: ((json['days'] as List?) ?? const [])
            .map((e) => InvestmentDay.fromJson(e as Map<String, dynamic>))
            .toList(),
        aggregatedAspects:
            ((json['aggregatedAspects'] as List?) ?? const [])
                .map((e) =>
                    AggregatedAspect.fromJson(e as Map<String, dynamic>))
                .toList(),
        aggregatedRulers: ((json['aggregatedRulers'] as List?) ?? const [])
            .map((e) => AggregatedRuler.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
