import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';

class TaskCard extends StatelessWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.api,
    this.onRefresh,
  });

  final TaskModel task;
  final ApiService api;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVideo = task.isVideo;
    final indeterminate = task.isActive && (task.totalSize <= 0 || (task.isGofileTransfer && task.status == 'completed') || (task.isGofileUpload && !task.gofileUploadProgressKnown));

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isVideo ? Icons.videocam_rounded : Icons.file_download_rounded,
                    color: colorScheme.onPrimaryContainer,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        task.statusLabel +
                            (task.speed > 0 ? '  ·  ${task.speedFormatted}' : ''),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  indeterminate
                      ? '...'
                      : '${(task.progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: indeterminate ? null : task.progress,
                minHeight: 8,
                backgroundColor:
                    colorScheme.surfaceContainerLow.withValues(alpha: 0.8),
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _stat(
                    context,
                    task.status == 'uploading_to_gofile' ? 'Uploaded' : 'Downloaded',
                    task.isGofileUpload && !task.gofileUploadProgressKnown ? '--' : task.downloadedFormatted,
                    Icons.done_outline,
                  ),
                ),
                Expanded(
                  child: _stat(
                    context,
                    'Total Size',
                    task.totalSize <= 0 ? '--' : task.sizeFormatted,
                    Icons.sd_storage_outlined,
                  ),
                ),
                Expanded(
                  child: _stat(
                    context,
                    'ETA',
                    task.etaFormatted,
                    Icons.access_time_outlined,
                  ),
                ),
              ],
            ),
            if (task.error != null && task.isError) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 18,
                      color: colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Error: ${task.error}',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (task.isActive) TextButton.icon(
                  onPressed: () async {
                    try { await api.cancelTask(task.taskId); onRefresh?.call(); }
                    catch (e) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()))); }
                  },
                  icon: const Icon(Icons.cancel_outlined), label: const Text('Cancel'),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    if (onRefresh != null) {
                      onRefresh!();
                      return;
                    }
                    try {
                      await api.getStatus(task.taskId);
                    } catch (_) {}
                  },
                  icon: const Icon(Icons.refresh_outlined, size: 18),
                  label: const Text('Refresh'),
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1);
  }

  Widget _stat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
