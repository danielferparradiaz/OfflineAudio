import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart' as ja;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';
import 'package:offline_audio_app/src/playback/mixer.dart';
import 'package:offline_audio_app/src/playback/smart_shuffle.dart';
import 'package:offline_audio_app/src/download/android_downloader.dart';
import 'package:offline_audio_app/src/search/youtube_search.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/events.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/rust/frb_generated.dart';

/// Rich progress state for one active download task.
/// `percent` comes from Rust as 0..100.
class DownloadState {
  final double percent;
  final BigInt downloadedBytes;
  final BigInt? totalBytes;
  final BigInt? speedBytesSec;
  final BigInt? etaSecs;

  const DownloadState({
    required this.percent,
    required this.downloadedBytes,
    this.totalBytes,
    this.speedBytesSec,
    this.etaSecs,
  });

  double get fraction => (percent / 100.0).clamp(0.0, 1.0);
}

/// Central app state: subscribes to the Rust engine event stream and lets the
/// UI observe changes (@see [ChangeNotifier]).
class AppModel extends ChangeNotifier {
  final List<Track> _library = [];
  final Map<String, DownloadState> _downloads = {};
  final Map<String, String> _downloadErrors = {};

  /// Título por taskId (se llena tras el sondeo de metadatos).
  final Map<String, String> _downloadTitles = {};
  final Map<String, Track> _completed = {};
  final List<Playlist> _playlists = [];

  StreamSubscription<Event>? _eventSub;
  StreamSubscription<AndroidDownloadProgress>? _androidProgressSub;

  String? _lastInfo;
  String? _lastYtdlpMessage;

  mk.Player? _player;
  bool _playerSubscribed = false;

  // Standby player: only alive with audio loaded DURING a crossfade
  // (song B enters while song A still sounds). Outside transitions there is
  // a single decoding player to save CPU/battery.
  mk.Player? _standby;
  bool _standbySubscribed = false;

  // Mixer (DJ-style crossfade, always on): song B enters while song A
  // still sounds, overlapping the last [kMixCrossfadeSeconds].
  Timer? _mixRamp;
  _MixTransition? _mixTransition;

  /// Track id already counted as a full listen (expert shuffle stats).
  String? _completedRecordedFor;

  /// True while two players overlap (crossfade running).
  bool get isCrossfading => _mixTransition != null;

  // Playback position tracking (P3).
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  Track? _currentTrack;
  List<Track> _queue = [];
  bool _playingPlaylist = false;

  /// True while the "random playlist based on library" shuffle session is
  /// active; la player bar muestra "Ver lista" para cualquier sesión de
  /// lista (aleatoria o creada por el usuario, @see [isPlayingPlaylist]).
  bool _shuffleSession = false;

  Track? get currentTrack => _currentTrack;

  // Avance de un resultado de búsqueda (stream remoto, fuera de la
  // biblioteca y sin estadísticas).
  String? _previewId;
  String? _previewTitle;
  String? _previewArtist;
  String? _previewUrl;
  bool _previewVideo = false;

  /// Último error de dispositivo de audio de mpv ("Could not
  /// open/initialize audio device"): el stream abre pero no suena. Se
  /// expone para avisarlo una vez en la UI en vez de fallar en silencio.
  String? _audioDeviceError;
  String? get audioDeviceError => _audioDeviceError;
  void consumeAudioDeviceError() {
    _audioDeviceError = null;
    notifyListeners();
  }

  bool get isPreview => _previewId != null;
  String? get previewId => _previewId;
  String? get previewTitle => _previewTitle;
  String? get previewArtist => _previewArtist;
  String? get previewUrl => _previewUrl;
  bool get isPreviewVideo => isPreview && _previewVideo;

  void _clearPreview() {
    _previewId = null;
    _previewTitle = null;
    _previewArtist = null;
    _previewUrl = null;
    _previewVideo = false;
    _previewFirstTickLogged = false;
    _nativeVideoPauseToggle = null;
    _nativeVideoSeek = null;
    _nativeLibraryActive = false;
    unawaited(_nativePreview?.stop());
  }

  /// Marca de log: primera vez que el cabezal del avance se mueve
  /// (distingue "abrió pero no avanza" de "avanza pero no suena").
  bool _previewFirstTickLogged = false;

  mk.Player? get player => _player;

  /// Whether the current track is a downloaded video (MP4), so the UI can
  /// offer the fullscreen video player.
  bool get isCurrentVideo => _currentTrack?.contentKind == 'video';

  /// Download any supported URL directly, bypassing the probe flow of the
  /// settings screen. `kind` selects an audio (music/speech) vs video task.
  Future<String> downloadFromUrl(
    String url, {
    ContentKind kind = ContentKind.music,
  }) async {
    if (Platform.isIOS) {
      // Sandbox de Apple: sin yt-dlp/ffmpeg CLI. Se resuelve el stream con
      // youtube_explode y se baja por HTTPS directo (ver _runIosDownload).
      final taskId = 'ios_${DateTime.now().microsecondsSinceEpoch}';
      _downloads[taskId] = DownloadState(
        percent: 0,
        downloadedBytes: BigInt.zero,
      );
      notifyListeners();
      unawaited(_runIosDownload(taskId, url, kind));
      return taskId;
    }
    if (!Platform.isAndroid) {
      return startDownload(url: url, kind: kind);
    }
    final taskId = 'android_${DateTime.now().microsecondsSinceEpoch}';
    _downloads[taskId] = DownloadState(
      percent: 0,
      downloadedBytes: BigInt.zero,
    );
    notifyListeners();
    unawaited(_runAndroidDownload(taskId, url, kind));
    return taskId;
  }

  AppModel();

  List<Track> get library => List.unmodifiable(_library);

  Map<String, DownloadState> get downloads => Map.unmodifiable(_downloads);

  /// Backwards-compat for existing callers: taskId -> percent 0..100.
  Map<String, double> get downloadProgress => Map.unmodifiable({
    for (final e in _downloads.entries) e.key: e.value.percent,
  });

  Map<String, String> get downloadErrors => Map.unmodifiable(_downloadErrors);

  /// Título conocido de cada tarea de descarga (tras el sondeo). Para las
  /// tarjetas de progreso/error: el id crudo no le dice nada al usuario.
  String? downloadTitle(String taskId) => _downloadTitles[taskId];

  /// Finished downloads kept visible until the user dismisses them.
  Map<String, Track> get completed => Map.unmodifiable(_completed);

  List<Playlist> get playlists => List.unmodifiable(_playlists);

  bool get hasActiveDownloads => _downloads.isNotEmpty;

  String? get lastInfo => _lastInfo;
  String? get lastYtdlpMessage => _lastYtdlpMessage;

  Duration get position => _position;
  Duration get duration => _duration;

  void consumeInfo() {
    _lastInfo = null;
    _lastYtdlpMessage = null;
    notifyListeners();
  }

  void clearDownloadError(String taskId) {
    _downloadErrors.remove(taskId);
    notifyListeners();
  }

  /// Dismiss a completed download card from the downloads screen.
  void clearCompleted(String taskId) {
    _completed.remove(taskId);
    notifyListeners();
  }

