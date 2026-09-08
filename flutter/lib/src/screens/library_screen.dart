import 'dart:async';
import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/add_screen.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _query = '';
  SortOrder _order = SortOrder.dateDesc;
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      AppModelProvider.of(context).reloadLibrary(
        search: _query.isEmpty ? null : _query,
        order: _order,
      );
    });
  }

  void _onOrderSelected(SortOrder value) {
    setState(() => _order = value);
    AppModelProvider.of(context).reloadLibrary(
      search: _query.isEmpty ? null : _query,
      order: _order,
    );
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final tracks = model.library;

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _buildList(context, model, tracks)),
          _buildFrostedTop(context),
        ],
      ),
    );
  }

  /// Frosted header + search that float above the scrolling list. Music flows
  /// underneath and the translucent surface lets the movement show through.
  Widget _buildFrostedTop(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.72),
            border: Border(
              bottom: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(context),
              _buildSearchField(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Mi biblioteca',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
          ),
          PopupMenuButton<SortOrder>(
            initialValue: _order,
            onSelected: _onOrderSelected,
            icon: const Icon(Icons.sort),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SortOrder.dateDesc,
                child: Text('Más recientes primero'),
              ),
              PopupMenuItem(
                value: SortOrder.dateAsc,
                child: Text('Más antiguos primero'),
              ),
              PopupMenuItem(
                value: SortOrder.titleAsc,
                child: Text('Título A-Z'),
              ),
              PopupMenuItem(
                value: SortOrder.titleDesc,
                child: Text('Título Z-A'),
              ),
            ],
          ),
          IconButton.filled(
            icon: const Icon(Icons.add),
            tooltip: 'Añadir URL',
            onPressed: () async {
              final taskId = await Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const AddScreen()),
              );
              if (context.mounted && taskId != null) {
                final short =
                    taskId.length <= 8 ? taskId : taskId.substring(0, 8);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Descarga iniciada ($short). Ver pestaña Descargas.')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search),
          hintText: 'Buscar en la biblioteca',
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
        ),
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildList(BuildContext context, AppModel model, List<Track> tracks) {
    // "Reciente": songs just downloaded this session (kept in
    // `model.completed` until the library reload lands) plus anything the
    // library reports as downloaded in the last 24 hours.
    final seen = <String>{};
    final recent = <Track>[];
    for (final t in model.completed.values) {
      if (seen.add(t.id)) recent.add(t);
    }
    final now = DateTime.now().toUtc();
    for (final t in tracks) {
      final downloaded = DateTime.tryParse(t.downloadDate)?.toUtc();
      if (downloaded != null &&
          now.difference(downloaded) < const Duration(hours: 24) &&
          seen.add(t.id)) {
        recent.add(t);
      }
    }

    if (tracks.isEmpty && recent.isEmpty) {
      return const _EmptyLibrary();
    }
    return ListView(
      // Start below the floating frosted header + search.
      padding: const EdgeInsets.only(top: 130, bottom: 8),
      children: [
        if (recent.isNotEmpty) ...[
          const _SectionHeader('Reciente'),
          _RecentBanner(
            track: recent.first,
            onPlay: () => model.playTrack(recent.first),
          ),
          ...recent
              .skip(1)
              .map(
                (t) => _TrackTile(props: t, onPlay: () => model.playTrack(t)),
              ),
          if (tracks.isNotEmpty) const _SectionHeader('Biblioteca'),
        ],
        ...tracks.map(
          (t) => _TrackTile(props: t, onPlay: () => model.playTrack(t)),
        ),
      ],
    );
  }
}

/// Calling card for the most recently downloaded item: artwork, metadata and
/// a direct "Escuchar" action.
class _RecentBanner extends StatelessWidget {
  const _RecentBanner({required this.track, required this.onPlay});

  final Track track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    final subtitle = [
      if (track.artist != null && track.artist!.isNotEmpty) track.artist!,
      if (track.album != null && track.album!.isNotEmpty) track.album!,
    ].join(' · ');
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Container(
          height: 96,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF14432E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              thumb != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(thumb),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const _ThumbPlaceholder(),
                      ),
                    )
                  : const _ThumbPlaceholder(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    const Text(
                      'Descarga reciente',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Escuchar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white70,
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.props, required this.onPlay});

  final Track props;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final thumb = props.thumbnailPath;
    return ListTile(
      leading: thumb != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(thumb),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => const _ThumbPlaceholder(),
              ),
            )
          : const _ThumbPlaceholder(),
      title: Text(
        props.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          if (props.artist != null && props.artist!.isNotEmpty) props.artist!,
          if (props.album != null && props.album!.isNotEmpty) props.album!,
          _fmtDuration(props.durationSeconds),
        ]
            .where((s) => s.isNotEmpty)
            .join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        await addToPlaylist(playlistId: chosen.id, trackId: props.id);
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
        content: Text('¿Eliminar «${props.title}»?\nSe borrarán sus archivos.'),
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
      await deleteTrack(id: props.id);
      if (context.mounted) {
        await AppModelProvider.of(context).reloadLibrary();
      }
    }
  }

  String _fmtDuration(int? secs) {
    if (secs == null) return '';
    final d = Duration(seconds: secs);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    return '${m}m ${s.toString().padLeft(2, '0')}s';
  }
}

class _ThumbPlaceholder extends StatelessWidget {
  const _ThumbPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 48,
      height: 48,
      child: ColoredBox(
        color: Color(0xFF2A2A2A),
        child: Icon(Icons.music_note, color: Colors.white54),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined, size: 64, color: Colors.white24),
            SizedBox(height: 16),
            Text(
              'Tu biblioteca está vacía.\nAñade una URL para empezar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}