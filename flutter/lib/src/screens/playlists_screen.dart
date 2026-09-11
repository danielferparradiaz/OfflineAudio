import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';

class PlaylistsScreen extends StatelessWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final playlists = model.playlists;

    return AppPage(
      title: 'Playlists',
      actions: [
        IconButton(
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
          tooltip: 'Nueva playlist',
          onPressed: () => _createPlaylist(context),
        ),
      ],
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
                  leading: const HugeIcon(icon: HugeIcons.strokeRoundedQueue01),
                  title: Text(p.name),
                  subtitle: Text('${p.trackCount} canciones'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedEdit01,
                        ),
                        tooltip: 'Renombrar',
                        onPressed: () => _renamePlaylist(context, p),
                      ),
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete01,
                        ),
                        tooltip: 'Borrar',
                        onPressed: () => _confirmDelete(context, p),
                      ),
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedArrowRight01,
                        ),
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
                        builder: (_) => PlaylistDetailScreen(playlistId: p.id),
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
          label: 'Crear',
          getValue: () => controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    if (name != null && name.trim().isNotEmpty) {
      try {
        await createPlaylist(name: name.trim());
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, message: 'No se pudo crear: $e');
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
    final name = await showAppDialog<String>(
      context,
      title: const Text('Renombrar playlist'),
      content: AppTextField(
        controller: controller,
        autofocus: true,
        label: 'Nombre',
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        AppDialogAction(label: 'Cancelar'),
        AppDialogAction(
          label: 'Guardar',
          getValue: () => controller.text.trim(),
          isDefault: true,
        ),
      ],
    );
    if (name != null && name.trim().isNotEmpty && name.trim() != p.name) {
      try {
        await renamePlaylist(id: p.id, name: name.trim());
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, message: 'No se pudo renombrar: $e');
          return;
        }
      }
      if (context.mounted) {
        await AppModelProvider.of(context).reloadPlaylists();
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Playlist p) async {
    final confirmed = await showAppDialog<bool>(
      context,
      title: const Text('Borrar playlist'),
      content: Text(
        '¿Borrar «${p.name}»?\nLas canciones se conservan en la biblioteca.',
      ),
      actions: [
        AppDialogAction<bool>(label: 'Cancelar', getValue: () => false),
        AppDialogAction<bool>(
          label: 'Borrar',
          getValue: () => true,
          isDefault: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    try {
      await deletePlaylist(id: p.id);
      if (!context.mounted) return;
      await AppModelProvider.of(context).reloadPlaylists();
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, message: 'No se pudo borrar: $e');
      }
    }
  }
}
