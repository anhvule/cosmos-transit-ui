// Models the response from POST /api/wealth-analysis.
// Mirrors the structure produced by services/wealth-analysis.js — five
// sections (lagna, nakshatra, houseAnalysis, hora, yogas) plus an overall
// effect summary.

class WealthAnalysis {
  final LagnaSection lagna;
  final NakshatraSection nakshatra;
  final HouseAnalysisSection houseAnalysis;
  final HoraSection hora;
  final List<YogaEntry> yogas;
  final int yogaCount;
  final String overallEffect;

  WealthAnalysis({
    required this.lagna,
    required this.nakshatra,
    required this.houseAnalysis,
    required this.hora,
    required this.yogas,
    required this.yogaCount,
    required this.overallEffect,
  });

  factory WealthAnalysis.fromJson(Map<String, dynamic> json) => WealthAnalysis(
        lagna: LagnaSection.fromJson(json['lagna'] as Map<String, dynamic>),
        nakshatra: NakshatraSection.fromJson(
            json['nakshatra'] as Map<String, dynamic>),
        houseAnalysis: HouseAnalysisSection.fromJson(
            json['houseAnalysis'] as Map<String, dynamic>),
        hora: HoraSection.fromJson(json['hora'] as Map<String, dynamic>),
        yogas: (json['yogas'] as List)
            .map((e) => YogaEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        yogaCount: json['yogaCount'] as int,
        overallEffect: json['overallEffect'] as String,
      );
}

class LagnaSection {
  final String sign;
  final String? signVedic;
  final String lord;
  final String? lordSign;
  final int? lordHouse;
  final String personalityPrediction;
  final String lordPrediction;

  LagnaSection({
    required this.sign,
    required this.signVedic,
    required this.lord,
    required this.lordSign,
    required this.lordHouse,
    required this.personalityPrediction,
    required this.lordPrediction,
  });

  factory LagnaSection.fromJson(Map<String, dynamic> json) => LagnaSection(
        sign: json['sign'] as String,
        signVedic: json['signVedic'] as String?,
        lord: json['lord'] as String,
        lordSign: json['lordSign'] as String?,
        lordHouse: json['lordHouse'] as int?,
        personalityPrediction: json['personalityPrediction'] as String? ?? '',
        lordPrediction: json['lordPrediction'] as String? ?? '',
      );
}

class NakshatraEntry {
  final String planet;
  final String sign;
  final String nakshatra;
  final int pada;
  final String lord;
  final String prediction;
  final String padaNote;

  NakshatraEntry({
    required this.planet,
    required this.sign,
    required this.nakshatra,
    required this.pada,
    required this.lord,
    required this.prediction,
    required this.padaNote,
  });

  factory NakshatraEntry.fromJson(Map<String, dynamic> json) => NakshatraEntry(
        planet: json['planet'] as String,
        sign: json['sign'] as String,
        nakshatra: json['nakshatra'] as String,
        pada: json['pada'] as int,
        lord: json['lord'] as String,
        prediction: json['prediction'] as String? ?? '',
        padaNote: json['padaNote'] as String? ?? '',
      );
}

class NakshatraSection {
  final NakshatraEntry? moon;
  final NakshatraEntry? jupiter;
  final NakshatraEntry? venus;

  NakshatraSection({
    required this.moon,
    required this.jupiter,
    required this.venus,
  });

  factory NakshatraSection.fromJson(Map<String, dynamic> json) =>
      NakshatraSection(
        moon: json['moon'] == null
            ? null
            : NakshatraEntry.fromJson(json['moon'] as Map<String, dynamic>),
        jupiter: json['jupiter'] == null
            ? null
            : NakshatraEntry.fromJson(json['jupiter'] as Map<String, dynamic>),
        venus: json['venus'] == null
            ? null
            : NakshatraEntry.fromJson(json['venus'] as Map<String, dynamic>),
      );
}

class HouseAspect {
  final String planet;
  final String prediction;

  HouseAspect({required this.planet, required this.prediction});

