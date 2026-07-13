// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_profile.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserProfileAdapter extends TypeAdapter<UserProfile> {
  @override
  final int typeId = 0;

  @override
  UserProfile read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserProfile(
      name: fields[0] as String,
      birthDate: fields[1] as DateTime,
      birthTime: fields[2] as String,
      birthCity: fields[3] as String,
      latitude: fields[4] as double,
      longitude: fields[5] as double,
      // field 6 was added later; default to 7 (Asia/Ho_Chi_Minh) for rows
      // written before the timezone field existed.
      timezone: (fields[6] as int?) ?? 7,
      // field 7 (topics) was added later; default to empty (= "all topics")
      // so existing rows keep showing every prediction tab after upgrade.
      topics: (fields[7] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  void write(BinaryWriter writer, UserProfile obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.name)
      ..writeByte(1)
      ..write(obj.birthDate)
      ..writeByte(2)
      ..write(obj.birthTime)
      ..writeByte(3)
      ..write(obj.birthCity)
      ..writeByte(4)
      ..write(obj.latitude)
      ..writeByte(5)
      ..write(obj.longitude)
      ..writeByte(6)
      ..write(obj.timezone)
      ..writeByte(7)
      ..write(obj.topics);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserProfileAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
