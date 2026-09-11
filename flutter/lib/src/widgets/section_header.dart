import 'package:flutter/material.dart';

/// Small bold section title ("Reciente", "Biblioteca") with an optional
/// widget aligned to the opposite side (e.g. the shuffle button).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});

  final String title;

  /// Optional widget aligned to the opposite side of the title (e.g. the
  /// shuffle button on the "Reciente" header).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      this.title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
    final trailing = this.trailing;
    if (trailing == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: title,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Expanded(child: title),
          trailing,
        ],
      ),
    );
  }
}
