import 'package:hive/hive.dart';

part 'user_model.g.dart';

@HiveType(typeId: 0)
class UserModel extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  List<List<double>> faceEmbeddings; // 3 embeddings untuk 3 foto

  @HiveField(2)
  DateTime registrationDate;

  @HiveField(3)
  List<DateTime> attendanceDates;

  UserModel({
    required this.name,
    required this.faceEmbeddings,
    required this.registrationDate,
    List<DateTime>? attendanceDates,
  }) : attendanceDates = attendanceDates ?? [];

  void addAttendance() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    if (!attendanceDates.any((date) =>
    DateTime(date.year, date.month, date.day) == todayDate)) {
      attendanceDates.add(DateTime.now());
      save(); // Simpan ke Hive
    }
  }

  bool hasAttendanceToday() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    return attendanceDates.any((date) =>
    DateTime(date.year, date.month, date.day) == todayDate);
  }
}