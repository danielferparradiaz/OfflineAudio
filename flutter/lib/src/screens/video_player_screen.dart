import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

/// Fullscreen player for downloaded videos. It reuses the shared [mk.Player]
/// owned by [AppModel], so playback is continuous when leaving the screen.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.track});

  final Track track;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoController? _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final model = AppModelProvider.of(context);
    // La pantalla garantiza su propia reproducción: si el player compartido
    // no viene ya con este track, lo pone en marcha (esto también crea el
    // player si aún no existe, de forma síncrona antes del primer await).
    if (model.currentTrack?.id != widget.track.id) {
      unawaited(model.playTrack(widget.track));
    }
    final player = model.player;
    if (player != null) {
      _controller = VideoController(player);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            Video(controller: controller)
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
}
