import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/search/search.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

class _TogglePlayIntent extends Intent {
  const _TogglePlayIntent();
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SortOrder _order = SortOrder.dateDesc;
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
      return SearchFeedback(
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
      return SearchFeedback(
        child: SearchError(
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
        SearchHeader(query: _activeQuery ?? '', onClose: _serveLibrary),
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
            (r) => SearchResultTile(
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
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) => _searchNow(),
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
      return const EmptyLibrary();
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
          SectionHeader(
            'Reciente',
            trailing: TextButton.icon(
              onPressed: model.shuffleLibrary,
              icon: const Icon(Icons.shuffle, size: 18),
              label: const Text('Aleatorio'),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
              ),
            ),
          ),
          RecentBanner(
            track: recent.first,
            selected: _selectedTrackId == recent.first.id,
            onPlay: () => openTrack(context, model, recent.first),
            onSelect: () => setState(() => _selectedTrackId = recent.first.id),
          ),
          ...recent
              .skip(1)
              .map(
                (t) => TrackTile(
                    track: t,
                    selected: _selectedTrackId == t.id,
                    onPlay: () => openTrack(context, model, t),
                    onSelect: () => setState(() => _selectedTrackId = t.id)),
              ),
          if (tracks.isNotEmpty) const SectionHeader('Biblioteca'),
        ],
        ...tracks.map(
          (t) => TrackTile(
            track: t,
            selected: _selectedTrackId == t.id,
            onPlay: () => openTrack(context, model, t),
            onSelect: () => setState(() => _selectedTrackId = t.id),
          ),
        ),
      ],
    );
  }
}
