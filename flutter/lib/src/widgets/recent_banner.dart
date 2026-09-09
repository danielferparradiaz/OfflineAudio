import 'dart:io';

import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/widgets/thumb_placeholder.dart';

/// Calling card for the most recently downloaded item: artwork, metadata and
/// a direct "Escuchar" action.
class RecentBanner extends StatelessWidget {
  const RecentBanner({
    super.key,
    required this.track,
    required this.onPlay,
    this.selected = false,
    this.onSelect,
  });

  final Track track;
  final VoidCallback onPlay;
  final bool selected;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final thumb = track.thumbnailPath;
    final subtitle = [
      if (track.artist != null && track.artist!.isNotEmpty) track.artist!,
      if (track.album != null && track.album!.isNotEmpty) track.album!,
    ].join(' · ');
    return Card(
      elevation: selected ? 4 : 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: selected
            ? const BorderSide(color: Colors.amber, width: 2)
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect ?? onPlay,
        onDoubleTap: onPlay,
        child: Container(
          height: 96,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF14432E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              thumb != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(thumb),
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            const ThumbPlaceholder(),
                      ),
                    )
                  : const ThumbPlaceholder(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.white70),
                      ),
                    const Text(
                      'Descarga reciente',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Escuchar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
