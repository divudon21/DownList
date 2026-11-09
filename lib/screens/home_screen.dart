import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    this.onViewTasks,
    this.onOpenSettings,
  });

  final ApiService api;
  final VoidCallback? onViewTasks;
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Clipboard is empty')),
      );
      return;
    }
    setState(() {
      _urlController.text = text;
    });
  }

  Future<void> _download() async {
    if (!widget.api.isConfigured) {
      setState(() {
        _message = 'Please configure your Server URL in Settings first.';
        _messageIsError = true;
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    try {
      final taskId = await widget.api.startDownload(_urlController.text);
      if (!mounted) return;
      setState(() {
        _urlController.clear();
        _message = 'Download started.\nTask ID: $taskId';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString().replaceFirst('Exception: ', '');
        _messageIsError = true;
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.api,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _buildHeader().animate().fadeIn(duration: 450.ms).slideY(begin: 0.06),
              const SizedBox(height: 20),
              if (!widget.api.isConfigured) ...[
                _buildServerPromptCard(),
                const SizedBox(height: 16),
              ],
              _buildCard()
                  .animate()
                  .fadeIn(duration: 500.ms)
                  .slideY(begin: 0.06, delay: 60.ms),
              const SizedBox(height: 20),
              if (_message != null)
                _buildMessage().animate().fadeIn(duration: 300.ms),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Remote Download',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.api.isConfigured
              ? 'Connected server: ${widget.api.baseUrl}'
              : 'Paste any direct file URL to download it on your server.',
          style: TextStyle(
            fontSize: 14,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildServerPromptCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No server URL set yet. Add your server URL in Settings to start downloads.',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (widget.onOpenSettings != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: widget.onOpenSettings,
              child: const Text('Settings'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _urlController,
                textInputAction: TextInputAction.done,
                keyboardType: TextInputType.url,
                textCapitalization: TextCapitalization.none,
                onFieldSubmitted: (_) => _download(),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter a URL';
                  }
                  final u = v.trim();
                  if (!(u.startsWith('http://') || u.startsWith('https://'))) {
                    return 'URL must start with http:// or https://';
                  }
                  return null;
                },
                decoration: const InputDecoration(
                  labelText: 'File URL',
                  hintText: 'https://example.com/file.mp4',
                  prefixIcon: Icon(Icons.link_outlined),
                  border: OutlineInputBorder(),
                  filled: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _download,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded),
                label: Text(_isSubmitting ? 'Starting...' : 'Start Download'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _isSubmitting ? null : _pasteFromClipboard,
                icon: const Icon(Icons.content_paste_rounded),
                label: const Text('Paste from Clipboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessage() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _messageIsError
            ? colorScheme.errorContainer
            : colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            _messageIsError ? Icons.error_outline : Icons.check_circle_outline,
            color: _messageIsError
                ? colorScheme.onErrorContainer
                : colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message!,
              style: TextStyle(
                color: _messageIsError
                    ? colorScheme.onErrorContainer
                    : colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (!_messageIsError && widget.onViewTasks != null)
            TextButton(
              onPressed: widget.onViewTasks,
              child: const Text('View Tasks'),
            ),
        ],
      ),
    );
  }
}
