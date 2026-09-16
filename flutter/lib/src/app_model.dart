import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';
import 'package:offline_audio_app/src/playback/mixer.dart';
import 'package:offline_audio_app/src/playback/smart_shuffle.dart';
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
  final Map<String, Track> _completed = {};
  final List<Playlist> _playlists = [];

  StreamSubscription<Event>? _eventSub;

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
  }

  mk.Player? get player => _player;

  /// Whether the current track is a downloaded video (MP4), so the UI can
  /// offer the fullscreen video player.
  bool get isCurrentVideo => _currentTrack?.contentKind == 'video';

  /// Download any supported URL directly, bypassing the probe flow of the
  /// settings screen. `kind` selects an audio (music/speech) vs video task.
  Future<String> downloadFromUrl(
    String url, {
    ContentKind kind = ContentKind.music,
  }) async => startDownload(url: url, kind: kind);

  AppModel();

  List<Track> get library => List.unmodifiable(_library);

  Map<String, DownloadState> get downloads => Map.unmodifiable(_downloads);

  /// Backwards-compat for existing callers: taskId -> percent 0..100.
  Map<String, double> get downloadProgress => Map.unmodifiable({
    for (final e in _downloads.entries) e.key: e.value.percent,
  });

  Map<String, String> get downloadErrors => Map.unmodifiable(_downloadErrors);

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

    // Subscribe to the engine event stream.
    _subscribeEvents();

    // Kick off the yt-dlp version check (runs on the Rust side too, but
    // surfacing status here keeps the UI responsive).
    checkYtdlp();

    await reloadLibrary();
    await reloadPlaylists();
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

  void _ensurePlayer() {
    _player ??= mk.Player(configuration: _playerConfig());
    if (!_playerSubscribed) {
      _playerSubscribed = true;
      _subscribePlayer(_player!);
    }
    _ensureStandby();
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
      if (!identical(p, _player) || !done) return;
      _onActiveCompleted();
    });
  }

  void _onActivePosition(Duration pos) {
    _position = pos;
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
    _ensurePlayer();
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
    _ensurePlayer();
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
    _ensurePlayer();
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
    _ensurePlayer();
    _clearPreview();
    _queue = tracks;
    _playingPlaylist = true;
    _shuffleSession = true;
    await _openQueueAt(0);
  }

  /// Reproduce un avance remoto de un resultado de búsqueda: stream directo
  /// por URL (audio o vídeo muxado), sin tocar biblioteca ni estadísticas.
  /// El siguiente `playTrack`/`playPlaylist` lo reemplaza limpiamente.
  Future<void> playPreview({
    required String id,
    required String title,
    String? artist,
    required String url,
    bool isVideo = false,
  }) async {
    _ensurePlayer();
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
    await _player!.open(mk.Media(url));
    notifyListeners();
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
    _ensurePlayer();
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
    _ensurePlayer();
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
    _mixRamp?.cancel();
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
