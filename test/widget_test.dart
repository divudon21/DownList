import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/main.dart';

void main() {
  testWidgets('DownList starts with unconfigured server state', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({'updates_auto_check': false});
    const channel = MethodChannel('com.dowlist.com/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'getUploadSnapshots':
        case 'getServerTaskSnapshots': return [];
        case 'getNotificationSettings': return {'uploads': true, 'downloads': true, 'enabled': true};
        case 'requestNotificationPermission': return true;
      }
      return null;
    });
    await tester.pumpWidget(const AiAgentApp());
    await tester.pumpAndSettle();

    expect(find.text('DownList'), findsOneWidget);
    expect(find.text('Remote Download'), findsOneWidget);
    expect(find.text('Upload to GoFile'), findsOneWidget);
    expect(find.byTooltip('Server Info'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
