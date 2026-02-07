import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/coffee_record.dart';
import 'data/coffee_repository.dart';
import 'features/stats/stats_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final isar = await Isar.open([CoffeeRecordSchema], directory: dir.path);
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
    return MaterialApp(
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
    );
  }
}
