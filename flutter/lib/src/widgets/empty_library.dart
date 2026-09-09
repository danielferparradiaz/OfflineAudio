import 'package:flutter/material.dart';

/// Placeholder shown when the library has no tracks yet.
class EmptyLibrary extends StatelessWidget {
  const EmptyLibrary({super.key});

  @override
  Widget build(BuildContext context) {
    final subtle =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined,
                size: 64, color: subtle.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Tu biblioteca está vacía.\nBusca en YouTube para empezar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtle),
            ),
          ],
        ),
      ),
    );
  }
}
