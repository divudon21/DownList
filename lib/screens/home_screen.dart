import 'dart:async';

import 'package:flutter/material.dart';
import 'package:liquid_glass_bottom_nav/liquid_glass_bottom_nav.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../services/api_service.dart';
import '../services/platform_service.dart';
import '../models/task_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    this.initiallyExpanded = false,
    this.onViewTasks,
    this.onOpenSettings,
  });

  final ApiService api;
  final bool initiallyExpanded;
  final VoidCallback? onViewTasks;
  final VoidCallback? onOpenSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _urlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  late bool _expanded;
  String? _gofileTaskId;
  String? _gofileServer;
  TaskModel? _gofileTask;
  Timer? _gofileTimer;
  bool _polling = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    if (widget.api.gofileTaskIds.isNotEmpty) {
      _gofileTaskId = widget.api.gofileTaskIds.last;
      _gofileServer = widget.api.baseUrl;
      _gofileTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollGofile());
      _pollGofile();
    }
  }

  @override
  void dispose() {
    _gofileTimer?.cancel();
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

  Future<void> _startGofile() async {
    if (!widget.api.isConfigured) {
      setState(() { _message = 'Please configure your Server URL in Settings first.'; _messageIsError = true; });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSubmitting = true; _message = null; });
    try {
      final server = widget.api.baseUrl;
      final id = await widget.api.startGofileTransfer(_urlController.text);
      if (!mounted) return;
      _gofileTimer?.cancel();
      setState(() { _gofileTaskId = id; _gofileServer = server; _gofileTask = null; });
      _gofileTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollGofile());
      await _pollGofile();
    } catch (e) {
      if (mounted) setState(() { _message = e.toString().replaceFirst('Exception: ', ''); _messageIsError = true; });
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _pollGofile() async {
    if (_polling || _gofileTaskId == null) return;
    if (_gofileServer != widget.api.baseUrl) { _gofileTimer?.cancel(); return; }
    _polling = true;
    try {
      final task = await widget.api.getStatus(_gofileTaskId!);
      if (!mounted || _gofileServer != widget.api.baseUrl) return;
      setState(() => _gofileTask = task);
      if (!task.isActive) { _gofileTimer?.cancel(); widget.api.notifyHistoryChanged(); }
    } catch (e) {
      if (mounted) setState(() { _message = 'Could not refresh GoFile transfer: ${e.toString().replaceFirst('Exception: ', '')}'; _messageIsError = true; });
    } finally { _polling = false; }
  }

  Widget _gofileCard(TaskModel task) => Card(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(task.hasGofileUrl ? 'GoFile Link Ready' : 'GoFile transfer: ${task.statusLabel}', style: Theme.of(context).textTheme.titleMedium),
      if (task.isActive) ...[
        const SizedBox(height: 10),
        LinearProgressIndicator(value: task.totalSize > 0 && (!task.isGofileUpload || task.gofileUploadProgressKnown) && task.status != 'completed' ? task.progress : null),
        Text(task.isGofileUpload && !task.gofileUploadProgressKnown
            ? 'Uploading to GoFile — progress unavailable or waiting for confirmation'
            : task.status == 'completed' && !task.hasGofileUrl
                ? 'Preparing to upload to GoFile…'
                : '${task.downloadedFormatted} / ${task.sizeFormatted}  ·  ${task.speedFormatted}'),
      ],
      if (task.error != null) Text(task.error!),
      if (task.hasGofileUrl) ...[
        const SizedBox(height: 8), SelectableText(task.gofileUrl!),
        Wrap(spacing: 8, children: [
          TextButton.icon(onPressed: () async { await Clipboard.setData(ClipboardData(text: task.gofileUrl!)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GoFile link copied'))); }, icon: const Icon(Icons.copy), label: const Text('Copy')),
          TextButton.icon(onPressed: () async { try { await PlatformService.instance.openUrl(task.gofileUrl!); } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to open link'))); } }, icon: const Icon(Icons.open_in_new), label: const Text('Open')),
        ]),
      ],
    ])),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.api,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20 + LiquidGlassNavBar.contentBottomInset),
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
              if (_gofileTask != null && _gofileServer == widget.api.baseUrl) _gofileCard(_gofileTask!),
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
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      padding: EdgeInsets.all(_expanded ? 16 : 0),
      decoration: BoxDecoration(
        color: _expanded ? colors.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextFormField(
            controller: _urlController,
            textInputAction: TextInputAction.done,
            keyboardType: TextInputType.url,
            textCapitalization: TextCapitalization.none,
            onTap: () { if (!_expanded) setState(() => _expanded = true); },
            onFieldSubmitted: (_) => _download(),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter a URL';
              final u = v.trim();
              if (!(u.startsWith('http://') || u.startsWith('https://'))) return 'URL must start with http:// or https://';
              return null;
            },
            decoration: InputDecoration(
              labelText: 'File URL',
              hintText: 'https://example.com/file.mp4',
              prefixIcon: const Icon(Icons.link_outlined),
              suffixIcon: _expanded ? IconButton(
                tooltip: 'Collapse download panel',
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _expanded = false);
                },
              ) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _expanded ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _isSubmitting ? null : _download,
                icon: _isSubmitting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: Text(_isSubmitting ? 'Starting...' : 'Start Download'),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _pasteFromClipboard,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('Clipboard')),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _startGofile,
                  style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: const FittedBox(fit: BoxFit.scaleDown, child: Text('GoFile')),
                )),
              ]),
            ]) : const SizedBox(width: double.infinity),
          ),
        ]),
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
