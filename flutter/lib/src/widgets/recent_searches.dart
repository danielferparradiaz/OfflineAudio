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

  @override
  void initState() {
    super.initState();
    _loadHistory();
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
      if (mounted) setState(() => _history = entries);
    } catch (_) {}
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _predictions = [];
        _loadingPredictions = false;
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
      setState(() => _predictions = results);
    } catch (_) {
      if (!mounted || seq != _predSeq) return;
      setState(() => _predictions = []);
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

    // Sólo el spinner en marcha: centrado en el área del visor.
    if (_loadingPredictions && _predictions.isEmpty && !hasHistory) {
      return Center(
        child: isApplePlatform
            ? const CupertinoActivityIndicator(radius: 12)
            : const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
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
              ..._predictions.map(
                (q) => ListTile(
                  dense: true,
                  leading: HugeIcon(
                    icon: HugeIcons.strokeRoundedTrendingUpDown,
                    size: 18,
                    color: subtle,
                  ),
                  title: Text(q, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => widget.onTap(q),
                ),
              ),
            ],
            if (_loadingPredictions && _predictions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: isApplePlatform
                    ? const CupertinoActivityIndicator()
                    : const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
              ..._history.map(
                (entry) => Dismissible(
                  key: ValueKey(entry.id),
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
                    widget.onDelete(entry);
                    setState(() => _history.remove(entry));
                  },
                  child: ListTile(
                    dense: true,
                    leading: HugeIcon(
                      icon: HugeIcons.strokeRoundedClock01,
                      size: 18,
                      color: subtle,
                    ),
                    title: Text(
                      entry.query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => widget.onTap(entry.query),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
