import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/settings.dart';
import 'package:offline_audio_app/src/widgets/color_picker.dart';

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
          _ytdlpMessage = ytdlp.outdated ? 'Versión desactualizada. Revisando…' : 'yt-dlp está actualizado';
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

  Future<void> _pickAccentColor() async {
    final settings = SettingsScope.of(context);
    final current = Color(settings.accent);
    final picked = await showColorPickerDialog(context, title: 'Color de los botones', initial: current);
    if (picked != null) settings.setAccent(picked.toARGB32());
  }

  Future<void> _pickBackgroundColor() async {
    final settings = SettingsScope.of(context);
    final current = settings.hasCustomBackground ? Color(settings.background!) : Colors.grey;
    final picked = await showColorPickerDialog(context, title: 'Color de fondo', initial: current, swatches: kGrayscaleSwatches);
    if (picked != null) settings.setBackground(picked.toARGB32());
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
          const Divider(),
          _SectionTitle('Paquetes del motor'),
          _buildBinaries(settings),
          const Divider(),
          _SectionTitle('Aplicación'),
          ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Comprobar yt-dlp'),
            subtitle: Text(_ytdlpSubtitle()),
            trailing: _checking
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(icon: const Icon(Icons.refresh), onPressed: _checkYtdlp),
          ),
          if (_ytdlpMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_ytdlpMessage!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            ),
          const Divider(),
          _SectionTitle('Almacenamiento'),
          if (_dirs != null) ...[
            ListTile(leading: const Icon(Icons.folder), title: const Text('Biblioteca (canciones .opus)'), subtitle: Text(_dirs!.cache)),
            ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Miniaturas'), subtitle: Text(_dirs!.thumbs)),
            ListTile(leading: const Icon(Icons.storage), title: const Text('Temporal'), subtitle: Text(_dirs!.tmp)),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Acerca de'),
            subtitle: const Text('OfflineAudio 1.0 · uso personal.\nUso exclusivo de contenidos que tienes derecho a descargar.'),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearance(SettingsController settings) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_outlined), label: Text('Claro')),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Oscuro')),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_outlined), label: Text('Sistema')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
            showSelectedIcon: false,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: Container(width: 28, height: 28, decoration: BoxDecoration(color: Color(settings.accent), shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline))),
          title: const Text('Color de los botones'),
          subtitle: const Text('Acento principal de la app'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _pickAccentColor,
        ),
        ListTile(
          leading: Container(width: 28, height: 28, decoration: BoxDecoration(color: settings.hasCustomBackground ? Color(settings.background!) : null, shape: BoxShape.circle, border: Border.all(color: Theme.of(context).colorScheme.outline))),
          title: const Text('Color de fondo'),
          subtitle: Text(settings.hasCustomBackground ? 'Personalizado' : 'Predeterminado según el modo'),
          trailing: settings.hasCustomBackground ? IconButton(icon: const Icon(Icons.settings_backup_restore), tooltip: 'Restablecer', onPressed: () => settings.setBackground(null)) : const Icon(Icons.chevron_right),
          onTap: _pickBackgroundColor,
        ),
      ],
    );
  }

  Widget _buildBinaries(SettingsController settings) {
    final b = _bins;
    final yt = b?.ytDlpPresent ?? false;
    final ff = b?.ffmpegPresent ?? false;
    final status = b == null ? 'Revisando…' : 'yt-dlp ${yt ? '✓' : '✗'} · ffmpeg ${ff ? '✓' : '✗'}';
    final installed = yt && ff;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.build_outlined),
          title: const Text('Binarios yt-dlp / ffmpeg'),
          subtitle: Text(status),
          trailing: _downloading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton.tonalIcon(
                  onPressed: installed ? null : _downloadBinaries,
                  icon: const Icon(Icons.download, size: 18),
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
      child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
    );
  }
}
