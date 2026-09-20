import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:video_player/video_player.dart';

/// Avance de vídeo a pantalla completa para un resultado de búsqueda:
/// reproduce el stream remoto con el player compartido del [AppModel], de
/// modo que al cerrar la pantalla la reproducción (y su audio) continúa en
/// la barra inferior.
///
/// En iOS el vídeo va por AVPlayer (`video_player`): el mpv empaquetado no
/// abre audio ahí. Al cerrar, el audio continúa en la barra mediante el
/// avance nativo ([AppModel.playPreview]) desde la última posición.
class PreviewVideoScreen extends StatefulWidget {
  const PreviewVideoScreen({
    super.key,
    required this.url,
    required this.title,
    this.id,
    this.artist,
  });

  final String url;
  final String title;

  /// Para el handoff de audio al cerrar en iOS (avance nativo).
  final String? id;
  final String? artist;

  @override
  State<PreviewVideoScreen> createState() => _PreviewVideoScreenState();
}

class _PreviewVideoScreenState extends State<PreviewVideoScreen> {
  VideoController? _controller;
  bool _initialized = false;

  /// Player propio solo en iOS (AVPlayer). Fuera de iOS se usa el mk
  /// compartido del modelo.
  VideoPlayerController? _native;
  bool _nativeReady = false;
  AppModel? _model;

  static const _previewHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/126.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  @override
  void initState() {
    super.initState();
    if (isIOSPlatform) {
      final c = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: _previewHttpHeaders,
      );
      _native = c;
      c.addListener(_syncNative);
      c.initialize().then((_) {
        if (!mounted) return;
        setState(() => _nativeReady = true);
        c.play();
      }, onError: (_) {});
    }
  }

  /// Empuja el estado del player propio al modelo para la barra inferior.
  void _syncNative() {
    final c = _native;
    final model = _model;
    if (c == null || model == null || !c.value.isInitialized) return;
    final pos = c.value.position;
    final dur = c.value.duration;
    model.syncNativeVideoPreview(
      playing: c.value.isPlaying,
      position: pos,
      duration: dur,
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    final c = _native;
    final model = _model;
    if (c != null) {
      c.removeListener(_syncNative);
      final pos = c.value.isInitialized ? c.value.position : Duration.zero;
      final wasActive =
          model != null &&
          model.isPreviewVideo &&
          model.previewUrl == widget.url;
      c.pause();
      c.dispose();
      _native = null;
      // Handoff: el audio continúa en la barra desde donde quedó el vídeo.
      if (wasActive) {
        unawaited(
          model.playPreview(
            id: widget.id ?? widget.url,
            title: widget.title,
            artist: widget.artist,
            url: widget.url,
            startAt: pos,
          ),
        );
      } else {
        model?.setNativeVideoControls();
      }
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final model = AppModelProvider.of(context);
    if (isIOSPlatform) {
      _model = model;
      model.setNativeVideoControls(
        onPauseToggle: () async {
          final c = _native;
          if (c == null || !c.value.isInitialized) return;
          if (c.value.isPlaying) {
            await c.pause();
          } else {
            await c.play();
          }
        },
        onSeek: (pos) async {
          await _native?.seekTo(pos);
        },
      );
      return;
    }
    final player = model.player;
    if (player != null) {
      _controller = VideoController(player);
    }
  }

  @override
  Widget build(BuildContext context) {
    // iOS: player propio (AVPlayer) con controles mínimos. Al cerrar, el
    // audio continúa en la barra inferior (ver dispose).
    if (isIOSPlatform) return _buildNative(context);
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            MaterialDesktopVideoControlsTheme(
              normal: MaterialDesktopVideoControlsThemeData(
                topButtonBar: [
                  const SizedBox(width: 56),
                  const Expanded(child: SizedBox()),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'Avance · ${widget.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              fullscreen: MaterialDesktopVideoControlsThemeData(
                topButtonBar: [
                  const SizedBox(width: 56),
                  const Expanded(child: SizedBox()),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Text(
                      'Avance · ${widget.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              child: Video(controller: controller),
            )
          else
            const ColoredBox(color: Colors.black),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      color: Colors.white,
                    ),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  /// Vista iOS con el player propio: vídeo + controles mínimos de
  /// play/pausa. El progreso vive en la barra inferior (vía modelo).
  Widget _buildNative(BuildContext context) {
    final c = _native;
    final ready = _nativeReady && c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: c.value.aspectRatio,
                child: VideoPlayer(c),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowLeft01,
                      color: Colors.white,
                    ),
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ),
          if (ready)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.black54,
                    child: IconButton(
                      icon: HugeIcon(
                        icon: c.value.isPlaying
                            ? HugeIcons.strokeRoundedPause
                            : HugeIcons.strokeRoundedPlay,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: c.value.isPlaying ? 'Pausar' : 'Reproducir',
                      onPressed: () {
                        if (c.value.isPlaying) {
                          c.pause();
                        } else {
                          c.play();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
