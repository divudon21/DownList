import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:ai_agent_downloader/screens/settings/update_settings_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_agent_downloader/services/update_service.dart';

final signerA = List.filled(64, 'a').join();
final signerB = List.filled(64, 'b').join();
final installed = InstalledBuild(versionName: '1.2.3', versionCode: 10, packageName: 'com.dowlist.com', signerSha256: signerA);

Map<String, dynamic> release(int code, {bool beta = false, String? signer, String package = 'com.dowlist.com'}) => {
  'draft': false,
  'prerelease': beta,
  'html_url': 'https://github.com/divudon21/DownList/releases/tag/build-$code',
  'body': '<!-- downlist-update:${jsonEncode({'versionCode': code, 'versionName': '1.2.3', 'packageName': package, 'signerSha256': signer ?? signerA})} -->',
  'assets': [
    {'name': 'DownList-universal.apk', 'state': 'uploaded', 'browser_download_url': 'https://github.com/divudon21/DownList/releases/download/build-$code/DownList-universal.apk'},
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Compares actual build codes, not release tags or version strings', () {
    expect(selectUpdateRelease([release(10), release(9)], installed, includeBeta: false), isNull);
    final newer = selectUpdateRelease([release(11), release(10)], installed, includeBeta: false)!;
    expect(newer.versionCode, 11);
    expect(newer.isCompatibleWith(installed), isTrue);
  });

  test('Beta filtering and signature mismatch are explicit', () {
    final releases = [release(10), release(11), release(12, beta: true, signer: signerB)];
    expect(selectUpdateRelease(releases, installed, includeBeta: false)!.versionCode, 11);
    final beta = selectUpdateRelease(releases, installed, includeBeta: true)!;
    expect(beta.versionCode, 12);
    expect(beta.isCompatibleWith(installed), isFalse);
    expect(beta.prerelease, isTrue);
  });

  test('Rejects wrong package, missing metadata and untrusted download links', () {
    final wrong = release(15, package: 'other.package');
    final badUrl = release(16);
    (badUrl['assets'] as List).first['browser_download_url'] = 'https://example.org/file.apk';
    expect(() => selectUpdateRelease([wrong, badUrl, {'body': 'old release'}], installed, includeBeta: true), throwsFormatException);
  });

  test('Network errors do not report up to date and preferences persist', () async {
    SharedPreferences.setMockInitialValues({});
    final service = UpdateService(
      client: MockClient((_) async => http.Response('no', 503)),
      buildInfo: () async => {'versionName': '1.2.3', 'versionCode': 10, 'packageName': 'com.dowlist.com', 'signerSha256': signerA},
    );
    await service.initialize();
    await service.check();
    expect(service.checked, isFalse);
    expect(service.error, contains('503'));
    await service.setOption('auto_check', false);
    await service.setOption('include_beta', true);
    await service.setOption('popup', false);
    final second = UpdateService(client: MockClient((_) async => http.Response('[]', 200)));
    await second.initialize();
    expect(second.autoCheck, isFalse);
    expect(second.includeBeta, isTrue);
    expect(second.popup, isFalse);
    service.dispose();
    second.dispose();
  });
  testWidgets('Updates page shows up-to-date and lets beta be enabled', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = UpdateService(
      client: MockClient((_) async => http.Response(jsonEncode([release(10), release(11, beta: true)]), 200)),
      buildInfo: () async => {'versionName': '1.2.3', 'versionCode': 10, 'packageName': 'com.dowlist.com', 'signerSha256': signerA},
    );
    await service.initialize();
    await tester.pumpWidget(MaterialApp(home: UpdateSettingsScreen(updates: service)));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('You’re up to date'), findsOneWidget);
    await tester.ensureVisible(find.text('Beta updates'));
    await tester.tap(find.text('Beta updates'));
    await tester.pumpAndSettle();
    expect(service.includeBeta, isTrue);
    await tester.ensureVisible(find.text('Check for updates'));
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('Update available'), findsOneWidget);
    expect(service.available!.versionCode, 11);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

}
