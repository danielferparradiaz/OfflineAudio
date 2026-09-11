import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/settings.dart';

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
    } catch (e) {
      if (mounted) {
        setState(
          () => _ytdlpMessage = 'Error cargando configuración: ${e.toString()}',
        );
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

  Future<void> _downloadBinaries() async {
    setState(() => _downloading = true);
    try {
      await downloadMobileBinaries();
      final status = await binariesStatus();
      if (mounted) setState(() => _bins = status);
      if (mounted) showAppSnackBar(context, message: 'Paquetes instalados');
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, message: 'No se pudo descargar: $e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsScope.of(context);
    final body = SingleChildScrollView(
      padding: EdgeInsets.all(isApplePlatform ? 20 : 16),
      child: Column(
        children: [
          _buildUserInfo(context),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
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
          const SizedBox(height: 32),
          _buildFooter(context),
        ],
      ),
    );
    return AppPage(title: 'Ajustes', body: body);
  }

  Widget _buildUserInfo(BuildContext context) {
    // Solo el avatar por ahora: en el futuro abrirá "sincronizar con la nube"
    // o "crear mi cuenta de OfflineAudio Cloud".
    return Center(
      child: CircleAvatar(
        radius: 28,
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedUser,
          size: 32,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'OfflineAudio 1.0 · uso personal.\n'
        'Uso exclusivo de contenidos que tienes derecho a descargar.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: subtle),
      ),
    );
  }

  Widget _buildAppearance(SettingsController settings) {
    final Widget segmented;
    if (isApplePlatform) {
      final isDark = Theme.of(context).brightness == Brightness.dark;
      final textColor = Theme.of(context).colorScheme.onSurface;
      segmented = CupertinoSegmentedControl<ThemeMode>(
        groupValue: settings.themeMode,
        onValueChanged: settings.setThemeMode,
        selectedColor: Color(settings.accent),
        unselectedColor: isDark
            ? const Color(0x26FFFFFF)
            : const Color(0x0A000000),
        borderColor: isDark ? const Color(0x33FFFFFF) : const Color(0x1A000000),
        children: {
          ThemeMode.light: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Claro', style: TextStyle(color: textColor)),
          ),
          ThemeMode.dark: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Oscuro', style: TextStyle(color: textColor)),
          ),
          ThemeMode.system: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('Sistema', style: TextStyle(color: textColor)),
          ),
        },
      );
    } else {
      segmented = SegmentedButton<ThemeMode>(
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
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: segmented,
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

  String _ytdlpSubtitle() {
    final y = _ytdlp;
    if (y == null) return 'Cargando…';
    if (!y.present) return 'No instalado';
    final v = y.version ?? 'desconocida';
    return 'v$v · ${y.outdated ? 'desactualizado' : 'actualizado'}';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
