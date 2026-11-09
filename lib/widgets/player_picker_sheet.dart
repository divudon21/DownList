import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/platform_service.dart';

Future<void> openStreamWithPlayerPicker(
  BuildContext context, {
  required String url,
  required String fileName,
  required String mimeType,
}) async {
  try {
    final players = await PlatformService.instance.getMediaPlayers(
      url: url,
      fileName: fileName,
      mimeType: mimeType,
    );

    if (players.isEmpty) {
      await PlatformService.instance.openExternalPlayer(
        url: url,
        fileName: fileName,
        mimeType: mimeType,
      );
      return;
    }

    if (players.length == 1) {
      final only = players.first;
      await PlatformService.instance.launchMediaPlayer(
        url: url,
        fileName: fileName,
        mimeType: mimeType,
        packageName: only.packageName,
        activityName: only.activityName,
      );
      return;
    }

    if (!context.mounted) return;
    final selected = await showModalBottomSheet<MediaPlayerApp>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _PlayerPickerSheet(
        fileName: fileName,
        players: players,
      ),
    );

    if (selected == null) return;
    await PlatformService.instance.launchMediaPlayer(
      url: url,
      fileName: fileName,
      mimeType: mimeType,
      packageName: selected.packageName,
      activityName: selected.activityName,
    );
  } on PlatformException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'No video player found on this device.',
          ),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open video player: $e')),
      );
    }
  }
}

class _PlayerPickerSheet extends StatelessWidget {
  const _PlayerPickerSheet({
    required this.fileName,
    required this.players,
  });

  final String fileName;
  final List<MediaPlayerApp> players;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Open Stream With',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${players.length} players',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 6),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: players.length,
                itemBuilder: (context, index) {
                  final player = players[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: player.iconBytes.isNotEmpty
                            ? Image.memory(
                                player.iconBytes,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              )
                            : ColoredBox(
                                color: colorScheme.primaryContainer,
                                child: Icon(
                                  Icons.play_circle_fill_rounded,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              ),
                      ),
                    ),
                    title: Text(
                      player.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => Navigator.of(context).pop(player),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
