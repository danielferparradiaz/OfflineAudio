import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pequeño ecualizador animado (4 barras) para el pie de la cola y otras
/// zonas "en vivo". Misma tónica visual que "Ver lista": color tenue del
/// texto. Solo anima cuando [active] es true; si no, las barras quedan bajas
/// y estáticas.
class MiniEqualizer extends StatefulWidget {
  const MiniEqualizer({super.key, this.active = true});

  final bool active;

  @override
  State<MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<MiniEqualizer>
    with SingleTickerProviderStateMixin {
  static const double _base = 4;
  static const List<double> _peaks = [7, 12, 9, 14];
  static const List<double> _phases = [0, 1.3, 2.4, 0.6];

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant MiniEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.repeat();
    } else if (!widget.active && oldWidget.active) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.55);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _peaks.length; i++)
              Container(
                width: 3,
                height: _barHeight(i, t),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            const SizedBox(width: 2),
          ],
        );
      },
    );
  }

  double _barHeight(int i, double t) {
    if (!widget.active) return _base * 0.8;
    final wave = 0.5 + 0.5 * math.sin(2 * math.pi * t + _phases[i]);
    return _base + _peaks[i] * wave * 0.7;
  }
}
