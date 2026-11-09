import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/api_service.dart';
import '../services/settings_service.dart';

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

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _urlController;
  bool _isLoading = true;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await widget.settings.getServerUrl();
    if (!mounted) return;
    setState(() {
      _urlController.text = url;
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final newUrl = _urlController.text.trim();
    if (newUrl.isEmpty) {
      setState(() {
        _status = 'Server URL cannot be empty.';
        _statusIsError = true;
      });
      return;
    }
    if (!(newUrl.startsWith('http://') || newUrl.startsWith('https://'))) {
      setState(() {
        _status = 'URL must start with http:// or https://';
        _statusIsError = true;
      });
      return;
    }
    setState(() => _status = null);
    try {
      await widget.settings.setServerUrl(newUrl);
      final normalized = await widget.settings.getServerUrl();
      widget.api.baseUrl = normalized;
      if (!mounted) return;
      setState(() {
        _urlController.text = normalized;
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

  Future<void> _reset() async {
    await widget.settings.resetToDefault();
    widget.api.baseUrl = await widget.settings.getServerUrl();
    await _load();
    if (!mounted) return;
    setState(() {
      _status = 'Reset to default server URL.';
      _statusIsError = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
          ).animate().fadeIn(duration: 500.ms).slideY(),
          const SizedBox(height: 10),
          Text(
            'The server URL is stored on this device and is NOT hardcoded '
            'anywhere in the app. Change it to point at your own server.',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant,
            ),
          ).animate().fadeIn(duration: 500.ms).slideY(delay: 80.ms),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Server URL',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _urlController,
                    enabled: !_isLoading,
                    decoration: const InputDecoration(
                      hintText: 'https://your-server.example.com',
                      border: OutlineInputBorder(),
                      filled: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _isLoading ? null : _save,
                          child: const Text('Save'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: _isLoading ? null : _reset,
                        child: const Text('Reset to default'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _statusBox(context).animate().fadeIn(duration: 400.ms),
          const SizedBox(height: 24),
          _infoPanel(context).animate().fadeIn(duration: 500.ms).slideY(),
        ],
      ),
    );
  }

  Widget _statusBox(BuildContext context) {
    if (_status == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _statusIsError
            ? colorScheme.errorContainer.withValues(alpha: 0.6)
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

  Widget _infoPanel(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Important',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _bullet(
            context,
            'Default server: https://thed1-aiagent.hf.space (THED1 AIAGENT)',
          ),
          _bullet(
            context,
            'Change the URL above to use your own server — nothing is hardcoded.',
          ),
          _bullet(
            context,
            'Delete and rename require server-side endpoints that this server '
            'does not currently expose, so they are reported honestly.',
          ),
          _bullet(
            context,
            'Resolution / bitrate are not exposed by the server, so they are '
            'shown as "not available" rather than being invented.',
          ),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(color: colorScheme.primary, fontSize: 16),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
