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
}