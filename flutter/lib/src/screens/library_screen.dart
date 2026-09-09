import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/preview_video_screen.dart';
import 'package:offline_audio_app/src/screens/video_player_screen.dart';
import 'package:offline_audio_app/src/search/youtube_search.dart';

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

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
  int? _lastElapsedMs;

  /// Guard contra doble pulsación mientras se obtiene el manifest del avance.
  bool _previewBusy = false;

  String? _selectedTrackId;
  final FocusNode _listFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    debugPrint('[LibrarySearch] initState hash=$hashCode');
  }

  @override
  void dispose() {
    debugPrint('[LibrarySearch] dispose hash=$hashCode');
    _searchController.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  Future<void> _serveLibrary() async {
    debugPrint('[LibrarySearch] _serveLibrary hash=$hashCode '
        'llamado, limpio búsqueda. Stack:\n'
        '${StackTrace.current.toString().split('\n').take(8).join('\n')}');
    _searchController.clear();
    setState(() {
      _results = null;
      _searchError = null;
      _searching = false;
      _activeQuery = null;
      _lastElapsedMs = null;
    });
    await AppModelProvider.of(context)
        .reloadLibrary(search: null, order: _order);
  }

  Future<void> _searchNow() async {
    final q = _searchController.text.trim();
    debugPrint('[LibrarySearch] _searchNow pulsado hash=$hashCode query="$q"');
    if (q.isEmpty) {
      debugPrint('[LibrarySearch] query vacía, no se busca');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _activeQuery = q;
      _lastElapsedMs = null;
    });
    final sw = Stopwatch()..start();
    try {
      final results = await YoutubeSearch.search(q);
      sw.stop();
      debugPrint(
          '[LibrarySearch] OK query="$q" resultados=${results.length} en ${sw.elapsedMilliseconds}ms');
      if (!mounted) {
        debugPrint('[LibrarySearch] descartado: widget desmontado');
        return;
      }
      setState(() {
        _searching = false;
        _results = results;
        _lastElapsedMs = sw.elapsedMilliseconds;
      });
      debugPrint('[LibrarySearch] setState resultados hash=$hashCode '
          'mounted=$mounted count=${results.length}');
    } catch (e, st) {
      sw.stop();
      debugPrint(
          '[LibrarySearch] ERROR query="$q" tras ${sw.elapsedMilliseconds}ms: $e\n$st');
      if (!mounted) return;
      setState(() {
        _searching = false;
        _lastElapsedMs = sw.elapsedMilliseconds;
        _searchError = 'No se pudo completar la búsqueda. Revisa tu conexión '
            'e inténtalo de nuevo.\n($e)';
      });
    }
  }

  /// Obtiene el stream directo y reproduce el avance: audio en la barra,
  /// vídeo a pantalla completa. No toca la biblioteca ni las estadísticas.
  Future<void> _preview(SearchResult r, {required bool video}) async {
    if (_previewBusy) return;
    final model = AppModelProvider.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _previewBusy = true);
    try {
      final url = video
          ? await YoutubeSearch.videoPreviewUrl(r.id)
          : await YoutubeSearch.audioPreviewUrl(r.id);
      if (!mounted) return;
      await model.playPreview(
        id: r.id,
        title: r.title,
        artist: r.author,
        url: url,
        isVideo: video,
      );
      if (video && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PreviewVideoScreen(url: url, title: r.title),
          ),
        );
      }
    } catch (e, st) {
      debugPrint('[LibrarySearch] avance ${video ? 'vídeo' : 'audio'} '
          'falló: $e\n$st');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('No se pudo reproducir el avance: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  /// Hoja con las 4 acciones de un resultado: avance (audio/vídeo) y
  /// descarga (audio/vídeo), más la tarjeta con miniatura y título.
  Future<void> _openResultActions(SearchResult r) async {
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.55);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  r.thumbnailUrl,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, error, stack) => const SizedBox(
                    width: 52,
                    height: 52,
                    child: ColoredBox(
                      color: Color(0xFF2A2A2A),
                      child: Icon(Icons.music_note, color: Colors.white54),
                    ),
                  ),
                ),
              ),
              title: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                r.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subtle),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('Escuchar avance'),
              onTap: () => Navigator.of(context).pop('play_audio'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Ver avance'),
              onTap: () => Navigator.of(context).pop('play_video'),
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Descargar audio'),
              onTap: () => Navigator.of(context).pop('dl_audio'),
            ),
            ListTile(
              leading: const Icon(Icons.movie_creation_outlined),
              title: const Text('Descargar vídeo'),
              onTap: () => Navigator.of(context).pop('dl_video'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'play_audio':
        await _preview(r, video: false);
      case 'play_video':
        await _preview(r, video: true);
      case 'dl_audio':
        await _startDownload(r, ContentKind.music);
      case 'dl_video':
        await _startDownload(r, ContentKind.video);
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

  /// Reproduce un track; si es vídeo, abre directamente el reproductor de
  /// vídeo (que además garantiza su propia reproducción).
  static Future<void> openTrack(
      BuildContext context, AppModel model, Track track) async {
    if (track.contentKind == 'video') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(track: track)),
      );
    } else {
      await model.playTrack(track);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    // Solo log cuando hay búsqueda en juego (fase spinner / error). El
    // rebuild por cada notify del AppModel spamearía la consola en reposo.
    if (_searching || _searchError != null) {
      debugPrint('[LibrarySearch] build hash=$hashCode searching=$_searching '
          'results=${_results?.length} error=${_searchError != null} '
          'query=$_activeQuery lib=${model.library.length}');
    }

    return SafeArea(
      child: Shortcuts(
        shortcuts: {
          SingleActivator(LogicalKeyboardKey.space): const _TogglePlayIntent(),
        },
        child: Actions(
          actions: {
            _TogglePlayIntent: CallbackAction<_TogglePlayIntent>(
              onInvoke: (_) {
                final m = AppModelProvider.of(context);
                m.togglePause();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            focusNode: _listFocusNode,
            onKeyEvent: (node, event) {
              // Keyboard navigation for arrow keys is handled via selection state.
              return KeyEventResult.ignored;
            },
            child: Column(
              children: [
                _buildFrostedTop(context),
                Expanded(child: _buildContent(context, model)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppModel model) {
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    if (_searching) {
      return _SearchFeedback(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 12),
            Text(
              'Buscando…',
              style: TextStyle(color: subtle, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return _SearchFeedback(
        child: _SearchError(
          message: '«${_activeQuery ?? ''}»'
              '${_lastElapsedMs != null ? ' · ${_lastElapsedMs}ms' : ''}\n'
              '${_searchError!}',
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
    final elapsed = _lastElapsedMs;
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        _SearchHeader(query: _activeQuery ?? '', onClose: _serveLibrary),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '${results.length} resultado(s)'
            '${elapsed != null ? ' · ${elapsed}ms' : ''}',
            style: TextStyle(fontSize: 11, color: subtle),
          ),
        ),
        const SizedBox(height: 4),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off,
                    size: 48, color: subtle.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Text(
                  'Sin resultados para «${_activeQuery ?? ''}»\n'
                  'Prueba con el nombre del artista, canción o una palabra clave.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtle),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.icon(
                      onPressed: _searchNow,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Reintentar'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _serveLibrary,
                      child: const Text('Volver a la biblioteca'),
                    ),
                  ],
                ),
              ],
            ),
          )
        else
          ...results.map(
            (r) => _SearchResultTile(
              result: r,
              onTap: () => _preview(r, video: false),
              onActions: () => _openResultActions(r),
            ),
          ),
      ],
    );
  }

  /// Panel superior (título sutil + buscador) con superficie translúcida.
  /// Va en flujo normal encima del contenido, sin solapes.
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
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Biblioteca',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: subtle,
              ),
            ),
          ),
          Builder(
            builder: (context) => InkWell(
              onTap: () => Scaffold.of(context).openEndDrawer(),
              borderRadius: BorderRadius.circular(24),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: CircleAvatar(
                  radius: 16,
                  child: Icon(Icons.person, size: 20),
                ),
              ),
            ),
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
    if (_selectedTrackId == null && recent.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedTrackId = recent.first.id);
      });
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        if (recent.isNotEmpty) ...[
          const _SectionHeader('Reciente'),
          _RecentBanner(
            track: recent.first,
            selected: _selectedTrackId == recent.first.id,
            onPlay: () => openTrack(context, model, recent.first),
            onSelect: () => setState(() => _selectedTrackId = recent.first.id),
          ),
          ...recent
              .skip(1)
              .map(
                (t) => _TrackTile(
                    props: t,
                    selected: _selectedTrackId == t.id,
                    onPlay: () => openTrack(context, model, t),
                    onSelect: () => setState(() => _selectedTrackId = t.id)),
              ),
          if (tracks.isNotEmpty) const _SectionHeader('Biblioteca'),
        ],
        ...tracks.map(
          (t) => _TrackTile(
            props: t,
            selected: _selectedTrackId == t.id,
            onPlay: () => openTrack(context, model, t),
            onSelect: () => setState(() => _selectedTrackId = t.id),
          ),
        ),
      ],
    );
  }
}

