import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Error banner for a failed search, with retry / back-to-library actions.
class SearchError extends StatelessWidget {
  const SearchError({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedCloudOff,
            size: 48,
            color: subtle.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: subtle),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onRetry,
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                label: const Text('Reintentar'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onClose,
                child: const Text('Volver a la biblioteca'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
