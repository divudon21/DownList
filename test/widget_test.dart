import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_bottom_nav/liquid_glass_bottom_nav.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
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
    await tester.pumpWidget(const AiAgentApp(impellerSupported: false));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Home')), findsOneWidget);
    expect(find.text('Remote Download'), findsOneWidget);
    final navigation = tester.widget<LiquidGlassNavBar>(find.byType(LiquidGlassNavBar));
    expect(navigation.items, hasLength(5));
    for (final label in ['Home', 'Task', 'History', 'Upload', 'Settings']) {
      expect(
        find.descendant(of: find.byType(LiquidGlassNavBar), matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(navigation.selectedIndex, 0);
    expect(find.text('Live server downloads and active file uploads.'), findsNothing);

    for (final tab in [
      ('Task', 1),
      ('Upload', 3),
      ('History', 2),
      ('Settings', 4),
      ('Home', 0),
    ]) {
      await tester.tap(find.descendant(
        of: find.byType(LiquidGlassNavBar), matching: find.text(tab.$1)));
      await tester.pumpAndSettle();
      expect(
        tester.widget<LiquidGlassNavBar>(find.byType(LiquidGlassNavBar)).selectedIndex,
        tab.$2,
      );
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(tab.$1)),
        findsOneWidget,
      );
      if (tab.$1 == 'Upload') {
        expect(find.text('FILE UPLOADS'), findsOneWidget);
        expect(find.text('Upload Files'), findsNothing);
      }
    }
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Home')), findsOneWidget);
    expect(find.text('GoFile'), findsNothing);
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    expect(find.text('GoFile'), findsOneWidget);
    expect(find.text('Clipboard'), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(LiquidGlassNavBar), matching: find.text('History')));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(LiquidGlassNavBar), matching: find.text('Home')));
    await tester.pumpAndSettle();
    expect(find.text('Start Download'), findsOneWidget);
    expect(find.text('GoFile'), findsOneWidget);
    expect(find.byTooltip('Server Info'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });
}
