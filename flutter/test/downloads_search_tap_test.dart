import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/screens/downloads_screen.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

class _FakeModel extends AppModel {
  @override
  Future<List<SearchHistoryEntry>> loadRecentSearches(String source) async {
    return [
      SearchHistoryEntry(
        id: 1,
        query: 'salsa queen astoria',
        source: 'youtube',
        createdAt: '2026-01-01',
      ),
    ];
  }
}

void main() {
  testWidgets('tapping a suggestion fills the field and searches',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      AppModelProvider(
        model: _FakeModel(),
        child: const MaterialApp(
          home: Scaffold(body: DownloadsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(EditableText));
    await tester.pumpAndSettle();

    expect(find.text('Búsquedas recientes'), findsOneWidget);
    expect(find.text('salsa queen astoria'), findsOneWidget);

    await tester.tap(find.text('salsa queen astoria'));
    await tester.pump();

    final editable =
        tester.widget<EditableText>(find.byType(EditableText).first);
    expect(editable.controller.text, 'salsa queen astoria');

    // La búsqueda dispara una red real (bloqueada en tests). Deja que su
    // timeout de 25s se agote en el reloj fake y desecha el árbol para
    // cancelar el debounce de predicciones antes del teardown.
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}