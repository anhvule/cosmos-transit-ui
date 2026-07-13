import 'package:hive/hive.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 0)
class UserProfile extends HiveObject {
  @HiveField(0)
  final String name;

  @HiveField(1)
  final DateTime birthDate;

  @HiveField(2)
  final String birthTime; // "HH:mm" format

  @HiveField(3)
  final String birthCity;

  @HiveField(4)
  final double latitude;

  @HiveField(5)
  final double longitude;

  /// Numeric UTC offset in hours, e.g. 7 for Vietnam, 8 for Philippines.
  /// Added so a saved profile can carry its own timezone — older rows
  /// written before this field existed default to 7 (Asia/Ho_Chi_Minh)
  /// in the Hive adapter to keep existing installs working.
  @HiveField(6)
  final int timezone;

  /// Prediction-area names (career, relationship, …) the user wants to see
  /// for this profile. The PredictionsScreen filters its tabs to this set;
  /// an empty list means "all topics" so older rows still surface every
  /// tab after upgrading.
  @HiveField(7)
  final List<String> topics;

  UserProfile({
    required this.name,
    required this.birthDate,
    required this.birthTime,
    required this.birthCity,
    required this.latitude,
    required this.longitude,
    required this.timezone,
    this.topics = const [],
  });

  /// Format birth date as YYYY-MM-DD for backend payloads.
  String get birthDateIso =>
      '${birthDate.year}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toApiJson() => {
        'name': name,
        'birthDate': birthDateIso,
        'birthTime': birthTime,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timezone,
      };

  UserProfile copyWith({
    String? name,
    DateTime? birthDate,
    String? birthTime,
    String? birthCity,
    double? latitude,
    double? longitude,
    int? timezone,
    List<String>? topics,
  }) =>
      UserProfile(
        name: name ?? this.name,
        birthDate: birthDate ?? this.birthDate,
        birthTime: birthTime ?? this.birthTime,
        birthCity: birthCity ?? this.birthCity,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        timezone: timezone ?? this.timezone,
        topics: topics ?? this.topics,
      );
}
