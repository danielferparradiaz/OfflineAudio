import 'package:flutter/material.dart';

/// Área de spinner / error: centrada en el espacio bajo la cabecera.
class SearchFeedback extends StatelessWidget {
  const SearchFeedback({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 32),
      alignment: Alignment.center,
      child: child,
    );
  }
}
