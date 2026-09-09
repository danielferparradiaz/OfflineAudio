import 'package:flutter/foundation.dart';
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

  /// Busca en YouTube y deja traza en consola para auditar el flujo.
  ///
  /// Filtra con `flutter run` (o `adb logcat`) por `[YoutubeSearch]`:
  /// verás inicio, nº de vídeos crudos, nº mapeados y cualquier error con
  /// su stacktrace. El mapeo es defensivo: si un item falla se salta y se
  /// registra, en vez de tumbar toda la búsqueda.
  static Future<List<SearchResult>> search(String query) async {
    final trimmed = query.trim();
    debugPrint('[YoutubeSearch] start query="$trimmed"');
    if (trimmed.isEmpty) {
      debugPrint('[YoutubeSearch] empty query -> 0 resultados');
      return const [];
    }
    final sw = Stopwatch()..start();
    try {
      final videos = await _yt.search
          .search(trimmed)
          .timeout(const Duration(seconds: 25));
      debugPrint(
          '[YoutubeSearch] raw videos=${videos.length} en ${sw.elapsedMilliseconds}ms');
      final out = <SearchResult>[];
      for (var i = 0; i < videos.length; i++) {
        try {
          final v = videos[i];
          out.add(SearchResult(
            id: v.id.toString(),
            title: v.title,
            author: v.author,
            duration: v.duration,
            thumbnailUrl: v.thumbnails.highResUrl,
            url: v.url,
          ));
        } catch (e, st) {
          debugPrint('[YoutubeSearch] salto item $i por error: $e\n$st');
        }
      }
      sw.stop();
      debugPrint(
          '[YoutubeSearch] done query="$trimmed" mapeados=${out.length}/${videos.length} en ${sw.elapsedMilliseconds}ms');
      if (out.isNotEmpty) {
        debugPrint(
            '[YoutubeSearch] primero: "${out.first.title}" · ${out.first.author}');
      }
      return out;
    } catch (e, st) {
      sw.stop();
      debugPrint(
          '[YoutubeSearch] ERROR query="$trimmed" tras ${sw.elapsedMilliseconds}ms: $e\n$st');
      rethrow;
    }
  }

  /// URL directa para el avance de escucha.
  ///
  /// Los streams `audioOnly` de YouTube son DASH fragmentados: libmpv/media_kit
  /// no puede reproducirlos con su URL simple (por eso el avance no sonaba).
  /// Usamos `muxed`, que es progresivo y sí reproduce; como este avance no
  /// empuja la pantalla de vídeo, solo se oye el audio.
  static Future<String> audioPreviewUrl(String videoId) async {
    debugPrint('[YoutubeSearch] manifest audio id=$videoId');
    final manifest = await _yt.videos.streams
        .getManifest(videoId)
        .timeout(const Duration(seconds: 25));
    final muxed = manifest.muxed;
    if (muxed.isEmpty) {
      throw StateError('Sin streams reproducibles para $videoId');
    }
    final s = muxed.withHighestBitrate();
    debugPrint('[YoutubeSearch] audio listo (muxed) id=$videoId '
        'host=${s.url.host}');
    return s.url.toString();
  }

  /// URL directa del mejor stream muxado (audio+vídeo, 360p máx — vale para
  /// previsualizar antes de descargar).
  static Future<String> videoPreviewUrl(String videoId) async {
    debugPrint('[YoutubeSearch] manifest vídeo id=$videoId');
    final manifest = await _yt.videos.streams
        .getManifest(videoId)
        .timeout(const Duration(seconds: 25));
    final muxed = manifest.muxed;
    if (muxed.isEmpty) {
      throw StateError('Sin streams de vídeo para $videoId');
    }
    final s = muxed.withHighestBitrate();
    debugPrint('[YoutubeSearch] vídeo listo id=$videoId host=${s.url.host}');
    return s.url.toString();
  }
}