import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';

  late final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();

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
