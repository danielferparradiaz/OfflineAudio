import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/library_screen.dart';

Widget _wrap(int tick) {
  return AppModelProvider(
    model: AppModel(),
    child: MaterialApp(
      home: Scaffold(body: LibraryScreen(settingsReturnTick: tick)),
    ),
  );
}

void main() {
  testWidgets('macOS: volver de Ajustes hace pop sutil en el buscador', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    await tester.pumpWidget(_wrap(0));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    // El shell sube el tick al volver de Ajustes: la animación corre sola.
    await tester.pumpWidget(_wrap(1));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('off-macOS: el tick no rompe nada', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    await tester.pumpWidget(_wrap(0));
    await tester.pumpAndSettle();
    await tester.pumpWidget(_wrap(1));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
