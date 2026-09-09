import 'package:flutter/material.dart';

/// Preset accents that look good in both light and dark themes.
const kPresetColors = <int>[
  0xFF1DB954, // spotify green
  0xFF0B8A3E,
  0xFF1F8BF1,
  0xFF7C4DFF,
  0xFFE91E63,
  0xFFFF3D00,
  0xFFFFB300,
  0xFF00B0FF,
  0xFF00BFA6,
  0xFF00C853,
  0xFFD500F9,
  0xFFF4511E,
  0xFFFB8C00,
  0xFF43A047,
  0xFF3949AB,
  0xFF6D4C41,
  0xFF757575,
  0xFFE0E0E0,
];

/// Escala de grises para colores de fondo (de negro a blanco).
const kGrayscaleSwatches = <int>[
  0xFF000000,
  0xFF111111,
  0xFF1E1E1E,
  0xFF2E2E2E,
  0xFF424242,
  0xFF616161,
  0xFF8A8A8A,
  0xFFBDBDBD,
  0xFFDCDCDC,
  0xFFF0F0F0,
  0xFFFFFFFF,
];

/// Opens a dialog to pick a color. Returns the chosen [Color] or `null` if
/// the user cancels. Pass [swatches] to override the default accent presets
/// (e.g. [kGrayscaleSwatches] for backgrounds).
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required String title,
  required Color initial,
  List<int> swatches = kPresetColors,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(
      title: title,
      initial: initial,
      swatches: swatches,
    ),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({
    required this.title,
    required this.initial,
    required this.swatches,
  });

  final String title;
  final Color initial;
  final List<int> swatches;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _color;

  @override
  void initState() {
    super.initState();
    _color = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGray = identical(widget.swatches, kGrayscaleSwatches);
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Preview(color: _color),
              const SizedBox(height: 16),
              Text(
                isGray ? 'Escala de grises' : 'Predefinidos',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  for (final value in widget.swatches)
                    _Swatch(
                      color: Color(value),
                      selected: _color.toARGB32() == value,
                      onTap: () => setState(() => _color = Color(value)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Elegir'),
        ),
      ],
    );
  }
}

/// Contraste legible sobre cualquier color (claro u oscuro).
Color _onColor(Color c) =>
    c.computeLuminance() > 0.45 ? Colors.black : Colors.white;

class _Preview extends StatelessWidget {
  const _Preview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return Container(
      height: 84,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: Text(
        hex.toUpperCase(),
        style: TextStyle(
          color: _onColor(color),
          fontSize: 17,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 2.5,
                )
              : Border.all(
                  color:
                      Theme.of(context).colorScheme.outlineVariant,
                ),
        ),
        child: selected
            ? Icon(Icons.check, color: _onColor(color), size: 22)
            : null,
      ),
    );
  }
}