  /// Initialize Rust: engine + event stream + media_kit.
  Future<void> init() async {
    await RustLib.init();
    // En móvil `dirs::config_dir()` no existe: se pasa el directorio privado
    // de la app antes de arrancar el motor.
    if (Platform.isAndroid || Platform.isIOS) {
      final support = await getApplicationSupportDirectory();
      await setAppDir(path: support.path);
    }
    await initApp();
    mk.MediaKit.ensureInitialized();

    // Configure YouTube cookies browser for yt-dlp extraction.
    // Solo como default de instalación nueva: no se pisa la elección del
    // usuario (en iOS yt-dlp no corre y el valor es irrelevante para los
    // avances; en escritorio 'chrome' genera PO-token sin cuenta real).
    final cookiesBrowser = await getSetting(key: 'ytdlp.cookies_browser');
    if (cookiesBrowser == null || cookiesBrowser.isEmpty) {
      await setSetting(key: 'ytdlp.cookies_browser', value: 'chrome');
    }

    // Subscribe to the engine event stream.
    _subscribeEvents();
    if (Platform.isAndroid) _subscribeAndroidProgress();

    // Kick off the yt-dlp version check (runs on the Rust side too, but
    // surfacing status here keeps the UI responsive).
    checkYtdlp();

    await reloadLibrary();
    await reloadPlaylists();
    // iOS: cada reinstalación cambia el UUID del contenedor y el sistema
    // migra los archivos, pero la DB guardó rutas absolutas del contenedor
    // anterior. Se reescriben contra el soporte vigente.
    if (Platform.isIOS) await _migrateStalePaths();
  }

  /// Reescribe las rutas absolutas que apuntan a un contenedor anterior
  /// (mismo subpath bajo "Application Support/"). Solo toca filas cuyo
  /// archivo ya no existe en la ruta guardada.
  Future<void> _migrateStalePaths() async {
    final support = (await getApplicationSupportDirectory()).path;
    const marker = 'Library/Application Support/';
    var changed = false;
    for (final t in List<Track>.from(_library)) {
      if (await File(t.filePath).exists()) continue;
      final newFile = _remapStalePath(t.filePath, support, marker);
      if (newFile == null || !await File(newFile).exists()) continue;
      String? newThumb;
      if (t.thumbnailPath != null) {
        if (await File(t.thumbnailPath!).exists()) {
          newThumb = t.thumbnailPath;
        } else {
          newThumb = _remapStalePath(t.thumbnailPath!, support, marker);
        }
      }
      final corrected = Track(
        id: t.id,
        sourceId: t.sourceId,
        networkUrl: t.networkUrl,
        title: t.title,
        artist: t.artist,
        album: t.album,
        durationSeconds: t.durationSeconds,
        filePath: newFile,
        thumbnailPath: newThumb,
        platform: t.platform,
        contentKind: t.contentKind,
        bitrateKbps: t.bitrateKbps,
        downloadDate: t.downloadDate,
        playCount: t.playCount,
        lastPlayed: t.lastPlayed,
        completedCount: t.completedCount,
        totalListenSeconds: t.totalListenSeconds,
      );
      try {
        await persistExternalTrack(track: corrected);
        changed = true;
        debugPrint('[Migrate] ${t.id} -> contenedor actual');
      } catch (_) {}
    }
    if (changed) await reloadLibrary();
  }

  String? _remapStalePath(String path, String support, String marker) {
    final idx = path.indexOf(marker);
    if (idx < 0) return null;
    return '$support/${path.substring(idx + marker.length)}';
  }

  /// Resuelve la ruta real de un archivo local: si la guardada no existe
  /// (contenedor cambiado) intenta remapearla al soporte vigente.
  Future<String> _resolveLocalPath(String path) async {
    if (await File(path).exists()) return path;
    final support = (await getApplicationSupportDirectory()).path;
    const marker = 'Library/Application Support/';
    final fixed = _remapStalePath(path, support, marker);
    if (fixed != null && await File(fixed).exists()) return fixed;
    return path;
  }

  /// Subscribe to engine events. The FRB stream is single-subscription: if it
  /// ever errors (e.g. a decode failure) Dart cancels it silently, so we
  /// attach `onError` and re-subscribe to never lose updates permanently.
  void _subscribeEvents() {
    _eventSub?.cancel();
    _eventSub = eventStream().listen(
      _onEvent,
      onError: (Object e) {
        _lastInfo = 'Error en el flujo de eventos: $e';
        notifyListeners();
        _subscribeEvents();
      },
    );
  }

  /// Progreso de las descargas nativas iOS (AVAssetDownloadTask). El
  /// porcentaje viene por tiempo de medio cargado, no por bytes.
  void _subscribeAndroidProgress() {
    _androidProgressSub?.cancel();
    _androidProgressSub = AndroidDownloader.progress.listen((progress) {
      final current = _downloads[progress.taskId];
      if (current == null) return;
      _downloads[progress.taskId] = DownloadState(
        percent: progress.percent,
        downloadedBytes: current.downloadedBytes,
        totalBytes: current.totalBytes,
        speedBytesSec: current.speedBytesSec,
        etaSecs: progress.etaSeconds == null
            ? null
            : BigInt.from(progress.etaSeconds!),
      );
      notifyListeners();
    });
  }

  /// HTTP clients de las tareas iOS activas: cancelar = cerrar el cliente.
  final Map<String, http.Client> _iosClients = {};

  /// Tareas iOS canceladas por el usuario (para no reportar el corte como
  /// error de red cuando el stream se interrumpe).
  final Set<String> _iosCancelled = {};

