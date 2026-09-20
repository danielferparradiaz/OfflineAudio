import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/widgets/queue_sheet.dart';

String _fmtClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

/// Compact player bar shown above the bottom nav while a track is loaded.
/// Includes title/artist, seek slider and prev/next controls.
///
/// El slider NO busca mientras se arrastra: el track sigue sonando normal y
/// solo al soltar se salta a la posición elegida. Así se evita el
/// tartamudeo de adelantar/retroceder durante el arrastre.
class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});

  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  /// Posición arrastrada en ms mientras el dedo está sobre el slider.
  /// `null` cuando no se arrastra: el slider sigue a la reproducción.
  double? _dragMs;

  void _onDragStart(double v) => setState(() => _dragMs = v);

  void _onDragging(double v) => setState(() => _dragMs = v);

  Future<void> _onDragEnd(double v, AppModel model) async {
    setState(() => _dragMs = null);
    await model.seek(Duration(milliseconds: v.toInt()));
  }

  @override
  Widget build(BuildContext context) {
    final model = AppModelProvider.of(context);
    final scheme = Theme.of(context).colorScheme;
    final subtle = scheme.onSurface.withValues(alpha: 0.6);
    final preview = model.isPreview;
    final track = model.currentTrack;
    if (track == null && !preview) {
      return SizedBox(
        height: 56,
        child: Row(
          children: [
            const SizedBox(width: 12),
            HugeIcon(icon: HugeIcons.strokeRoundedMusicNote01, color: subtle),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sin reproducción',
                style: TextStyle(color: subtle),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Texto e icono unificados para biblioteca y avance (preview).
    final title = preview ? (model.previewTitle ?? 'Avance') : track!.title;
    final subtitle = preview
        ? [
            if ((model.previewArtist ?? '').isNotEmpty) model.previewArtist!,
            'Avance · sin guardar',
          ].join(' · ')
        : (track?.artist ?? '');
    final isVideo = preview ? model.isPreviewVideo : model.isCurrentVideo;

    Widget leading;
    if (preview) {
      leading = HugeIcon(
        icon: isVideo
            ? HugeIcons.strokeRoundedCameraVideo
            : HugeIcons.strokeRoundedMusicNote01,
        color: subtle,
      );
    } else if (track?.thumbnailPath != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(track!.thumbnailPath!),
          width: 36,
          height: 36,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => HugeIcon(
            icon: isVideo
                ? HugeIcons.strokeRoundedCameraVideo
                : HugeIcons.strokeRoundedMusicNote01,
            color: subtle,
            size: 24,
          ),
        ),
      );
    } else {
      leading = HugeIcon(
        icon: isVideo
            ? HugeIcons.strokeRoundedCameraVideo
            : HugeIcons.strokeRoundedMusicNote01,
        color: subtle,
      );
    }

    final duration = model.duration;
    final position = model.position;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs = position.inMilliseconds
        .clamp(0, duration.inMilliseconds)
        .toDouble();
    // Mientras se arrastra se muestra la posición del dedo, pero la
    // reproducción sigue su curso hasta que se suelta.
    final shownMs = _dragMs ?? posMs;
    final shownPosition = _dragMs != null
        ? Duration(milliseconds: _dragMs!.toInt())
        : position;
    final canSeek = duration.inMilliseconds > 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  // Toda el área del track (miniatura, título, artista y el
                  // hueco hasta los controles) despliega la tracklist cuando
                  // hay una lista/aleatorio activo.
                  behavior: HitTestBehavior.opaque,
                  onTap: (!preview && model.isPlayingPlaylist)
                      ? () => showQueueSheet(context)
                      : null,
                  child: Row(
                    children: [
                      leading,
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(color: scheme.onSurface),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (!preview && model.isPlayingPlaylist)
                              Text(
                                'Ver lista',
                                style: TextStyle(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.55),
                                  fontSize: 11,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: TextStyle(color: subtle, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isVideo)
                IconButton(
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedFullscreen),
                  tooltip: 'Ver vídeo',
                  onPressed: () {
                    if (preview) {
                      final url = model.previewUrl;
                      if (url == null) return;
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PreviewVideoScreen(
                            url: url,
                            title: model.previewTitle ?? 'Avance',
                            id: model.previewId,
                            artist: model.previewArtist,
                          ),
                        ),
                      );
                    } else if (track != null) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(track: track),
                        ),
                      );
                    }
                  },
                ),
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedBackward01),
                tooltip: 'Anterior',
                onPressed: () => model.skipPrevious(),
              ),
              IconButton(
                icon: HugeIcon(
                  icon: model.isPlaying
                      ? HugeIcons.strokeRoundedPauseCircle
                      : HugeIcons.strokeRoundedPlayCircle,
                  size: 36,
                ),
                tooltip: model.isPlaying ? 'Pausar' : 'Reproducir',
                onPressed: () => model.togglePause(),
              ),
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedForward01),
                tooltip: 'Siguiente',
                onPressed: () => model.skipNext(),
              ),
            ],
          ),
          Row(
            children: [
              SizedBox(
                width: 46,
                child: Text(
                  _fmtClock(shownPosition),
                  style: TextStyle(color: subtle, fontSize: 11),
                ),
              ),
              Expanded(
                child: isApplePlatform
                    ? CupertinoSlider(
                        min: 0,
                        max: maxMs,
                        value: canSeek ? shownMs : 0,
                        activeColor: scheme.primary,
                        onChangeStart: canSeek ? _onDragStart : null,
                        onChanged: canSeek ? _onDragging : null,
                        onChangeEnd: canSeek
                            ? (v) => _onDragEnd(v, model)
                            : null,
                      )
                    : Slider(
                        min: 0,
                        max: maxMs,
                        value: canSeek ? shownMs : 0,
                        onChangeStart: canSeek ? _onDragStart : null,
                        onChanged: canSeek ? _onDragging : null,
                        onChangeEnd: canSeek
                            ? (v) => _onDragEnd(v, model)
                            : null,
                      ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  _fmtClock(duration),
                  style: TextStyle(color: subtle, fontSize: 11),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
