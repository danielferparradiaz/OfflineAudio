import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/downloads_screen.dart';
import 'package:offline_audio_app/src/screens/playlists_screen.dart';
import 'package:offline_audio_app/src/widgets/player_bar.dart';

Widget _wrap(Widget child, {AppModel? model}) {
  return AppModelProvider(
    model: model ?? AppModel(),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  test('DownloadState fraction clamps 0..100', () {
    final st = DownloadState(
      percent: 43.7,
      downloadedBytes: BigInt.from(100),
    );
    expect(st.fraction, closeTo(0.437, 0.001));

    final over = DownloadState(
      percent: 150,
      downloadedBytes: BigInt.from(1),
    );
    expect(over.fraction, 1.0);

    final neg = DownloadState(
      percent: -5,
      downloadedBytes: BigInt.from(1),
    );
    expect(neg.fraction, 0.0);
  });

  testWidgets('PlayerBar shows empty state without track',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PlayerBar()));
    expect(find.text('Sin reproducción'), findsOneWidget);
  });

  testWidgets('DownloadsScreen shows empty state', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const DownloadsScreen()));
    expect(find.text('Descargas'), findsOneWidget);
    expect(find.text('No hay descargas activas'), findsOneWidget);
  });

  testWidgets('PlaylistsScreen shows empty state', (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PlaylistsScreen()));
    expect(find.text('Playlists'), findsOneWidget);
    expect(find.textContaining('Aún no hay playlists'), findsOneWidget);
  });
}
