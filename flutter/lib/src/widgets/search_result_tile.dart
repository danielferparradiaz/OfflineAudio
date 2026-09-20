import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/search/youtube_search.dart';
import 'package:offline_audio_app/src/utils/format.dart';

/// A single YouTube search result row: thumbnail, title, author/duration
/// and a trailing "more" button with preview/download actions.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.result,
    required this.onTap,
    required this.onActions,
    this.loading = false,
  });

  final SearchResult result;
  final VoidCallback onTap;
  final VoidCallback onActions;

  /// El avance de esta fila se está resolviendo: se muestra un spinner en
  /// vez del botón de opciones para que la espera sea visible.
  final bool loading;

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
          errorBuilder: (_, error, stack) => const SizedBox(
            width: 56,
            height: 56,
            child: ColoredBox(
              color: Color(0xFF2A2A2A),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedFilm01,
                color: Colors.white54,
              ),
            ),
          ),
        ),
      ),
      title: Text(result.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [result.author, if (duration != null) fmtLength(duration)].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: loading
          ? const SizedBox(
              width: 48,
              height: 48,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
              tooltip: 'Ver y descargar',
              onPressed: onActions,
            ),
    );
  }
}