/// Área de spinner / error: centrada en el espacio bajo la cabecera.
class _SearchFeedback extends StatelessWidget {
  const _SearchFeedback({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      alignment: Alignment.center,
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
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off,
              size: 48, color: subtle.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: subtle),
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
    required this.onTap,
    required this.onActions,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final duration = result.duration;
    return ListTile(
      onTap: onTap,
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
      trailing: IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Ver y descargar',
        onPressed: onActions,
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
  const _RecentBanner({required this.track, required this.onPlay, this.selected = false, this.onSelect});

  final Track track;
  final VoidCallback onPlay;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    final subtitle = [
      if (track.artist != null && track.artist!.isNotEmpty) track.artist!,
      if (track.album != null && track.album!.isNotEmpty) track.album!,
    ].join(' · ');
    return Card(
      elevation: selected ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected ? const BorderSide(color: Colors.amber, width: 2) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect ?? onPlay,
        onDoubleTap: onPlay,
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
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({required this.props, required this.onPlay, this.selected = false, this.onSelect});

  final Track props;
  final VoidCallback onPlay;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final thumb = props.thumbnailPath;
    final isVideo = props.contentKind == 'video';
    return GestureDetector(
      onTap: onSelect,
      onDoubleTap: onPlay,
      child: Container(
        decoration: BoxDecoration(
          border: selected ? Border(left: BorderSide(color: Colors.amber, width: 3)) : null,
          color: selected ? Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.2) : null,
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
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined,
                size: 64, color: subtle.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Tu biblioteca está vacía.\nBusca en YouTube para empezar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtle),
            ),
          ],
        ),
      ),
    );
  }
}