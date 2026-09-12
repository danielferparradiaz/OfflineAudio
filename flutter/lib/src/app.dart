import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:offline_audio_app/src/adaptive.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/screens/screens.dart';
import 'package:offline_audio_app/src/settings.dart';
import 'package:offline_audio_app/src/widgets/widgets.dart';

/// Single appearance settings instance used by the whole app.
final SettingsController appSettings = SettingsController();

class OfflineAudioApp extends StatefulWidget {
  const OfflineAudioApp({super.key});

  @override
  State<OfflineAudioApp> createState() => _OfflineAudioAppState();
}

class _OfflineAudioAppState extends State<OfflineAudioApp> {
  @override
  void initState() {
    super.initState();
    appSettings.load();
  }

  @override
  Widget build(BuildContext context) {
    return AppModelProvider(
      child: SettingsScope(
        notifier: appSettings,
        child: Builder(
          builder: (context) {
            final settings = SettingsScope.of(context);
            return ListenableBuilder(
              listenable: settings,
              builder: (context, _) {
                final light = _buildTheme(Brightness.light, settings);
                final dark = _buildTheme(Brightness.dark, settings);
                return MaterialApp(
                  title: 'OfflineAudio',
                  debugShowCheckedModeBanner: false,
                  theme: light,
                  darkTheme: dark,
                  themeMode: settings.themeMode,
                  builder: (context, child) => CupertinoTheme(
                    data: _buildCupertinoTheme(
                      Theme.of(context).brightness,
                      settings,
                    ),
                    child: child ?? const SizedBox.shrink(),
                  ),
                  home: const RootBootstrap(),
                );
              },
            );
          },
        ),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness, SettingsController s) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Color(s.accent),
      brightness: brightness,
    );
    // Mismo fondo que el shell (macOS/Windows): negro en oscuro, blanco en
    // claro, para que ajustes, playlists y detalle de playlist no destaquen
    // con otro tono.
    final background = brightness == Brightness.dark
        ? const Color(0xFF0E0E0E)
        : const Color(0xFFFFFFFF);
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      cardColor: scheme.surface,
    );
  }

  /// Tema Cupertino para los widgets nativos en iOS/macOS. Toma el acento
  /// del mismo SettingsController que el tema Material.
  CupertinoThemeData _buildCupertinoTheme(
    Brightness brightness,
    SettingsController s,
  ) {
    final primary = Color(s.accent);
    return CupertinoThemeData(
      brightness: brightness,
      primaryColor: primary,
      textTheme: CupertinoTextThemeData(primaryColor: primary),
    );
  }
}

/// Shows the branded splash while the engine boots, then swaps to [HomeShell].
/// On Android it also asks whether to download yt-dlp/ffmpeg when missing.
class RootBootstrap extends StatefulWidget {
  const RootBootstrap({super.key});

  @override
  State<RootBootstrap> createState() => _RootBootstrapState();
}

