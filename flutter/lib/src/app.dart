import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/screens/library_screen.dart';
import 'package:offline_audio_app/src/screens/downloads_screen.dart';
import 'package:offline_audio_app/src/screens/playlists_screen.dart';
import 'package:offline_audio_app/src/screens/settings_screen.dart';
import 'package:offline_audio_app/src/settings.dart';
import 'package:offline_audio_app/src/widgets/player_bar.dart';

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
    final bg = s.background;
    final colorScheme = bg != null
        ? scheme.copyWith(
            surface: Color(bg),
            surfaceContainerHighest: Color(bg),
          )
        : scheme;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: bg != null ? Color(bg) : scheme.surface,
      cardColor: bg != null ? Color(bg) : scheme.surface,
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

    final messenger = ScaffoldMessenger.of(context);
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

    try {
      await downloadMobileBinaries();
      messenger.showSnackBar(
        const SnackBar(content: Text('Paquetes instalados')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo descargar: $e')),
      );
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
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primary, primary.withValues(alpha: 0.55)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Icon(Icons.graphic_eq, size: 56, color: Colors.white),
            ),
            const SizedBox(height: 24),
            Text(
              'OfflineAudio',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Reproductor offline',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    AppModelProvider.of(context); // rebuild on state changes
    final pages = [
      const LibraryScreen(),
      const DownloadsScreen(),
      const PlaylistsScreen(),
    ];
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(index: _index, children: pages),
          ),
          const PlayerBar(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _navButton(0, Icons.library_music, 'Biblioteca'),
            _navButtonWithBadge(1, Icons.download, 'Descargas',
                completedCount: AppModelProvider.of(context).downloads.length +
                    AppModelProvider.of(context).downloadErrors.length),
            _navButton(2, Icons.queue_music, 'Playlists'),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Ajustes',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButton(int index, IconData icon, String label) {
    final selected = _index == index;
    return InkWell(
      onTap: () => setState(() => _index = index),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.white54),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: selected ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _navButtonWithBadge(
      int index, IconData icon, String label, {int? completedCount}) {
    final selected = _index == index;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: () => setState(() => _index = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: selected ? Colors.white : Colors.white54),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: selected ? Colors.white : Colors.white54,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (completedCount != null && completedCount > 0)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                completedCount > 99 ? '99+' : completedCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}