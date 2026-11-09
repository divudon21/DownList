import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/task_model.dart';
import '../services/api_service.dart';

class HistoryCard extends StatelessWidget {
  const HistoryCard({
    super.key,
    required this.task,
    required this.api,
  });

  final TaskModel task;
  final ApiService api;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVideo = task.isVideo;
    final isImage = task.isImage;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showInfo(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: _iconBg(colorScheme),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam
                          : isImage
                              ? Icons.image
                              : task.isZip
                                  ? Icons.folder_zip
                                  : Icons.insert_drive_file,
                      color: _iconColor(colorScheme),
                      size: 28,
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
                            fontWeight: FontWeight.w700,
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
                            _chip(
                              context,
                              task.isCompleted ? 'Completed' : 'Failed',
                              task.isCompleted
                                  ? colorScheme.tertiaryContainer
                                  : colorScheme.errorContainer,
                              task.isCompleted
                                  ? colorScheme.onTertiaryContainer
                                  : colorScheme.onErrorContainer,
                              task.isCompleted
                                  ? Icons.done_all
                                  : Icons.error_outline,
                            ),
                            Text(
                              '${task.sizeFormatted}  ·  ${task.extension.isEmpty ? "FILE" : task.extension.toUpperCase()}',
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _timestampText(task.timestamp),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _ActionButtons(
                onInfo: () => _showInfo(context),
                onCopyLink: () => _copyLink(context),
                onStream: () => _stream(context),
                onDelete: () => _delete(context),
                onRename: () => _rename(context),
              ),
              if (task.totalSize > 0) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: task.progress,
                    minHeight: 7,
                    backgroundColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      task.isError ? colorScheme.error : colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${task.downloadedFormatted} / ${task.sizeFormatted}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (task.speed > 0)
                      Text(
                        task.speedFormatted,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                  ],
                ),
              ],
              if (task.isError && task.error != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Error: ${task.error}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1);
  }

  Color _iconBg(ColorScheme c) {
    if (task.isVideo) return c.tertiaryContainer;
    if (task.isImage) return c.secondaryContainer;
    return c.primaryContainer;
  }

  Color _iconColor(ColorScheme c) {
    if (task.isVideo) return c.onTertiaryContainer;
    if (task.isImage) return c.onSecondaryContainer;
    return c.onPrimaryContainer;
  }

  Widget _chip(
    BuildContext context,
    String label,
    Color bg,
    Color fg,
    IconData icon,
  ) {
    return Chip(
      avatar: Icon(icon, size: 14, color: fg),
      label: Text(
        label,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      backgroundColor: bg,
      side: BorderSide.none,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  String _timestampText(int? ts) {
    if (ts == null) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) {
      return 'Today ${_hm(date)}';
    }
    if (diff == 1) return 'Yesterday ${_hm(date)}';
    return '${date.day}/${date.month}/${date.year}';
  }

  String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  void _showInfo(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('File Info — ${task.fileName}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _infoRow(dialogContext, 'Status', task.statusLabel),
              _infoRow(
                dialogContext,
                'Type',
                task.isVideo
                    ? 'Video'
                    : task.isImage
                        ? 'Image'
                        : 'File',
              ),
              _infoRow(dialogContext, 'Size', task.sizeFormatted),
              _infoRow(dialogContext, 'Downloaded', task.downloadedFormatted),
              _infoRow(
                dialogContext,
                'Extension',
                task.extension.isEmpty ? 'N/A' : '.${task.extension}',
              ),
              if (task.resumable != null)
                _infoRow(
                  dialogContext,
                  'Resumable',
                  task.resumable! ? 'Yes' : 'No',
                ),
              if (task.verified != null)
                _infoRow(
                  dialogContext,
                  'Verified',
                  task.verified! ? 'Yes' : 'No',
                ),
              const Divider(height: 20),
              Text(
                'Video details',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              _infoRow(
                dialogContext,
                'Resolution',
                'Not available (server exposes no media-metadata endpoint)',
              ),
              _infoRow(
                dialogContext,
                'Bitrate',
                'Not available (server exposes no media-metadata endpoint)',
              ),
              if (task.isVideo)
                _infoRow(dialogContext, 'Streamable', 'Yes — open in player'),
              if (task.error != null) ...[
                const Divider(height: 20),
                _infoRow(dialogContext, 'Error', task.error!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final url = api.downloadUrl(task.taskId);
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Link copied: $url'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _stream(BuildContext context) async {
    final url = api.streamUrl(task.taskId);
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open stream URL')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stream error: $e')),
        );
      }
    }
  }

  Future<void> _delete(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete not supported'),
        content: const Text(
          'This server does not expose a single-file delete endpoint, so '
          'delete cannot be performed server-side.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _rename(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename not supported'),
        content: const Text(
          'This server does not expose a rename endpoint, so rename cannot be '
          'performed server-side.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.onInfo,
    required this.onCopyLink,
    required this.onStream,
    required this.onDelete,
    required this.onRename,
  });

  final VoidCallback onInfo;
  final VoidCallback onCopyLink;
  final VoidCallback onStream;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _iconBtn(Icons.info_outline, 'Info', onInfo),
        _iconBtn(Icons.link_outlined, 'Copy link', onCopyLink),
        _iconBtn(Icons.play_circle_outline, 'Stream', onStream),
        _iconBtn(Icons.delete_outline, 'Delete', onDelete),
        _iconBtn(Icons.edit_outlined, 'Rename', onRename),
      ],
    );
  }

  Widget _iconBtn(IconData icon, String label, VoidCallback onPressed) {
    return Tooltip(
      message: label,
      child: FilledButton.tonalIcon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 11)),
      ),
    );
  }
}
