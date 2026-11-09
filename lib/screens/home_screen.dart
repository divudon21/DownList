import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    this.onViewTasks,
  });

  final ApiService api;
  final VoidCallback? onViewTasks;

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

  Future<void> _download() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    try {
      final taskId = await widget.api.startDownload(_urlController.text);
      if (!mounted) return;
      setState(() {
        _message = 'Download started.\nTask ID: $taskId';
        _messageIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString();
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _buildHeader().animate().fadeIn(duration: 600.ms).slideY(),
          const SizedBox(height: 24),
          _buildCard()
              .animate()
              .fadeIn(duration: 700.ms)
              .slideY(delay: 100.ms),
          const SizedBox(height: 20),
          if (_message != null)
            _buildMessage().animate().fadeIn(duration: 400.ms),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Download from server',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Paste any file URL. It will be downloaded on your server '
          '${widget.api.baseUrl.isNotEmpty ? widget.api.baseUrl : '(not set)'}.',
          style: TextStyle(
            fontSize: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(22),
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
                  hintText: 'https://example.com/file.zip',
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
                    : const Icon(Icons.download_outlined),
                label: Text(_isSubmitting ? 'Starting...' : 'Start Download'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () {
                        setState(() {
                          _urlController.text =
                              'https://thed1-aiagent.hf.space/download/';
                        });
                      },
                icon: const Icon(Icons.paste_outlined),
                label: const Text('Paste example'),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
