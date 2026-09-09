import 'package:flutter/material.dart';

/// Header shown above search results: the active query plus a close button
/// that clears the results and returns to the library.
class SearchHeader extends StatelessWidget {
  const SearchHeader({super.key, required this.query, required this.onClose});

  final String query;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Resultados para «$query»',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar búsqueda',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
