import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_service.dart';
import '../services/platform_service.dart';
import '../services/upload_manager.dart';

class UploadItemCard extends StatelessWidget {
  const UploadItemCard({
    super.key,
    required this.item,
    required this.api,
    required this.onStart,
    required this.onCancel,
    required this.onRemove,
    this.compactForTaskTab = false,
  });

  final UploadItem item;
  final ApiService api;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final bool compactForTaskTab;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUploading = item.status == UploadStatus.uploading;
    final isQueued = item.status == UploadStatus.queued;
    final isCompleted = item.status == UploadStatus.completed;
    final isError = item.status == UploadStatus.error;
    final isCancelled = item.status == UploadStatus.cancelled;
    final isReady = item.status == UploadStatus.ready;

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
                    color: _iconBg(colorScheme),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _fileIcon(),
                    color: _iconFg(colorScheme),
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fileName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _statusBadge(context),
                          Text(
                            '${item.sizeFormatted}${item.extension.isNotEmpty ? '  ·  ${item.extension.toUpperCase()}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isUploading || isCompleted) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(item.progress * 100).toInt()}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isCompleted
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ] else if (!compactForTaskTab &&
                    (isReady || isCancelled || isError)) ...[
                  IconButton(
                    tooltip: 'Remove',
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
            if (isUploading || isQueued || isCompleted) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: isQueued && item.uploadedBytes == 0
                      ? null
                      : item.progress,
                  minHeight: 8,
                  backgroundColor:
                      colorScheme.surfaceContainerLow.withValues(alpha: 0.8),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCompleted ? colorScheme.tertiary : colorScheme.primary,
                  ),
                ),
              ),
            ],
            if (isUploading || isQueued) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      context,
                      'Uploaded',
                      '${item.uploadedFormatted} / ${item.sizeFormatted}',
                      Icons.cloud_upload_outlined,
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      context,
                      'Speed',
                      item.speedFormatted,
                      Icons.speed_rounded,
                    ),
                  ),
                  Expanded(
                    child: _stat(
                      context,
                      'ETA',
                      item.etaFormatted,
                      Icons.schedule_rounded,
                    ),
                  ),
                ],
              ),
            ],
            if (isError && item.errorMessage != null) ...[
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
                        item.errorMessage!,
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
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                if (isReady)
                  FilledButton.tonalIcon(
                    onPressed: api.isConfigured ? onStart : null,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('Upload'),
                  ),
                if (isUploading || isQueued)
                  OutlinedButton.icon(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colorScheme.error,
                      side: BorderSide(
                        color: colorScheme.error.withValues(alpha: 0.6),
                      ),
                    ),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Cancel'),
                  ),
                if (isCancelled || isError)
                  FilledButton.tonalIcon(
                    onPressed: api.isConfigured ? onStart : null,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retry'),
                  ),
                if (isCompleted &&
                    item.serverTaskId != null &&
                    item.serverTaskId!.isNotEmpty) ...[
                  FilledButton.tonalIcon(
                    onPressed: () => _copyLink(context, item.serverTaskId!),
                    icon: const Icon(Icons.link_rounded, size: 17),
                    label: const Text('Copy Link'),
                  ),
                  if (item.isVideo || item.isAudio)
                    FilledButton.tonalIcon(
                      onPressed: () => _openPlayer(context, item.serverTaskId!),
                      icon: const Icon(Icons.play_circle_outline, size: 17),
                      label: const Text('Play'),
                    ),
                ],
                if (isCompleted && !compactForTaskTab)
                  TextButton.icon(
                    onPressed: onRemove,
                    icon: const Icon(Icons.check_rounded, size: 17),
                    label: const Text('Dismiss'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon() {
    if (item.isVideo) return Icons.videocam_rounded;
    if (item.isAudio) return Icons.audiotrack_rounded;
    if (item.isImage) return Icons.image_rounded;
    if (item.isZip) return Icons.folder_zip_rounded;
    if (item.isApk) return Icons.android_rounded;
    if (item.extension == 'pdf') return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _iconBg(ColorScheme c) {
    if (item.status == UploadStatus.error) return c.errorContainer;
    if (item.status == UploadStatus.completed) return c.tertiaryContainer;
    if (item.isVideo) return c.secondaryContainer;
    return c.primaryContainer;
  }

  Color _iconFg(ColorScheme c) {
    if (item.status == UploadStatus.error) return c.onErrorContainer;
    if (item.status == UploadStatus.completed) return c.onTertiaryContainer;
    if (item.isVideo) return c.onSecondaryContainer;
    return c.onPrimaryContainer;
  }

  Widget _statusBadge(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    switch (item.status) {
      case UploadStatus.uploading:
        bg = c.primaryContainer;
        fg = c.onPrimaryContainer;
        break;
      case UploadStatus.queued:
        bg = c.secondaryContainer;
        fg = c.onSecondaryContainer;
        break;
      case UploadStatus.completed:
        bg = c.tertiaryContainer;
        fg = c.onTertiaryContainer;
        break;
      case UploadStatus.error:
        bg = c.errorContainer;
        fg = c.onErrorContainer;
        break;
      case UploadStatus.cancelled:
      case UploadStatus.ready:
        bg = c.surfaceContainerLow;
        fg = c.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        item.statusLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
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
        Icon(icon, size: 17, color: colorScheme.onSurfaceVariant),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
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

  Future<void> _copyLink(BuildContext context, String taskId) async {
    final url = api.downloadUrl(taskId);
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download link copied: $url'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openPlayer(BuildContext context, String taskId) async {
    final url = api.streamUrl(taskId);
    final mime = PlatformService.guessMediaMimeType(
      item.extension,
      isAudio: item.isAudio,
    );
    try {
      await PlatformService.instance.openExternalPlayer(
        url: url,
        fileName: item.fileName,
        mimeType: mime,
      );
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Could not open video player')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Player error: $e')),
        );
      }
    }
  }
}
