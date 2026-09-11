import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/utils/format.dart';
import 'package:offline_audio_app/src/widgets/thumb_placeholder.dart';

/// A single library track row: artwork, title, metadata, and actions
/// (play, add to playlist, delete). When [selected], it shows the selector
/// highlight (amber left border + tinted background) and an "Escuchar"
/// button as the trailing action.
class TrackTile extends StatelessWidget {
  const TrackTile({
    super.key,
    required this.track,
    required this.onPlay,
    this.selected = false,
    this.onSelect,
  });

  final Track track;
  final VoidCallback onPlay;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    final isVideo = track.contentKind == 'video';
    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onPlay,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.horizontal(left: Radius.circular(12)),
          border: selected
              ? const Border(left: BorderSide(color: Colors.amber, width: 0.7))
              : null,
          color: selected
              ? Theme.of(context).colorScheme.secondaryContainer
                    .withValues(alpha: 0.2)
              : null,
        ),
        child: ListTile(
          leading: thumb != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(thumb),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const ThumbPlaceholder(),
                  ),
                )
              : const ThumbPlaceholder(),
          title: Text(
            track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (track.artist != null && track.artist!.isNotEmpty)
                track.artist!,
              if (track.album != null && track.album!.isNotEmpty) track.album!,
              _fmtDuration(track.durationSeconds),
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected
              ? FilledButton.icon(
                  onPressed: onPlay,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlay),
                  label: const Text('Escuchar'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF14432E),
                    foregroundColor: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isVideo)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: HugeIcon(
                          icon: HugeIcons.strokeRoundedCameraVideo,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    IconButton(
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedMoreVertical,
                      ),
                      tooltip: 'Más opciones',
                      onPressed: () => _openActions(context),
                    ),
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlay),
                      onPressed: onPlay,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openActions(BuildContext context) async {
    final action = await showAppBottomSheet<String>(
      context,
      items: const [
        AppSheetItem(
          value: 'add_playlist',
          icon: HugeIcons.strokeRoundedQueue01,
          label: 'Añadir a playlist',
        ),
        AppSheetItem(
          value: 'delete',
          icon: HugeIcons.strokeRoundedDelete01,
          label: 'Eliminar',
          destructive: true,
        ),
      ],
    );
    if (!context.mounted) return;
    if (action == 'add_playlist') {
      await _openAddToPlaylist(context);
    } else if (action == 'delete') {
      await _deleteTrack(context);
    }
  }

  Future<void> _openAddToPlaylist(BuildContext context) async {
    final model = AppModelProvider.of(context);
    if (model.playlists.isEmpty) {
      showAppSnackBar(context, message: 'Primero crea una playlist');
      return;
    }
    final chosen = await showAppBottomSheet<Playlist>(
      context,
      title: const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Añadir a playlist',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      items: [
        for (final p in model.playlists)
          AppSheetItem(
            value: p,
            icon: HugeIcons.strokeRoundedQueue01,
            label: p.name,
          ),
      ],
    );
    if (chosen != null) {
      try {
        await addToPlaylist(playlistId: chosen.id, trackId: track.id);
        if (context.mounted) {
          showAppSnackBar(context, message: 'Añadido a «${chosen.name}»');
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, message: 'No se pudo añadir: $e');
        }
      }
    }
  }

  Future<void> _deleteTrack(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context,
      title: const Text('Eliminar'),
      content: Text('¿Eliminar «${track.title}»?\nSe borrarán sus archivos.'),
      actions: [
        AppDialogAction<bool>(label: 'Cancelar', getValue: () => false),
        AppDialogAction<bool>(
          label: 'Eliminar',
          getValue: () => true,
          isDefault: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed == true) {
      await deleteTrack(id: track.id);
      if (context.mounted) {
        await AppModelProvider.of(context).reloadLibrary();
      }
    }
  }

  String _fmtDuration(int? secs) {
    if (secs == null) return '';
    return fmtLength(Duration(seconds: secs));
  }
}
