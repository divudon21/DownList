import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/task_model.dart';
import '../../services/api_service.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings_components.dart';

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key, required this.settings, required this.api});

  final SettingsService settings;
  final ApiService api;

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _testing = false;
  String? _message;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final url = await widget.settings.getServerUrl();
      if (!mounted) return;
      setState(() { _controller.text = url; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _isError = true; _message = 'Could not load server settings.'; });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _validate() {
    final value = _controller.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
      setState(() { _message = 'Enter a valid HTTP or HTTPS server URL.'; _isError = true; });
      return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (!_validate()) return;
    try {
      await widget.settings.setServerUrl(_controller.text);
      final url = await widget.settings.getServerUrl();
      widget.api.baseUrl = url;
      if (!mounted) return;
      setState(() { _controller.text = url; _message = 'Server URL saved.'; _isError = false; });
    } catch (_) {
      if (mounted) setState(() { _message = 'Could not save the server URL.'; _isError = true; });
    }
  }

  Future<void> _test() async {
    if (!_validate()) return;
    setState(() { _testing = true; _message = null; });
    try {
      final status = await widget.api.getServerStatus(overrideBaseUrl: _controller.text.trim());
      if (!mounted) return;
      final free = status.storageFree;
      setState(() {
        _isError = !status.serverOnline;
        _message = status.serverOnline
            ? 'Server is online${free != null ? ' · ${TaskModel.formatBytes(free)} free' : ''}'
            : 'Server is not online.';
      });
    } catch (e) {
      if (mounted) setState(() { _message = 'Connection failed: ${e.toString().replaceFirst('Exception: ', '')}'; _isError = true; });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _paste() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clipboard is empty')));
    } else {
      setState(() => _controller.text = text);
    }
  }

  Future<void> _clear() async {
    await widget.settings.clearServerUrl();
    widget.api.baseUrl = '';
    if (mounted) setState(() { _controller.clear(); _message = 'Server URL cleared.'; _isError = false; });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsPage(
      title: 'Server',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SettingsSectionTitle('Connection'),
        SettingsGroup(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Server URL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_loading,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                textCapitalization: TextCapitalization.none,
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  hintText: 'Enter server URL',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: IconButton(tooltip: 'Paste', onPressed: _loading ? null : _paste, icon: const Icon(Icons.content_paste_rounded)),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: FilledButton.icon(onPressed: _loading ? null : _save, icon: const Icon(Icons.check_rounded), label: const Text('Save'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _loading || _testing ? null : _test,
                  icon: _testing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_tethering_rounded),
                  label: const Text('Test'),
                )),
              ]),
              if (widget.api.isConfigured) Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: _loading ? null : _clear, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Clear URL')),
              ),
            ]),
          ),
        ]),
        if (_message != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: _isError ? colors.errorContainer : colors.secondaryContainer, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(_isError ? Icons.error_outline : Icons.check_circle_outline, color: _isError ? colors.onErrorContainer : colors.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(_message!, style: TextStyle(color: _isError ? colors.onErrorContainer : colors.onSecondaryContainer))),
            ]),
          ),
        ],
      ]),
    );
  }
}
