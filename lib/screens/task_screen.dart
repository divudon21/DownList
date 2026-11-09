import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';
import '../services/upload_manager.dart';
import '../widgets/task_card.dart';
import '../widgets/upload_item_card.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({
    super.key,
    required this.api,
    required this.uploadManager,
    this.onGoHome,
    this.onOpenSettings,
  });

  final ApiService api;
  final UploadManager uploadManager;
  final VoidCallback? onGoHome;
  final VoidCallback? onOpenSettings;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final Map<String, TaskModel> _serverTasks = <String, TaskModel>{};
  Set<String> _previousActiveIds = <String>{};
  bool _isLoading = false;
  bool _fetchInFlight = false;
  String? _error;
  String _lastBaseUrl = '';
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _lastBaseUrl = widget.api.baseUrl;
    widget.api.addListener(_onApiChanged);
    widget.uploadManager.addListener(_onUploadsChanged);
    if (widget.api.isConfigured) {
      _load(initial: true);
    }
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    widget.api.removeListener(_onApiChanged);
    widget.uploadManager.removeListener(_onUploadsChanged);
    super.dispose();
  }

  void _onUploadsChanged() {
    if (mounted) setState(() {});
  }

  void _onApiChanged() {
    if (!mounted) return;
    if (_lastBaseUrl != widget.api.baseUrl) {
      _lastBaseUrl = widget.api.baseUrl;
      _serverTasks.clear();
      _previousActiveIds.clear();
      _error = null;
    }
    if (widget.api.isConfigured) {
      _load(initial: _serverTasks.isEmpty);
    } else {
      setState(() {
        _isLoading = false;
        _error = null;
      });
    }
  }

  Future<void> _load({bool initial = false, bool manualRefresh = false}) async {
    if (!widget.api.isConfigured) return;
    if (_fetchInFlight) return;
    _fetchInFlight = true;

    if ((initial || manualRefresh) && mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final list = await widget.api.getHistory();
      final active = <String, TaskModel>{};

      for (final task in list) {
        if (task.isActive) {
          active[task.taskId] = task;
        } else {
          widget.api.untrackSessionTask(task.taskId);
        }
      }

      // Also check any session-started task_ids not yet visible in /history
      final trackedIds = widget.api.sessionTaskIds;
      for (final trackedId in trackedIds) {
        if (!active.containsKey(trackedId)) {
          try {
            final t = await widget.api.getStatus(trackedId);
            if (t.isActive) {
              active[t.taskId] = t;
            } else {
              widget.api.untrackSessionTask(trackedId);
            }
          } catch (_) {
            widget.api.untrackSessionTask(trackedId);
          }
        }
      }

      final currentIds = active.keys.toSet();
      final anyFinished =
          _previousActiveIds.any((oldId) => !currentIds.contains(oldId));
      _previousActiveIds = currentIds;

      if (!mounted) return;
      setState(() {
        _serverTasks
          ..clear()
          ..addAll(active);
        _isLoading = false;
        _error = null;
      });

      widget.api.updateActiveServerTaskCount(active.length);
      if (anyFinished) {
        widget.api.notifyHistoryChanged();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      _fetchInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeUploads = widget.uploadManager.activeItems;
    final activeDownloads = _serverTasks.values.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

    final hasNothingActive = activeUploads.isEmpty && activeDownloads.isEmpty;

    return RefreshIndicator(
      onRefresh: () => _load(manualRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Tasks',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Live server downloads and active file uploads.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null && widget.api.isConfigured) ...[
                    const SizedBox(height: 10),
                    _errorBanner(_error!),
                  ],
                ],
              ),
            ),
          ),
          if (!widget.api.isConfigured && activeUploads.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _unconfiguredState(),
            )
          else if (_isLoading && hasNothingActive)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (hasNothingActive)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _emptyState().animate().fadeIn(duration: 400.ms),
            )
          else ...[
            if (activeUploads.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Text(
                        'UPLOADING (${activeUploads.length})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (activeUploads.length > 1)
                        TextButton.icon(
                          onPressed: widget.uploadManager.cancelAll,
                          icon: const Icon(Icons.cancel_outlined, size: 16),
                          label: const Text('Cancel All'),
                        ),
                    ],
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: activeUploads.length,
                itemBuilder: (context, index) {
                  final item = activeUploads[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: UploadItemCard(
                      item: item,
                      api: widget.api,
                      compactForTaskTab: true,
                      onStart: () => widget.uploadManager.startSingle(item.id),
                      onCancel: () => widget.uploadManager.cancelUpload(item.id),
                      onRemove: () => widget.uploadManager.removeItem(item.id),
                    ),
                  );
                },
              ),
            ],
            if (activeDownloads.isNotEmpty) ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'SERVER DOWNLOADS (${activeDownloads.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: activeDownloads.length,
                itemBuilder: (context, index) {
                  final task = activeDownloads[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: TaskCard(
                      task: task,
                      api: widget.api,
                      onRefresh: () => _load(manualRefresh: true),
                    ),
                  );
                },
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
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
              'Enter your server URL in Settings to track active downloads and uploads.',
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
            Icon(
              Icons.task_alt_rounded,
              size: 62,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No active tasks',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Active URL downloads and file uploads will appear here live.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            if (widget.onGoHome != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: widget.onGoHome,
                icon: const Icon(Icons.home_outlined),
                label: const Text('Go to Home'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
