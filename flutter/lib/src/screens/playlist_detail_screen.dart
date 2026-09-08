import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({required this.playlistId, super.key});

  final String playlistId;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  List<Track>? _tracks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tracks = await playlistTracks(playlistId: widget.playlistId);
      if (mounted) setState(() => _tracks = tracks);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar: $e')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo reordenar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final tracks = _tracks;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlist'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Añadir de la biblioteca',
            onPressed: () => _addFromLibrary(context, model),
          ),
        ],
      ),
      body: tracks == null
          ? const Center(child: CircularProgressIndicator())
          : tracks.isEmpty
              ? const Center(
                  child: Text(
                    'Playlist vacía.\nAñade canciones desde la biblioteca.',
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
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Reproducir (${tracks.length})'),
                          onPressed: () => model.playPlaylist(widget.playlistId),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.drag_handle,
                              size: 16, color: Colors.white38),
                          SizedBox(width: 6),
                          Text(
                            'Mantén y arrastra para reordenar',
                            style: TextStyle(
                                color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ReorderableListView.builder(
                        itemCount: tracks.length,
                        onReorderItem: _onReorder,
                        itemBuilder: (context, index) {
                          final t = tracks[index];
                          return ListTile(
                            key: ValueKey(t.id),
                            leading: indexDisplay(index),
                            title: Text(t.title),
                            subtitle: Text(t.artist ?? ''),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.remove_circle_outline),
                                  tooltip: 'Quitar',
                                  onPressed: () async {
                                    try {
                                      await removeFromPlaylist(
                                        playlistId: widget.playlistId,
                                        trackId: t.id,
                                      );
                                      await _load();
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  'No se pudo quitar: $e')),
                                        );
                                      }
                                    }
                                  },
                                ),
                                const Icon(Icons.drag_handle,
                                    color: Colors.white38),
                              ],
                            ),
                            onTap: () => model.playTrack(t),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget indexDisplay(int index) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Colors.white10,
      child: Text('${index + 1}'),
    );
  }

  Future<void> _addFromLibrary(BuildContext context, AppModel model) async {
    final messenger = ScaffoldMessenger.of(context);
    final candidates = model.library;
    if (candidates.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('La biblioteca está vacía')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<Track>(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: candidates.length,
        itemBuilder: (context, index) {
          final t = candidates[index];
          return ListTile(
            title: Text(t.title),
            subtitle: Text(t.artist ?? ''),
            onTap: () => Navigator.of(context).pop(t),
          );
        },
      ),
    );
    if (chosen != null) {
      try {
        await addToPlaylist(playlistId: widget.playlistId, trackId: chosen.id);
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo añadir: $e')),
        );
      }
      await _load();
    }
  }
}
