import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/search/preview_errors.dart';
import 'package:offline_audio_app/src/search/youtube_search.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

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

/// Pestaña Descargas: buscador de YouTube (recomendaciones, búsquedas
/// recientes, avances y descargas) sobre el listado de descargas activas,
/// fallidas y completadas. El buscador tiene exactamente el mismo aspecto
/// que el de la Biblioteca.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _searchController = TextEditingController();

  /// Search state. While `null`, the downloads list is shown; otherwise we
  /// show either results, the spinner, or an error banner.
  List<SearchResult>? _results;
  bool _searching = false;
  String? _searchError;
  String? _activeQuery;
  int? _lastElapsedMs;

  /// Guard contra doble pulsación mientras se obtiene el manifest del avance.
  bool _previewBusy = false;

  /// Id del resultado cuyo avance se está resolviendo (para el spinner por
  /// fila). Acompaña a `_previewBusy`, que bloquea avances simultáneos.
  String? _resolvingId;

  /// URLs directas de avance ya resueltas por `videoId`: las URLs de
  /// googlevideo caducan en horas, así que se cachean con TTL y re-tocar
  /// el mismo resultado suena al instante sin volver a resolver.
  static const _previewCacheTtl = Duration(hours: 4);
  final Map<String, ({String url, DateTime expiresAt})> _previewUrlCache = {};

  /// Nº de secuencia de búsqueda: solo la consulta más reciente aplica su
  /// resultado. Evita que respuestas tardías pisen unas más nuevas y hace
  /// imposible lanzar dos peticiones idénticas a la vez.
  int _searchSeq = 0;

  final FocusNode _searchFocusNode = FocusNode();
  bool _showingRecent = false;
  final GlobalKey<RecentSearchesState> _recentKey = GlobalKey();
  String _currentQuery = '';

  /// grupo TapRegion común entre el buscador y la lista de sugerencias:
  /// solo los toques FUERA de ambos cierran las recomendaciones, así el tap
  /// en una sugerencia siempre llega a su ListTile y lanza la búsqueda.
  static const _searchRegion = 'downloads-search-region';

  @override
  void initState() {
    super.initState();
    // Flechas + Enter + Escape sobre el propio nodo del campo, para que el
    // handler corra antes que el submit interno del TextField.
    _searchFocusNode.onKeyEvent = _onSearchFieldKey;
  }

  /// Navegación por teclado del buscador (Windows/macOS): flecha abajo entra
  /// a sugerencias/historial, arriba/abajo mueven el resaltado, Enter busca
  /// lo resaltado (o lo escrito si no hay nada resaltado) y Escape quita el
  /// resaltado. Sin lista visible todo se ignora (comportamiento normal).
  KeyEventResult _onSearchFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final recent = _recentKey.currentState;
    final listOpen =
        _showingRecent && recent != null && recent.navItemCount > 0;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      if (!listOpen) return KeyEventResult.ignored;
      recent.moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (!listOpen || !recent.hasNavSelection) {
        return KeyEventResult.ignored;
      }
      recent.moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      final q = recent?.confirmSelection();
      if (q == null) return KeyEventResult.ignored;
      _searchController.text = q;
      _searchNow(q);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (recent?.hasNavSelection == true) {
        recent!.clearSelection();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Sale del modo búsqueda y vuelve al listado de descargas.
  Future<void> _clearSearch() async {
    _searchController.clear();
    _searchSeq++; // Invalida cualquier búsqueda aún en vuelo.
    setState(() {
      _results = null;
      _searchError = null;
      _searching = false;
      _activeQuery = null;
      _lastElapsedMs = null;
      _showingRecent = false;
      _currentQuery = '';
    });
    _recentKey.currentState?.refresh();
  }

  Future<void> _searchNow([String? queryOverride]) async {
    final q = (queryOverride ?? _searchController.text).trim();
    if (q.isEmpty) {
      await _clearSearch();
      return;
    }
    // Ya hay una búsqueda idéntica en vuelo: no lanzamos otra petición.
    if (_searching && _activeQuery == q) return;
    final seq = ++_searchSeq;
    FocusScope.of(context).unfocus();
    setState(() {
      _searching = true;
      _searchError = null;
      _activeQuery = q;
      _lastElapsedMs = null;
      _showingRecent = false;
    });
    final sw = Stopwatch()..start();
    try {
      final results = await YoutubeSearch.search(q);
      sw.stop();
      if (!mounted || seq != _searchSeq) return;
      // Conservar la búsqueda en el historial.
      final model = AppModelProvider.of(context);
      unawaited(model.saveToSearchHistory(q, 'youtube'));
      setState(() {
        _searching = false;
        _results = results;
        _lastElapsedMs = sw.elapsedMilliseconds;
      });
    } catch (e) {
      sw.stop();
      if (!mounted || seq != _searchSeq) return;
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
  ///
  /// Vía rápida con `youtube_explode`; si el manifest falla (vídeos con
  /// restricción, cipher nuevo, etc.), fallback al motor (`yt-dlp -g`),
  /// que sí los resuelve. El usuario solo ve un mensaje corto en español.
  Future<void> _preview(SearchResult r, {required bool video}) async {
    if (_previewBusy) return;
    final model = AppModelProvider.of(context);
    setState(() {
      _previewBusy = true;
      _resolvingId = r.id;
    });
    try {
      final url = await _previewUrl(r, video: video);
      if (!mounted) return;
      try {
        await model.playPreview(
          id: r.id,
          title: r.title,
          artist: r.author,
          url: url,
          isVideo: video,
        );
      } catch (playError) {
        // La URL de googlevideo caduca a las horas: si venía de caché,
        // re-resolvemos fresca y reintentamos una sola vez antes de rendir.
        _previewUrlCache.remove('${video ? 'v' : 'a'}:${r.id}');
        final fresh = await _previewUrl(r, video: video);
        await model.playPreview(
          id: r.id,
          title: r.title,
          artist: r.author,
          url: fresh,
          isVideo: video,
        );
      }
      if (video && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PreviewVideoScreen(
              url: url,
              title: r.title,
              id: r.id,
              artist: r.author,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: friendlyPreviewError(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _previewBusy = false;
          _resolvingId = null;
        });
      } else {
        _previewBusy = false;
        _resolvingId = null;
      }
    }
  }

  /// URL del avance: primero el motor (`yt-dlp -g`), que es el que
  /// resuelve hoy; la vía rápida de Dart queda como fallback por si el
  /// motor falla. En iOS NO hay motor (sandbox), así que solo vía rápida.
  /// Si el motor falla por auth/bot/cookies, se reporta directo: la vía
  /// rápida tampoco lo resolvería y solo taparía el error útil.
  Future<String> _previewUrl(SearchResult r, {required bool video}) async {
    // Caché con TTL: re-tocar el mismo resultado no vuelve a resolver.
    final cacheKey = '${video ? 'v' : 'a'}:${r.id}';
    final hit = _previewUrlCache[cacheKey];
    if (hit != null) {
      if (DateTime.now().isBefore(hit.expiresAt)) return hit.url;
      _previewUrlCache.remove(cacheKey);
    }
    final url = await _resolvePreviewUrl(r, video: video);
    _previewUrlCache[cacheKey] =
        (url: url, expiresAt: DateTime.now().add(_previewCacheTtl));
    return url;
  }

  /// Resolución real de la URL del avance (motor primero, vía rápida de
  /// fallback). Ver doc de `_previewUrl` para el orden y errores.
  Future<String> _resolvePreviewUrl(SearchResult r, {required bool video}) async {
    if (isIOSPlatform) {
      return video
          ? await YoutubeSearch.videoPreviewUrl(r.id)
          : await YoutubeSearch.audioPreviewUrl(r.id);
    }
    Object? motorError;
    try {
      return await previewStreamUrl(url: r.url, video: video);
    } catch (e) {
      motorError = e;
      final msg = e.toString().toLowerCase();
      if (msg.contains('bot') ||
          msg.contains('cookie') ||
          msg.contains('login') ||
          msg.contains('sign in') ||
          msg.contains('iniciar sesión')) {
        rethrow;
      }
      debugPrint('[Preview] motor falló (${e.runtimeType}), fallback vía rápida');
    }
    try {
      return video
          ? await YoutubeSearch.videoPreviewUrl(r.id)
          : await YoutubeSearch.audioPreviewUrl(r.id);
    } catch (_) {
      // La vía rápida falla de forma crónica; el error del motor suele
      // ser más informativo (privado, restricción real, red, etc.).
      // `motorError` siempre está seteado aquí: es el único camino que
      // llega a este punto.
      throw motorError;
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
          icon: HugeIcons.strokeRoundedPlay,
          label: 'Escuchar avance',
        ),
        AppSheetItem(
          value: 'play_video',
          icon: HugeIcons.strokeRoundedCameraVideo,
          label: 'Ver avance',
        ),
        AppSheetItem(
          value: 'dl_audio',
          icon: HugeIcons.strokeRoundedDownload01,
          label: 'Descargar audio',
        ),
        AppSheetItem(
          value: 'dl_video',
          icon: HugeIcons.strokeRoundedFilm01,
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
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedMusicNote01,
                color: Colors.white54,
              ),
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
    // En iOS la descarga va por el camino nativo (stream HTTPS directo,
    // sin yt-dlp); en el resto de plataformas lo resuelve el motor Rust.
    try {
      final model = AppModelProvider.of(context);
      await model.downloadFromUrl(result.url, kind: kind);
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: 'Descarga iniciada. Ver pestaña Descargas.',
      );
    } catch (e) {
      if (!mounted) return;
      showAppSnackBar(context, message: 'No se pudo iniciar la descarga: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    // Error de dispositivo de audio: se avisa una sola vez por post-frame
    // (el player lo reemite mientras parpadea playing).
    if (model.audioDeviceError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || model.audioDeviceError == null) return;
        showAppSnackBar(context, message: model.audioDeviceError!);
        model.consumeAudioDeviceError();
      });
    }
    return SafeArea(
      child: Column(
        children: [
          TapRegion(
            groupId: _searchRegion,
            child: _buildFrostedTop(context),
          ),
          Expanded(
            child: _showingRecent
                // Las sugerencias van en el mismo grupo TapRegion: un tap
                // sobre ellas no las cierra; un tap fuera (lista de
                // descargas, etc.) sí, vía onTapOutside.
                ? TapRegion(
                    groupId: _searchRegion,
                    onTapOutside: (_) => _hideRecent(),
                    child: _buildRecentSearches(context),
                  )
                : TapRegion(
                    groupId: _searchRegion,
                    onTapOutside: (_) => _hideRecent(),
                    child: _buildContent(context, model),
                  ),
          ),
        ],
      ),
    );
  }

  void _hideRecent() {
    if (_showingRecent) setState(() => _showingRecent = false);
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
          onClose: _clearSearch,
        ),
      );
    }
    final results = _results;
    if (results != null) {
      return _buildResults(context, model, results);
    }
    if (_showingRecent) {
      return _buildRecentSearches(context);
    }
    return _buildDownloads(context, model);
  }

  Widget _buildRecentSearches(BuildContext context) {
    return RecentSearches(
      key: _recentKey,
      query: _currentQuery,
      source: 'youtube',
      onTap: (q) {
        _searchController.text = q;
        _searchNow(q);
      },
      onDelete: (entry) async {
        final model = AppModelProvider.of(context);
        try {
          await model.removeSearch(entry.id.toInt());
        } catch (_) {}
      },
    );
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
                HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch02,
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
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedRefresh,
                      ),
                      label: const Text('Reintentar'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _clearSearch,
                      child: const Text('Volver a Descargas'),
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
              loading: _resolvingId == r.id,
              onTap: () => _preview(r, video: false),
              onActions: () => _openResultActions(r),
            ),
          ),
      ],
    );
  }

  /// Panel superior (buscador) con superficie translúcida, mismo aspecto que
  /// el de la pestaña Biblioteca.
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
              // En macOS solo el buscador (los ajustes están en el sidebar).
              // En iOS y Material, buscador y acceso a ajustes en la misma fila.
              if (isMacOSPlatform)
                _buildSearchField(context)
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 4, 10),
                  child: Row(
                    children: [
                      Expanded(child: _searchField(context)),
                      Builder(
                        builder: (context) => IconButton(
                          onPressed: () {
                            // iOS no tiene drawer: se abre Ajustes con push,
                            // igual que hace el sidebar en macOS.
                            if (isIOSPlatform) {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SettingsScreen(),
                                ),
                              );
                            } else {
                              Scaffold.of(context).openEndDrawer();
                            }
                          },
                          tooltip: 'Ajustes',
                          icon: HugeIcon(
                            icon: HugeIcons.strokeRoundedSettings01,
                            size: 22,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      // En macOS no hay cabecera sobre el buscador, así que necesita más
      // margen superior para no quedar pegado al borde del panel.
      padding: EdgeInsets.fromLTRB(16, isMacOSPlatform ? 12 : 4, 16, 10),
      child: _searchField(context),
    );
  }

  Widget _searchField(BuildContext context) {
    return AppSearchField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onSearch: _searchNow,
      onChanged: (value) {
        setState(() {
          _currentQuery = value;
          if (value.isNotEmpty) _showingRecent = true;
        });
        // La X del buscador está vaciando el campo: si estábamos viendo
        // resultados, cerramos la búsqueda y volvemos a las descargas.
        if (value.isEmpty && _activeQuery != null) _clearSearch();
      },
      onFocusChanged: (focused) {
        if (focused && _activeQuery == null) {
          setState(() => _showingRecent = true);
          _recentKey.currentState?.refresh();
        }
      },
    );
  }

  Widget _buildDownloads(BuildContext context, AppModel model) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.6);
    final progress = model.downloads;
    final errors = model.downloadErrors;
    final completed = model.completed;
    final info = model.lastInfo;
    final hasAny =
        progress.isNotEmpty || errors.isNotEmpty || completed.isNotEmpty;

    return Column(
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
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCancel01,
                    size: 18,
                  ),
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
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedDownload01,
                      ),
                      title: Text(
                        model.downloadTitle(taskId) ??
                            'Descarga ${_shortId(taskId)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                        ),
                        tooltip: 'Cancelar',
                        onPressed: () async {
                          try {
                            await model.cancelDownloadForTask(taskId);
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
                      leading: const HugeIcon(
                        icon: HugeIcons.strokeRoundedAlertCircle,
                        color: Colors.redAccent,
                      ),
                      title: Text(
                        'Falló · ${model.downloadTitle(taskId) ?? _shortId(taskId)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        reason,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedCancel01,
                        ),
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
        leading: const HugeIcon(
          icon: HugeIcons.strokeRoundedCheckmarkCircle01,
          color: Colors.greenAccent,
        ),
        title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: const Text('Completada'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (track.contentKind == 'video')
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedCameraVideo),
                tooltip: 'Ver vídeo',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VideoPlayerScreen(track: track),
                  ),
                ),
              ),
            IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlay),
              tooltip: 'Escuchar',
              onPressed: () => model.playTrack(track),
            ),
            IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01),
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
            icon: HugeIcons.strokeRoundedQueue01,
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
