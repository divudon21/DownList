import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppAccent {
  const AppAccent(this.id, this.name, this.color);
  final String id;
  final String name;
  final Color color;
}

const appAccents = <AppAccent>[
  AppAccent('indigo', 'Indigo', Color(0xFF4F46E5)),
  AppAccent('blue', 'Blue', Color(0xFF2563EB)),
  AppAccent('cyan', 'Cyan', Color(0xFF0891B2)),
  AppAccent('teal', 'Teal', Color(0xFF0D9488)),
  AppAccent('green', 'Green', Color(0xFF16A34A)),
  AppAccent('lime', 'Lime', Color(0xFF65A30D)),
  AppAccent('amber', 'Amber', Color(0xFFD97706)),
  AppAccent('orange', 'Orange', Color(0xFFEA580C)),
  AppAccent('red', 'Red', Color(0xFFDC2626)),
  AppAccent('rose', 'Rose', Color(0xFFE11D48)),
  AppAccent('pink', 'Pink', Color(0xFFDB2777)),
  AppAccent('purple', 'Purple', Color(0xFF9333EA)),
  AppAccent('sky', 'Sky', Color(0xFF0284C7)),
  AppAccent('violet', 'Violet', Color(0xFF7C3AED)),
  AppAccent('slate', 'Slate', Color(0xFF475569)),
];

class AppFont {
  const AppFont(this.id, this.name, this.family, this.description);
  final String id;
  final String name;
  final String? family;
  final String description;
}

const appFonts = <AppFont>[
  AppFont('system', 'System default', null, 'Use your device’s default font'),
  AppFont('inter', 'Inter', 'Inter', 'Clean and modern'),
  AppFont('nunito', 'Nunito', 'Nunito', 'Soft and rounded'),
  AppFont('lato', 'Lato', 'Lato', 'Friendly and balanced'),
  AppFont('jetbrains', 'JetBrains Mono', 'JetBrainsMono', 'Distinctive monospace'),
  AppFont('manrope', 'Manrope', 'Manrope', 'Crisp, modern and easy to read'),
];

class AppearanceService extends ChangeNotifier {
  ThemeMode themeMode = ThemeMode.system;
  bool highContrastDark = false;
  AppAccent accent = appAccents.first;
  AppFont font = appFonts.first;
  bool _disposed = false;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('appearance_theme');
    themeMode = ThemeMode.values.firstWhere((value) => value.name == mode, orElse: () => ThemeMode.system);
    highContrastDark = prefs.getBool('appearance_high_contrast_dark') ?? false;
    final color = prefs.getString('appearance_accent');
    accent = appAccents.firstWhere((value) => value.id == color, orElse: () => appAccents.first);
    final fontId = prefs.getString('appearance_font');
    font = appFonts.firstWhere((value) => value.id == fontId, orElse: () => appFonts.first);
    _notify();
  }

  void _notify() { if (!_disposed) notifyListeners(); }

  Future<void> setThemeMode(ThemeMode value) async {
    themeMode = value;
    _notify();
    await (await SharedPreferences.getInstance()).setString('appearance_theme', value.name);
  }

  Future<void> setHighContrastDark(bool value) async {
    highContrastDark = value;
    _notify();
    await (await SharedPreferences.getInstance()).setBool('appearance_high_contrast_dark', value);
  }

  Future<void> setAccent(AppAccent value) async {
    if (!appAccents.contains(value)) return;
    accent = value;
    _notify();
    await (await SharedPreferences.getInstance()).setString('appearance_accent', value.id);
  }

  Future<void> setFont(AppFont value) async {
    if (!appFonts.contains(value)) return;
    font = value;
    _notify();
    await (await SharedPreferences.getInstance()).setString('appearance_font', value.id);
  }

  ThemeData theme(Brightness brightness) {
    var colors = ColorScheme.fromSeed(seedColor: accent.color, brightness: brightness);
    if (brightness == Brightness.dark && highContrastDark) {
      colors = colors.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF090909),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF1A1A1A),
        surfaceContainerHighest: const Color(0xFF242424),
        onSurface: Colors.white,
        onSurfaceVariant: const Color(0xFFE0E0E0),
      );
    }
    return ThemeData(useMaterial3: true, colorScheme: colors, fontFamily: font.family);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
