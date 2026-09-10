import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';

String _shortId(String taskId) =>
    taskId.length <= 8 ? taskId : taskId.substring(0, 8);

String _fmtBytes(BigInt bytes) {
  final mb = bytes.toDouble() / 1024.0 / 1024.0;
  if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(2)} GB';
  if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
  final kb = bytes.toDouble() / 1024.0;
  return '${kb.toStringAsFixed(0)} KB';
}

String _fmtSpeed(BigInt? speed) {
  if (speed == null) return '';
  final mb = speed.toDouble() / 1024.0 / 1024.0;
  if (mb >= 1) return '${mb.toStringAsFixed(2)} MB/s';
  final kb = speed.toDouble() / 1024.0;
  return '${kb.toStringAsFixed(0)} KB/s';
}

String _fmtEta(BigInt? eta) {
  if (eta == null) return '';
  final s = eta.toInt();
  if (s >= 3600) return 'ETA ${s ~/ 3600}h ${(s % 3600) ~/ 60}m';
  if (s >= 60) return 'ETA ${s ~/ 60}m ${s % 60}s';
  return 'ETA ${s}s';
}

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);
    final progress = model.downloads;
    final errors = model.downloadErrors;
    final completed = model.completed;
    final info = model.lastInfo;
    final hasAny =
        progress.isNotEmpty || errors.isNotEmpty || completed.isNotEmpty;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              'Descargas',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          if (info != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      info,
                      style: TextStyle(color: subtle),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Descartar',
                    onPressed: () => model.consumeInfo(),
                  ),
                ],
              ),
            ),
          if (!hasAny)
            Expanded(
              child: Center(
                child: Text(
                  'No hay descargas activas',
                  style: TextStyle(color: subtle),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
                children: [
                  ...progress.entries.map((e) {
                    final taskId = e.key;
                    final st = e.value;
                    final detail = [
                      '${st.percent.toStringAsFixed(1)}%',
                      '${_fmtBytes(st.downloadedBytes)}'
                          '${st.totalBytes != null ? ' / ${_fmtBytes(st.totalBytes!)}' : ''}',
                      if (st.speedBytesSec != null) _fmtSpeed(st.speedBytesSec),
                      if (st.etaSecs != null) _fmtEta(st.etaSecs),
                    ].join(' · ');
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.download),
                        title: Text('Descarga ${_shortId(taskId)}'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            LinearProgressIndicator(value: st.fraction),
                            const SizedBox(height: 6),
                            Text(detail, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancelar',
                          onPressed: () async {
                            try {
                              await cancelDownload(taskId: taskId);
                            } catch (e) {
                              if (context.mounted) {
                                showAppSnackBar(
                                  context,
                                  message: 'No se pudo cancelar: $e',
                                );
                              }
                            }
                          },
                        ),
                      ),
                    );
                  }),
                  ...errors.entries.map((e) {
                    final taskId = e.key;
                    final reason = e.value;
                    return Card(
                      color: const Color(0xFF3A1F1F),
                      child: ListTile(
                        leading: const Icon(
                          Icons.error_outline,
                          color: Colors.redAccent,
                        ),
                        title: Text('Falló ${_shortId(taskId)}'),
                        subtitle: Text(
                          reason,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Descartar',
                          onPressed: () => model.clearDownloadError(taskId),
                        ),
                      ),
                    );
                  }),
                  if (completed.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                      child: Text(
                        'Completadas',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: subtle,
                        ),
                      ),
                    ),
                    ...completed.entries.map(
                      (e) => _CompletedCard(taskId: e.key, track: e.value),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Card for a finished download: play it, add it to a playlist, or dismiss it.
class _CompletedCard extends StatelessWidget {
  const _CompletedCard({required this.taskId, required this.track});

  final String taskId;
  final Track track;

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    return Card(
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: Colors.greenAccent),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Completada'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.contentKind == 'video')
              IconButton(
                icon: const Icon(Icons.videocam),
                tooltip: 'Ver vídeo',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(track: track),
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Escuchar',
              onPressed: () => model.playTrack(track),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Añadir a playlist',
              onPressed: () => _addToPlaylist(context, model),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addToPlaylist(BuildContext context, AppModel model) async {
    if (model.playlists.isEmpty) {
      await _createPlaylistAndAdd(context, model);
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
            icon: Icons.queue_music,
            label: p.name,
            subtitle: '${p.trackCount} canciones',
          ),
      ],
    );
    if (chosen == null || !context.mounted) return;
    await _addToChosen(context, chosen);
    if (context.mounted) model.clearCompleted(taskId);
  }

  Future<void> _addToChosen(BuildContext context, Playlist chosen) async {
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

  /// No playlists exist yet: ask for a name, create it and add the track in a
  /// single step.
  Future<void> _createPlaylistAndAdd(
    BuildContext context,
    AppModel model,
  ) async {
    final controller = TextEditingController();
    final name = await showAppDialog<String>(
      context,
      title: const Text('Nueva playlist'),
      content: AppTextField(
        controller: controller,
        autofocus: true,
        label: 'Nombre',
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        AppDialogAction(label: 'Cancelar'),
        AppDialogAction(
          label: 'Crear y añadir',
          getValue: () => controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !context.mounted) return;
    try {
      final pl = await createPlaylist(name: trimmed);
      await addToPlaylist(playlistId: pl.id, trackId: track.id);
      await model.reloadPlaylists();
      model.clearCompleted(taskId);
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: 'Creada «${pl.name}» y añadida la canción',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, message: 'No se pudo crear la playlist: $e');
      }
    }
  }
}
