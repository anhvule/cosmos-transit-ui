// Models for POST /api/yearly-summary — Tajika Varshaphal annual summary.
// Fields mirror the JSON envelope produced by services/varshaphal.js. See the
// Yearly.docx reference report for what each factor represents.

class YearlySummary {
  final int year;
  final int tajikaYear;
  final String varshapravesh; // ISO-ish "YYYY-MM-DDTHH:mm:ss"
  final AnnualChart annualChart;
  final MunthaInfo muntha;
  final Map<String, int> sarvashtavarga; // Vedic sign → bindus
  final List<FactorRow> factors;
  final String overallEffect; // "Favourable" | "Unfavourable"
  final VarsheshwaraInfo varsheshwara;

  YearlySummary({
    required this.year,
    required this.tajikaYear,
    required this.varshapravesh,
    required this.annualChart,
    required this.muntha,
    required this.sarvashtavarga,
    required this.factors,
    required this.overallEffect,
    required this.varsheshwara,
  });

  factory YearlySummary.fromJson(Map<String, dynamic> json) {
    final sav = (json['sarvashtavarga'] as Map<String, dynamic>);
    return YearlySummary(
      year: json['year'] as int,
      tajikaYear: json['tajikaYear'] as int,
      varshapravesh: json['varshapravesh'] as String,
      annualChart:
          AnnualChart.fromJson(json['annualChart'] as Map<String, dynamic>),
      muntha: MunthaInfo.fromJson(json['muntha'] as Map<String, dynamic>),
      sarvashtavarga: {
        for (final e in sav.entries)
          if (e.key != '_western' && e.value is num)
            e.key: (e.value as num).toInt(),
      },
      factors: (json['factors'] as List)
          .map((e) => FactorRow.fromJson(e as Map<String, dynamic>))
          .toList(),
      overallEffect: json['overallEffect'] as String,
      varsheshwara: VarsheshwaraInfo.fromJson(
          json['varsheshwara'] as Map<String, dynamic>),
    );
  }
}

class AnnualChart {
  final String lagna; // Western
  final String lagnaVedic; // Sanskrit
  final String lagnaLord;
  final String birthLagna;
  final String birthLagnaVedic;
  final String birthLagnaLord;
  final int birthLagnaHouseInAnnual;
  final List<AnnualPlanet> planets;

  AnnualChart({
    required this.lagna,
    required this.lagnaVedic,
    required this.lagnaLord,
    required this.birthLagna,
    required this.birthLagnaVedic,
    required this.birthLagnaLord,
    required this.birthLagnaHouseInAnnual,
    required this.planets,
  });

  factory AnnualChart.fromJson(Map<String, dynamic> j) => AnnualChart(
        lagna: j['lagna'] as String,
        lagnaVedic: j['lagnaVedic'] as String,
        lagnaLord: j['lagnaLord'] as String,
        birthLagna: j['birthLagna'] as String,
        birthLagnaVedic: j['birthLagnaVedic'] as String,
        birthLagnaLord: j['birthLagnaLord'] as String,
        birthLagnaHouseInAnnual: j['birthLagnaHouseInAnnual'] as int,
        planets: (j['planets'] as List)
            .map((e) => AnnualPlanet.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class AnnualPlanet {
  final String name;
  final String sign;
  final String signVedic;
  final int house;
  final double longitude;

  AnnualPlanet({
    required this.name,
    required this.sign,
    required this.signVedic,
    required this.house,
    required this.longitude,
  });

  factory AnnualPlanet.fromJson(Map<String, dynamic> j) => AnnualPlanet(
        name: j['name'] as String,
        sign: j['sign'] as String,
        signVedic: j['signVedic'] as String? ?? j['sign'] as String,
        house: j['house'] as int,
        longitude: (j['longitude'] as num).toDouble(),
      );
}

class MunthaInfo {
  final String sign;
  final String signVedic;
  final int house;
  final String lord;
  final int? lordHouseInAnnual;
  final String? lordSign;

  MunthaInfo({
    required this.sign,
    required this.signVedic,
    required this.house,
    required this.lord,
    required this.lordHouseInAnnual,
    required this.lordSign,
  });

  factory MunthaInfo.fromJson(Map<String, dynamic> j) => MunthaInfo(
        sign: j['sign'] as String,
        signVedic: j['signVedic'] as String? ?? j['sign'] as String,
        house: j['house'] as int,
        lord: j['lord'] as String,
        lordHouseInAnnual: j['lordHouseInAnnual'] as int?,
        lordSign: j['lordSign'] as String?,
      );
}

class FactorRow {
  final String factor; // "Muntha" / "Muntha Lord" / "Varsheshwara" / "Birth Lagna" / "Planets in Houses"
  final String detail;
  final int? house;
  final String effect; // "Favourable" | "Unfavourable"
  final List<PlanetEffectRow>? rows; // populated only for "Planets in Houses"

  FactorRow({
    required this.factor,
    required this.detail,
    required this.house,
    required this.effect,
    required this.rows,
  });

  factory FactorRow.fromJson(Map<String, dynamic> j) => FactorRow(
        factor: j['factor'] as String,
        detail: j['detail'] as String,
        house: j['house'] as int?,
        effect: j['effect'] as String,
        rows: j['rows'] is List
            ? (j['rows'] as List)
                .map((e) => PlanetEffectRow.fromJson(e as Map<String, dynamic>))
                .toList()
            : null,
      );
}

class PlanetEffectRow {
  final String planet;
  final String sign;
  final int house;
  final String effect;

  PlanetEffectRow({
    required this.planet,
    required this.sign,
    required this.house,
    required this.effect,
  });

  factory PlanetEffectRow.fromJson(Map<String, dynamic> j) => PlanetEffectRow(
        planet: j['planet'] as String,
        sign: j['sign'] as String,
        house: j['house'] as int,
        effect: j['effect'] as String,
      );
}

class VarsheshwaraInfo {
  final String planet;
  final String role;
  final String? sign;
  final int? house;

  VarsheshwaraInfo({
    required this.planet,
    required this.role,
    required this.sign,
    required this.house,
  });

  factory VarsheshwaraInfo.fromJson(Map<String, dynamic> j) => VarsheshwaraInfo(
        planet: j['planet'] as String,
        role: j['role'] as String,
        sign: j['sign'] as String?,
        house: j['house'] as int?,
      );
}
