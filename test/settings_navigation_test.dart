import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/screens/settings_screen.dart';
import 'package:ai_agent_downloader/services/api_service.dart';
import 'package:ai_agent_downloader/services/settings_service.dart';
import 'package:ai_agent_downloader/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.dowlist.com/native');

  testWidgets('Settings opens separate server and about pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    String? openedUrl;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getAppVersion': return '1.2.1';
        case 'openUrl': openedUrl = (call.arguments as Map)['url'] as String?; return true;
      }
      return null;
    });
    final api = ApiService();
    final updates = UpdateService();
    await updates.initialize();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(settings: SettingsService(), api: api, updates: updates))));
    await tester.pumpAndSettle();
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.text('Enter server URL'), findsNothing);

    await tester.tap(find.text('Server'));
    await tester.pumpAndSettle();
    expect(find.text('Enter server URL'), findsOneWidget);
    expect(api.baseUrl, isEmpty);
    final testUrl = Uri(scheme: 'https', host: '${DateTime.now().microsecondsSinceEpoch}.invalid').toString();
    await tester.enterText(find.byType(TextField), testUrl);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(api.baseUrl, testUrl);
    expect(find.text('Server URL saved.'), findsOneWidget);
    await tester.tap(find.text('Clear URL'));
    await tester.pumpAndSettle();
    expect(api.baseUrl, isEmpty);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();
    expect(find.text('DownList'), findsOneWidget);
    expect(find.text('Version 1.2.1'), findsOneWidget);
    expect(find.text('Libraries'), findsOneWidget);
    await tester.tap(find.text('GitHub'));
    await tester.pumpAndSettle();
    expect(openedUrl, 'https://github.com/divudon21/DownList');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    updates.dispose();
    api.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
