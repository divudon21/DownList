import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_service.dart';

const _releasesUrl = 'https://api.github.com/repos/divudon21/DownList/releases?per_page=100';
const _packageName = 'com.dowlist.com';
final _metadataPattern = RegExp(r'<!--\s*downlist-update:(\{[^\r\n]*\})\s*-->');
final _fingerprintPattern = RegExp(r'^[a-f0-9]{64}$');

class InstalledBuild {
  const InstalledBuild({required this.versionName, required this.versionCode, required this.packageName, required this.signerSha256});
  final String versionName;
  final int versionCode;
  final String packageName;
  final String signerSha256;

  factory InstalledBuild.fromMap(Map<String, dynamic> map) {
    final code = (map['versionCode'] as num?)?.toInt() ?? 0;
    final package = map['packageName']?.toString() ?? '';
    final signer = (map['signerSha256']?.toString() ?? '').toLowerCase();
    if (code <= 0 || package != _packageName || !_fingerprintPattern.hasMatch(signer)) {
      throw const FormatException('Installed app information is unavailable or invalid.');
    }
    return InstalledBuild(versionName: map['versionName']?.toString() ?? '', versionCode: code, packageName: package, signerSha256: signer);
  }
}

class UpdateRelease {
  const UpdateRelease({required this.versionName, required this.versionCode, required this.prerelease, required this.releaseUrl, required this.downloadUrl, required this.signerSha256});
  final String versionName;
  final int versionCode;
  final bool prerelease;
  final String releaseUrl;
  final String downloadUrl;
  final String signerSha256;
  String get label => '$versionName (build $versionCode)${prerelease ? ' · Beta' : ''}';
  bool isCompatibleWith(InstalledBuild installed) => signerSha256 == installed.signerSha256;
}

/// Only releases with validated package, build number, certificate and APK metadata are considered.
UpdateRelease? selectUpdateRelease(List<dynamic> releases, InstalledBuild installed, {required bool includeBeta}) {
  UpdateRelease? newest;
  var validCount = 0;
  for (final item in releases) {
    if (item is! Map || item['draft'] == true || (!includeBeta && item['prerelease'] == true)) continue;
    final body = item['body'];
    if (body is! String) continue;
    final match = _metadataPattern.firstMatch(body);
    if (match == null) continue;
    try {
      final data = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      final code = (data['versionCode'] as num?)?.toInt() ?? 0;
      final name = data['versionName']?.toString().trim() ?? '';
      final signer = (data['signerSha256']?.toString() ?? '').toLowerCase();
      final releaseUrl = item['html_url']?.toString() ?? '';
      final releaseUri = Uri.tryParse(releaseUrl);
      final assets = item['assets'];
      if (data['packageName'] != installed.packageName || code <= 0 || name.isEmpty || name.length > 80 || !_fingerprintPattern.hasMatch(signer) ||
          releaseUri?.scheme != 'https' || releaseUri?.host != 'github.com' || !(releaseUri?.path.startsWith('/divudon21/DownList/releases/tag/') ?? false) || assets is! List) continue;
      Map? apk;
      for (final asset in assets.whereType<Map>()) {
        if (asset['name'] == 'DownList-universal.apk' && asset['state'] == 'uploaded') { apk = asset; break; }
      }
      if (apk == null) continue;
      final downloadUrl = apk['browser_download_url']?.toString() ?? '';
      final downloadUri = Uri.tryParse(downloadUrl);
      if (downloadUri?.scheme != 'https' || downloadUri?.host != 'github.com' || !(downloadUri?.path.startsWith('/divudon21/DownList/releases/download/') ?? false)) continue;
      validCount++;
      final release = UpdateRelease(versionName: name, versionCode: code, prerelease: item['prerelease'] == true, releaseUrl: releaseUrl, downloadUrl: downloadUrl, signerSha256: signer);
      if (newest == null || release.versionCode > newest.versionCode) newest = release;
    } catch (_) {
      // Skip releases that don't carry valid DownList metadata.
    }
  }
  if (validCount == 0) throw const FormatException('No compatible release information is available yet.');
  return newest != null && newest.versionCode > installed.versionCode ? newest : null;
}

class UpdateService extends ChangeNotifier {
  UpdateService({http.Client? client, Future<Map<String, dynamic>> Function()? buildInfo})
      : _client = client ?? http.Client(),
        _buildInfo = buildInfo ?? PlatformService.instance.getAppBuildInfo;

  final http.Client _client;
  final Future<Map<String, dynamic>> Function() _buildInfo;
  bool autoCheck = true;
  bool notifications = true;
  bool includeBeta = false;
  bool popup = true;
  bool ready = false;
  bool checking = false;
  bool checked = false;
  String? error;
  InstalledBuild? installed;
  UpdateRelease? available;
  bool _disposed = false;
  Future<UpdateRelease?>? _pending;

  void _notify() { if (!_disposed) notifyListeners(); }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    autoCheck = prefs.getBool('updates_auto_check') ?? true;
    notifications = prefs.getBool('updates_notifications') ?? true;
    includeBeta = prefs.getBool('updates_include_beta') ?? false;
    popup = prefs.getBool('updates_popup') ?? true;
    ready = true;
    _notify();
  }

  Future<void> setOption(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    switch (key) {
      case 'auto_check': autoCheck = value; break;
      case 'notifications': notifications = value; break;
      case 'include_beta':
        includeBeta = value;
        checked = false;
        error = null;
        available = null;
        break;
      case 'popup': popup = value; break;
      default: throw ArgumentError.value(key, 'key');
    }
    await prefs.setBool('updates_$key', value);
    _notify();
    if (key == 'notifications' && !value) {
      try { await PlatformService.instance.clearUpdateNotification(); } catch (_) {}
    }
    if (key == 'notifications' && value) {
      try { await PlatformService.instance.requestNotificationPermission(); } catch (_) {}
    }
  }

  Future<UpdateRelease?> check() {
    if (_pending != null) return _pending!;
    final future = _check();
    _pending = future;
    return future.whenComplete(() => _pending = null);
  }

  Future<UpdateRelease?> _check() async {
    checking = true;
    error = null;
    _notify();
    try {
      final build = InstalledBuild.fromMap(await _buildInfo());
      final response = await _client.get(Uri.parse(_releasesUrl), headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw Exception('Update service returned HTTP ${response.statusCode}.');
      final data = jsonDecode(response.body);
      if (data is! List) throw const FormatException('Invalid response from the update service.');
      final release = selectUpdateRelease(data, build, includeBeta: includeBeta);
      installed = build;
      available = release;
      checked = true;
      return release;
    } catch (e) {
      checked = false;
      available = null;
      error = e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', '');
      return null;
    } finally {
      checking = false;
      _notify();
    }
  }

  Future<void> notifyIfNeeded(UpdateRelease release) async {
    if (!notifications || installed == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt('updates_notified_build') == release.versionCode) return;
      final shown = await PlatformService.instance.showUpdateNotification(release.label, release.releaseUrl, release.isCompatibleWith(installed!));
      if (shown) await prefs.setInt('updates_notified_build', release.versionCode);
    } catch (_) {}
  }

  Future<void> openRelease(UpdateRelease release) => PlatformService.instance.openUrl(release.releaseUrl);

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
