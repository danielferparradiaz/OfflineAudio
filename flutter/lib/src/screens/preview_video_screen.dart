import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:offline_audio_app/src/app_model.dart';

/// Avance de vídeo a pantalla completa para un resultado de búsqueda:
/// reproduce el stream remoto con el player compartido del [AppModel], de
/// modo que al cerrar la pantalla la reproducción (y su audio) continúa en
/// la barra inferior.
class PreviewVideoScreen extends StatefulWidget {
  const PreviewVideoScreen({super.key, required this.url, required this.title});

  final String url;
  final String title;

  @override
  State<PreviewVideoScreen> createState() => _PreviewVideoScreenState();
}

class _PreviewVideoScreenState extends State<PreviewVideoScreen> {
  VideoController? _controller;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final player = AppModelProvider.of(context).player;
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
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
