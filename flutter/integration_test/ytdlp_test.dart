import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/events.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/rust/frb_generated.dart';

const _videoUrl = 'https://www.youtube.com/watch?v=jNQXAC9IVRw'; // 19s

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await RustLib.init();
  });

  testWidgets('yt-dlp can spawn and probe a URL', (tester) async {
    final info = await probeUrl(url: _videoUrl);
    expect(info.id, isNotEmpty);
    expect(info.title, isNotEmpty);
  });

  testWidgets(
    'download finishes: terminal event arrives and track lands in library',
    (tester) async {
      final sub = eventStream().listen((_) {});
      try {
        final taskId = await startDownload(url: _videoUrl, kind: ContentKind.music);
        expect(taskId, isNotEmpty);

        // Wait until the engine reports the task finished (terminal events are
        // library events; poll the library to stay tolerant of event timing).
        Track? track;
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (DateTime.now().isBefore(deadline)) {
          final library = await getLibrary(order: SortOrder.dateDesc);
          if (library.isNotEmpty) {
            track = library.first;
            break;
          }
          final active = await activeDownloadCount();
          if (active == BigInt.zero) break;
          await Future<void>.delayed(const Duration(seconds: 2));
        }

        expect(
          track,
          isNotNull,
          reason: 'La descarga nunca terminó (sin evento/estado final)',
        );
        expect(track!.title, isNotEmpty);

        // The completed entry must be playable from disk.
        final fetched = await getTrack(id: track.id);
        expect(fetched, isNotNull);
        expect(fetched!.filePath, endsWith('.opus'));

        // Clean up so the test does not pollute the user library.
        await deleteTrack(id: track.id);
        final afterDelete = await getLibrary(order: SortOrder.dateDesc);
        expect(afterDelete.where((t) => t.id == track!.id), isEmpty);
      } finally {
        await sub.cancel();
      }
    },
  );
}
