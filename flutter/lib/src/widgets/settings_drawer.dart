import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/app_update.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  String _appVersion = '…';
  String? _updateMessage;
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
    try {
      final ytdlp = await getYtdlpStatus();
      final dirs = await appDirs();
      if (mounted) {
        setState(() {
          _ytdlp = ytdlp;
          _dirs = dirs;
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
          _ytdlpMessage = !ytdlp.present
              ? 'Motor preparándose…'
              : ytdlp.outdated
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

  Future<void> _checkAppVersion() async {
    setState(() {
      _checkingUpdate = true;
      _updateMessage = null;
    });
    final message = await checkAppUpdate(_appVersion);
    if (!mounted) return;
    setState(() {
      _updateMessage = message;
      _checkingUpdate = false;
    });
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
          _SectionTitle('Aplicación'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Versión'),
            subtitle: Text('OfflineAudio v$_appVersion instalada'),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    iconSize: 22,
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                    onPressed: _checkAppVersion,
                  ),
          ),
          if (_updateMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _updateMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: const Text('Comprobar yt-dlp'),
            subtitle: Text(_ytdlpSubtitle()),
            trailing: _checking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    iconSize: 22,
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
              'OfflineAudio 1.1.1 · uso personal.\nUso exclusivo de contenidos que tienes derecho a descargar.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearance(SettingsController settings) {
    // El cajón es estrecho (~300dp): segmentos solo con icono para que no
    // desborden ni se estiren las filas, centrados como en el resto.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(child: _AppearanceSegments(settings: settings)),
    );
  }
}

class _AppearanceSegments extends StatelessWidget {
  const _AppearanceSegments({required this.settings});

  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
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
