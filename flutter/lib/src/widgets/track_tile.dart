import 'dart:io';

import 'package:flutter/material.dart';
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
          border: selected
              ? const Border(left: BorderSide(color: Colors.amber, width: 3))
              : null,
          color: selected
              ? Theme.of(context)
                  .colorScheme
                  .secondaryContainer
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
                    errorBuilder: (_, error, stack) =>
                        const ThumbPlaceholder(),
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
              if (track.album != null && track.album!.isNotEmpty)
                track.album!,
              _fmtDuration(track.durationSeconds),
            ].where((s) => s.isNotEmpty).join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: selected
              ? FilledButton.icon(
                  onPressed: onPlay,
                  icon: const Icon(Icons.play_arrow_rounded),
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
                        child: Icon(Icons.videocam,
                            size: 16,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.5)),
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'add_playlist') {
                          _openAddToPlaylist(context);
                        } else if (value == 'delete') {
                          _deleteTrack(context);
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'add_playlist',
                          child: Text('Añadir a playlist'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Eliminar'),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow),
                      onPressed: onPlay,
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Future<void> _openAddToPlaylist(BuildContext context) async {
    final model = AppModelProvider.of(context);
    if (model.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea una playlist')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<Playlist>(
      context: context,
      builder: (context) => ListView(
        children: model.playlists
            .map(
              (p) => ListTile(
                leading: const Icon(Icons.queue_music),
                title: Text(p.name),
                onTap: () => Navigator.of(context).pop(p),
              ),
            )
            .toList(),
      ),
    );
    if (chosen != null) {
      try {
        await addToPlaylist(playlistId: chosen.id, trackId: track.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Añadido a «${chosen.name}»')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo añadir: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteTrack(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar'),
        content:
            Text('¿Eliminar «${track.title}»?\nSe borrarán sus archivos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
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
