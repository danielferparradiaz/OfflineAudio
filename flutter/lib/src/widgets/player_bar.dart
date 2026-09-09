import 'dart:io';

import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/screens.dart';

String _fmtClock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

/// Compact player bar shown above the bottom nav while a track is loaded.
/// Includes title/artist, seek slider and prev/next controls.
class PlayerBar extends StatelessWidget {
  const PlayerBar({super.key});

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
            Icon(Icons.music_note, color: subtle),
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
      leading = Icon(
        isVideo ? Icons.videocam : Icons.music_note,
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
          errorBuilder: (_, _, _) => Icon(
            isVideo ? Icons.videocam : Icons.music_note,
            color: subtle,
          ),
        ),
      );
    } else {
      leading = Icon(
        isVideo ? Icons.videocam : Icons.music_note,
        color: subtle,
      );
    }

    final duration = model.duration;
    final position = model.position;
    final maxMs = duration.inMilliseconds > 0
        ? duration.inMilliseconds.toDouble()
        : 1.0;
    final posMs =
        position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: model.isPlaying
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if (!preview && model.isShuffleSession)
                      Text(
                        'View playlist',
                        style: TextStyle(color: subtle, fontSize: 11),
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
              if (isVideo)
                IconButton(
                  icon: const Icon(Icons.fullscreen),
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
                icon: const Icon(Icons.skip_previous),
                tooltip: 'Anterior',
                onPressed: () => model.skipPrevious(),
              ),
              IconButton(
                icon: Icon(
                  model.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  size: 36,
                ),
                tooltip: model.isPlaying ? 'Pausar' : 'Reproducir',
                onPressed: () => model.togglePause(),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
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
                  _fmtClock(position),
                  style: TextStyle(color: subtle, fontSize: 11),
                ),
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: maxMs,
                  value: duration.inMilliseconds > 0 ? posMs : 0,
                  onChanged: duration.inMilliseconds > 0
                      ? (v) => model.seek(
                          Duration(milliseconds: v.toInt()))
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