class _RootBootstrapState extends State<RootBootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    await AppModelProvider.of(context).init();
    if (!mounted) return;
    await _ensureMobileBinaries(context);
    if (!mounted) return;
    setState(() => _ready = true);
  }

  Future<void> _ensureMobileBinaries(BuildContext context) async {
    if (!Platform.isAndroid) return;

    BinariesStatus? status;
    try {
      status = await binariesStatus();
    } catch (_) {
      return;
    }
    if (!context.mounted) return;
    if (status.ytDlpPresent && status.ffmpegPresent) return;

    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Paquetes necesarios'),
        content: const Text(
          'En Android el motor necesita yt-dlp y ffmpeg para descargar y '
          'convertir audio.\n\n¿Descargarlos ahora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Más tarde'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Descargar'),
          ),
        ],
      ),
    );
    if (go != true || !context.mounted) return;

    final contextForToast = context;
    try {
      await downloadMobileBinaries();
      if (contextForToast.mounted) {
        showAppSnackBar(contextForToast, message: 'Paquetes instalados');
      }
    } catch (e) {
      if (contextForToast.mounted) {
        showAppSnackBar(contextForToast, message: 'No se pudo descargar: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _ready ? const HomeShell() : const SplashScreen();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF0E0E1E);
    return Scaffold(
      backgroundColor: navy,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', width: 220, fit: BoxFit.contain),
            const SizedBox(height: 28),
            const Text(
              'OfflineAudio',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Reproductor offline',
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shell de navegación adaptativo:
/// - macOS: barra lateral nativa a la izquierda.
/// - iOS: CupertinoTabBar inferior con mini-player justo encima.
/// - Android/Windows: Scaffold Material con Drawer y BottomAppBar (el actual).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// Instancias estables: si se recrean en cada build, el State de
  /// LibraryScreen (búsqueda en curso / resultados) se puede perder en
  /// cada notify del AppModel.
  static const _pages = [LibraryScreen(), DownloadsScreen(), PlaylistsScreen()];

  int _completedCount() {
    final model = AppModelProvider.of(context);
    return model.downloads.length + model.downloadErrors.length;
  }

  @override
  Widget build(BuildContext context) {
    AppModelProvider.of(context); // rebuild on state changes
    if (isMacOSPlatform) return _buildMacShell(context);
    if (isIOSPlatform) return _buildIosShell(context);
    return _buildMaterialShell(context);
  }

  // ---------------------------------------------------------------- macOS
  Widget _buildMacShell(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFF2F2F7);
    final background = isDark
        ? const Color(0xFF0E0E0E)
        : const Color(0xFFFFFFFF);
    return CupertinoPageScaffold(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: background,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 220, child: _buildSidebar(context, sidebarColor)),
              const VerticalDivider(width: 1),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(index: _index, children: _pages),
                    ),
                    const PlayerBar(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, Color background) {
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 18, 24, 10),
              child: Text(
                'OfflineAudio',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            _sideItem(context, 0, HugeIcons.strokeRoundedLibrary, 'Biblioteca'),
            _sideItem(
              context,
              1,
              HugeIcons.strokeRoundedDownload01,
              'Descargas',
              badge: _completedCount(),
            ),
            _sideItem(context, 2, HugeIcons.strokeRoundedQueue01,
                'Listas de reproducción'),
            const Spacer(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        HugeIcon(
                          icon: HugeIcons.strokeRoundedSettings01,
                          size: 18,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        const SizedBox(width: 10),
                        const Text('Ajustes'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Icono Hugeicons (datos JSON del trazo).
  Widget _sideItem(
    BuildContext context,
    int index,
    List<List<dynamic>> icon,
    String label, {
    int? badge,
  }) {
    final selected = _index == index;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected
            ? onSurface.withValues(alpha: isApplePlatform ? 0.12 : 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _index = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                HugeIcon(
                  icon: icon,
                  size: 18,
                  color: selected
                      ? scheme.primary
                      : onSurface.withValues(alpha: 0.75),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: selected
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
                if (badge != null && badge > 0) _badge(badge),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- iOS
  Widget _buildIosShell(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        activeColor: scheme.primary,
        inactiveColor: scheme.onSurface.withValues(alpha: 0.45),
        items: [
          _iosTab(HugeIcons.strokeRoundedLibrary, 'Biblioteca'),
          _iosTab(
            HugeIcons.strokeRoundedDownload01,
            'Descargas',
            badge: _completedCount(),
          ),
          _iosTab(HugeIcons.strokeRoundedQueue01, 'Listas de reproducción'),
        ],
      ),
      tabBuilder: (context, index) => Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(
            children: [
              Expanded(child: _pages[index]),
              const PlayerBar(),
            ],
          ),
        ),
      ),
    );
  }

  BottomNavigationBarItem _iosTab(
    List<List<dynamic>> icon,
    String label, {
    int? badge,
  }) {
    final iconWidget = badge != null && badge > 0
        ? _badgedIcon(icon, badge)
        : HugeIcon(icon: icon, size: 24);
    return BottomNavigationBarItem(
      icon: iconWidget,
      activeIcon: iconWidget,
      label: label,
    );
  }

  Stack _badgedIcon(List<List<dynamic>> icon, int badge) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        HugeIcon(icon: icon, size: 24),
        Positioned(right: -8, top: -4, child: _badge(badge)),
      ],
    );
  }

  Widget _badge(int count) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: const BoxDecoration(
        color: Colors.green,
        shape: BoxShape.circle,
      ),
      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  // --------------------------------------------- Android / Windows / Linux
  Widget _buildMaterialShell(BuildContext context) {
    return Scaffold(
      endDrawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 32,
                  horizontal: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      child: HugeIcon(
                        icon: HugeIcons.strokeRoundedUser,
                        size: 32,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Invitado',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      'Cuenta sin iniciar',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
              const Divider(height: 1),
              const Expanded(child: SettingsDrawerContent()),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _index, children: _pages),
          ),
          const PlayerBar(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navButton(0, HugeIcons.strokeRoundedLibrary, 'Biblioteca'),
            _navButtonWithBadge(
              1,
              HugeIcons.strokeRoundedDownload01,
              'Descargas',
              completedCount: _completedCount(),
            ),
            _navButton(2, HugeIcons.strokeRoundedQueue01, 'Listas de reproducción'),
          ],
        ),
      ),
    );
  }

  Widget _navButton(int index, List<List<dynamic>> icon, String label) {
    final selected = _index == index;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => setState(() => _index = index),
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: selected
                    ? scheme.secondaryContainer
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: HugeIcon(
                icon: icon,
                color: selected
                    ? scheme.onSecondaryContainer
                    : scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: selected
                  ? Padding(
                      padding: const EdgeInsets.only(top: 2),
                      // Límite de ancho para que el nuevo nombre largo
                      // ("Listas de reproducción") no desborde el
                      // BottomAppBar en pantallas estrechas.
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 108),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurface.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButtonWithBadge(
    int index,
    List<List<dynamic>> icon,
    String label, {
    int? completedCount,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _navButton(index, icon, label),
        if (completedCount != null && completedCount > 0)
          Positioned(right: -4, top: -4, child: _badge(completedCount)),
      ],
    );
  }
}
