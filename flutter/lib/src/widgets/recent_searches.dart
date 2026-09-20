import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/search/search.dart';

/// Shows recent search history and live YouTube autocomplete predictions
/// below the search field. Tap a history row to re-search; tap a prediction
/// to search with that text. Swipe-to-delete removes history entries.
class RecentSearches extends StatefulWidget {
  const RecentSearches({
    super.key,
    this.query,
    required this.source,
    required this.onTap,
    required this.onDelete,
  });

  /// Current search text; used to fetch YouTube autocomplete predictions.
  final String? query;

  /// Search source tag (e.g. `"youtube"`).
  final String source;

  /// Called when the user taps a history query or prediction.
  final ValueChanged<String> onTap;

  /// Called when the user swipes to delete a history entry.
  final ValueChanged<SearchHistoryEntry> onDelete;

  @override
  RecentSearchesState createState() => RecentSearchesState();
}

class RecentSearchesState extends State<RecentSearches> {
  List<SearchHistoryEntry> _history = [];
  List<String> _predictions = [];
  bool _loadingPredictions = false;
  Timer? _debounce;
  String? _lastQuery;

  /// Nº de secuencia de predicciones: solo gana la solicitud más reciente,
  /// de modo que nunca se aplican resultados obsoletos ni se apilan llamadas.
  int _predSeq = 0;

  /// Guard: el historial se carga una única vez, en `didChangeDependencies`
  /// (no en initState, porque `AppModelProvider.of` usa dependOnInherited*,
  /// que el framework prohíbe antes de que initState termine).
  bool _historyLoaded = false;

  /// Índice seleccionado con el teclado (flechas) sobre la lista navegable
  /// (sugerencias + historial). -1 = ninguno: se está escribiendo.
  int _selectedIndex = -1;

  /// Ítems navegables con el teclado, en orden visual: sugerencias primero,
  /// luego historial.
  List<String> get _navItems => [
    ..._predictions,
    ..._history.map((e) => e.query),
  ];

  /// Nº de ítems navegables (0 si la lista está vacía o solo hay spinner).
  int get navItemCount => _navItems.length;

  /// ¿Hay una sugerencia/historial resaltado por teclado?
  bool get hasNavSelection =>
      _selectedIndex >= 0 && _selectedIndex < _navItems.length;

  /// Mueve el resaltado `delta` posiciones (típico +1/-1). Desde -1, bajar
  /// entra al primer ítem; desde el primero, subir vuelve a -1 (al campo).
  void moveSelection(int delta) {
    final n = _navItems.length;
    if (n == 0) return;
    setState(() {
      _selectedIndex = (_selectedIndex + delta).clamp(-1, n - 1);
    });
  }

  /// Texto resaltado para buscar con Enter, o `null` si no hay selección.
  String? confirmSelection() => hasNavSelection ? _navItems[_selectedIndex] : null;

  /// Quita el resaltado y vuelve al texto que se está escribiendo.
  void clearSelection() {
    if (_selectedIndex != -1) setState(() => _selectedIndex = -1);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_historyLoaded) {
      _historyLoaded = true;
      _loadHistory();
    }
  }

  @override
  void didUpdateWidget(covariant RecentSearches oldWidget) {
    super.didUpdateWidget(oldWidget);
    final q = widget.query;
    if (q != _lastQuery) {
      _lastQuery = q;
      _onQueryChanged(q ?? '');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final model = AppModelProvider.of(context);
      final entries = await model.loadRecentSearches(widget.source);
      // La lista cambió: el resaltado de teclado deja de ser válido.
      if (mounted) {
        setState(() {
          _history = entries;
          _selectedIndex = -1;
        });
      }
    } catch (_) {}
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _loadingPredictions = false;
        _selectedIndex = -1;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _fetchPredictions(query.trim());
    });
  }

  Future<void> _fetchPredictions(String query) async {
    final seq = ++_predSeq;
    setState(() => _loadingPredictions = true);
    try {
      final results = await YoutubeSearch.getQuerySuggestions(query);
      if (!mounted || seq != _predSeq) return;
      // Nuevas sugerencias: se resetea el resaltado de teclado.
      setState(() {
        _predictions = results;
        _selectedIndex = -1;
      });
    } catch (_) {
      if (!mounted || seq != _predSeq) return;
      setState(() {
        _predictions = [];
        _selectedIndex = -1;
      });
    } finally {
      if (mounted && seq == _predSeq) {
        setState(() => _loadingPredictions = false);
      }
    }
  }

  void refresh() => _loadHistory();

  @override
  Widget build(BuildContext context) {
    final hasHistory = _history.isNotEmpty;
    final hasPredictions = _predictions.isNotEmpty || _loadingPredictions;
    if (!hasHistory && !hasPredictions) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.55);

    // Sólo el spinner en marcha: centrado en el área del visor, con aire
    // vertical para que no quede pegado arriba. El padre es una columna de
    // tamaño mínimo, así que el Padding + Center garantiza el centrado
    // horizontal aunque no haya más contenido.
    if (_loadingPredictions && _predictions.isEmpty && !hasHistory) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: isApplePlatform
              ? const CupertinoActivityIndicator(radius: 12)
              : const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_predictions.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Sugerencias',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subtle,
                  ),
                ),
              ),
              for (var i = 0; i < _predictions.length; i++)
                _navTile(
                  context: context,
                  navIndex: i,
                  leadingIcon: HugeIcons.strokeRoundedTrendingUpDown,
                  subtle: subtle,
                  title: _predictions[i],
                  onTap: () => widget.onTap(_predictions[i]),
                ),
            ],
            if (_loadingPredictions && _predictions.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: _PredictionsSpinner(),
                ),
              ),
            if (hasHistory) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Búsquedas recientes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subtle,
                  ),
                ),
              ),
              for (var j = 0; j < _history.length; j++)
                Dismissible(
                  key: ValueKey(_history[j].id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 16),
                    color: scheme.error,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedDelete01,
                      color: scheme.onError,
                    ),
                  ),
                  onDismissed: (_) {
                    widget.onDelete(_history[j]);
                    setState(() {
                      _history.removeAt(j);
                      _selectedIndex = -1;
                    });
                  },
                  child: _navTile(
                    context: context,
                    navIndex: _predictions.length + j,
                    leadingIcon: HugeIcons.strokeRoundedClock01,
                    subtle: subtle,
                    title: _history[j].query,
                    onTap: () => widget.onTap(_history[j].query),
                  ),
                ),
            ],
            if (_navItems.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  '↑↓ navegar · Enter buscar',
                  style: TextStyle(fontSize: 11, color: subtle),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Fila navegable por teclado: cuando su índice coincide con
  /// [_selectedIndex] se resalta para mostrar por dónde va el cursor.
  Widget _navTile({
    required BuildContext context,
    required int navIndex,
    required List<List<dynamic>> leadingIcon,
    required Color subtle,
    required String title,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: navIndex == _selectedIndex,
      selectedTileColor: scheme.primary.withValues(alpha: 0.14),
      selectedColor: scheme.onSurface,
      leading: HugeIcon(icon: leadingIcon, size: 18, color: subtle),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    );
  }
}

/// Spinner pequeño y centrado para las sugerencias en curso cuando ya hay
/// historial en pantalla. Extraído para usarlo dentro de un `const`.
class _PredictionsSpinner extends StatelessWidget {
  const _PredictionsSpinner();

  @override
  Widget build(BuildContext context) {
    if (isApplePlatform) return const CupertinoActivityIndicator();
    return const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
