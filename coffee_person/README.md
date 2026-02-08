# 咖记

把每天那杯咖啡，变成一段可追踪的故事。  
咖记是一款专注于「咖啡记录 + 咖啡因管理 + 统计复盘」的轻量工具，让你的咖啡习惯有据可循、有趣可看。

## 一句话亮点

- 像写日记一样记录咖啡，像看数据看板一样复盘习惯
- 日历、趋势、偏好一目了然，爱上复盘的成就感
- 轻量本地存储，不要注册，也不打扰

## 功能一览

- 记录咖啡：类型、杯型、温度、咖啡因（mg）、糖量（g）、价格、是否自制、备注、图片
- 日历视图：按月查看每天是否喝过咖啡，点日期查看当日详情与记录列表
- 快速新增：在首页一键“添加一杯”
- 记录编辑：点击当日记录条目可进入编辑页，保存后更新原记录
- 统计分析：周 / 月 / 年维度趋势与偏好概览
- OCR 识别：拍照识别菜单/咖啡豆包装信息，辅助生成记录
- 所在地天气：在首页显示当前天气与温度（需要定位权限）
- 主题配色：内置多套配色方案，设置页可一键切换并自动记住
- 每日咖啡因上限：支持设置每日咖啡因目标，进度条实时反馈

## 使用的技术栈

- Flutter / Dart 3.x
- Isar（本地数据库）
- shared_preferences（轻量持久化）
- image_picker（图片选择）
- google_mlkit_text_recognition（OCR 识别）
- geolocator（定位）
- HTTP（Open-Meteo 天气接口）
- Material 3 / ThemeExtension（主题与配色）

## 适合谁

- 想知道每天喝了多少咖啡因的人
- 习惯用数据复盘日常的人
- 喜欢用好看的配色记录生活的人

## 数据与隐私

- 应用不要求注册账号
- 记录数据主要存储在本地设备（例如数据库/偏好设置），用于实现查询与统计
- OCR/拍照/天气等能力需要相机、相册与定位等系统权限；仅在你主动使用相关功能时请求

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
- 相册：用于选择咖啡图片
- 定位：用于获取所在地天气（可拒绝，不影响核心记录与统计功能）

## 开源许可

项目基于 Flutter 构建，并使用了若干开源依赖（例如 isar、shared_preferences、image_picker、google_mlkit_text_recognition、geolocator 等）。
你可以在应用内「设置 → 开源许可」查看完整许可列表。

## 你可以从这里开始

- 想记一杯？打开首页，点“添加一杯”
- 想看趋势？切到统计页，选周/月/年
- 想换风格？到设置页选一套配色
