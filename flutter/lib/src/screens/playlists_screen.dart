import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/playlist_detail_screen.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final playlists = model.playlists;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Playlists'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Nueva playlist',
            onPressed: () => _createPlaylist(context),
          ),
        ],
      ),
      body: playlists.isEmpty
          ? const Center(
              child: Text(
                'Aún no hay playlists\nCrea una para agrupar canciones.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: playlists.length,
              itemBuilder: (context, index) {
                final p = playlists[index];
                return ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(p.name),
                  subtitle: Text('${p.trackCount} canciones'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Renombrar',
                        onPressed: () => _renamePlaylist(context, p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Borrar',
                        onPressed: () => _confirmDelete(context, p),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  PlaylistDetailScreen(playlistId: p.id),
                            ),
                          );
                          if (context.mounted) {
                            await AppModelProvider.of(context)
                                .reloadPlaylists();
                          }
                        },
                      ),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlaylistDetailScreen(playlistId: p.id),
                      ),
                    );
                    if (context.mounted) {
                      await AppModelProvider.of(context).reloadPlaylists();
                    }
                  },
                );
              },
            ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nueva playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      try {
        await createPlaylist(name: name.trim());
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo crear: $e')),
          );
          return;
        }
      }
      if (context.mounted) {
        await AppModelProvider.of(context).reloadPlaylists();
      }
    }
  }

  Future<void> _renamePlaylist(BuildContext context, Playlist p) async {
    final controller = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Renombrar playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty && name.trim() != p.name) {
      try {
        await renamePlaylist(id: p.id, name: name.trim());
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo renombrar: $e')),
          );
          return;
        }
      }
      if (context.mounted) {
        await AppModelProvider.of(context).reloadPlaylists();
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Playlist p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Borrar playlist'),
        content: Text(
            '¿Borrar «${p.name}»?\nLas canciones se conservan en la biblioteca.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    try {
      await deletePlaylist(id: p.id);
      if (!context.mounted) return;
      await AppModelProvider.of(context).reloadPlaylists();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: $e')),
        );
      }
    }
  }
}
