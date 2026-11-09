import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/screens/settings/appearance_settings_screen.dart';
import 'package:ai_agent_downloader/services/appearance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Preferences persist and invalid values fall back safely', () async {
    SharedPreferences.setMockInitialValues({'appearance_theme': 'invalid', 'appearance_accent': 'invalid'});
    final appearance = AppearanceService();
    await appearance.initialize();
    expect(appearance.themeMode, ThemeMode.system);
    expect(appearance.accent.id, 'indigo');
    await appearance.setThemeMode(ThemeMode.dark);
    await appearance.setHighContrastDark(true);
    await appearance.setAccent(appAccents[3]);
    final restored = AppearanceService();
    await restored.initialize();
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.highContrastDark, isTrue);
    expect(restored.accent.id, 'teal');
    expect(restored.theme(Brightness.dark).colorScheme.surface, Colors.black);
    expect(restored.theme(Brightness.light).colorScheme.surface, isNot(Colors.black));
    appearance.dispose();
    restored.dispose();
  });

  test('All 12 accents generate distinct light and dark schemes', () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceService();
    final light = <Color>{};
    final dark = <Color>{};
    for (final accent in appAccents) {
      await appearance.setAccent(accent);
      light.add(appearance.theme(Brightness.light).colorScheme.primary);
      dark.add(appearance.theme(Brightness.dark).colorScheme.primary);
    }
    expect(appAccents.length, 12);
    expect(light.length, 12);
    expect(dark.length, 12);
    appearance.dispose();
  });

  testWidgets('Appearance controls update the app theme immediately', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceService();
    await appearance.initialize();
    await tester.pumpWidget(ListenableBuilder(
      listenable: appearance,
      builder: (_, __) => MaterialApp(
        themeMode: appearance.themeMode,
        theme: appearance.theme(Brightness.light),
        darkTheme: appearance.theme(Brightness.dark),
        home: AppearanceSettingsScreen(appearance: appearance),
      ),
    ));
    await tester.tap(find.text('App theme'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('App theme'))).brightness, Brightness.dark);
    await tester.tap(find.text('High contrast dark theme'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('App theme'))).colorScheme.surface, Colors.black);
    final oldColor = Theme.of(tester.element(find.text('App theme'))).colorScheme.primary;
    await tester.ensureVisible(find.text('Teal'));
    await tester.tap(find.text('Teal'));
    await tester.pumpAndSettle();
    expect(appearance.accent.id, 'teal');
    expect(Theme.of(tester.element(find.text('App theme'))).colorScheme.primary, isNot(oldColor));
    await tester.pumpWidget(const SizedBox());
    appearance.dispose();
  });
}
