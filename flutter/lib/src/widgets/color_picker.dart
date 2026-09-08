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

/// Opens a dialog to pick a color. Returns the chosen [Color] or `null` if
/// the user cancels.
Future<Color?> showColorPickerDialog(
  BuildContext context, {
  required String title,
  required Color initial,
}) {
  return showDialog<Color>(
    context: context,
    builder: (_) => _ColorPickerDialog(title: title, initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.title, required this.initial});

  final String title;
  final Color initial;

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

  double get _hue => HSLColor.fromColor(_color).hue;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Preview(color: _color),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in kPresetColors)
                _Swatch(
                  color: Color(value),
                  selected: _color.toARGB32() == value,
                  onTap: () => setState(() => _color = Color(value)),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const _HueBar(),
              const SizedBox(width: 12),
              Expanded(
                child: Slider(
                  value: _hue,
                  min: 0,
                  max: 360,
                  onChanged: (h) => setState(
                    () => _color = HSLColor.fromColor(_color).withHue(h).toColor(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('Usar'),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final hex =
        '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        const SizedBox(width: 12),
        Text(hex.toUpperCase(), style: Theme.of(context).textTheme.bodyLarge),
      ],
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
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : Border.all(color: Colors.transparent),
        ),
      ),
    );
  }
}

/// Thin rainbow strip used as the visual backdrop for the hue slider.
class _HueBar extends StatelessWidget {
  const _HueBar();

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[
      for (var h = 0.0; h <= 360; h += 24) HSLColor.fromAHSL(1, h, 1, 0.5).toColor(),
    ];
    return Container(
      width: 20,
      height: 12,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: LinearGradient(colors: colors),
      ),
    );
  }
}