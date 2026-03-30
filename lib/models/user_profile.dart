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

  UserProfile({
    required this.name,
    required this.birthDate,
    required this.birthTime,
    required this.birthCity,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toApiJson() => {
        'name': name,
        'birthDate':
            '${birthDate.year}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}',
        'birthTime': birthTime,
        'latitude': latitude,
        'longitude': longitude,
      };
}
