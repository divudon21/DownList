import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_agent_downloader/screens/settings_screen.dart';
import 'package:ai_agent_downloader/services/api_service.dart';
import 'package:ai_agent_downloader/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.ai_agent_downloader/native');
  testWidgets('Notification detail switches persist separately', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var uploads = true;
    var downloads = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getNotificationSettings': return {'uploads': uploads, 'downloads': downloads, 'enabled': true};
        case 'setNotificationSetting':
          final args = Map<Object?, Object?>.from(call.arguments as Map);
          if (args['key'] == 'uploads') uploads = args['value'] == true;
          if (args['key'] == 'downloads') downloads = args['value'] == true;
          return true;
        case 'requestNotificationPermission': return true;
      }
      return null;
    });
    final api = ApiService();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SettingsScreen(settings: SettingsService(), api: api))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Show upload details'));
    await tester.tap(find.text('Show upload details'));
    await tester.pumpAndSettle();
    expect(uploads, false);
    expect(downloads, true);
    await tester.ensureVisible(find.text('Show download details'));
    await tester.tap(find.text('Show download details'));
    await tester.pumpAndSettle();
    expect(downloads, false);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
