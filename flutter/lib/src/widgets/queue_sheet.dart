import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

/// Modal sheet that shows the current playback queue with live search
/// filtering and drag-to-reorder. Presented as a Material bottom sheet so it
/// never takes the full screen.
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
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'La cola está vacía',
                          style: TextStyle(color: Colors.white54),
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
                              ? const HugeIcon(
                                  icon: HugeIcons.strokeRoundedAudioWave01,
                                  color: Colors.amber,
                                  size: 20,
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
                              child: HugeIcon(
                                icon: HugeIcons.strokeRoundedMenu01,
                                color: Colors.white38,
                              ),
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

void showQueueSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => const QueueSheet(),
  );
}
