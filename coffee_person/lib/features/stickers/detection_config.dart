import 'package:shared_preferences/shared_preferences.dart';

/// YOLOv8 检测配置
class DetectionConfig {
  static const String _scoreThresholdKey = 'yolo_score_threshold';
  static const String _targetClassIdsKey = 'yolo_target_class_ids';
  static const String _enableAllClassesKey = 'yolo_enable_all_classes';

  /// 获取检测阈值（默认 0.15）
  static Future<double> getScoreThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_scoreThresholdKey) ?? 0.15;
  }

  /// 设置检测阈值
  static Future<void> setScoreThreshold(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_scoreThresholdKey, value);
  }

  /// 获取目标类别 ID 列表（默认 [41] - 杯子）
  static Future<Set<int>> getTargetClassIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_targetClassIdsKey);
    if (list == null || list.isEmpty) {
      return {41}; // COCO 数据集中的 cup
    }
    return list.map((s) => int.tryParse(s) ?? 41).toSet();
  }

  /// 设置目标类别 ID 列表
  static Future<void> setTargetClassIds(Set<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_targetClassIdsKey, ids.map((i) => i.toString()).toList());
  }

  /// 是否启用所有类别检测（调试用）
  static Future<bool> isEnableAllClasses() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enableAllClassesKey) ?? false;
  }

  /// 设置是否启用所有类别检测
  static Future<void> setEnableAllClasses(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enableAllClassesKey, value);
  }

  /// 重置为默认配置
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scoreThresholdKey);
    await prefs.remove(_targetClassIdsKey);
    await prefs.remove(_enableAllClassesKey);
  }
}

/// COCO 数据集常见类别
class CocoClasses {
  static const int person = 0;
  static const int bicycle = 1;
  static const int car = 2;
  static const int motorcycle = 3;
  static const int airplane = 4;
  static const int bus = 5;
  static const int train = 6;
  static const int truck = 7;
  static const int boat = 8;
  static const int trafficLight = 9;
  static const int fireHydrant = 10;
  static const int stopSign = 11;
  static const int parkingMeter = 12;
  static const int bench = 13;
  static const int bird = 14;
  static const int cat = 15;
  static const int dog = 16;
  static const int horse = 17;
  static const int sheep = 18;
  static const int cow = 19;
  static const int elephant = 20;
  static const int bear = 21;
  static const int zebra = 22;
  static const int giraffe = 23;
  static const int backpack = 24;
  static const int umbrella = 25;
  static const int handbag = 26;
  static const int tie = 27;
  static const int suitcase = 28;
  static const int frisbee = 29;
  static const int skis = 30;
  static const int snowboard = 31;
  static const int sportsBall = 32;
  static const int kite = 33;
  static const int baseballBat = 34;
  static const int baseballGlove = 35;
  static const int skateboard = 36;
  static const int surfboard = 37;
  static const int tennisRacket = 38;
  static const int bottle = 39;
  static const int wineGlass = 40;
  static const int cup = 41; // 咖啡杯
  static const int fork = 42;
  static const int knife = 43;
  static const int spoon = 44;
  static const int bowl = 45;
  static const int banana = 46;
  static const int apple = 47;
  static const int sandwich = 48;
  static const int orange = 49;
  static const int broccoli = 50;
  static const int carrot = 51;
  static const int hotDog = 52;
  static const int pizza = 53;
  static const int donut = 54;
  static const int cake = 55;

  static String getName(int classId) {
    switch (classId) {
      case 0: return 'person';
      case 39: return 'bottle';
      case 40: return 'wine glass';
      case 41: return 'cup';
      case 42: return 'fork';
      case 43: return 'knife';
      case 44: return 'spoon';
      case 45: return 'bowl';
      default: return 'class_$classId';
    }
  }
}

