import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';
import '../services/upload_manager.dart';
import '../widgets/settings_components.dart';
import '../widgets/upload_item_card.dart';

class UploadScreen extends StatelessWidget {
  const UploadScreen({
    super.key,
    required this.api,
    required this.uploadManager,
    this.onOpenSettings,
  });

  final ApiService api;
  final UploadManager uploadManager;
  final VoidCallback? onOpenSettings;

  Future<void> _pickFiles(BuildContext context) async {
    try {
      await uploadManager.pickFiles();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open file picker: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([api, uploadManager]),
      builder: (context, _) {
        final colorScheme = Theme.of(context).colorScheme;
        final items = uploadManager.items;
        final readyCount = uploadManager.readyItems.length;
        final activeCount = uploadManager.activeItems.length;
        final completedCount = items
            .where((i) => i.status == UploadStatus.completed)
            .length;
        final totalBytes = uploadManager.totalSelectedBytes;
        final uploadedBytes = uploadManager.totalUploadedBytes;
        final batchProgress =
            totalBytes > 0 ? (uploadedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

        return ColoredBox(
          color: colorScheme.surfaceContainer,
          child: CustomScrollView(
            slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SettingsSectionTitle('FILE UPLOADS'),
                    if (!api.isConfigured) ...[
                      _buildServerBanner(context),
                      const SizedBox(height: 12),
                    ],
                    SettingsGroup(children: [
                      _buildControlCard(
                        context: context,
                        totalCount: items.length,
                        readyCount: readyCount,
                        activeCount: activeCount,
                        completedCount: completedCount,
                        totalBytes: totalBytes,
                        uploadedBytes: uploadedBytes,
                        batchProgress: batchProgress,
                      ),
                    ]),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(context)
                    .animate()
                    .fadeIn(duration: 350.ms),
              )
            else ...[
              SliverList.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: UploadItemCard(
                      item: item,
                      api: api,
                      onStart: () => uploadManager.startSingle(item.id),
                      onCancel: () => uploadManager.cancelUpload(item.id),
                      onRemove: () => uploadManager.removeItem(item.id),
                    ),
                  );
                },
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ],
          ),
        );
      },
    );
  }

  Widget _buildServerBanner(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_outlined, color: colorScheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Set your Server URL in Settings before starting uploads.',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (onOpenSettings != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: onOpenSettings,
              child: const Text('Settings'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlCard({
    required BuildContext context,
    required int totalCount,
    required int readyCount,
    required int activeCount,
    required int completedCount,
    required int totalBytes,
    required int uploadedBytes,
    required double batchProgress,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final speed = uploadManager.combinedSpeed;

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pickFiles(context),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                      totalCount == 0 ? 'Select Files' : 'Add More Files',
                    ),
                  ),
                ),
                if (readyCount > 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: api.isConfigured ? uploadManager.startAll : null,
                      icon: const Icon(Icons.cloud_upload_rounded),
                      label: Text('Upload All ($readyCount)'),
                    ),
                  ),
                ],
              ],
            ),
            if (totalCount > 0) ...[
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _summaryMetric(
                      context,
                      'Files',
                      '$completedCount / $totalCount done',
                    ),
                  ),
                  Expanded(
                    child: _summaryMetric(
                      context,
                      'Total Size',
                      TaskModel.formatBytes(totalBytes),
                    ),
                  ),
                  Expanded(
                    child: _summaryMetric(
                      context,
                      'Upload Speed',
                      speed > 0 ? '${TaskModel.formatBytes(speed.round())}/s' : '--',
                    ),
                  ),
                ],
              ),
              if (activeCount > 0) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: totalBytes > 0 ? batchProgress : null,
                    minHeight: 7,
                    backgroundColor:
                        colorScheme.surfaceContainerLow.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${TaskModel.formatBytes(uploadedBytes)} of ${TaskModel.formatBytes(totalBytes)} uploaded  ·  ${(batchProgress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (activeCount > 0 || uploadManager.hasFinishedItems) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (activeCount > 0)
                      OutlinedButton.icon(
                        onPressed: uploadManager.cancelAll,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                          side: BorderSide(
                            color: colorScheme.error.withValues(alpha: 0.6),
                          ),
                        ),
                        icon: const Icon(Icons.cancel_outlined, size: 17),
                        label: const Text('Cancel All'),
                      ),
                    if (uploadManager.hasFinishedItems)
                      TextButton.icon(
                        onPressed: uploadManager.clearFinished,
                        icon: const Icon(Icons.cleaning_services_outlined, size: 17),
                        label: const Text('Clear Finished'),
                      ),
                  ],
                ),
              ],
            ],
          ],
      ),
    );
  }

  Widget _summaryMetric(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 36,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No files selected',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "Select Files" above to choose single or multiple files at once.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
