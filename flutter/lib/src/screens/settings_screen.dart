import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  YtdlpInfo? _ytdlp;
  String? _ytdlpMessage;
  bool _checking = false;
  AppDirs? _dirs;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ytdlp = await getYtdlpStatus();
      final dirs = await appDirs();
      if (mounted) {
        setState(() {
          _ytdlp = ytdlp;
          _dirs = dirs;
        });
      }
    } catch (e) {
      // Error al obtener estado de yt-dlp o directorios - muestra mensaje
      if (mounted) {
        setState(() {
          _ytdlpMessage = 'Error cargando configuración: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _checkYtdlp() async {
    setState(() => _checking = true);
    try {
      await checkYtdlp();
      // wait a moment for the background check to persist
      await Future.delayed(const Duration(milliseconds: 800));
      final ytdlp = await getYtdlpStatus();
      if (mounted) {
        setState(() {
          _ytdlp = ytdlp;
          _ytdlpMessage = ytdlp.outdated
              ? 'Versión desactualizada. Revisando…'
              : 'yt-dlp está actualizado';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _ytdlpMessage = 'Error: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aplicación',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.download_for_offline_outlined),
              title: const Text('Comprobar yt-dlp'),
              subtitle: Text(_ytdlpSubtitle()),
              trailing: _checking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _checkYtdlp,
                    ),
          ),
          if (_ytdlpMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _ytdlpMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Almacenamiento',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (_dirs != null) ...[
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text('Biblioteca (canciones .opus)'),
                subtitle: Text(_dirs!.cache),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined),
                title: const Text('Miniaturas'),
                subtitle: Text(_dirs!.thumbs),
              ),
              ListTile(
                leading: const Icon(Icons.storage),
                title: const Text('Temporal'),
                subtitle: Text(_dirs!.tmp),
              ),
            ],
            const Divider(),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Acerca de'),
              subtitle: const Text('OfflineAudio 0.1 · uso personal.\n'
                  'Uso exclusivo de contenidos que tienes derecho a descargar.'),
            ),
          ],
        ),
      ),
    );
  }

  String _ytdlpSubtitle() {
    final y = _ytdlp;
    if (y == null) return 'Cargando…';
    if (!y.present) return 'No instalado';
    final v = y.version ?? 'desconocida';
    return 'v$v · ${y.outdated ? 'desactualizado' : 'actualizado'}';
  }
}