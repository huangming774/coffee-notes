import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import 'data/coffee_diary_entry.dart';
import 'data/coffee_diary_repository.dart';
import 'data/coffee_record.dart';
import 'data/coffee_repository.dart';
import 'features/stats/stats_page.dart';
import 'features/stickers/detection_service.dart';
import 'features/stickers/sticker_store.dart';
import 'features/stickers/storage_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 优化图片缓存配置
  PaintingBinding.instance.imageCache.maximumSize = 100; // 最多缓存100张图片
  PaintingBinding.instance.imageCache.maximumSizeBytes = 50 << 20; // 50MB内存限制

  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open([CoffeeRecordSchema, CoffeeDiaryEntrySchema],
      directory: dir.path);
  runApp(MyApp(repository: CoffeeRepository(isar)));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, required this.repository});

  final CoffeeRepository repository;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _themeMode = ThemeMode.light;
  AppAccentPalette _accentPalette = AppAccentPalette.coffee;
  static const String _accentPaletteKey = 'accent_palette';

  @override
  void initState() {
    super.initState();
    _setHighRefreshRate();
    _loadAccentPalette();
  }

  Future<void> _loadAccentPalette() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_accentPaletteKey);
    if (!mounted) return;
    setState(() {
      _accentPalette = AppAccentPaletteX.fromId(id);
    });
  }

  Future<void> _saveAccentPalette(AppAccentPalette palette) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accentPaletteKey, palette.id);
  }

  Future<void> _setHighRefreshRate() async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } on PlatformException {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CoffeeDiaryRepository>(
          create: (_) => IsarCoffeeDiaryRepository(widget.repository.isar),
        ),
        ChangeNotifierProvider(
          create: (_) {
            final store = StickerStore(
              storageService: StorageService(),
              detectionService: DetectionService(),
            );
            store.load();
            return store;
          },
        ),
      ],
      child: MaterialApp(
        title: '咖记',
        theme: AppTheme.lightTheme(accentColor: _accentPalette.color),
        darkTheme: AppTheme.darkTheme(accentColor: _accentPalette.color),
        themeMode: _themeMode,
        builder: (context, child) {
          final brightness = Theme.of(context).brightness;
          final background = Theme.of(context).scaffoldBackgroundColor;
          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarBrightness: brightness,
              statusBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
              systemNavigationBarColor: background,
              systemNavigationBarIconBrightness: brightness == Brightness.dark
                  ? Brightness.light
                  : Brightness.dark,
            ),
          );
          return child ?? const SizedBox.shrink();
        },
        home: StatsPage(
          repository: widget.repository,
          themeMode: _themeMode,
          onThemeModeChange: (mode) {
            if (_themeMode == mode) return;
            setState(() {
              _themeMode = mode;
            });
          },
          accentPalette: _accentPalette,
          onAccentPaletteChange: (palette) {
            if (_accentPalette == palette) return;
            setState(() {
              _accentPalette = palette;
            });
            _saveAccentPalette(palette);
          },
        ),
      ),
    );
  }
}
