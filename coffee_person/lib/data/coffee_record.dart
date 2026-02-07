import 'package:isar/isar.dart';

part 'coffee_record.g.dart';

@collection
class CoffeeRecord {
  Id id = Isar.autoIncrement;
  late String type;
  late int caffeineMg;
  int sugarG = 0;
  bool homemade = false;
  String? name;
  String? cupSize;
  String? temperature;
  String? note;
  String? imagePath;
  late double cost;
  late DateTime createdAt;
}
