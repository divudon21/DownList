import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String _keyHomeExpanded = 'home_expanded_on_start';
  static const String _keyNotificationAsked = 'notification_permission_asked';

  late final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();

  Future<bool> notificationPermissionAsked() async => (await _prefs).getBool(_keyNotificationAsked) ?? false;
  Future<void> markNotificationPermissionAsked() async { await (await _prefs).setBool(_keyNotificationAsked, true); }

  Future<bool> getHomeExpandedOnStart() async => (await _prefs).getBool(_keyHomeExpanded) ?? false;
  Future<void> setHomeExpandedOnStart(bool value) async { await (await _prefs).setBool(_keyHomeExpanded, value); }

  Future<String> getServerUrl() async {
    final prefs = await _prefs;
    return prefs.getString(_keyServerUrl) ?? '';
  }

  Future<void> setServerUrl(String url) async {
    var cleaned = url.trim();
    while (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    final prefs = await _prefs;
    await prefs.setString(_keyServerUrl, cleaned);
  }

  Future<void> clearServerUrl() async {
    final prefs = await _prefs;
    await prefs.remove(_keyServerUrl);
  }
}
