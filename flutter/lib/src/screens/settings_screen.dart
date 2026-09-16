import 'package:flutter/cupertino.dart' show CupertinoSegmentedControl;
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_update.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/settings.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

  /// Versión de la app instalada (pubspec `version:`) y resultado del
  /// chequeo contra el último release publicado en GitHub.
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
          // Sin binario el motor se auto-abastece en segundo plano: no se
          // le pide nada al usuario, solo se refleja el estado.
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

  /// Comprueba si hay una release más nueva en GitHub (ver [checkAppUpdate]).
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
          _SectionTitle('Aplicación'),
          ListTile(
            leading: const HugeIcon(
              icon: HugeIcons.strokeRoundedCloudSavingDone01,
            ),
            title: const Text('Versión de OfflineAudio'),
            subtitle: Text('v$_appVersion instalada'),
            trailing: _checkingUpdate
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
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
          const Divider(),
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
    return Column(
      children: [
        CircleAvatar(
          radius: 28,
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedUser,
            size: 32,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => _showSyncInfo(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCloud,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Sync',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Explica la utilidad de Sync: mantener biblioteca, listas de reproducción
  /// y vídeos sincronizados entre dispositivos con la cuenta de OfflineAudio.
  Future<void> _showSyncInfo(BuildContext context) {
    return showSyncInfoDialog(context);
  }

  Widget _buildFooter(BuildContext context) {
    final subtle = Theme.of(context).colorScheme.onSurface
        .withValues(alpha: 0.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'OfflineAudio 1.1.0 · uso personal.\n'
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
      // En anchos estrechos (cajón de Windows/Android, ventanas pequeñas)
      // los 3 segmentos con icono+texto desbordan: se muestran solo iconos.
      segmented = LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 400;
          ButtonSegment<ThemeMode> seg(
            ThemeMode value,
            List<List<dynamic>> icon,
            String label,
          ) {
            return ButtonSegment(
              value: value,
              icon: HugeIcon(icon: icon, size: 24),
              label: compact
                  ? null
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(label),
                    ),
              tooltip: compact ? label : null,
            );
          }

          return SegmentedButton<ThemeMode>(
            segments: [
              seg(ThemeMode.light, HugeIcons.strokeRoundedSun01, 'Claro'),
              seg(ThemeMode.dark, HugeIcons.strokeRoundedMoon02, 'Oscuro'),
              seg(
                ThemeMode.system,
                HugeIcons.strokeRoundedMagicWand01,
                'Sistema',
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
            showSelectedIcon: false,
          );
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: segmented,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
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
