import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/widgets/mini_equalizer.dart';
import 'package:offline_audio_app/src/widgets/reorder_grip.dart';

/// Tracklist: current playback queue with live search filtering and
/// drag-to-reorder. Logic (state, search, ordering, reorder math, player
/// integration) is shared; only the presentation branches per platform.
///
/// - macOS: floating translucent panel (toolbar-like header, compact search,
///   native rows with hover-only drag handles).
/// - Elsewhere: the original Material bottom sheet, untouched.
class QueueSheet extends StatefulWidget {
  const QueueSheet({super.key});

  @override
  State<QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<QueueSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Track> _visible(AppModel model) {
    final q = _query.trim().toLowerCase();
    final items = model.queue;
    if (q.isEmpty) return items;
    return items
        .where(
          (t) =>
              t.title.toLowerCase().contains(q) ||
              (t.artist?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (isMacOSPlatform || isIOSPlatform) return _buildMacPanel(context);
    return _buildLegacySheet(context);
  }

  // ---- macOS panel -------------------------------------------------------

  Widget _buildMacPanel(BuildContext context) {
    final model = AppModelProvider.of(context);
    final queue = model.queue;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.72),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                width: 0.5,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _macHeader(context, queue.length),
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Flexible(child: _macList(context, model, queue)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Toolbar-like header: system semibold title, quiet count, compact search.
  Widget _macHeader(BuildContext context, int count) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
      child: Row(
        children: [
          const Text(
            'Tracklist',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text('$count', style: TextStyle(fontSize: 12, color: secondary)),
          const Spacer(),
          SizedBox(
            width: 200,
            height: 30,
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(fontSize: 13),
              cursorHeight: 14,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Buscar',
                hintStyle: TextStyle(fontSize: 13, color: secondary),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Icon(
                    CupertinoIcons.search,
                    size: 14,
                    color: secondary,
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 26,
                  minHeight: 30,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : GestureDetector(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 14,
                            color: secondary,
                          ),
                        ),
                      ),
                suffixIconConstraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 30,
                ),
                filled: true,
                fillColor: scheme.onSurface.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: scheme.primary.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macList(BuildContext context, AppModel model, List<Track> queue) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    final visible = _visible(model);
    if (queue.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'La cola está vacía',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ),
      );
    }
    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Sin coincidencias en la cola',
            style: TextStyle(fontSize: 13, color: secondary),
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      itemCount: visible.length,
      onReorderItem: _onReorder,
      itemBuilder: (context, index) {
        final track = visible[index];
        return _MacTrackRow(
          key: ValueKey('${track.id}-$index'),
          track: track,
          index: index,
          isCurrent: track.id == model.currentTrack?.id,
          playing: model.isPlaying,
          onTap: () async {
            final idx = model.queue.indexWhere((t) => t.id == track.id);
            if (idx >= 0) await model.playAtIndex(idx);
          },
        );
      },
    );
  }

  // ---- legacy Material sheet (other platforms, untouched) ----------------

  Widget _buildLegacySheet(BuildContext context) {
    final model = AppModelProvider.of(context);
    final queue = model.queue;
    final currentId = model.currentTrack?.id;
    final visible = _visible(model);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Tracklist',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '${queue.length}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AppSearchField(
                controller: _searchController,
                onSearch: () {},
                onChanged: (v) => setState(() => _query = v),
                hint: 'Buscar en la cola',
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: queue.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'La cola está vacía',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    )
                  : visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Sin coincidencias en la cola',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      shrinkWrap: true,
                      buildDefaultDragHandles: false,
                      itemCount: visible.length,
                      onReorderItem: _onReorder,
                      itemBuilder: (context, index) {
                        final track = visible[index];
                        final isCurrent = track.id == currentId;
                        return ListTile(
                          key: ValueKey('${track.id}-$index'),
                          dense: true,
                          leading: isCurrent
                              ? SizedBox(
                                  width: 20,
                                  child: Center(
                                    child: MiniEqualizer(
                                      active:
                                          isCurrent && model.isPlaying,
                                    ),
                                  ),
                                )
                              : SizedBox(
                                  width: 20,
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.5),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: track.artist != null
                              ? Text(
                                  track.artist!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                )
                              : null,
                          onTap: () async {
                            final idx = model.queue.indexWhere(
                              (t) => t.id == track.id,
                            );
                            if (idx >= 0) await model.playAtIndex(idx);
                          },
                          trailing: ReorderableDragStartListener(
                            index: index,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: ReorderGrip(),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final model = AppModelProvider.of(context);
    final queue = model.queue;
    final visible = _visible(model);
    if (visible.isEmpty || oldIndex < 0 || oldIndex >= visible.length) return;
    if (newIndex > visible.length) newIndex = visible.length;

    // onReorderItem already adjusts newIndex, so the handler is simply
    // removeAt(oldIndex) + insert(newIndex). Compute the intended final
    // order of the visible (filtered) list.
    final dragged = visible[oldIndex];
    final finalPos = newIndex.clamp(0, visible.length);
    if (oldIndex == finalPos) return;

    final finalVisible = List.of(visible)
      ..removeAt(oldIndex)
      ..insert(finalPos, dragged);

    // Reduce the full queue by the dragged item, then re-insert it right
    // before its new successor (or at the end if it has none).
    final reduced = queue.where((t) => t.id != dragged.id).toList();
    final oldFullIdx = queue.indexWhere((t) => t.id == dragged.id);
    final successor = finalPos + 1 < finalVisible.length
        ? finalVisible[finalPos + 1]
        : null;

    final int insertIdx;
    if (successor != null) {
      insertIdx = reduced.indexWhere((t) => t.id == successor.id);
    } else {
      insertIdx = reduced.length;
    }
    if (insertIdx < 0) return;

    await model.reorderQueue(oldFullIdx, insertIdx);
  }
}

/// macOS-native queue row: compact system-type row, secondary track number,
/// hover-only drag handle. Tap plays the track at its queue position.
class _MacTrackRow extends StatefulWidget {
  const _MacTrackRow({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.playing,
    required this.onTap,
  });

  final Track track;
  final int index;
  final bool isCurrent;
  final bool playing;
  final Future<void> Function() onTap;

  @override
  State<_MacTrackRow> createState() => _MacTrackRowState();
}

class _MacTrackRowState extends State<_MacTrackRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurface.withValues(alpha: 0.55);
    // En táctil (iOS) no hay hover: el grip de arrastre siempre visible
    // para que reordenar sea descubrible.
    final showGrip = _hovered || !isMacOSPlatform;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: widget.isCurrent
                ? scheme.primary.withValues(alpha: 0.12)
                : _hovered
                ? scheme.onSurface.withValues(alpha: 0.05)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: widget.isCurrent
                    ? Center(child: MiniEqualizer(active: widget.playing))
                    : Text(
                        '${widget.index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: secondary),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: widget.isCurrent
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    if (widget.track.artist != null)
                      Text(
                        widget.track.artist!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: secondary),
                      ),
                  ],
                ),
              ),
              // En táctil (iOS) no hay hover: el grip de arrastre siempre
              // visible para que reordenar sea descubrible.
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: showGrip ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !showGrip,
                  child: ReorderableDragStartListener(
                    index: widget.index,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: ReorderGrip(
                        size: const Size(10, 14),
                        color: secondary.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showQueueSheet(BuildContext context) {
  if (isMacOSPlatform || isIOSPlatform) return showMacTracklist(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const QueueSheet(),
  );
}

/// macOS presentation: centered floating panel with a soft spring-ish
/// fade+scale entrance instead of a bottom sheet.
Future<void> showMacTracklist(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar Tracklist',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: Padding(
          padding: EdgeInsets.all(24),
          child: QueueSheet(),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
