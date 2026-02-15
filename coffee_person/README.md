# 咖记

把每天那杯咖啡，变成一份可持续复盘的日常记录。  
咖记是一款专注于「咖啡记录 + 咖啡因管理 + 统计复盘」的轻量工具，记录、分析与提醒都在本地完成，帮助你更清晰地了解自己的饮用节奏。

## 一句话亮点

- 像写日记一样记录咖啡，像看数据看板一样复盘习惯
- 日历、趋势、贴纸、AI 分析与 OCR 识别一体化
- 轻量本地存储，不要注册，也不打扰

## 功能一览

- 咖啡记录：类型、杯型、温度、咖啡因（mg）、糖量（g）、价格、是否自制、备注、图片与时间
- 自制咖啡：记录咖啡豆信息与冲煮细节（产地、烘焙、风味、方法等）
- 统计分析：周 / 月 / 年趋势、杯数与咖啡因热力图、偏好统计
- 日历视图：按月查看每天记录，点击日期查看当日详情与记录列表
- 日历贴纸：基于 YOLOv8n-seg 从咖啡图片生成贴纸，日历直观看到当天封面
- AI 分析：OpenAI 兼容接口，支持自定义 Base URL / 模型进行咖啡因分析
- OCR 识别：拍照/相册识别菜单与咖啡豆包装，结果可一键生成记录
- 咖啡日记：图文记录、封面图与头像，自由书写每日咖啡故事
- 视频支持：日记可添加视频并预览
- 所在地天气：显示当前天气与温度，可切换 Open-Meteo / OpenWeatherMap
- 主题与配色：浅色 / 深色 / 跟随系统，多套主题配色一键切换
- 每日咖啡因上限：可设置上限，进度条实时反馈
- 桌面小组件：同步今日杯数与咖啡因（Android）

## 主要页面

- 记录页：快速添加/编辑咖啡记录
- 统计页：趋势、热力图、AI 分析、日历与当日详情
- 日记页：咖啡日记列表与详情
- OCR 页：菜单与咖啡豆识别
- 设置页：主题、配色、AI 与天气配置、隐私与开源许可

## 使用的技术栈

- Flutter / Dart 3.x
- Isar（本地数据库）
- shared_preferences（轻量持久化）
- image_picker / photo_manager（相册与视频）
- google_mlkit_text_recognition（OCR 识别）
- tflite_flutter / google_mlkit_object_detection（贴纸识别与分割）
- YOLOv8n-seg（咖啡杯贴纸检测模型）
- table_calendar（贴纸日历）
- geolocator（定位）
- http（天气与 AI 接口）
- provider（状态管理）
- Material 3 / ThemeExtension（主题与配色）

## 适合谁

- 想知道每天喝了多少咖啡因的人
- 习惯用数据复盘日常的人
- 喜欢记录咖啡故事、图片与细节的人

## 数据与隐私

- 应用不要求注册账号
- 记录数据主要存储在本地设备（数据库/偏好设置/本地媒体）
- OCR/拍照/天气等能力需要相机、相册与定位权限，仅在你主动使用相关功能时请求

## 快速开始（开发）

### 环境要求

- Flutter SDK（Dart 3.x）
- Android Studio / Xcode（按目标平台）

### 运行

```bash
flutter pub get
flutter run
```

### 代码检查与测试

```bash
flutter analyze
flutter test
```

## 打包发布（Android）

- AAB（上架用）：`flutter build appbundle --release`
- APK（安装用）：`flutter build apk --release --split-per-abi`

产物默认输出到：

- `build/app/outputs/bundle/release/app-release.aab`
- `build/app/outputs/flutter-apk/`

如需正式签名，请在 `android/key.properties` 配置 keystore（项目已支持读取该文件；缺失时会回退使用 debug 签名以便本地构建）。

## 权限说明

- 相机：用于拍照进行 OCR 识别、添加图片
- 相册：用于选择咖啡图片、日记图片与视频
- 定位：用于获取所在地天气（可拒绝，不影响核心记录与统计功能）

## 开源许可

项目基于 Flutter 构建，并使用了若干开源依赖（例如 isar、shared_preferences、image_picker、photo_manager、google_mlkit_text_recognition、tflite_flutter、geolocator 等）。
你可以在应用内「设置 → 开源许可」查看完整许可列表。

## 你可以从这里开始

- 想记一杯？打开记录页，点“添加咖啡”
- 想看趋势？切到统计页，选周/月/年
- 想写故事？在日记页记录今天的咖啡时光
