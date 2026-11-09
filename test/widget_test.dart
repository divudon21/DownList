import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/main.dart';

void main() {
  testWidgets('AI Agent Downloader starts with unconfigured server state', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiAgentApp());
    await tester.pumpAndSettle();

    expect(find.text('AI Agent Downloader'), findsOneWidget);
    expect(find.text('Remote Download'), findsOneWidget);
  });
}
