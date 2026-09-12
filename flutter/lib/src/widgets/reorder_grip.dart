import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';

/// Affordance de arrastre/reordenado adaptativa.
///
/// En Apple (iOS/macOS) dibuja el agarre de seis puntos típico de las listas
/// de Cupertino (discreto y "serio"); en el resto usa la hamburguesa de
/// Hugeicons.
class ReorderGrip extends StatelessWidget {
  const ReorderGrip({super.key, this.color, this.size = const Size(12, 16)});

  final Color? color;

  /// Tamaño del agarre en Apple (ignorado en el resto, que usa el icono).
  final Size size;

  @override
  Widget build(BuildContext context) {
    final c = color ??
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55);
    if (!isApplePlatform) {
      return HugeIcon(icon: HugeIcons.strokeRoundedMenu01, color: c);
    }
    return CustomPaint(
      size: size,
      painter: _SixDotGripPainter(c),
    );
  }
}

class _SixDotGripPainter extends CustomPainter {
  _SixDotGripPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const rows = 3;
    const cols = 2;
    final rowStep = size.height / rows;
    final colStep = size.width / cols;
    final radius = math.min(size.width, size.height) * 0.11;
    for (var row = 0; row < rows; row++) {
      final y = rowStep * (row + 0.5);
      for (var col = 0; col < cols; col++) {
        final x = colStep * (col + 0.5);
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SixDotGripPainter oldDelegate) =>
      oldDelegate.color != color;
}