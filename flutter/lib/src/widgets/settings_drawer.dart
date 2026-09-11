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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final ytdlp = await getYtdlpStatus();
      final dirs = await appDirs();
      final bins = await binariesStatus();
      if (mounted) {
        setState(() {
          _ytdlp = ytdlp;
          _dirs = dirs;
          _bins = bins;
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
              'OfflineAudio 1.0 · uso personal.\nUso exclusivo de contenidos que tienes derecho a descargar.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearance(SettingsController settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedSun01, size: 24),
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Claro'),
            ),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedMoon02, size: 24),
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Oscuro'),
            ),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: HugeIcon(icon: HugeIcons.strokeRoundedMagicWand01, size: 24),
            label: Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Sistema'),
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const HugeIcon(icon: HugeIcons.strokeRoundedWrench01),
          title: const Text('Binarios yt-dlp / ffmpeg'),
          subtitle: Text(status),
          trailing: _downloading
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
        ),
      ],
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
