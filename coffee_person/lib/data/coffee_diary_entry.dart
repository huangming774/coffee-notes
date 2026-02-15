import 'package:isar/isar.dart';

part 'coffee_diary_entry.g.dart';

@collection
class CoffeeDiaryEntry {
  Id id = Isar.autoIncrement;

  late DateTime date;
  String? text;

  @Index()
  late DateTime createdAt;

  List<String> imagePaths = [];
  List<String> motionVideoPaths = [];
}
