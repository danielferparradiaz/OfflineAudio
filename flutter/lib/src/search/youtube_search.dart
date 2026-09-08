import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// One YouTube hit shown in the library search results.
class SearchResult {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final String url;

  const SearchResult({
    required this.id,
    required this.title,
    required this.author,
    required this.duration,
    required this.thumbnailUrl,
    required this.url,
  });
}

/// Thin, swappable wrapper around `youtube_explode_dart`.
///
/// Deliberately decoupled from the download engine: search lives here and
/// downloads go through the Rust engine by URL. If the YouTube parsing shape
/// ever breaks, only this file needs to be replaced — the UI and engine stay
/// untouched.
class YoutubeSearch {
  static final YoutubeExplode _yt = YoutubeExplode();

  static Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final videos = await _yt.search.search(trimmed);
    return videos
        .map(
          (v) => SearchResult(
            id: v.id.toString(),
            title: v.title,
            author: v.author,
            duration: v.duration,
            thumbnailUrl: v.thumbnails.highResUrl,
            url: v.url,
          ),
        )
        .toList();
  }
}