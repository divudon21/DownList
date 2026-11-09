import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';
import '../services/settings_service.dart';
import '../services/platform_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.api,
  });

  final SettingsService settings;
  final ApiService api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final TextEditingController _urlController;
  bool _isLoading = true;
  bool _isTesting = false;
  String? _status;
  bool _statusIsError = false;
  bool _showUploads = true;
  bool _showDownloads = true;
  bool _notificationsEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _urlController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _urlController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadNotificationSettings();
  }

  Future<void> _loadNotificationSettings() async {
    try {
      final values = await PlatformService.instance.getNotificationSettings();
      if (mounted) setState(() { _showUploads = values['uploads'] ?? true; _showDownloads = values['downloads'] ?? true; _notificationsEnabled = values['enabled'] ?? false; });
    } catch (_) {}
  }

  Future<void> _setNotification(String key, bool value) async {
    try {
      await PlatformService.instance.setNotificationSetting(key, value);
      if (value) await PlatformService.instance.requestNotificationPermission();
      await _loadNotificationSettings();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notification settings unavailable: $e')));
    }
  }

  Future<void> _load() async {
    _loadNotificationSettings();
    final url = await widget.settings.getServerUrl();
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _isLoading = false;
    });
  }

  Future<void> _pasteUrl() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) return;
    setState(() {
      _urlController.text = text;
    });
  }

  Future<void> _save() async {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) {
      setState(() {
        _status = 'Please enter your Server URL.';
        _statusIsError = true;
      });
      return;
    }
    if (!(newUrl.startsWith('http://') || newUrl.startsWith('https://'))) {
      setState(() {
        _status = 'Server URL must start with http:// or https://';
        _statusIsError = true;
      });
      return;
    }
    setState(() => _status = null);
    try {
      await widget.settings.setServerUrl(newUrl);
      final saved = await widget.settings.getServerUrl();
      widget.api.baseUrl = saved;
      if (!mounted) return;
      setState(() {
        _urlController.text = saved;
        _status = 'Server URL saved.';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Save failed: $e';
        _statusIsError = true;
      });
    }
  }

  Future<void> _testConnection() async {
    final candidate = _urlController.text.trim();
    if (candidate.isEmpty) {
      setState(() {
        _status = 'Enter a Server URL first to test connection.';
        _statusIsError = true;
      });
      return;
    }
    if (!(candidate.startsWith('http://') || candidate.startsWith('https://'))) {
      setState(() {
        _status = 'Server URL must start with http:// or https://';
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _status = null;
    });

    try {
      final info = await widget.api.getServerStatus(overrideBaseUrl: candidate);
      if (!mounted) return;
      final freeDisk = info.storageFree != null && info.storageFree! > 0
          ? ' · Free storage: ${TaskModel.formatBytes(info.storageFree!)}'
          : '';
      setState(() {
        _status = info.serverOnline
            ? 'Server is online$freeDisk'
            : 'Connected to server$freeDisk';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status =
            'Connection failed: ${e.toString().replaceFirst("Exception: ", "")}';
        _statusIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  Future<void> _clearUrl() async {
    await widget.settings.clearServerUrl();
    widget.api.baseUrl = '';
    if (!mounted) return;
    setState(() {
      _urlController.clear();
      _status = 'Server URL cleared.';
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.api,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text(
                'Server Settings',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06),
              const SizedBox(height: 8),
              Text(
                'Enter your own server URL to manage remote downloads, uploads, and media streaming.',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ).animate().fadeIn(duration: 450.ms).slideY(begin: 0.06, delay: 50.ms),
              const SizedBox(height: 22),
              Card(
                elevation: 0,
                color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Server URL',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _urlController,
                        enabled: !_isLoading,
                        keyboardType: TextInputType.url,
                        textCapitalization: TextCapitalization.none,
                        onFieldSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          hintText: 'https://your-server-address.com',
                          prefixIcon: const Icon(Icons.dns_outlined),
                          suffixIcon: IconButton(
                            tooltip: 'Paste',
                            onPressed: _isLoading ? null : _pasteUrl,
                            icon: const Icon(Icons.content_paste_rounded),
                          ),
                          border: const OutlineInputBorder(),
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isLoading ? null : _save,
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: const Text('Save'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            onPressed:
                                (_isLoading || _isTesting) ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.wifi_tethering_rounded, size: 18),
                            label: const Text('Test'),
                          ),
                        ],
                      ),
                      if (widget.api.isConfigured) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _isLoading ? null : _clearUrl,
                            icon: Icon(
                              Icons.delete_outline,
                              size: 17,
                              color: colorScheme.error,
                            ),
                            label: Text(
                              'Clear saved URL',
                              style: TextStyle(color: colorScheme.error),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Notifications', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text('Choose which transfer details appear in the notification.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              Card(
                elevation: 0, color: colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.cloud_upload_outlined),
                    title: const Text('Show upload details'),
                    subtitle: const Text('Device and GoFile uploads with progress'),
                    value: _showUploads, onChanged: (value) => _setNotification('uploads', value),
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  SwitchListTile(
                    secondary: const Icon(Icons.download_outlined),
                    title: const Text('Show download details'),
                    subtitle: const Text('Server download progress'),
                    value: _showDownloads, onChanged: (value) => _setNotification('downloads', value),
                  ),
                  if (!_notificationsEnabled)
                    ListTile(leading: const Icon(Icons.notifications_off_outlined),
                      title: const Text('Notifications are disabled'),
                      subtitle: const Text('Allow notifications in Android settings to see transfer progress.'),
                      trailing: TextButton(onPressed: () async { try { await PlatformService.instance.openNotificationSettings(); } catch (_) {} }, child: const Text('Open'))),
                ]),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text('Android may show a basic service notification during background transfers even when details are off.', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
              if (_status != null) ...[
                const SizedBox(height: 16),
                _statusBox(context).animate().fadeIn(duration: 300.ms),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusBox(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _statusIsError
            ? colorScheme.errorContainer.withValues(alpha: 0.7)
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _statusIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: _statusIsError
                ? colorScheme.onErrorContainer
                : colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _status!,
              style: TextStyle(
                color: _statusIsError
                    ? colorScheme.onErrorContainer
                    : colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
