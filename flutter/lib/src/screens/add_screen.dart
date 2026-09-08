import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

class AddScreen extends StatefulWidget {
  const AddScreen({super.key});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _urlController = TextEditingController();
  bool _probing = false;
  String? _error;
  ProbeInfo? _probeInfo;
  ContentKind _kind = ContentKind.music;
  bool _downloading = false;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _probe() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _probing = true;
      _error = null;
      _probeInfo = null;
    });
    try {
      final info = await probeUrl(url: url);
      if (!mounted) return;
      setState(() {
        _probeInfo = info;
        _kind = info.likelySpeech ? ContentKind.speech : ContentKind.music;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _probing = false);
    }
  }

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _downloading = true;
      _error = null;
    });
    try {
      final taskId = await startDownload(url: url, kind: _kind);
      if (!mounted) return;
      final short =
          taskId.length <= 8 ? taskId : taskId.substring(0, 8);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Descarga iniciada ($short)')),
      );
      Navigator.of(context).pop(taskId);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canDownload = _probeInfo != null && !_downloading;
    return Scaffold(
      appBar: AppBar(title: const Text('Añadir música o podcast')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'URL (YouTube, Instagram, etc.)',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _probe(),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: _probing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_probing ? 'Analizando…' : 'Analizar'),
              onPressed: _probing ? null : _probe,
            ),
            const SizedBox(height: 16),
            if (_probeInfo != null) _buildProbeInfoCard(),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.black,
              ),
              icon: _downloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(_downloading ? 'Descargando…' : 'Descargar'),
              onPressed: canDownload ? _startDownload : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProbeInfoCard() {
    final p = _probeInfo!;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.music_note),
        title: Text(p.title),
        subtitle: Text([
          if (p.artist?.isNotEmpty ?? false) p.artist!,
          if (p.platform?.isNotEmpty ?? false) p.platform!,
          if (p.durationSeconds != null) '${p.durationSeconds}s',
        ].join(' · ')),
        trailing: DropdownButton<ContentKind>(
          value: _kind,
          onChanged: (v) => setState(() => _kind = v!),
          items: const [
            DropdownMenuItem(
              value: ContentKind.music,
              child: Text('Música (96k)'),
            ),
            DropdownMenuItem(
              value: ContentKind.speech,
              child: Text('Podcast/habla (32k)'),
            ),
          ],
        ),
      ),
    );
  }
}