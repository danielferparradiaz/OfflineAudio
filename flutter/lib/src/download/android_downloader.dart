import 'dart:async';

import 'package:flutter/services.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

/// Metadata returned by the Android youtubedl-android backend.
class AndroidProbe {
  const AndroidProbe({
    required this.id,
    required this.sourceId,
    required this.title,
    required this.networkUrl,
    this.artist,
    this.album,
    this.durationSeconds,
    this.thumbnailUrl,
    this.platform,
    this.uploader,
  });

  final String id;
  final String sourceId;
  final String title;
  final String networkUrl;
  final String? artist;
  final String? album;
  final int? durationSeconds;
  final String? thumbnailUrl;
  final String? platform;
  final String? uploader;

  factory AndroidProbe.fromMap(Map<Object?, Object?> raw, String fallbackUrl) {
    final id = _string(raw['id']) ?? '';
    final platform = _string(raw['extractor']);
    return AndroidProbe(
      id: id,
      sourceId: '${platform ?? 'youtube'}:$id',
      title: _string(raw['title']) ?? 'Sin título',
      networkUrl: _string(raw['webpage_url']) ?? fallbackUrl,
      artist: _string(raw['artist']) ?? _string(raw['uploader']),
      album: _string(raw['album']),
      durationSeconds: _int(raw['duration']),
      thumbnailUrl: _string(raw['thumbnail']),
      platform: platform,
      uploader: _string(raw['uploader']),
    );
  }
}

class AndroidDownloadProgress {
  const AndroidDownloadProgress({
    required this.taskId,
    required this.percent,
    required this.etaSeconds,
  });

  final String taskId;
  final double percent;
  final int? etaSeconds;

  factory AndroidDownloadProgress.fromMap(Map<Object?, Object?> raw) {
    return AndroidDownloadProgress(
      taskId: _string(raw['taskId']) ?? '',
      percent: _number(raw['progress']),
      etaSeconds: _int(raw['eta']),
    );
  }
}

/// Flutter-facing adapter for the Android native download backend.
///
/// The Rust CLI pipeline remains the backend for desktop and iOS. Android
/// cannot execute the downloaded CLI runtime on modern target SDKs, so the
/// platform channel delegates yt-dlp and ffmpeg to native libraries instead.
class AndroidDownloader {
  AndroidDownloader._();

  static const _methods = MethodChannel('com.offlineaudio.app/ytdlp');
  static const _progressEvents = EventChannel('com.offlineaudio.app/progress');

  static Stream<AndroidDownloadProgress> get progress => _progressEvents
      .receiveBroadcastStream()
      .map((event) => AndroidDownloadProgress.fromMap(
            Map<Object?, Object?>.from(event as Map),
          ));

  static Future<bool> isReady() async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>('status');
    return raw?["ready"] == true;
  }

  static Future<AndroidProbe> probe(String url) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>('probe', {
      'url': url,
    });
    if (raw == null) throw StateError('Android probe devolvió una respuesta vacía');
    return AndroidProbe.fromMap(raw, url);
  }

  static Future<String> download({
    required String url,
    required String outputDir,
    required ContentKind kind,
    required String taskId,
  }) async {
    final format = kind == ContentKind.video ? 'bv*+ba/b' : 'bestaudio/best';
    final path = await _methods.invokeMethod<String>('download', {
      'url': url,
      'outputDir': outputDir,
      'format': format,
      'taskId': taskId,
    });
    if (path == null || path.isEmpty) {
      throw StateError('Android download no devolvió una ruta');
    }
    return path;
  }

  static Future<void> transcode({
    required String input,
    required String output,
    required Map<String, String> metadata,
    required int bitrateKbps,
  }) async {
    await _methods.invokeMethod<bool>('transcode', {
      'input': input,
      'output': output,
      'metadata': metadata,
      'bitrateKbps': bitrateKbps,
    });
  }

  static Future<void> cancel(String taskId) async {
    await _methods.invokeMethod<bool>('cancelDownload', {'taskId': taskId});
  }
}

String? _string(Object? value) => value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return null;
}

double _number(Object? value) => value is num ? value.toDouble() : 0;
