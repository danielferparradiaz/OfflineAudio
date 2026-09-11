import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Grey 48x48 box with a music note, used when a track has no artwork
/// (or the artwork file fails to load).
class ThumbPlaceholder extends StatelessWidget {
  const ThumbPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 48,
      height: 48,
      child: ColoredBox(
        color: Color(0xFF2A2A2A),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedMusicNote01,
          color: Colors.white54,
        ),
      ),
    );
  }
}
