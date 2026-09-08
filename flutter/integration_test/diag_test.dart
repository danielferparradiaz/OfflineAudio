import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_audio_app/src/rust/api/engine_api.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/rust/frb_generated.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'diag: start download and watch state',
    (tester) async {
      await RustLib.init();
      addTearDown(() async {});

      final events = <String>[];
      final sub = eventStream().listen((e) {
        events.add(e.runtimeType.toString());
      });

      await startDownload(
        url: 'https://www.youtube.com/watch?v=jNQXAC9IVRw',
        kind: ContentKind.music,
      );

      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final active = await activeDownloadCount();
        if (active == 0) break;
      }

      final lib = await getLibrary(order: SortOrder.dateDesc);
      final ev = events.toSet().toList();
      // Summary intentionally printed via expect message on pass/fail.
      expect(
        lib.isNotEmpty,
        isTrue,
        reason:
            'events=$events distinct=$ev active observations done lib=${lib.length}',
      );
      if (lib.isNotEmpty) {
        await deleteTrack(id: lib.first.id);
      }
      await sub.cancel();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
