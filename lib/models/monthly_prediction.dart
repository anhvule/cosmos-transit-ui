// Models for POST /api/monthly-prediction — Sun-transit + Sarvashtavarga
// monthly periods for a Tajika year.

class MonthlyPrediction {
  final int year;
  final String varshapravesh;
  final String nextVarshapravesh;
  final String natalMoonSign;
  final String natalMoonSignVedic;
  final List<MonthlyPeriod> periods;

  MonthlyPrediction({
    required this.year,
    required this.varshapravesh,
    required this.nextVarshapravesh,
    required this.natalMoonSign,
    required this.natalMoonSignVedic,
    required this.periods,
  });

  factory MonthlyPrediction.fromJson(Map<String, dynamic> j) => MonthlyPrediction(
        year: j['year'] as int,
        varshapravesh: j['varshapravesh'] as String,
        nextVarshapravesh: j['nextVarshapravesh'] as String,
        natalMoonSign: j['natalMoonSign'] as String,
        natalMoonSignVedic:
            j['natalMoonSignVedic'] as String? ?? j['natalMoonSign'] as String,
        periods: (j['periods'] as List)
            .map((e) => MonthlyPeriod.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Per-period prediction split into four life-area categories. The backend
/// composes each string by concatenating the Sun-house-from-Moon × bindu-band
/// template with the Jupiter-house-from-Moon modifier for that category.
class MonthlyPredictionText {
  final String work;
  final String health;
  final String relationship;
  final String investment;

  const MonthlyPredictionText({
    required this.work,
    required this.health,
    required this.relationship,
    required this.investment,
  });

  static const empty = MonthlyPredictionText(
    work: '',
    health: '',
    relationship: '',
    investment: '',
  );

  factory MonthlyPredictionText.fromJson(Map<String, dynamic> j) =>
      MonthlyPredictionText(
        work: j['work'] as String? ?? '',
        health: j['health'] as String? ?? '',
        relationship: j['relationship'] as String? ?? '',
        investment: j['investment'] as String? ?? '',
      );

  bool get isEmpty =>
      work.isEmpty && health.isEmpty && relationship.isEmpty && investment.isEmpty;
}

class MonthlyPeriod {
  final String fromDate; // YYYY-MM-DD
  final String toDate;   // YYYY-MM-DD
  final String sunSign;
  final String sunSignVedic;
  final String jupiterSign;
  final String jupiterSignVedic;
  final int sarvashtavargaPoints;
  final int sunHouseFromMoon;
  final int jupiterHouseFromMoon;
  final String band; // "high" | "neutral" | "low"
  final String theme;
  final MonthlyPredictionText prediction;

  MonthlyPeriod({
    required this.fromDate,
    required this.toDate,
    required this.sunSign,
    required this.sunSignVedic,
    required this.jupiterSign,
    required this.jupiterSignVedic,
    required this.sarvashtavargaPoints,
    required this.sunHouseFromMoon,
    required this.jupiterHouseFromMoon,
    required this.band,
    required this.theme,
    required this.prediction,
  });

  factory MonthlyPeriod.fromJson(Map<String, dynamic> j) {
    // Be tolerant of pre-migration cached payloads where `prediction` was
    // a flat string. Drop the legacy text and fall back to empty so we
    // never crash on `cast<String>`-into-Map.
    final rawPrediction = j['prediction'];
    final prediction = rawPrediction is Map<String, dynamic>
        ? MonthlyPredictionText.fromJson(rawPrediction)
        : MonthlyPredictionText.empty;
    return MonthlyPeriod(
      fromDate: j['fromDate'] as String,
      toDate: j['toDate'] as String,
      sunSign: j['sunSign'] as String,
      sunSignVedic:
          j['sunSignVedic'] as String? ?? j['sunSign'] as String,
      jupiterSign: j['jupiterSign'] as String,
      jupiterSignVedic:
          j['jupiterSignVedic'] as String? ?? j['jupiterSign'] as String,
      sarvashtavargaPoints: (j['sarvashtavargaPoints'] as num).toInt(),
      sunHouseFromMoon: (j['sunHouseFromMoon'] as num).toInt(),
      jupiterHouseFromMoon: (j['jupiterHouseFromMoon'] as num).toInt(),
      band: j['band'] as String? ?? 'neutral',
      theme: j['theme'] as String? ?? '',
      prediction: prediction,
    );
  }
}
