import 'package:flutter/material.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/library_screen.dart';
import 'package:offline_audio_app/src/screens/downloads_screen.dart';
import 'package:offline_audio_app/src/screens/playlists_screen.dart';
import 'package:offline_audio_app/src/screens/settings_screen.dart';
import 'package:offline_audio_app/src/widgets/player_bar.dart';

class OfflineAudioApp extends StatelessWidget {
  const OfflineAudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppModelProvider(
      child: MaterialApp(
        title: 'OfflineAudio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1DB954),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomeShell(),
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppModelProvider.of(context).init();
    });
  }

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
                fontSize: 10,  // redujimos de 11 a 10
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