import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/search/youtube_search.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  SortOrder _order = SortOrder.dateDesc;
  final _searchController = TextEditingController();

  /// Search state. While `null`, the library list is shown; otherwise we show
  /// either results, the spinner, or an error banner.
  List<SearchResult>? _results;
  bool _searching = false;
  String? _searchError;
  String? _activeQuery;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _serveLibrary() async {
    setState(() {
      _results = null;
      _searchError = null;
      _searching = false;
      _activeQuery = null;
    });
    await AppModelProvider.of(context)
        .reloadLibrary(search: null, order: _order);
  }

  Future<void> _searchNow() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _activeQuery = q;
    });
    try {
      final results = await YoutubeSearch.search(q);
      if (!mounted) return;
      setState(() {
        _searching = false;
        _results = results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'No se pudo buscar en YouTube. Revisa tu conexión e '
            'inténtalo de nuevo.\n($e)';
      });
    }
  }

  Future<void> _startDownload(SearchResult result, ContentKind kind) async {
    try {
      final model = AppModelProvider.of(context);
      final taskId = await model.downloadFromUrl(result.url, kind: kind);
      if (!mounted) return;
      final short = taskId.length <= 8 ? taskId : taskId.substring(0, 8);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Descarga iniciada ($short). Ver pestaña Descargas.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo iniciar la descarga: $e')),
      );
    }
  }

  void _onOrderSelected(SortOrder value) {
    setState(() => _order = value);
    _serveLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);

    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _buildContent(context, model)),
          _buildFrostedTop(context),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppModel model) {
    if (_searching) {
      return const _SearchFeedback(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_searchError != null) {
      return _SearchFeedback(
        child: _SearchError(
          message: _searchError!,
          onRetry: _searchNow,
          onClose: _serveLibrary,
        ),
      );
    }
    final results = _results;
    if (results != null) {
      return _buildResults(context, model, results);
    }
    return _buildList(context, model, model.library);
  }

  Widget _buildResults(
      BuildContext context, AppModel model, List<SearchResult> results) {
    return ListView(
      padding: const EdgeInsets.only(top: 150, bottom: 8),
      children: [
        _SearchHeader(query: _activeQuery ?? '', onClose: _serveLibrary),
        const SizedBox(height: 4),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Sin resultados para «${_activeQuery ?? ''}»\n'
              'Prueba con el nombre del artista, canción o una palabra clave.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          )
        else
          ...results.map(
            (r) => _SearchResultTile(
              result: r,
              onDownloadAudio: () =>
                  _startDownload(r, ContentKind.music),
              onDownloadVideo: () =>
                  _startDownload(r, ContentKind.video),
            ),
          ),
      ],
    );
  }

  /// Frosted header + search that float above the scrolling content. Music
  /// flows underneath and the translucent surface lets the movement show
  /// through. `mainAxisSize.min` keeps this panel to its own contents so the
  /// blurred surface never swallows the whole screen.
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
            mainAxisSize: MainAxisSize.min,
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
          prefixIcon: IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Buscar en YouTube',
            onPressed: _searchNow,
          ),
          hintText: 'Buscar',
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.08),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(26),
            borderSide: BorderSide.none,
          ),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _serveLibrary,
                ),
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchNow(),
        onChanged: (_) => setState(() {}),
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
      padding: const EdgeInsets.only(top: 150, bottom: 8),
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

/// Shared area shown between the frosted header and the list bottom while the
/// search is busy / failed.
class _SearchFeedback extends StatelessWidget {
  const _SearchFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 150, bottom: 32),
      child: child,
    );
  }
}

class _SearchError extends StatelessWidget {
  const _SearchError({
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.white38),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onClose,
                child: const Text('Volver a la biblioteca'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({required this.query, required this.onClose});

  final String query;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Resultados para «$query»',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar búsqueda',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onDownloadAudio,
    required this.onDownloadVideo,
  });

  final SearchResult result;
  final VoidCallback onDownloadAudio;
  final VoidCallback onDownloadVideo;

  @override
  Widget build(BuildContext context) {
    final duration = result.duration;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          result.thumbnailUrl,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, error, stack) =>
              const SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(
                  color: Color(0xFF2A2A2A),
                  child: Icon(Icons.movie, color: Colors.white54),
                ),
              ),
        ),
      ),
      title: Text(
        result.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          result.author,
          if (duration != null) _fmtLength(duration),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Descargar audio',
            onPressed: onDownloadAudio,
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            tooltip: 'Descargar vídeo (MP4)',
            onPressed: onDownloadVideo,
          ),
        ],
      ),
    );
  }
}

String _fmtLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${m}m ${s.toString().padLeft(2, '0')}s';
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
    final isVideo = props.contentKind == 'video';
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
          if (isVideo)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.videocam, size: 16, color: Colors.white54),
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
    return _fmtLength(Duration(seconds: secs));
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
              'Tu biblioteca está vacía.\nBusca en YouTube o añade una URL '
              'para empezar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}