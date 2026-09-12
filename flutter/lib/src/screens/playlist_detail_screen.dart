import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Track>? _tracks;
  String _name = 'Lista de reproducción';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tracks = await playlistTracks(playlistId: widget.playlistId);
      // Título con el nombre real de la playlist.
      try {
        final lists = await listPlaylists();
        for (final p in lists) {
          if (p.id == widget.playlistId) {
            _name = p.name;
            break;
          }
        }
      } catch (_) {}
      if (mounted) setState(() => _tracks = tracks);
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: 'No se pudo cargar: $e');
      }
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final tracks = _tracks;
    if (tracks == null) return;
    final previous = List<Track>.from(tracks);
    setState(() {
      final item = tracks.removeAt(oldIndex);
      tracks.insert(newIndex, item);
    });
    try {
      await reorderPlaylist(
        playlistId: widget.playlistId,
        orderedTrackIds: tracks.map((t) => t.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _tracks = previous);
        showAppSnackBar(context, message: 'No se pudo reordenar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final tracks = _tracks;

    return AppPage(
      title: _name,
      actions: [
        IconButton(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
          tooltip: 'Añadir de la biblioteca',
          onPressed: () => _addFromLibrary(context, model),
        ),
      ],
      body: Column(
        children: [
          Expanded(
            child: tracks == null
                ? Center(
                    child: isApplePlatform
                        ? const CupertinoActivityIndicator()
                        : const CircularProgressIndicator(),
                  )
                : tracks.isEmpty
                ? const Center(
                    child: Text(
                      'Lista vacía.\nAñade canciones desde la biblioteca.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedPlay,
                            ),
                            label: Text('Reproducir (${tracks.length})'),
                            onPressed: () =>
                                model.playPlaylist(widget.playlistId),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(alpha: 0.5),
                                width: 1,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        child: Center(
                          child: Text(
                            '${tracks.length} '
                            '${tracks.length == 1 ? 'Track' : 'Tracks'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: tracks.length,
                          onReorderItem: _onReorder,
                          itemBuilder: (context, index) => _buildTrackRow(
                            context,
                            model,
                            index,
                            tracks[index],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          const PlayerBar(),
        ],
      ),
    );
  }

  /// Fila de track: número, título y artista centrados verticalmente, sin
  /// iconos al final. El arrastre ocupa toda la fila (long-press en táctil,
  /// clic y arrastre en escritorio) sin mostrar icono visible.
  Widget _buildTrackRow(
    BuildContext context,
    AppModel model,
    int index,
    Track t,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.5);
    final row = InkWell(
      onTap: () => model.playTrack(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white10,
              child: Text('${index + 1}'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  if ((t.artist ?? '').isNotEmpty)
                    Text(
                      t.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: subtle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return switch (Theme.of(context).platform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.fuchsia => ReorderableDelayedDragStartListener(
        key: ValueKey(t.id),
        index: index,
        child: row,
      ),
      _ => ReorderableDragStartListener(
        key: ValueKey(t.id),
        index: index,
        child: row,
      ),
    };
  }

  Future<void> _addFromLibrary(BuildContext context, AppModel model) async {
    final candidates = model.library;
    if (candidates.isEmpty) {
      showAppSnackBar(context, message: 'La biblioteca está vacía');
      return;
    }
    final chosen = await showAppBottomSheetWithSearch<Track>(
      context,
      title: const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          'Añadir de la biblioteca',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      searchHint: 'Filtrar biblioteca',
      items: [
        for (final t in candidates)
          AppSheetItem(
            value: t,
            icon: HugeIcons.strokeRoundedMusicNote01,
            label: t.title,
            subtitle: t.artist,
          ),
      ],
      filter: (item, query) =>
          item.label.toLowerCase().contains(query) ||
          (item.subtitle?.toLowerCase().contains(query) ?? false),
    );
    if (chosen != null) {
      try {
        await addToPlaylist(playlistId: widget.playlistId, trackId: chosen.id);
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, message: 'No se pudo añadir: $e');
        }
      }
      await _load();
    }
  }
}
