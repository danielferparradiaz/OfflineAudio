import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/widgets/queue_sheet.dart';

Widget _wrap() {
  return AppModelProvider(
    model: AppModel(),
    child: const MaterialApp(home: Scaffold(body: QueueSheet())),
  );
}

void main() {
  testWidgets('macOS Tracklist renders native panel', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(_wrap());
    expect(find.text('Tracklist'), findsOneWidget);
    // Toolbar search with SF magnifier, no legacy hint.
    expect(find.byIcon(CupertinoIcons.search), findsOneWidget);
    expect(find.text('Buscar en la cola'), findsNothing);
    // Translucent panel, no bottom-sheet grabber context.
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.text('La cola está vacía'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('legacy sheet renders off-macOS', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(_wrap());
    expect(find.text('Tracklist'), findsOneWidget);
    expect(find.text('La cola está vacía'), findsOneWidget);
    // No SF search icon, no vibrancy panel off-macOS.
    expect(find.byIcon(CupertinoIcons.search), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
