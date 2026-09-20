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

/// Metadatos de un vídeo de YouTube (para tareas de descarga en iOS, donde
/// no hay motor que sondee con yt-dlp).
class VideoInfo {
  final String id;
  final String title;
  final String author;
  final Duration? duration;
  final String thumbnailUrl;
  final String url;

  const VideoInfo({
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
        '[YoutubeSearch] raw videos=${videos.length} en ${sw.elapsedMilliseconds}ms',
      );
      final out = <SearchResult>[];
      for (var i = 0; i < videos.length; i++) {
        try {
          final v = videos[i];
          out.add(
            SearchResult(
              id: v.id.toString(),
              title: v.title,
              author: v.author,
              duration: v.duration,
              thumbnailUrl: v.thumbnails.highResUrl,
              url: v.url,
            ),
          );
        } catch (e, st) {
          debugPrint('[YoutubeSearch] salto item $i por error: $e\n$st');
        }
      }
      sw.stop();
      debugPrint(
        '[YoutubeSearch] done query="$trimmed" mapeados=${out.length}/${videos.length} en ${sw.elapsedMilliseconds}ms',
      );
      if (out.isNotEmpty) {
        debugPrint(
          '[YoutubeSearch] primero: "${out.first.title}" · ${out.first.author}',
        );
      }
      return out;
    } catch (e, st) {
      sw.stop();
      debugPrint(
        '[YoutubeSearch] ERROR query="$trimmed" tras ${sw.elapsedMilliseconds}ms: $e\n$st',
      );
      rethrow;
    }
  }

  /// Manifest con dos caminos: rápido (client `androidSdkless` sin watch
  /// page, medido ~300ms; sin PO-token, el `android` clásico dispara el
  /// reto "Sign in to confirm you're not a bot" en muchos vídeos) y
  /// completo (por si el vídeo necesita descifrado con watch page).
  /// Devuelve `null` si ese intento no rinde streams.
  static Future<StreamManifest?> _streamManifest(
    String videoId, {
    required bool fast,
  }) async {
    try {
      final manifest = fast
          ? await _yt.videos.streams
              .getManifest(
                videoId,
                ytClients: [YoutubeApiClient.androidSdkless],
                requireWatchPage: false,
              )
              .timeout(const Duration(seconds: 8))
          : await _yt.videos.streams
              .getManifest(videoId)
              .timeout(const Duration(seconds: 15));
      return manifest.muxed.isEmpty &&
              manifest.audioOnly.isEmpty &&
              manifest.hls.isEmpty
          ? null
          : manifest;
    } catch (e) {
      debugPrint('[YoutubeSearch] manifest ${fast ? 'rápido' : 'completo'} '
          'id=$videoId falló: $e');
      return null;
    }
  }

  /// Candidatos de AUDIO de un manifest en orden de compatibilidad con
  /// AVPlayer (iOS): muxed progresivo → audioOnly en mp4 (m4a/AAC) → HLS
  /// (muxed/audio, nunca video-only: sonaría a silencio). webm/opus queda
  /// fuera: AVPlayer no lo decodifica.
  static List<StreamInfo> _audioCandidates(StreamManifest m, {required bool withHls}) {
    final out = <StreamInfo>[];
    if (m.muxed.isNotEmpty) out.add(m.muxed.withHighestBitrate());
    final m4a = m.audioOnly
        .where((s) => s.container == StreamContainer.mp4)
        .toList(growable: false);
    if (m4a.isNotEmpty) out.add(m4a.withHighestBitrate());
    if (withHls) {
      final hls = m.hls
          .where((s) => s is HlsMuxedStreamInfo || s is HlsAudioStreamInfo)
          .toList(growable: false);
      if (hls.isNotEmpty) out.add(hls.withHighestBitrate());
    }
    return out;
  }

  /// Candidatos de VÍDEO: muxed progresivo primero, HLS muxed (con audio)
  /// como respaldo (video_player/AVPlayer reproduce m3u8 de forma nativa).
  static List<StreamInfo> _videoCandidates(StreamManifest m, {required bool withHls}) {
    final out = <StreamInfo>[];
    if (m.muxed.isNotEmpty) out.add(m.muxed.withHighestBitrate());
    if (withHls) {
      final hls = m.hls.whereType<HlsMuxedStreamInfo>().toList(growable: false);
      if (hls.isNotEmpty) out.add(hls.withHighestBitrate());
    }
    return out;
  }

  /// Resuelve la primera URL disponible probando el manifest rápido y, si
  /// no rinde nada reproducible, el camino completo (con HLS incluido).
  /// Devuelve el texto del stream elegido para la traza.
  static Future<String> _previewUrlFromCandidates(
    String videoId, {
    required bool video,
    required String kind,
  }) async {
    final sw = Stopwatch()..start();
    debugPrint('[YoutubeSearch] manifest $kind id=$videoId');
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final fast = attempt == 0;
      final manifest = await _streamManifest(videoId, fast: fast);
      if (manifest == null) continue;
      try {
        final candidates = video
            ? _videoCandidates(manifest, withHls: !fast)
            : _audioCandidates(manifest, withHls: !fast);
        if (candidates.isEmpty) continue;
        final s = candidates.first;
        debugPrint(
          '[YoutubeSearch] $kind listo (${s.container}) id=$videoId '
          'host=${s.url.host} en ${sw.elapsedMilliseconds}ms',
        );
        return s.url.toString();
      } catch (e) {
        lastError = e;
        debugPrint('[YoutubeSearch] $kind intento ${attempt + 1} falló: $e');
      }
    }
    throw lastError ??
        StateError(
          video ? 'Sin streams de vídeo para $videoId' : 'Sin streams reproducibles para $videoId',
        );
  }

  /// URL directa para el avance de escucha.
  ///
  /// En iOS es la ÚNICA vía (sin motor yt-dlp por el sandbox) y el reproductor
  /// es AVPlayer: reproduce mp4/m4a y HLS, pero no webm/opus. La cadena de
  /// candidatos ([_audioCandidates]) baja de muxed progresivo a audioOnly
  /// m4a y a HLS para cubrir los vídeos que ya no exponen streams muxados.
  static Future<String> audioPreviewUrl(String videoId) =>
      _previewUrlFromCandidates(videoId, video: false, kind: 'audio');

  /// URL directa del mejor stream para previsualizar antes de descargar.
  /// Misma estrategia que el audio: manifest rápido primero, completo
  /// (con HLS de respaldo) después.
  static Future<String> videoPreviewUrl(String videoId) =>
      _previewUrlFromCandidates(videoId, video: true, kind: 'vídeo');

  /// Metadatos del vídeo (título, autor, duración) para tareas de descarga.
  /// Acepta ID o URL (watch, youtu.be, shorts, live).
  static Future<VideoInfo> videoInfo(String videoIdOrUrl) async {
    final id = VideoId(videoIdOrUrl);
    final v = await _yt.videos.get(id).timeout(const Duration(seconds: 15));
    return VideoInfo(
      id: id.value,
      title: v.title,
      author: v.author,
      duration: v.duration,
      thumbnailUrl: v.thumbnails.highResUrl,
      url: 'https://www.youtube.com/watch?v=${id.value}',
    );
  }

  /// Mejor URL para DESCARGAR el stream como archivo único.
  ///
  /// OJO: los streams audioOnly (rqh=1) están capados a ~1 MiB por HTTP
  /// plano; los muxed progresivos (itag 18/22) llevan `ratebypass=yes`
  /// firmado y se bajan COMPLETOS con un GET simple — probado 200 en 17 MB.
  /// Devuelve la URL y la extensión correcta del contenedor; `null` si no
  /// hay nada descargable.
  static Future<(String url, String ext)?> bestDownloadUrl(
    String videoIdOrUrl, {
    required bool audioOnly,
  }) async {
    final id = VideoId(videoIdOrUrl);
    for (var attempt = 0; attempt < 2; attempt++) {
      final manifest = await _streamManifest(id.value, fast: attempt == 0);
      if (manifest == null) continue;
      if (audioOnly) {
        final m4a = manifest.audioOnly
            .where((s) => s.container == StreamContainer.mp4)
            .toList(growable: false);
        if (m4a.isNotEmpty) {
          final s = m4a.withHighestBitrate();
          debugPrint('[YoutubeSearch] descarga m4a id=${id.value} '
              'host=${s.url.host} kbps=${s.bitrate.kiloBitsPerSecond}');
          return (s.url.toString(), 'm4a');
        }
      }
      if (manifest.muxed.isNotEmpty) {
        final s = manifest.muxed.withHighestBitrate();
        debugPrint('[YoutubeSearch] descarga muxed id=${id.value} '
            'host=${s.url.host} kbps=${s.bitrate.kiloBitsPerSecond}');
        return (s.url.toString(), 'mp4');
      }
    }
    return null;
  }

  /// YouTube search autocomplete predictions for the given partial query.
  static Future<List<String>> getQuerySuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    try {
      return await _yt.search
          .getQuerySuggestions(trimmed)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[YoutubeSearch] suggestions error: $e');
      return const [];
    }
  }
}
