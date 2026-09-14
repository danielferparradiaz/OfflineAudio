import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/settings.dart';

class SettingsDrawerContent extends StatefulWidget {
  const SettingsDrawerContent({super.key});

  @override
  State<SettingsDrawerContent> createState() => _SettingsDrawerContentState();
}

class _SettingsDrawerContentState extends State<SettingsDrawerContent> {
  YtdlpInfo? _ytdlp;
  String? _ytdlpMessage;
  bool _checking = false;
  AppDirs? _dirs;
  BinariesStatus? _bins;
  bool _downloading = false;
  final _ytUrlController = TextEditingController();
  final _ffmpegUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ytUrlController.dispose();
    _ffmpegUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final ytdlp = await getYtdlpStatus();
      final dirs = await appDirs();
      final bins = await binariesStatus();
      final ytUrl = await getSetting(key: 'binary.ytdlp_url');
      final ffUrl = await getSetting(key: 'binary.ffmpeg_url');
      if (mounted) {
        setState(() {
          _ytdlp = ytdlp;
          _dirs = dirs;
          _bins = bins;
          if (ytUrl != null) _ytUrlController.text = ytUrl;
          if (ffUrl != null) _ffmpegUrlController.text = ffUrl;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkYtdlp() async {
    setState(() => _checking = true);
    try {
      await checkYtdlp();
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

  Future<void> _downloadBinaries() async {
    setState(() => _downloading = true);
    try {
      final ytUrl = _ytUrlController.text.trim();
      final ffUrl = _ffmpegUrlController.text.trim();
      if (ytUrl.isNotEmpty) {
        await setSetting(key: 'binary.ytdlp_url', value: ytUrl);
      }
      if (ffUrl.isNotEmpty) {
        await setSetting(key: 'binary.ffmpeg_url', value: ffUrl);
      }
      await downloadMobileBinaries();
      final status = await binariesStatus();
      if (mounted) setState(() => _bins = status);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String _ytdlpSubtitle() {
    final y = _ytdlp;
    if (y == null) return 'Cargando…';
    if (!y.present) return 'No instalado';
    final v = y.version ?? 'desconocida';
    return 'v$v · ${y.outdated ? 'desactualizado' : 'actualizado'}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionTitle('Apariencia'),
          _buildAppearance(settings),
          const SizedBox(height: 12),
          const Divider(),
          _SectionTitle('Paquetes del motor'),
          _buildBinaries(settings),
          const Divider(),
          _SectionTitle('Aplicación'),
          ListTile(
            leading: const HugeIcon(
              icon: HugeIcons.strokeRoundedDownloadSquare01,
            ),
            title: const Text('Comprobar yt-dlp'),
            subtitle: Text(_ytdlpSubtitle()),
            trailing: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
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
          _SectionTitle('Almacenamiento'),
          if (_dirs != null) ...[
            ListTile(
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedFolder01),
              title: const Text('Biblioteca (canciones .opus)'),
              subtitle: Text(_dirs!.cache),
            ),
            ListTile(
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedImage01),
              title: const Text('Miniaturas'),
              subtitle: Text(_dirs!.thumbs),
            ),
            ListTile(
              leading: const HugeIcon(icon: HugeIcons.strokeRoundedDatabase),
              title: const Text('Temporal'),
              subtitle: Text(_dirs!.tmp),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const HugeIcon(
              icon: HugeIcons.strokeRoundedInformationCircle,
            ),
            title: const Text('Acerca de'),
            subtitle: const Text(
              'OfflineAudio 1.0.2 · uso personal.\nUso exclusivo de contenidos que tienes derecho a descargar.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearance(SettingsController settings) {
    // El cajón es estrecho (~300dp): segmentos solo con icono para que no
    // desborden ni se estiren las filas.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSun01, size: 24),
            tooltip: 'Claro',
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedMoon02, size: 24),
            tooltip: 'Oscuro',
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedMagicWand01, size: 24),
            tooltip: 'Sistema',
          ),
        ],
        selected: {settings.themeMode},
        onSelectionChanged: (s) => settings.setThemeMode(s.first),
        showSelectedIcon: false,
      ),
    );
  }

  Widget _buildBinaries(SettingsController settings) {
    final b = _bins;
    final yt = b?.ytDlpPresent ?? false;
    final ff = b?.ffmpegPresent ?? false;
    final status = b == null
        ? 'Revisando…'
        : 'yt-dlp ${yt ? '✓' : '✗'} · ffmpeg ${ff ? '✓' : '✗'}';
    final installed = yt && ff;
    // Columna en vez de ListTile con trailing: en el cajón estrecho el
    // botón nunca comprime el texto ni se estira la fila.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HugeIcon(icon: HugeIcons.strokeRoundedWrench01),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Binarios yt-dlp / ffmpeg'),
                    Text(
                      status,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _downloading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton.tonalIcon(
                  onPressed: installed ? null : _downloadBinaries,
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedDownload01,
                    size: 18,
                  ),
                  label: Text(installed ? 'Instalados' : 'Descargar'),
                ),
          const SizedBox(height: 8),
          TextField(
            controller: _ytUrlController,
            decoration: const InputDecoration(
              labelText: 'URL personalizada de yt-dlp (opcional)',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _ffmpegUrlController,
            decoration: const InputDecoration(
              labelText: 'URL personalizada de ffmpeg (opcional)',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);
  final String title;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
