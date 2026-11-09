import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/screens/home_screen.dart';
import 'package:ai_agent_downloader/screens/settings/home_settings_screen.dart';
import 'package:ai_agent_downloader/services/api_service.dart';
import 'package:ai_agent_downloader/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Compact URL expands on tap, actions share a row and URL survives collapse', (tester) async {
    final api = ApiService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeScreen(api: api))));
    await tester.pumpAndSettle();
    expect(find.text('File URL'), findsOneWidget);
    expect(find.text('Start Download'), findsNothing);
    await tester.tap(find.text('File URL'));
    await tester.pumpAndSettle();
    expect(find.text('Start Download'), findsOneWidget);
    expect(find.text('Clipboard'), findsOneWidget);
    expect(find.text('GoFile'), findsOneWidget);
    final paste = tester.getCenter(find.text('Clipboard'));
    final gofile = tester.getCenter(find.text('GoFile'));
    expect(paste.dx, lessThan(gofile.dx));
    expect(paste.dy, closeTo(gofile.dy, 0.1));
    await tester.enterText(find.byType(TextFormField), 'https://example.com/file');
    await tester.tap(find.byTooltip('Collapse download panel'));
    await tester.pumpAndSettle();
    expect(find.text('Start Download'), findsNothing);
    expect(find.text('https://example.com/file'), findsOneWidget);
    await tester.tap(find.text('https://example.com/file'));
    await tester.pumpAndSettle();
    expect(find.text('Clipboard'), findsOneWidget);
    await Clipboard.setData(const ClipboardData(text: 'https://example.com/new'));
    await tester.tap(find.text('Clipboard'));
    await tester.pumpAndSettle();
    expect(find.text('https://example.com/new'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('Home preference persists and controls next startup layout', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    expect(await settings.getHomeExpandedOnStart(), isFalse);
    await tester.pumpWidget(MaterialApp(home: HomeSettingsScreen(settings: settings)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand on startup'));
    await tester.pumpAndSettle();
    expect(await SettingsService().getHomeExpandedOnStart(), isTrue);
    final api = ApiService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: HomeScreen(api: api, initiallyExpanded: await SettingsService().getHomeExpandedOnStart()))));
    await tester.pumpAndSettle();
    expect(find.text('Start Download'), findsOneWidget);
    expect(find.text('GoFile'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: HomeSettingsScreen(settings: settings)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expand on startup'));
    await tester.pumpAndSettle();
    expect(await SettingsService().getHomeExpandedOnStart(), isFalse);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });
}