  factory HouseAspect.fromJson(Map<String, dynamic> json) => HouseAspect(
        planet: json['planet'] as String,
        prediction: json['prediction'] as String? ?? '',
      );
}

class HouseEntry {
  final int house;
  final String title;
  final String? sign;
  final String? signVedic;
  final String preamble;
  final String lord;
  final String? lordSign;
  final int? lordHouse;
  final String lordPrediction;
  final List<HouseAspect> aspects;

  HouseEntry({
    required this.house,
    required this.title,
    required this.sign,
    required this.signVedic,
    required this.preamble,
    required this.lord,
    required this.lordSign,
    required this.lordHouse,
    required this.lordPrediction,
    required this.aspects,
  });

  factory HouseEntry.fromJson(Map<String, dynamic> json) => HouseEntry(
        house: json['house'] as int,
        title: json['title'] as String,
        sign: json['sign'] as String?,
        signVedic: json['signVedic'] as String?,
        preamble: json['preamble'] as String? ?? '',
        lord: json['lord'] as String,
        lordSign: json['lordSign'] as String?,
        lordHouse: json['lordHouse'] as int?,
        lordPrediction: json['lordPrediction'] as String? ?? '',
        aspects: (json['aspects'] as List? ?? [])
            .map((e) => HouseAspect.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class HouseAnalysisSection {
  final HouseEntry? second;
  final HouseEntry? fourth;
  final HouseEntry? ninth;
  final HouseEntry? eleventh;

  HouseAnalysisSection({
    required this.second,
    required this.fourth,
    required this.ninth,
    required this.eleventh,
  });

  factory HouseAnalysisSection.fromJson(Map<String, dynamic> json) =>
      HouseAnalysisSection(
        second: json['second'] == null
            ? null
            : HouseEntry.fromJson(json['second'] as Map<String, dynamic>),
        fourth: json['fourth'] == null
            ? null
            : HouseEntry.fromJson(json['fourth'] as Map<String, dynamic>),
        ninth: json['ninth'] == null
            ? null
            : HouseEntry.fromJson(json['ninth'] as Map<String, dynamic>),
        eleventh: json['eleventh'] == null
            ? null
            : HouseEntry.fromJson(json['eleventh'] as Map<String, dynamic>),
      );

  List<HouseEntry> get all =>
      [second, fourth, ninth, eleventh].whereType<HouseEntry>().toList();
}

class HoraPlacement {
  final String planet;
  final String natalSign;
  final String hora;
  final String prediction;

  HoraPlacement({
    required this.planet,
    required this.natalSign,
    required this.hora,
    required this.prediction,
  });

  factory HoraPlacement.fromJson(Map<String, dynamic> json) => HoraPlacement(
        planet: json['planet'] as String,
        natalSign: json['natalSign'] as String,
        hora: json['hora'] as String,
        prediction: json['prediction'] as String? ?? '',
      );
}

class HoraSection {
  final String preamble;
  final List<HoraPlacement> placements;
  final String ascendantNote;

  HoraSection({
    required this.preamble,
    required this.placements,
    required this.ascendantNote,
  });

  factory HoraSection.fromJson(Map<String, dynamic> json) => HoraSection(
        preamble: json['preamble'] as String? ?? '',
        placements: (json['placements'] as List? ?? [])
            .map((e) => HoraPlacement.fromJson(e as Map<String, dynamic>))
            .toList(),
        ascendantNote: json['ascendantNote'] as String? ?? '',
      );
}

class YogaEntry {
  final String name;
  final String logic;
  final String description;
  final String? detail;
  final List<String>? planets;

  YogaEntry({
    required this.name,
    required this.logic,
    required this.description,
    required this.detail,
    required this.planets,
  });

  factory YogaEntry.fromJson(Map<String, dynamic> json) => YogaEntry(
        name: json['name'] as String,
        logic: json['logic'] as String? ?? '',
        description: json['description'] as String? ?? '',
        detail: json['detail'] as String?,
        planets: json['planets'] == null
            ? null
            : (json['planets'] as List).map((e) => e as String).toList(),
      );
}
