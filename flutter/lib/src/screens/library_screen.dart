import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/search/search.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

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
    debugPrint(
      '[LibrarySearch] _serveLibrary hash=$hashCode '
      'llamado, limpio búsqueda. Stack:\n'
      '${StackTrace.current.toString().split('\n').take(8).join('\n')}',
    );
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
        '[LibrarySearch] OK query="$q" resultados=${results.length} en ${sw.elapsedMilliseconds}ms',
      );
      if (!mounted) {
        debugPrint('[LibrarySearch] descartado: widget desmontado');
        return;
      }
      setState(() {
        _searching = false;
        _results = results;
        _lastElapsedMs = sw.elapsedMilliseconds;
      });
      debugPrint(
        '[LibrarySearch] setState resultados hash=$hashCode '
        'mounted=$mounted count=${results.length}',
      );
    } catch (e, st) {
      sw.stop();
      debugPrint(
        '[LibrarySearch] ERROR query="$q" tras ${sw.elapsedMilliseconds}ms: $e\n$st',
      );
      if (!mounted) return;
      setState(() {
        _searching = false;
        _lastElapsedMs = sw.elapsedMilliseconds;
        _searchError =
            'No se pudo completar la búsqueda. Revisa tu conexión '
            'e inténtalo de nuevo.\n($e)';
      });
    }
  }

  /// Obtiene el stream directo y reproduce el avance: audio en la barra,
  /// vídeo a pantalla completa. No toca la biblioteca ni las estadísticas.
  Future<void> _preview(SearchResult r, {required bool video}) async {
    if (_previewBusy) return;
    final model = AppModelProvider.of(context);
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
      debugPrint(
        '[LibrarySearch] avance ${video ? 'vídeo' : 'audio'} '
        'falló: $e\n$st',
      );
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'No se pudo reproducir el avance: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _previewBusy = false);
    }
  }

  /// Hoja con las 4 acciones de un resultado: avance (audio/vídeo) y
  /// descarga (audio/vídeo), más la tarjeta con miniatura y título.
  Future<void> _openResultActions(SearchResult r) async {
    final action = await showAppBottomSheet<String>(
      context,
      title: _resultSheetHeader(r),
      items: const [
        AppSheetItem(
          value: 'play_audio',
          icon: Icons.play_arrow,
          label: 'Escuchar avance',
        ),
        AppSheetItem(
          value: 'play_video',
          icon: Icons.videocam_outlined,
          label: 'Ver avance',
        ),
        AppSheetItem(
          value: 'dl_audio',
          icon: Icons.download,
          label: 'Descargar audio',
        ),
        AppSheetItem(
          value: 'dl_video',
          icon: Icons.movie_creation_outlined,
          label: 'Descargar vídeo',
        ),
      ],
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

  Widget _resultSheetHeader(SearchResult r) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            r.thumbnailUrl,
            width: 72,
            height: 72,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => Container(
              width: 72,
              height: 72,
              color: const Color(0xFF2A2A2A),
              child: const Icon(Icons.music_note, color: Colors.white54),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          r.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          r.author,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: subtle),
        ),
      ],
    );
  }

  Future<void> _startDownload(SearchResult result, ContentKind kind) async {
    try {
      final model = AppModelProvider.of(context);
      final taskId = await model.downloadFromUrl(result.url, kind: kind);
      if (!mounted) return;
      final short = taskId.length <= 8 ? taskId : taskId.substring(0, 8);
      showAppSnackBar(
        context,
        message: 'Descarga iniciada ($short). Ver pestaña Descargas.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'No se pudo iniciar la descarga: $e');
    }
  }

  /// Reproduce un track; si es vídeo, abre directamente el reproductor de
  /// vídeo (que además garantiza su propia reproducción).
  static Future<void> openTrack(
    BuildContext context,
    AppModel model,
    Track track,
  ) async {
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
      debugPrint(
        '[LibrarySearch] build hash=$hashCode searching=$_searching '
        'results=${_results?.length} error=${_searchError != null} '
        'query=$_activeQuery lib=${model.library.length}',
      );
    }

    return SafeArea(
      child: Focus(
        autofocus: true,
        focusNode: _listFocusNode,
        onKeyEvent: (node, event) {
          // Espacio alterna play/pause SOLO cuando el foco es la propia
          // lista. Mientras se escribe en el buscador (foco en el campo), el
          // evento nunca se reclama y el espacio se inserta con normalidad.
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.space &&
              FocusManager.instance.primaryFocus == _listFocusNode) {
            AppModelProvider.of(context).togglePause();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            _buildFrostedTop(context),
            Expanded(child: _buildContent(context, model)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AppModel model) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);
    if (_searching) {
      return SearchFeedback(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: isApplePlatform
                  ? const CupertinoActivityIndicator()
                  : const CircularProgressIndicator(),
            ),
            const SizedBox(height: 12),
            Text('Buscando…', style: TextStyle(color: subtle, fontSize: 12)),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return SearchFeedback(
        child: SearchError(
          message:
              '«${_activeQuery ?? ''}»'
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
    BuildContext context,
    AppModel model,
    List<SearchResult> results,
  ) {
    final elapsed = _lastElapsedMs;
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'Resultados para «${_activeQuery ?? ''}»',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
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
                Icon(
                  Icons.search_off,
                  size: 48,
                  color: subtle.withValues(alpha: 0.5),
                ),
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
            children: [_buildHeader(context), _buildSearchField(context)],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
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
          // En Apple la cabecera no lleva avatar: los ajustes (con la info de
          // usuario) están en el sidebar/tab. En Material mantiene el acceso
          // al cajón de ajustes.
          if (!isApplePlatform)
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
      child: AppSearchField(
        controller: _searchController,
        onSearch: _searchNow,
        onChanged: (value) {
          // La X del buscador está vaciando el campo: si estábamos viendo
          // resultados, cerramos la búsqueda y volvemos a la biblioteca.
          if (value.isEmpty && _activeQuery != null) _serveLibrary();
        },
      ),
    );
  }

  Widget _buildList(BuildContext context, AppModel model, List<Track> tracks) {
    if (tracks.isEmpty) {
      return const EmptyLibrary();
    }
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        const SectionHeader('Biblioteca'),
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
