import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';
import '../widgets/task_card.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({
    super.key,
    required this.api,
    this.onGoHome,
  });

  final ApiService api;
  final VoidCallback? onGoHome;

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  final Map<String, TaskModel> _tasks = {};
  bool _isLoading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh && !_isLoading) {
      setState(() => _isLoading = true);
    }
    try {
      final list = await widget.api.getHistory();
      final active = <String, TaskModel>{};
      for (final t in list) {
        if (t.isActive) {
          active[t.taskId] = t;
        }
      }
      if (!mounted) return;
      setState(() {
        _tasks
          ..clear()
          ..addAll(active);
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTasks = _tasks.values.toList()
      ..sort((a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

    return RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Tasks',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tasks that are downloading or processing on the server.',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    _errorBanner(_error!),
                  ],
                ],
              ),
            ),
          ),
          if (_isLoading && activeTasks.isEmpty)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (activeTasks.isEmpty)
            SliverFillRemaining(
              child: _emptyState().animate().fadeIn(duration: 500.ms),
            )
          else
            SliverList.builder(
              itemCount: activeTasks.length,
              itemBuilder: (context, index) {
                final task = activeTasks[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: TaskCard(
                    task: task,
                    api: widget.api,
                    onRefresh: () => _load(refresh: true),
                  ).animate().fadeIn(duration: 400.ms).slideX(),
                );
              },
            ),
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

  Widget _emptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.file_download_outlined,
            size: 64,
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
            'Start a download from Home and it will appear here.',
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
    );
  }
}
