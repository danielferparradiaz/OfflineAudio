import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';

/// Resumen amigable de almacenamiento para Ajustes: nº de canciones y
/// tamaño total en disco, sin exponer rutas internas de la app.
class StorageSummaryTile extends StatelessWidget {
  const StorageSummaryTile({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StorageUsage>(
      future: storageUsage(),
      builder: (context, snapshot) {
        final subtle = Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.6);
        final usage = snapshot.data;
        final String subtitle;
        final Widget? trailing;
        if (snapshot.hasError) {
          subtitle = 'No se pudo calcular el espacio usado';
          trailing = null;
        } else if (usage == null) {
          subtitle = 'Calculando…';
          trailing = const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        } else {
          final n = usage.trackCount.toInt();
          subtitle =
              '$n ${n == 1 ? 'canción' : 'canciones'} · '
              '${_fmtBytes(usage.totalBytes)} en este dispositivo';
          trailing = null;
        }
        return ListTile(
          leading: const HugeIcon(icon: HugeIcons.strokeRoundedDatabase),
          title: Text(
            'Almacenamiento de la biblioteca',
            style: TextStyle(color: snapshot.hasError ? subtle : null),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: subtle)),
          trailing: trailing,
        );
      },
    );
  }

  static String _fmtBytes(BigInt bytes) {
    final b = bytes.toDouble();
    if (b >= 1024 * 1024 * 1024) {
      return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    if (b >= 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }
}
