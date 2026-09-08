import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';

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
    final track = model.currentTrack;
    if (track == null) {
      return const SizedBox(
        height: 56,
        child: Row(
          children: [
            SizedBox(width: 12),
            Icon(Icons.music_note, color: Colors.white24),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sin reproducción',
                style: TextStyle(color: Colors.white38),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
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
              const Icon(Icons.music_note, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      track.title,
                      style: TextStyle(
                        color:
                            model.isPlaying ? Colors.white : Colors.white70,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    if ((track.artist ?? '').isNotEmpty)
                      Text(
                        track.artist!,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                  ],
                ),
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
              Text(
                _fmtClock(position),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
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
              Text(
                _fmtClock(duration),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
