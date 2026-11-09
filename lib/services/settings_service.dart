import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _keyServerUrl = 'server_url';
  static const String defaultServerUrl = 'https://thed1-aiagent.hf.space';

  late final Future<SharedPreferences> _prefs =
      SharedPreferences.getInstance();

  Future<String> getServerUrl() async {
    final prefs = await _prefs;
    return prefs.getString(_keyServerUrl) ?? defaultServerUrl;
  }

  Future<void> setServerUrl(String url) async {
    final cleaned = url.trim();
    final normalized = cleaned.endsWith('/')
        ? cleaned.substring(0, cleaned.length - 1)
        : cleaned;
    final prefs = await _prefs;
    await prefs.setString(_keyServerUrl, normalized);
  }

  Future<void> resetToDefault() async {
    final prefs = await _prefs;
    await prefs.setString(_keyServerUrl, defaultServerUrl);
  }
}
