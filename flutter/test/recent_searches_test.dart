import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/app_model.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';
import 'package:offline_audio_app/src/widgets/recent_searches.dart';

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
  testWidgets('RecentSearches loads history from model', (tester) async {
    await tester.pumpWidget(
      AppModelProvider(
        model: _FakeModel(),
        child: MaterialApp(
          home: Scaffold(
            body: RecentSearches(
              source: 'youtube',
              onTap: (q) {},
              onDelete: (e) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Búsquedas recientes'), findsOneWidget);
    expect(find.text('salsa queen astoria'), findsOneWidget);
  });

  testWidgets('Keyboard selection moves and confirms history', (tester) async {
    final key = GlobalKey<RecentSearchesState>();
    await tester.pumpWidget(
      AppModelProvider(
        model: _FakeModel(),
        child: MaterialApp(
          home: Scaffold(
            body: RecentSearches(
              key: key,
              source: 'youtube',
              onTap: (q) {},
              onDelete: (e) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final state = key.currentState!;
    expect(state.navItemCount, 1);
    expect(state.hasNavSelection, isFalse);
    expect(state.confirmSelection(), isNull);

    // Sin ítems no hace nada; con uno, abajo entra al primero.
    state.moveSelection(1);
    await tester.pump();
    expect(state.hasNavSelection, isTrue);
    expect(state.confirmSelection(), 'salsa queen astoria');
    // Resaltado visible en la lista.
    expect(find.text('↑↓ navegar · Enter buscar'), findsOneWidget);

    // Arriba desde el primero vuelve al campo (sin selección).
    state.moveSelection(-1);
    await tester.pump();
    expect(state.hasNavSelection, isFalse);

    state.moveSelection(1);
    await tester.pump();
    state.clearSelection();
    await tester.pump();
    expect(state.hasNavSelection, isFalse);
  });
}