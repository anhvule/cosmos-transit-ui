/// One transit letter (per stream: physical / mental / spiritual) within
/// the Essence Cycle. The API used to return bare letter strings here; it
/// now returns descriptor objects with metadata + per-letter copy. The
/// parser still accepts a bare String for backward compatibility with old
/// cached responses.
class EssenceTransit {
  final String letter;
  final int value;
  final String plane; // "Physical" | "Mental" | "Spiritual"
  final int durationYears;
  final String meaning;
  final String detailedMeaning;

  EssenceTransit({
    required this.letter,
    required this.value,
    required this.plane,
    required this.durationYears,
    required this.meaning,
    required this.detailedMeaning,
  });

  /// Accepts either the new object form or the legacy bare-string letter
  /// (still possibly emitted by older cached responses). Returns null when
  /// the upstream value is null/empty (pre-influence age, missing name part).
  static EssenceTransit? fromJsonOrString(dynamic raw, String defaultPlane) {
    if (raw == null) return null;
    if (raw is String) {
      if (raw.isEmpty) return null;
      return EssenceTransit(
        letter: raw,
        value: 0,
        plane: defaultPlane,
        durationYears: 0,
        meaning: '',
        detailedMeaning: '',
      );
    }
    if (raw is Map) {
      final m = raw.cast<String, dynamic>();
      final letter = (m['letter'] ?? '') as String;
      if (letter.isEmpty) return null;
      return EssenceTransit(
        letter: letter,
        value: (m['value'] as num?)?.toInt() ?? 0,
        plane: (m['plane'] as String?)?.isNotEmpty == true
            ? m['plane'] as String
            : defaultPlane,
        durationYears: (m['duration_years'] as num?)?.toInt() ?? 0,
        meaning: (m['meaning'] ?? '') as String,
        detailedMeaning: (m['detailed_meaning'] ?? '') as String,
      );
    }
    return null;
  }
}

class EssenceTransits {
  final EssenceTransit? physical;
  final EssenceTransit? mental;
  final EssenceTransit? spiritual;

  EssenceTransits({
    required this.physical,
    required this.mental,
    required this.spiritual,
  });

  factory EssenceTransits.fromJson(Map<String, dynamic> json) =>
      EssenceTransits(
        physical: EssenceTransit.fromJsonOrString(json['physical'], 'Physical'),
        mental: EssenceTransit.fromJsonOrString(json['mental'], 'Mental'),
        spiritual:
            EssenceTransit.fromJsonOrString(json['spiritual'], 'Spiritual'),
      );
}

class EssenceDuality {
  final String period; // "before_birthday" | "after_birthday"
  final String startDate;
  final String endDate;
  final int essenceNumber;
  final int personalYear;
  final int dualityNumber;
  final String keyword;
  final String description;

  EssenceDuality({
    required this.period,
    required this.startDate,
    required this.endDate,
    required this.essenceNumber,
    required this.personalYear,
    required this.dualityNumber,
    required this.keyword,
    required this.description,
  });

  factory EssenceDuality.fromJson(Map<String, dynamic> json) => EssenceDuality(
        period: (json['period'] ?? '') as String,
        startDate: (json['start_date'] ?? '') as String,
        endDate: (json['end_date'] ?? '') as String,
        essenceNumber: (json['essence_number'] as num?)?.toInt() ?? 0,
        personalYear: (json['personal_year'] as num?)?.toInt() ?? 0,
        dualityNumber: (json['duality_number'] as num?)?.toInt() ?? 0,
        keyword: (json['keyword'] ?? '') as String,
        description: (json['description'] ?? '') as String,
      );
}

class EssenceYear {
  final int year;
  final int age;
  final EssenceTransits transits;
  final int personalYear;
  final int essenceNumber;
  final String keyword;
  final String meaning;
  final String detailedMeaning;
  final List<EssenceDuality> dualities;

  EssenceYear({
    required this.year,
    required this.age,
    required this.transits,
    required this.personalYear,
    required this.essenceNumber,
    required this.keyword,
    required this.meaning,
    required this.detailedMeaning,
    required this.dualities,
  });

  factory EssenceYear.fromJson(Map<String, dynamic> json) => EssenceYear(
        year: (json['year'] as num?)?.toInt() ?? 0,
        age: (json['age'] as num?)?.toInt() ?? 0,
        transits: EssenceTransits.fromJson(
            (json['transits'] as Map?)?.cast<String, dynamic>() ?? const {}),
        personalYear: (json['personal_year'] as num?)?.toInt() ?? 0,
        essenceNumber: (json['essence_number'] as num?)?.toInt() ?? 0,
        keyword: (json['keyword'] ?? '') as String,
        meaning: (json['meaning'] ?? '') as String,
        detailedMeaning: (json['detailed_meaning'] ?? '') as String,
        dualities: ((json['dualities'] as List?) ?? const [])
            .map((e) => EssenceDuality.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class EssenceCycle {
  final String fullName;
  final String dob;
  final int startYear;
  final List<EssenceYear> essenceTable;

  EssenceCycle({
    required this.fullName,
    required this.dob,
    required this.startYear,
    required this.essenceTable,
  });

  factory EssenceCycle.fromJson(Map<String, dynamic> json) => EssenceCycle(
        fullName: (json['full_name'] ?? '') as String,
        dob: (json['dob'] ?? '') as String,
        startYear: (json['start_year'] as num?)?.toInt() ?? 0,
        essenceTable: ((json['essence_table'] as List?) ?? const [])
            .map((e) => EssenceYear.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
