import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

/// Biblioteca local: lista de tracks descargados. El buscador mantiene el
/// mismo aspecto que el de Descargas pero solo filtra la biblioteca local
/// (no hace búsquedas de YouTube ni descargas).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final SortOrder _order = SortOrder.dateDesc;
  final _searchController = TextEditingController();

  /// Búsqueda local en curso / consulta activa en la biblioteca.
  bool _searching = false;
  String? _activeQuery;

  String? _selectedTrackId;
  final FocusNode _listFocusNode = FocusNode();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _listFocusNode.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// Vuelve a mostrar la biblioteca completa (sin filtro de búsqueda).
  Future<void> _serveLibrary() async {
    _searchController.clear();
    setState(() {
      _searching = false;
      _activeQuery = null;
    });
    await AppModelProvider.of(context)
        .reloadLibrary(search: null, order: _order);
  }

  /// Busca dentro de la biblioteca local. El backend filtra las pistas por
  /// título/artista/álbum; sin llamadas de red.
  Future<void> _searchNow([String? queryOverride]) async {
    final q = (queryOverride ?? _searchController.text).trim();
    if (q.isEmpty) {
      await _serveLibrary();
      return;
    }
    FocusScope.of(context).unfocus();
    final model = AppModelProvider.of(context);
    setState(() {
      _searching = true;
      _activeQuery = q;
    });
    try {
      await model.reloadLibrary(search: q, order: _order);
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
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
    if (_activeQuery != null) {
      return _buildResults(context, model);
    }
    return _buildList(context, model, model.library);
  }

  Widget _buildResults(BuildContext context, AppModel model) {
    final tracks = model.library;
    final query = _activeQuery ?? '';
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      children: [
        Padding(
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
              TextButton(
                onPressed: _serveLibrary,
                child: const Text('Volver a la biblioteca'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            '${tracks.length} '
            '${tracks.length == 1 ? 'canción' : 'canciones'}',
            style: TextStyle(fontSize: 11, color: subtle),
          ),
        ),
        const SizedBox(height: 4),
        if (tracks.isEmpty)
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
                  'Sin resultados en la biblioteca para «$query»',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subtle),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _serveLibrary,
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                  label: const Text('Volver a la biblioteca'),
                ),
              ],
            ),
          )
        else
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

  /// Panel superior (buscador) con superficie translúcida, mismo aspecto que
  /// el de la pestaña Descargas.
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
              // En Apple no hay avatar sobre el buscador (los ajustes están
              // en el sidebar). En Material se conserva el avatar que abre el
              // cajón de ajustes.
              if (!isApplePlatform) _buildHeader(context),
              _buildSearchField(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Align(
        alignment: Alignment.centerRight,
        child: Builder(
          builder: (context) => InkWell(
            onTap: () => Scaffold.of(context).openEndDrawer(),
            borderRadius: BorderRadius.circular(24),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CircleAvatar(
                radius: 16,
                child: HugeIcon(
                  icon: HugeIcons.strokeRoundedUser,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, isApplePlatform ? 12 : 4, 16, 10),
      child: AppSearchField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onSearch: _searchNow,
        onChanged: (value) {
          // La X del buscador está vaciando el campo: si estábamos viendo
          // resultados, volvemos a la biblioteca completa.
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
        SectionHeader(
          'Biblioteca',
          trailing: OutlinedButton.icon(
            onPressed: model.shuffleLibrary,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedDice, size: 24.0),
            label: const Text('Aleatorio'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.5),
                width: 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              // Sin relleno: solo contorno redondeado.
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
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
