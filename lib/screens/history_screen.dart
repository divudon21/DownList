import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';
import '../widgets/history_card.dart';
import '../widgets/settings_components.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.api,
    this.onOpenSettings,
  });

  final ApiService api;
  final VoidCallback? onOpenSettings;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final List<TaskModel> _tasks = <TaskModel>[];
  bool _isLoading = false;
  String? _error;
  String _lastBaseUrl = '';
  int _lastHistoryVersion = -1;

  @override
  void initState() {
    super.initState();
    _lastBaseUrl = widget.api.baseUrl;
    _lastHistoryVersion = widget.api.historyVersion;
    widget.api.addListener(_onApiUpdated);
    if (widget.api.isConfigured) {
      _load(showSpinner: true);
    }
  }

  @override
  void dispose() {
    widget.api.removeListener(_onApiUpdated);
    super.dispose();
  }

  void _onApiUpdated() {
    if (!mounted) return;
    final urlChanged = _lastBaseUrl != widget.api.baseUrl;
    final versionChanged = _lastHistoryVersion != widget.api.historyVersion;
    _lastBaseUrl = widget.api.baseUrl;
    _lastHistoryVersion = widget.api.historyVersion;

    if (!widget.api.isConfigured) {
      setState(() {
        _tasks.clear();
        _isLoading = false;
        _error = null;
      });
      return;
    }

    if (urlChanged) {
      _tasks.clear();
      _load(showSpinner: true);
    } else if (versionChanged) {
      _load();
    }
  }

  Future<void> _load({bool showSpinner = false}) async {
    if (!widget.api.isConfigured) return;
    if (showSpinner && mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final list = await widget.api.getHistory();
      final done = list.where((t) => t.isCompleted || t.isError).toList()
        ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));
      if (!mounted) return;
      setState(() {
        _tasks
          ..clear()
          ..addAll(done);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: RefreshIndicator(
        onRefresh: () => _load(showSpinner: _tasks.isEmpty),
        child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SettingsGroup(children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    child: const Icon(Icons.history_rounded),
                  ),
                  title: const Text('Transfer history', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${_tasks.length} completed or failed transfers'),
                  trailing: _tasks.isEmpty
                      ? Text('${_tasks.length}', style: Theme.of(context).textTheme.titleMedium)
                      : IconButton.filledTonal(
                          tooltip: 'Clear all server files',
                          onPressed: _clearAll,
                          icon: const Icon(Icons.delete_sweep_outlined),
                        ),
                ),
              ]),
            ),
          ),
          if (_error != null && widget.api.isConfigured)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              sliver: SliverToBoxAdapter(child: _errorBanner(_error!)),
            ),
          if (!widget.api.isConfigured)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _unconfiguredState(),
            )
          else if (_isLoading && _tasks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_tasks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState().animate().fadeIn(duration: 400.ms),
            )
          else ...[
            SliverList.builder(
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  child: HistoryCard(
                    task: task,
                    api: widget.api,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
        ),
      ),
    );
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Delete all server files?'),
      content: const Text('This cancels active server tasks and deletes all server files and history. GoFile copies are not deleted.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete all'))],
    ));
    if (confirmed != true) return;
    try { await widget.api.deleteAllTasks(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
  }

  Widget _errorBanner(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _unconfiguredState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 60,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Server Not Configured',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set your server URL in Settings to browse completed files and stream media.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (widget.onOpenSettings != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: widget.onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open Settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No history yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Completed downloads and uploaded files will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