  Future<void> _runIosDownload(
    String taskId,
    String url,
    ContentKind kind,
  ) async {
    // Ruta del archivo en curso: se borra si la tarea se cancela o falla
    // (no dejar metadatos corruptos en la caché).
    String? partial;
    String? thumbPartial;
    try {
      final dirs = await appDirs();
      final info = await YoutubeSearch.videoInfo(url);
      _downloadTitles[taskId] = info.title;
      notifyListeners();
      final sourceId = 'youtube:${info.id}';
      if (_library.any((track) => track.sourceId == sourceId)) {
        _downloads.remove(taskId);
        _lastInfo = 'Ya en biblioteca: ${info.title}';
        notifyListeners();
        return;
      }

      // SIEMPRE muxed (para audio y vídeo): los streams audioOnly
      // (rqh=1) están capados a ~1 MiB por HTTP plano; el muxed
      // progresivo lleva `ratebypass=yes` firmado y se baja completo con
      // un GET simple (medido 200 en 17 MB desde la app). El mp4 muxed
      // se guarda tal cual y suena igual.
      final stream = await YoutubeSearch.bestDownloadUrl(
        info.id,
        audioOnly: false,
      );
      if (stream == null) {
        throw StateError('Sin streams descargables para ${info.id}');
      }
      final (streamUrl, ext) = stream;
      final output = partial = '${dirs.cache}/$taskId.$ext';
      final headers = {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/126.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
      };

      int received;
      try {
        received = await _httpFullDownload(
          taskId: taskId,
          streamUrl: streamUrl,
          headers: headers,
          output: output,
        );
      } catch (error) {
        if (_iosCancelled.contains(taskId)) rethrow;
        // Respaldo por rangos cerrados (capado a ~1 MiB, mejor que nada).
        debugPrint('[IosDownload] GET completo falló, respaldo rangos: $error');
        received = await _httpChunkedDownload(
          taskId: taskId,
          streamUrl: streamUrl,
          headers: headers,
          output: output,
        );
      }
      _downloads[taskId] = DownloadState(
        percent: 100,
        downloadedBytes: BigInt.from(received),
      );
      notifyListeners();

      // Miniatura: googlevideo sirve la portada sin cuota ni cap, así que
      // se guarda en thumbs/ y la biblioteca la muestra como el resto.
      String? thumbnailPath;
      if (info.thumbnailUrl.isNotEmpty) {
        final thumb = thumbnailPath = '${dirs.thumbs}/$taskId.jpg';
        thumbPartial = thumb;
        try {
          final thumbRes = await http
              .get(Uri.parse(info.thumbnailUrl), headers: headers)
              .timeout(const Duration(seconds: 15));
          if (thumbRes.statusCode == 200 && thumbRes.bodyBytes.isNotEmpty) {
            await File(thumb).writeAsBytes(thumbRes.bodyBytes, flush: true);
          } else {
            thumbnailPath = null;
          }
        } catch (_) {
          thumbnailPath = null;
        }
        thumbPartial = thumbnailPath != null ? null : thumb;
      }

      final contentKind = switch (kind) {
        ContentKind.music => 'music',
        ContentKind.speech => 'speech',
        ContentKind.video => 'video',
      };
      final track = Track(
        id: taskId,
        sourceId: sourceId,
        networkUrl: info.url,
        title: info.title,
        artist: info.author,
        album: null,
        durationSeconds: info.duration?.inSeconds ?? 0,
        filePath: output,
        thumbnailPath: thumbnailPath,
        platform: 'youtube',
        contentKind: contentKind,
        // El muxed mp4 mezcla audio+vídeo: un bitrate "de audio" sería
        // engañoso, se deja sin etiqueta.
        bitrateKbps: null,
        downloadDate: DateTime.now().toUtc().toIso8601String(),
        playCount: 0,
        lastPlayed: null,
        completedCount: 0,
        totalListenSeconds: 0,
      );
      await persistExternalTrack(track: track);
      partial = null;
      _iosClients.remove(taskId);
      _downloads.remove(taskId);
      _downloadErrors.remove(taskId);
      _completed[taskId] = track;
      _lastInfo = 'Descarga completada: ${track.title}';
      notifyListeners();
      await reloadLibrary();
    } catch (error) {
      final client = _iosClients.remove(taskId);
      client?.close();
      final cancelled = _iosCancelled.remove(taskId);
      if (partial != null) {
        try {
          await File(partial).delete();
        } catch (_) {}
      }
      if (thumbPartial != null) {
        try {
          await File(thumbPartial).delete();
        } catch (_) {}
      }
      if (cancelled) {
        // Cancelado por el usuario: no es un fallo.
        return;
      }
      _downloads.remove(taskId);
      _downloadErrors[taskId] = error.toString();
      _lastInfo = 'Descarga fallida: $error';
      notifyListeners();
    }
  }

