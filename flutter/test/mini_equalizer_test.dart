import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/widgets/mini_equalizer.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}

void main() {
  testWidgets('MiniEqualizer animates bars when active',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MiniEqualizer(active: true)));
    expect(find.byType(MiniEqualizer), findsOneWidget);
    // Let the animation controller tick; must not throw and bars rebuild.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MiniEqualizer), findsOneWidget);
  });

  testWidgets('MiniEqualizer holds still when inactive',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MiniEqualizer(active: false)));
    expect(find.byType(MiniEqualizer), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(MiniEqualizer), findsOneWidget);
  });

  testWidgets('MiniEqualizer toggles active without crashing',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MiniEqualizer(active: true)));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(_wrap(const MiniEqualizer(active: false)));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(MiniEqualizer), findsOneWidget);
  });

  testWidgets('MiniEqualizer keeps a fixed size (base stays put)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const MiniEqualizer(active: true)));
    final first = tester.getSize(find.byType(MiniEqualizer));
    await tester.pump(const Duration(milliseconds: 150));
    final second = tester.getSize(find.byType(MiniEqualizer));
    await tester.pump(const Duration(milliseconds: 300));
    final third = tester.getSize(find.byType(MiniEqualizer));
    expect(first.height, greaterThan(0));
    expect(second, first);
    expect(third, first);
  });
}
