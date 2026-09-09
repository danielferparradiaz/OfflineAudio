import 'package:flutter/material.dart';
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
          errorBuilder: (_, error, stack) => const SizedBox(
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
          if (duration != null) fmtLength(duration),
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