  /// GET completo (sin Range) de un stream muxed con `ratebypass=yes`:
  /// googlevideo sirve el archivo entero en una sola respuesta.
  Future<int> _httpFullDownload({
    required String taskId,
    required String streamUrl,
    required Map<String, String> headers,
    required String output,
  }) async {
    final client = _iosClients[taskId] = http.Client();
    final req = http.Request('GET', Uri.parse(streamUrl))
      ..headers.addAll(headers);
    final res = await client.send(req).timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      await res.stream.drain<void>();
      throw Exception('HTTP ${res.statusCode} al descargar el stream');
    }
    final totalBytes = res.contentLength;
    final sink = File(output).openWrite();
    var received = 0;
    var lastNotify = DateTime.now();
    try {
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        // UI: máx. ~4 refrescos/segundo para no reventar el árbol.
        if (now.difference(lastNotify).inMilliseconds >= 250) {
          lastNotify = now;
          _downloads[taskId] = DownloadState(
            percent: totalBytes != null && totalBytes > 0
                ? received * 100 / totalBytes
                : 0.0,
            downloadedBytes: BigInt.from(received),
            totalBytes: totalBytes != null ? BigInt.from(totalBytes) : null,
          );
          notifyListeners();
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return received;
  }

  /// Respaldo HTTP por rangos cerrados. googlevideo con `rqh=1` rechaza
  /// (403) un GET completo sin Range y también `bytes=0-` abierto; un
  /// rango cerrado (`bytes=0-1`) responde 206 con Content-Range. OJO: los
  /// streams sin PO-token solo sirven ~1 MiB por URL — este camino es el
  /// último recurso si el transporte nativo (AVAssetDownloadTask) no está.
  Future<int> _httpChunkedDownload({
    required String taskId,
    required String streamUrl,
    required Map<String, String> headers,
    required String output,
  }) async {
    final client = _iosClients[taskId] = http.Client();
    final probeReq = http.Request('GET', Uri.parse(streamUrl))
      ..headers.addAll({...headers, 'Range': 'bytes=0-1'});
    final probe = await client.send(probeReq).timeout(
      const Duration(seconds: 20),
    );
    final totalBytes = probe.statusCode == 206
        ? int.tryParse(
            RegExp(r'/(\d+)$')
                    .firstMatch(probe.headers['content-range'] ?? '')
                    ?.group(1) ??
                '',
          )
        : probe.contentLength;
    if (probe.statusCode != 206 && probe.statusCode != 200) {
      await probe.stream.drain<void>();
      throw Exception('HTTP ${probe.statusCode} al descargar el stream');
    }

    final sink = File(output).openWrite();
    var received = 0;
    var lastNotify = DateTime.now();

    void pushProgress() {
      final now = DateTime.now();
      // UI: máx. ~4 refrescos/segundo para no reventar el árbol.
      if (now.difference(lastNotify).inMilliseconds >= 250) {
        lastNotify = now;
        _downloads[taskId] = DownloadState(
          percent: totalBytes != null && totalBytes > 0
              ? received * 100 / totalBytes
              : 0.0,
          downloadedBytes: BigInt.from(received),
          totalBytes: totalBytes != null ? BigInt.from(totalBytes) : null,
        );
        notifyListeners();
      }
    }

    Future<void> pump(http.StreamedResponse part) async {
      // Sin drain final: el body de la respuesta es single-subscription y
      // llamar drain() tras el `await for` lanza "Stream has already been
      // listened to" (de forma síncrona, sin catchError que lo recoja).
      await for (final chunk in part.stream) {
        sink.add(chunk);
        received += chunk.length;
        pushProgress();
      }
    }

    try {
      if (probe.statusCode == 200) {
        await pump(probe);
      } else {
        // 206: descartar los 2 bytes de la sonda y bajar por rangos
        // cerrados (el abierto `bytes=0-` vuelve 403).
        await probe.stream.drain<void>();
        if (totalBytes == null) {
          throw Exception('No pude determinar el tamaño del stream');
        }
        const chunkSize = 1 << 20; // 1 MiB: límite que googlevideo sí sirve
        for (var start = 0; start < totalBytes; start += chunkSize) {
          final end = start + chunkSize <= totalBytes
              ? start + chunkSize - 1
              : totalBytes - 1;
          final partReq = http.Request('GET', Uri.parse(streamUrl))
            ..headers.addAll({...headers, 'Range': 'bytes=$start-$end'});
          final part = await client.send(partReq).timeout(
            const Duration(seconds: 30),
          );
          if (part.statusCode != 206) {
            await part.stream.drain<void>();
            throw Exception('HTTP ${part.statusCode} en rango $start-$end');
          }
          await pump(part);
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return received;
  }

  Future<void> _runAndroidDownload(
    String taskId,
    String url,
    ContentKind kind,
  ) async {
    try {
      final dirs = await appDirs();
      final probe = await AndroidDownloader.probe(url);
      _downloadTitles[taskId] = probe.title;
      notifyListeners();
      if (_library.any((track) => track.sourceId == probe.sourceId)) {
        _downloads.remove(taskId);
        _lastInfo = 'Ya en biblioteca: ${probe.title}';
        notifyListeners();
        return;
      }

      final downloaded = await AndroidDownloader.download(
        url: probe.networkUrl,
        outputDir: dirs.tmp,
        kind: kind,
        taskId: taskId,
      );
      final contentKind = switch (kind) {
        ContentKind.music => 'music',
        ContentKind.speech => 'speech',
        ContentKind.video => 'video',
      };
      final output = '${dirs.cache}/$taskId.${kind == ContentKind.video ? 'mp4' : 'opus'}';
      if (kind == ContentKind.video) {
        await File(downloaded).rename(output);
      } else {
        await AndroidDownloader.transcode(
          input: downloaded,
          output: output,
          metadata: {
            'title': probe.title,
            if (probe.artist != null) 'artist': probe.artist!,
            if (probe.album != null) 'album': probe.album!,
          },
          bitrateKbps: kind == ContentKind.speech ? 32 : 96,
        );
        await File(downloaded).delete();
      }

      // Miniatura (si el sondeo la trajo): se guarda en thumbs/ como el
      // resto del motor; si falla, la fila muestra su icono de siempre.
      String? thumbnailPath;
      if (probe.thumbnailUrl != null && probe.thumbnailUrl!.isNotEmpty) {
        final thumb = '${dirs.thumbs}/$taskId.jpg';
        try {
          final thumbRes = await http
              .get(Uri.parse(probe.thumbnailUrl!))
              .timeout(const Duration(seconds: 15));
          if (thumbRes.statusCode == 200 && thumbRes.bodyBytes.isNotEmpty) {
            await File(thumb).writeAsBytes(thumbRes.bodyBytes, flush: true);
            thumbnailPath = thumb;
          }
        } catch (_) {}
      }

      final track = Track(
        id: taskId,
        sourceId: probe.sourceId,
        networkUrl: probe.networkUrl,
        title: probe.title,
        artist: probe.artist,
        album: probe.album,
        durationSeconds: probe.durationSeconds,
        filePath: output,
        thumbnailPath: thumbnailPath,
        platform: probe.platform,
        contentKind: contentKind,
        bitrateKbps: kind == ContentKind.video
            ? null
            : (kind == ContentKind.speech ? 32 : 96),
        downloadDate: DateTime.now().toUtc().toIso8601String(),
        playCount: 0,
        lastPlayed: null,
        completedCount: 0,
        totalListenSeconds: 0,
      );
      await persistExternalTrack(track: track);
      _downloads.remove(taskId);
      _downloadErrors.remove(taskId);
      _completed[taskId] = track;
      _lastInfo = 'Descarga completada: ${track.title}';
      notifyListeners();
      await reloadLibrary();
    } catch (error) {
      _downloads.remove(taskId);
      _downloadErrors[taskId] = error.toString();
      _lastInfo = 'Descarga fallida: $error';
      notifyListeners();
    }
  }

  Future<void> cancelDownloadForTask(String taskId) async {
    if (taskId.startsWith('ios_')) {
      // iOS: la descarga es un GET en Dart; cancelar = cerrar el cliente
      // HTTP para cortar el stream.
      _iosCancelled.add(taskId);
      _iosClients.remove(taskId)?.close();
      _downloads.remove(taskId);
      notifyListeners();
      return;
    }
    if (Platform.isAndroid && taskId.startsWith('android_')) {
      await AndroidDownloader.cancel(taskId);
      _downloads.remove(taskId);
      notifyListeners();
      return;
    }
    await cancelDownload(taskId: taskId);
  }

  Future<void> reloadLibrary({
    String? search,
    SortOrder order = SortOrder.dateDesc,
  }) async {
    final tracks = await getLibrary(search: search, order: order);
    _library
      ..clear()
      ..addAll(tracks);
    notifyListeners();
  }

  Future<void> reloadPlaylists() async {
    final lists = await listPlaylists();
    _playlists
      ..clear()
      ..addAll(lists);
    notifyListeners();
  }

  void _onEvent(Event ev) {
    switch (ev) {
      case Event_DownloadProgress(
        :final taskId,
        :final percent,
        :final downloadedBytes,
        :final totalBytes,
        :final speedBytesSec,
        :final etaSecs,
      ):
        _downloads[taskId] = DownloadState(
          percent: percent,
          downloadedBytes: downloadedBytes,
          totalBytes: totalBytes,
          speedBytesSec: speedBytesSec,
          etaSecs: etaSecs,
        );
        _downloadErrors.remove(taskId);
      case Event_DownloadFinished(:final taskId, :final track):
        _downloads.remove(taskId);
        _downloadErrors.remove(taskId);
        _completed[taskId] = track;
        _lastInfo = 'Descarga completada: ${track.title}';
        reloadLibrary();
      case Event_DownloadFailed(:final taskId, :final reason):
        _downloads.remove(taskId);
        _downloadErrors[taskId] = reason;
        _lastInfo = 'Descarga fallida: $reason';
      case Event_DownloadCancelled(:final taskId):
        _downloads.remove(taskId);
        _downloadErrors.remove(taskId);
      case Event_DownloadSkippedDuplicate(:final taskId, :final track):
        _downloads.remove(taskId);
        _downloadErrors.remove(taskId);
        _completed[taskId] = track;
        _lastInfo = 'Ya en biblioteca: ${track.title}';
        reloadLibrary();
      case Event_YtdlpStatus(:final message):
        if (message != null && message.isNotEmpty) {
          _lastYtdlpMessage = message;
        }
      case Event_Notify(:final message):
        _lastInfo = message;
      case Event_LibraryChanged():
        reloadLibrary();
        reloadPlaylists();
    }
    notifyListeners();
  }

  Future<void> _ensurePlayer() async {
    _player ??= mk.Player(configuration: _playerConfig());
    if (!_playerSubscribed) {
      _playerSubscribed = true;
      _subscribePlayer(_player!);
    }
    await _activateAudioSession();
    _ensureStandby();
  }

  /// iOS: AVAudioSession en playback y ACTIVA antes de cada `open`. La
  /// activación es asíncrona (IPC con mediaserverd) y se pierde
  /// (interrupciones, otras apps, arranque): hay que ESPERARLA, porque si
  /// mpv intenta abrir el AO antes, falla ("Could not open/initialize
  /// audio device", con playing parpadeando) aunque se active un ms después.
  Future<void> _activateAudioSession() async {
    if (!Platform.isIOS) return;
    try {
      final session = await AudioSession.instance;
      final active = await session.setActive(true);
      debugPrint('[AudioSession] setActive=$active');
    } catch (e) {
      debugPrint('[AudioSession] setActive FALLÓ: $e');
    }
  }

  mk.PlayerConfiguration _playerConfig() => const mk.PlayerConfiguration(
    vo: 'libmpv',
    protocolWhitelist: [
      'udp',
      'rtp',
      'tcp',
      'tls',
      'data',
      'file',
      'http',
      'https',
      'crypto',
    ],
  );

  /// Standby player for crossfades. Created eagerly (cheap until a media is
  /// opened) so the overlap can start without init latency; it only decodes
  /// while a transition runs.
  void _ensureStandby() {
    _standby ??= mk.Player(configuration: _playerConfig());
    if (!_standbySubscribed) {
      _standbySubscribed = true;
      _subscribePlayer(_standby!);
    }
  }

  /// Attach stream listeners to a player. Every callback ignores events from
  /// the non-active player, so swapping active/standby needs no re-subscribe.
  void _subscribePlayer(mk.Player p) {
    p.stream.playing.listen((playing) {
      if (!identical(p, _player)) return;
      _playing = playing;
      notifyListeners();
    });
    p.stream.position.listen((pos) {
      if (!identical(p, _player)) return;
      _onActivePosition(pos);
    });
    p.stream.playing.listen((playing) {
      if (!identical(p, _player) || !isPreview) return;
      debugPrint('[Preview] playing=$playing id=$_previewId');
    });
    p.stream.duration.listen((dur) {
      if (!identical(p, _player)) return;
      _duration = dur;
      notifyListeners();
    });
    // When media_kit advances inside a Playlist, keep our queue in sync
    // so the UI title and play-count stay correct.
    p.stream.playlist.listen((pl) {
      if (!identical(p, _player)) return;
      _onPlaylistIndex(pl.index);
    });
    p.stream.completed.listen((done) {
      if (!identical(p, _player)) return;
      _onActiveCompleted();
    });
    // Errores del player (403, demux, codec…): sin este log pasan en
    // silencio y un avance roto parece "reproducir sin sonido".
    p.stream.error.listen((e) {
      if (!identical(p, _player)) return;
      debugPrint('[Player] error activo: $e');
      // El dispositivo de audio no abrió: se avisa una vez en la UI.
      if (e.toString().toLowerCase().contains('audio device') &&
          _audioDeviceError == null) {
        _audioDeviceError =
            'Sin sonido: iOS no abrió el dispositivo de audio. Sube el '
            'volumen, desactiva el silencio y reintenta. En simulador, '
            'revisa la salida de audio del Mac.';
        notifyListeners();
      }
    });
  }

  void _onActivePosition(Duration pos) {
    _position = pos;
    if (isPreview && pos > Duration.zero && !_previewFirstTickLogged) {
      _previewFirstTickLogged = true;
      debugPrint('[Preview] playhead avanza id=$_previewId pos=$pos');
    }
    notifyListeners();
    _maybeRecordCompletion();
    // Crossfade trigger: B starts entering during the last seconds of A.
    if (_mixTransition != null || !_playingPlaylist || isPreview) {
      return;
    }
    if (_duration <= Duration.zero) return;
    final remaining = _duration - pos;
    if (remaining <= Duration.zero) return;
    final idx = _currentTrackIdx();
    if (idx == null || idx + 1 >= _queue.length || _queueHasVideo) return;
    final trigger = mixTriggerRemaining(hasNext: true, eligible: true);
    if (trigger == null) return;
    if (remaining <= Duration(milliseconds: (trigger * 1000).round())) {
      _beginCrossfade(idx + 1);
    }
  }

  void _onPlaylistIndex(int idx) {
    // In manual crossfade mode the queue is driven track-by-track (single
    // Media opens), so playlist-index events carry no advance.
    if (_manualAdvance) return;
    if (!_playingPlaylist || _queue.isEmpty) return;
    if (idx < 0 || idx >= _queue.length) return;
    final track = _queue[idx];
    if (_currentTrack?.id != track.id) {
      _currentTrack = track;
      notifyListeners();
      _recordPlay(track);
    }
  }

  void _onActiveCompleted() {
    // The outgoing track ended mid-transition: snap to the incoming one.
    if (_mixTransition != null) {
      _finishCrossfade();
      return;
    }
    // Manual crossfade mode has no mk.Playlist auto-advance: step over.
    if (_manualAdvance) {
      final idx = _currentTrackIdx();
      if (idx != null && idx + 1 < _queue.length) {
        unawaited(_openQueueAt(idx + 1));
      }
    }
  }

  bool get _manualAdvance => isManualQueueEligible(
    playingPlaylist: _playingPlaylist,
    queueLength: _queue.length,
    hasVideo: _queueHasVideo,
    preview: isPreview,
  );

  bool get _queueHasVideo => _queue.any((t) => t.contentKind == 'video');

  /// Open the queue item at [index], choosing single-Media (manual crossfade
  /// mode) or mk.Playlist (auto-advance) transparently.
  Future<void> _openQueueAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    // iOS: audio de biblioteca por el player nativo (mpv no suena ahí).
    if (Platform.isIOS && _queue[index].contentKind != 'video') {
      await _openNativeQueueAt(index);
      return;
    }
    await _ensurePlayer();
    _cancelTransition();
    _clearPreview();
    _currentTrack = _queue[index];
    _position = Duration.zero;
    await _player!.setVolume(100);
    if (_manualAdvance) {
      await _player!.open(mk.Media(_queue[index].filePath));
    } else {
      await _player!.open(
        mk.Playlist(_queue.map((t) => mk.Media(t.filePath)).toList()),
        play: false,
      );
      await _player!.jump(index);
      await _player!.play();
    }
    notifyListeners();
    _recordPlay(_queue[index]);
  }

  // ---- mixer transitions -------------------------------------------------

  /// Start the overlap: song B enters on the standby player at volume 0
  /// while song A keeps sounding, then both ramp with an equal-power curve.
  Future<void> _beginCrossfade(int nextIndex) async {
    if (_mixTransition != null) return;
    if (nextIndex < 0 || nextIndex >= _queue.length) return;
    _ensureStandby();
    final incoming = _standby!;
    final next = _queue[nextIndex];
    try {
      await incoming.setVolume(0);
      await incoming.open(mk.Media(next.filePath), play: false);
      await incoming.play();
    } catch (_) {
      // Standby failed: let A finish; [_onActiveCompleted] steps over.
      return;
    }
    _mixTransition = _MixTransition(
      next: next,
      t: 0,
      span: kMixCrossfadeSeconds,
      incoming: incoming,
      outgoing: _player!,
    );
    _mixRamp?.cancel();
    _mixRamp = Timer.periodic(const Duration(milliseconds: 100), _mixTick);
  }

  void _mixTick(Timer _) {
    final tr = _mixTransition;
    if (tr == null) return;
    // Freeze the ramp while paused so pause/resume feels seamless.
    if (!isPlaying) return;
    tr.t += 0.1 / tr.span;
    if (tr.t >= 1) {
      _finishCrossfade();
      return;
    }
    final g = equalPowerGains(tr.t);
    unawaited(tr.outgoing.setVolume(g.outGain * 100));
    unawaited(tr.incoming.setVolume(g.inGain * 100));
  }

  /// Snap the overlap shut: B at full volume becomes the active player, A
  /// stops and is recycled as the next standby.
  void _finishCrossfade() {
    final tr = _mixTransition;
    if (tr == null) return;
    _mixRamp?.cancel();
    _mixRamp = null;
    _mixTransition = null;
    unawaited(tr.incoming.setVolume(100));
    unawaited(tr.outgoing.stop());
    final oldActive = _player!;
    _player = _standby;
    _standby = oldActive;
    _currentTrack = tr.next;
    _position = Duration.zero;
    notifyListeners();
    _recordPlay(tr.next);
  }

  /// Cancel any running overlap and restore full volume on the active
  /// player. The standby is stopped so it decodes nothing.
  void _cancelTransition() {
    _mixRamp?.cancel();
    _mixRamp = null;
    _mixTransition = null;
    final active = _player;
    if (active != null) unawaited(active.setVolume(100));
    final standby = _standby;
    if (standby != null) {
      unawaited(standby.stop());
      unawaited(standby.setVolume(0));
    }
  }

  /// Play a single track.
  Future<void> playTrack(Track track) async {
    // iOS: mpv no abre el dispositivo de audio — la biblioteca suena por
    // AVPlayer (just_audio). Los vídeos de biblioteca van por mk aparte.
    if (Platform.isIOS && track.contentKind != 'video') {
      await _playNativeLocalTrack(track);
      return;
    }
    await _ensurePlayer();
    _cancelTransition();
    _clearPreview();
    _currentTrack = track;
    _queue = [track];
    _playingPlaylist = false;
    _shuffleSession = false;
    _position = Duration.zero;
    await _player!.open(mk.Media(track.filePath));
    notifyListeners();
    _recordPlay(track);
  }

  /// Play all tracks of a playlist in expert-shuffle order (the neglected
  /// classics first, @see [smartShuffleOrder]). The stored playlist order
  /// is untouched; only this queue is ordered.
  Future<void> playPlaylist(String playlistId) async {
    final tracks = await playlistTracks(playlistId: playlistId);
    if (tracks.isEmpty) return;
    await _ensurePlayer();
    _clearPreview();
    _queue = smartShuffleOrder(tracks);
    _playingPlaylist = true;
    _shuffleSession = false;
    await _openQueueAt(0);
  }

  /// Play the whole library in expert-shuffle order (the poker-chip button):
  /// neglected classics surface instead of a flat random.
  Future<void> shuffleLibrary() async {
    if (_library.isEmpty) return;
    final tracks = smartShuffleOrder(List<Track>.of(_library));
    await _ensurePlayer();
    _clearPreview();
    _queue = tracks;
    _playingPlaylist = true;
    _shuffleSession = true;
    await _openQueueAt(0);
  }

  /// Reproduce un avance remoto de un resultado de búsqueda: stream directo
  /// por URL (audio o vídeo muxado), sin tocar biblioteca ni estadísticas.
  /// El siguiente `playTrack`/`playPlaylist` lo reemplaza limpiamente.
  ///
  /// En iOS el audio va por AVPlayer (`just_audio`): el mpv empaquetado no
  /// logra abrir el dispositivo de audio ahí. Con `isVideo`, el player lo
  /// pone la pantalla de vídeo (`video_player`) y aquí solo queda el estado
  /// para la barra inferior. [startAt] retoma donde se dejó (vuelta desde
  /// la pantalla de vídeo).
  Future<void> playPreview({
    required String id,
    required String title,
    String? artist,
    required String url,
    bool isVideo = false,
    Duration startAt = Duration.zero,
  }) async {
    await _ensurePlayer();
    _currentTrack = null;
    _queue = [];
    _playingPlaylist = false;
    _shuffleSession = false;
    _previewId = id;
    _previewTitle = title;
    _previewArtist = artist;
    _previewUrl = url;
    _previewVideo = isVideo;
    _position = Duration.zero;
    _duration = Duration.zero;
    _cancelTransition();
    // Controles de la pantalla de vídeo iOS (los registra ella; el player
    // es suyo). Al cambiar de avance se sueltan.
    _nativeVideoPauseToggle = null;
    _nativeVideoSeek = null;
    debugPrint('[Preview] open id=$id video=$isVideo');
    if (Platform.isIOS && !isVideo) {
      try {
        await _playNativePreview(url, startAt: startAt);
      } catch (e) {
        debugPrint('[Preview] open FALLÓ id=$id: $e');
        _clearPreview();
        rethrow;
      }
      notifyListeners();
      return;
    }
    if (Platform.isIOS && isVideo) {
      // El player lo pone la pantalla (video_player): aquí solo queda el
      // estado para la barra. Abrir el mk además solo sumaría el error de
      // audio ya conocido.
      debugPrint('[Preview] open ok id=$id (player en pantalla)');
      notifyListeners();
      return;
    }
    try {
      await _player!.open(
        mk.Media(
          url,
          // googlevideo valida el UA en algunas plataformas (iOS usa el
          // transporte URLSession de mpv, más estricto): sin UA de navegador
          // responde con 403 y el avance suena a silencio.
          httpHeaders: url.startsWith('http')
              ? const {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/126.0.0.0 Safari/537.36',
                  'Referer': 'https://www.youtube.com/',
                }
              : null,
        ),
      );
      debugPrint('[Preview] open ok id=$id');
      if (Platform.isIOS) {
        // Diagnóstico: ¿qué salidas ve mpv? Lista vacía = no hay ruta de
        // audio visible para mpv aunque el sistema sí suene (Safari).
        debugPrint('[Preview] audioDevices=${_player!.state.audioDevices}');
      }
    } catch (e) {
      debugPrint('[Preview] open FALLÓ id=$id: $e');
      _clearPreview();
      rethrow;
    }
    notifyListeners();
  }

  /// Player nativo (AVPlayer) en iOS: avances de audio y —desde que se
  /// sabió que mpv no abre el dispositivo de audio ahí— TAMBIÉN los
  /// archivos de la biblioteca (canciones descargadas). Perezoso y
  /// reutilizado; `_clearPreview` lo detiene.
  ja.AudioPlayer? _nativePreview;
  StreamSubscription<Duration>? _nativePosSub;
  StreamSubscription<Duration?>? _nativeDurSub;
  StreamSubscription<bool>? _nativePlayingSub;
  StreamSubscription<ja.ProcessingState>? _nativeCompletedSub;

  /// ¿La pista local (biblioteca) suena por el player nativo? Modo
  /// exclusivo con los avances: `_clearPreview` lo apaga.
  bool _nativeLibraryActive = false;

  /// ¿El avance actual suena por el player nativo? (iOS + audio + avance).
  bool get _nativePreviewActive =>
      Platform.isIOS && isPreview && !isPreviewVideo && _nativePreview != null;

  /// ¿Una pista local de la biblioteca suena por el player nativo?
  bool get _nativeLocalActive =>
      Platform.isIOS && _nativeLibraryActive && !isPreview && _nativePreview != null;

  /// Player nativo perezoso + suscripciones compartidas entre avances y
  /// biblioteca (mismo AVPlayer, dos modos de uso).
  ja.AudioPlayer _ensureNativePlayer() {
    final p = _nativePreview ??= ja.AudioPlayer();
    if (_nativePlayingSub == null) {
      _nativePlayingSub = p.playingStream.listen((playing) {
        if (isPreviewVideo) return;
        _playing = playing;
        if (isPreview) debugPrint('[Preview] playing=$playing id=$_previewId');
        notifyListeners();
      });
      _nativePosSub = p.positionStream.listen((pos) {
        if (isPreviewVideo) return;
        _position = pos;
        if (isPreview && pos > Duration.zero && !_previewFirstTickLogged) {
          _previewFirstTickLogged = true;
          debugPrint('[Preview] playhead avanza id=$_previewId pos=$pos');
        }
        notifyListeners();
        _maybeRecordCompletion();
      });
      _nativeDurSub = p.durationStream.listen((dur) {
        if (isPreviewVideo) return;
        _duration = dur ?? Duration.zero;
        notifyListeners();
      });
      _nativeCompletedSub = p.processingStateStream.listen((state) {
        if (isPreviewVideo) return;
        if (state != ja.ProcessingState.completed) return;
        if (!isPreview && _nativeLibraryActive) {
          _onNativeLibraryCompleted();
        }
      });
    }
    return p;
  }

  /// Fin de pista local en el player nativo: avanza la cola (sin crossfade
  /// en iOS — el mpv de las transiciones tampoco suena ahí).
  void _onNativeLibraryCompleted() {
    final idx = _currentTrackIdx();
    if (idx != null && idx + 1 < _queue.length) {
      unawaited(_openQueueAt(idx + 1));
    } else {
      _playing = false;
      notifyListeners();
    }
  }

  /// Pista local de la biblioteca por AVPlayer (mpv no abre el audio en
  /// iOS). Misma semántica de estado que `playTrack` de mk.
  Future<void> _playNativeLocalTrack(Track track) async {
    _cancelTransition();
    _clearPreview();
    _currentTrack = track;
    _queue = [track];
    _playingPlaylist = false;
    _shuffleSession = false;
    await _openNativeQueueAt(0);
  }

  /// Abre la pista [index] de la cola en el player nativo y suena.
  Future<void> _openNativeQueueAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final p = _ensureNativePlayer();
    _clearPreview();
    _currentTrack = _queue[index];
    _position = Duration.zero;
    _duration = Duration.zero;
    _nativeLibraryActive = true;
    _previewFirstTickLogged = false;
    debugPrint('[Library] native open ${_queue[index].id}');
    await _activateAudioSession();
    // Completa el stop que lanzó _clearPreview sin esperar: un stop en
    // vuelo podría limpiar la fuente que setFilePath acaba de fijar.
    await p.stop();
    final filePath = await _resolveLocalPath(_queue[index].filePath);
    await p.setFilePath(filePath);
    unawaited(p.play());
    notifyListeners();
    _recordPlay(_queue[index]);
  }

  /// Pausa/reanuda y seek que la pantalla de vídeo iOS registra cuando su
  /// player (`video_player`) es el que suena. La barra inferior los usa.
  Future<void> Function()? _nativeVideoPauseToggle;
  Future<void> Function(Duration)? _nativeVideoSeek;

  /// La pantalla de vídeo iOS empuja su estado (su player es suyo) para que
  /// la barra inferior muestre progreso y play/pause reales.
  void syncNativeVideoPreview({
    required bool playing,
    required Duration position,
    required Duration? duration,
  }) {
    if (!Platform.isIOS || !isPreviewVideo) return;
    _playing = playing;
    _position = position;
    if (duration != null) _duration = duration;
    notifyListeners();
  }

  /// La pantalla de vídeo iOS registra cómo pausar/retomar y buscar en su
  /// player. Con `null` se sueltan (al cambiar de avance o cerrar).
  void setNativeVideoControls({
    Future<void> Function()? onPauseToggle,
    Future<void> Function(Duration)? onSeek,
  }) {
    _nativeVideoPauseToggle = onPauseToggle;
    _nativeVideoSeek = onSeek;
  }

  static const _previewHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  Future<void> _playNativePreview(String url, {required Duration startAt}) async {
    final p = _ensureNativePlayer();
    debugPrint('[Preview] native open id=$_previewId at=$startAt');
    final loading = p.setUrl(
      url,
      headers: url.startsWith('http') ? _previewHttpHeaders : null,
      initialPosition: startAt,
    );
    try {
      await loading.timeout(const Duration(seconds: 25));
    } on TimeoutException {
      // La carga sigue en curso: cuando esté lista, el play de abajo ya
      // la arranca. No bloqueamos al llamador (el spinner de la fila se
      // quita en cuanto esto retorna).
      debugPrint('[Preview] native open lento id=$_previewId (play en espera)');
    }
    // Un error tardío del load (p. ej. 403 tras el watchdog) no debe
    // ensuciar la zona muerta de la zona de errores de Dart.
    unawaited(loading.catchError((Object _) => null, test: (Object e) => e is Exception));
    // `play()` NO se espera: su Future completa cuando la canción TERMINA
    // o se pausa (doc de just_audio), no cuando empieza a sonar. Esperarlo
    // mantenía el spinner de la fila girando durante toda la reproducción.
    unawaited(p.play());
    debugPrint('[Preview] native open ok id=$_previewId');
  }

  void _recordPlay(Track track) {
    // fire-and-forget stats update
    recordPlay(id: track.id).then((_) {}, onError: (_) {});
  }

  /// Fire once per track when the playhead passes [kCompletionThreshold]:
  /// counts a full listen for the expert shuffle. Resets automatically on
  /// track change (first tick of the new track clears the stale id).
  void _maybeRecordCompletion() {
    final track = _currentTrack;
    if (track == null || isPreview) return;
    if (_completedRecordedFor != track.id) {
      _completedRecordedFor = null;
    }
    if (_completedRecordedFor != null) return;
    if (_duration <= Duration.zero) return;
    if (_position.inMilliseconds <
        (_duration.inMilliseconds * kCompletionThreshold).round()) {
      return;
    }
    _completedRecordedFor = track.id;
    recordPlayCompleted(
      id: track.id,
      listenedSeconds: _position.inSeconds,
    ).then((_) {}, onError: (_) {});
  }

  Future<void> togglePause() async {
    // Avance o pista local iOS por player nativo (just_audio o el
    // video_player de la pantalla de vídeo): el player mpv está parado ahí.
    if (_nativePreviewActive || _nativeLocalActive) {
      final np = _nativePreview!;
      if (np.playing) {
        await np.pause();
      } else {
        unawaited(np.play());
      }
      notifyListeners();
      return;
    }
    if (Platform.isIOS && isPreviewVideo && _nativeVideoPauseToggle != null) {
      await _nativeVideoPauseToggle!();
      return;
    }
    final p = _player;
    if (p == null) return;
    // During a crossfade both players move together so the ramp can freeze
    // and resume seamlessly.
    if (_mixTransition != null) {
      if (isPlaying) {
        await p.pause();
        await _standby?.pause();
      } else {
        await p.play();
        await _standby?.play();
      }
      notifyListeners();
      return;
    }
    if (p.state.playing) {
      await p.pause();
    } else {
      await p.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    if (_nativePreviewActive || _nativeLocalActive) {
      await _nativePreview!.seek(position);
      notifyListeners();
      return;
    }
    if (Platform.isIOS && isPreviewVideo && _nativeVideoSeek != null) {
      await _nativeVideoSeek!(position);
      return;
    }
    // A seek invalidates any pending fade/overlap: volumes back to full and
    // the trigger is recomputed from the new playhead.
    _cancelTransition();
    await _player?.seek(position);
    notifyListeners();
  }

  Future<void> skipNext() async {
    if (_manualAdvance) {
      final idx = _currentTrackIdx();
      if (idx != null && idx + 1 < _queue.length) {
        await _openQueueAt(idx + 1);
      }
      return;
    }
    // In playlist mode media_kit advances the Playlist and our
    // stream.playlist listener updates _currentTrack.
    _cancelTransition();
    await _player?.next();
    notifyListeners();
  }

  Future<void> skipPrevious() async {
    // If well into the track, restart it instead of going back.
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    if (_manualAdvance) {
      final idx = _currentTrackIdx();
      if (idx != null && idx - 1 >= 0) {
        await _openQueueAt(idx - 1);
      }
      return;
    }
    _cancelTransition();
    await _player?.previous();
    notifyListeners();
  }

  bool get isPlaying => _playing || (_player?.state.playing ?? false);

  bool get isPlayingPlaylist => _playingPlaylist;

  bool get isShuffleSession => _shuffleSession;

  List<Track> get queue => List.unmodifiable(_queue);

  /// Jump to the queue item at [index] and keep playing through the rest.
  Future<void> playAtIndex(int index) async {
    if (index < 0 || index >= _queue.length) return;
    if (_manualAdvance) {
      await _openQueueAt(index);
      return;
    }
    await _ensurePlayer();
    _cancelTransition();
    _previewId = null;
    _currentTrack = _queue[index];
    _position = Duration.zero;
    await _player!.open(
      mk.Playlist(_queue.map((t) => mk.Media(t.filePath)).toList()),
      play: false,
    );
    await _player!.jump(index);
    notifyListeners();
    _recordPlay(_queue[index]);
  }

  // ---- search history --------------------------------------------------

  Future<List<SearchHistoryEntry>> loadRecentSearches(String source) async {
    return recentSearches(source: source, limit: 20);
  }

  Future<void> saveToSearchHistory(String query, String source) async {
    await recordSearch(query: query, source: source);
  }

  Future<void> removeSearch(int id) async {
    await deleteSearch(id: id);
  }

  // ---- queue reorder ---------------------------------------------------

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex == newIndex) return;
    final q = List<Track>.from(_queue);
    final item = q.removeAt(oldIndex);
    q.insert(newIndex, item);
    _queue = q;
    // Keep current track in sync.
    final currentIndex = _currentTrackIdx();
    _currentTrack = currentIndex != null
        ? _queue[currentIndex]
        : (_queue.isEmpty ? null : _queue.first);
    // A reorder invalidates any pending overlap target: volumes back up.
    _cancelTransition();
    if (_manualAdvance) {
      // No mk.Playlist to rebuild in manual mode: the active player keeps
      // sounding and the queue order is already updated.
      notifyListeners();
      return;
    }
    // Capturamos el estado de reproducción ANTES de reconstruir el playlist:
    // `open` resetea el índice y el playhead, y no debe reiniciar la canción.
    final wasPlaying = isPlaying;
    final positionMs = _position.inMilliseconds;
    // Rebuild media_kit playlist with the new order.
    await _ensurePlayer();
    await _player!.open(
      mk.Playlist(q.map((t) => mk.Media(t.filePath)).toList()),
      play: false,
    );
    // Jump to the correct track after reordering.
    if (currentIndex != null && currentIndex < q.length) {
      await _player!.jump(currentIndex);
      _currentTrack = q[currentIndex];
    }
    // media_kit descarta los `seek` emitidos antes de tener la pista lista
    // (la canción caía a 0 y volvía a sonar desde el principio). Esperamos a
    // que se notifique la duración antes de restaurar posición y play.
    try {
      await _player!.stream.duration
          .firstWhere((d) => d > Duration.zero)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Duración desconocida (p. ej. streams): proseguimos igualmente.
    }
    if (positionMs > 0) {
      await _player!.seek(Duration(milliseconds: positionMs));
    }
    if (wasPlaying && !isPlaying) {
      await _player!.play();
    }
    notifyListeners();
  }

  int? _currentTrackIdx() {
    if (_currentTrack == null) return null;
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].id == _currentTrack!.id) return i;
    }
    return null;
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _androidProgressSub?.cancel();
    _mixRamp?.cancel();
    _nativePosSub?.cancel();
    _nativeDurSub?.cancel();
    _nativePlayingSub?.cancel();
    _nativeCompletedSub?.cancel();
    _nativePreview?.dispose();
    _player?.dispose();
    _standby?.dispose();
    super.dispose();
  }
}

/// A running crossfade: song [next] entering on [incoming] while [outgoing]
/// leaves. [t] goes 0 → 1 over [span] seconds with an equal-power curve.
class _MixTransition {
  _MixTransition({
    required this.next,
    required this.t,
    required this.span,
    required this.incoming,
    required this.outgoing,
  });

  final Track next;
  double t;
  final double span;
  final mk.Player incoming;
  final mk.Player outgoing;
}

/// Provides a shared [AppModel] to the whole widget tree and rebuilds
/// dependents when it notifies.
class AppModelProvider extends InheritedNotifier<AppModel> {
  AppModelProvider({super.key, required super.child, AppModel? model})
    : super(notifier: model ?? AppModel());

  static AppModel of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<AppModelProvider>();
    assert(provider != null, 'No AppModelProvider found in context');
    return provider!.notifier!;
  }
}
