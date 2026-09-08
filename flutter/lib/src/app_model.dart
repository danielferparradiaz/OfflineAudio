import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
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

  // Playback position tracking (P3).
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  Track? _currentTrack;
  List<Track> _queue = [];
  bool _playingPlaylist = false;

  Track? get currentTrack => _currentTrack;

  mk.Player? get player => _player;

  /// Whether the current track is a downloaded video (MP4), so the UI can
  /// offer the fullscreen video player.
  bool get isCurrentVideo => _currentTrack?.contentKind == 'video';

  /// Download any supported URL directly, bypassing the probe flow of the
  /// settings screen. `kind` selects an audio (music/speech) vs video task.
  Future<String> downloadFromUrl(String url,
          {ContentKind kind = ContentKind.music}) async =>
      startDownload(url: url, kind: kind);

  AppModel();

  List<Track> get library => List.unmodifiable(_library);

  Map<String, DownloadState> get downloads => Map.unmodifiable(_downloads);

  /// Backwards-compat for existing callers: taskId -> percent 0..100.
  Map<String, double> get downloadProgress =>
      Map.unmodifiable({for (final e in _downloads.entries) e.key: e.value.percent});

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

  Future<void> reloadLibrary(
      {String? search, SortOrder order = SortOrder.dateDesc}) async {
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
    _player ??= mk.Player();
    if (_playerSubscribed) return;
    _playerSubscribed = true;
    final p = _player!;
    p.stream.playing.listen((playing) {
      _playing = playing;
      notifyListeners();
    });
    p.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    });
    p.stream.duration.listen((dur) {
      _duration = dur;
      notifyListeners();
    });
    // When media_kit advances inside a Playlist, keep our queue in sync
    // so the UI title and play-count stay correct.
    p.stream.playlist.listen((pl) {
      if (!_playingPlaylist || _queue.isEmpty) return;
      final idx = pl.index;
      if (idx < 0 || idx >= _queue.length) return;
      final track = _queue[idx];
      if (_currentTrack?.id != track.id) {
        _currentTrack = track;
        notifyListeners();
        _recordPlay(track);
      }
    });
  }

  /// Play a single track.
  Future<void> playTrack(Track track) async {
    _ensurePlayer();
    _currentTrack = track;
    _queue = [track];
    _playingPlaylist = false;
    _position = Duration.zero;
    await _player!.open(mk.Media(track.filePath));
    notifyListeners();
    _recordPlay(track);
  }

  /// Play all tracks of a playlist in order (media_kit auto-advances).
  Future<void> playPlaylist(String playlistId) async {
    final tracks = await playlistTracks(playlistId: playlistId);
    if (tracks.isEmpty) return;
    _ensurePlayer();
    _queue = tracks;
    _currentTrack = tracks.first;
    _playingPlaylist = true;
    _position = Duration.zero;
    await _player!.open(
      mk.Playlist(tracks.map((t) => mk.Media(t.filePath)).toList()),
    );
    notifyListeners();
    _recordPlay(tracks.first);
  }

  void _recordPlay(Track track) {
    // fire-and-forget stats update
    recordPlay(id: track.id).then((_) {}, onError: (_) {});
  }

  Future<void> togglePause() async {
    final p = _player;
    if (p == null) return;
    if (p.state.playing) {
      await p.pause();
    } else {
      await p.play();
    }
    notifyListeners();
  }

  Future<void> seek(Duration position) async {
    await _player?.seek(position);
    notifyListeners();
  }

  Future<void> skipNext() async {
    // In playlist mode media_kit advances the Playlist and our
    // stream.playlist listener updates _currentTrack.
    await _player?.next();
    notifyListeners();
  }

  Future<void> skipPrevious() async {
    // If well into the track, restart it instead of going back.
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return;
    }
    await _player?.previous();
    notifyListeners();
  }

  bool get isPlaying => _playing || (_player?.state.playing ?? false);

  bool get isPlayingPlaylist => _playingPlaylist;

  @override
  void dispose() {
    _eventSub?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

/// Provides a shared [AppModel] to the whole widget tree and rebuilds
/// dependents when it notifies.
class AppModelProvider extends InheritedNotifier<AppModel> {
  AppModelProvider({super.key, required super.child, AppModel? model})
      : super(notifier: model ?? AppModel());

  static AppModel of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<AppModelProvider>();
    assert(provider != null, 'No AppModelProvider found in context');
    return provider!.notifier!;
  }
}
