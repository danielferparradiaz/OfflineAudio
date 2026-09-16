import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/playback/smart_shuffle.dart';
import 'package:offline_audio_app/src/rust/engine/models.dart';

Track _track({
  required String id,
  int completions = 0,
  int starts = 0,
  String? lastPlayed,
  String downloadDate = '2024-01-01T00:00:00Z',
  int durationSeconds = 240,
}) {
  return Track(
    id: id,
    sourceId: 'youtube:$id',
    networkUrl: 'https://example.com/watch?v=$id',
    title: 'Song $id',
    filePath: '/cache/$id.opus',
    contentKind: 'music',
    downloadDate: downloadDate,
    playCount: starts,
    lastPlayed: lastPlayed,
    completedCount: completions,
    totalListenSeconds: completions * durationSeconds,
    durationSeconds: durationSeconds,
  );
}

void main() {
  final now = DateTime.utc(2026, 9, 16);

  test('neglected classic outranks the overplayed hit', () {
    final classic = _track(
      id: 'classic',
      completions: 2,
      starts: 2,
      lastPlayed: '2026-02-01T00:00:00Z',
    );
    final hit = _track(
      id: 'hit',
      completions: 50,
      starts: 60,
      lastPlayed: '2026-09-15T00:00:00Z',
    );
    expect(
      smartWeight(classic, now),
      greaterThan(smartWeight(hit, now) * 2),
    );
  });

  test('forgotten unplayed classic outranks brand-new unplayed', () {
    final forgotten = _track(id: 'old', downloadDate: '2023-01-01T00:00:00Z');
    final fresh = _track(id: 'new', downloadDate: '2026-09-10T00:00:00Z');
    expect(
      smartWeight(forgotten, now),
      greaterThan(smartWeight(fresh, now)),
    );
  });

  test('chronic skip (starts without finishes) is penalized', () {
    final finisher = _track(
      id: 'fin',
      completions: 2,
      starts: 2,
      lastPlayed: '2026-01-01T00:00:00Z',
    );
    final skipper = _track(
      id: 'skip',
      completions: 2,
      starts: 30,
      lastPlayed: '2026-01-01T00:00:00Z',
    );
    expect(
      smartWeight(finisher, now),
      greaterThan(smartWeight(skipper, now)),
    );
  });

  test('order keeps every track and is seed-deterministic', () {
    final tracks = [
      _track(id: 'a', completions: 2, lastPlayed: '2026-01-01T00:00:00Z'),
      _track(id: 'b', completions: 40, lastPlayed: '2026-09-15T00:00:00Z'),
      _track(id: 'c', downloadDate: '2023-06-01T00:00:00Z'),
      _track(id: 'd', completions: 1, lastPlayed: '2025-01-01T00:00:00Z'),
    ];
    final first = smartShuffleOrder(tracks, now: now, random: math.Random(7));
    final second = smartShuffleOrder(tracks, now: now, random: math.Random(7));
    expect(first.map((t) => t.id), orderedEquals(second.map((t) => t.id)));
    expect(
      first.map((t) => t.id).toSet(),
      equals({'a', 'b', 'c', 'd'}),
    );
    // The overplayed recent hit should not headline with this seed.
    expect(first.first.id, isNot('b'));
  });

  test('singletons and empty pass through', () {
    expect(smartShuffleOrder([]), isEmpty);
    final one = [_track(id: 'solo')];
    expect(smartShuffleOrder(one).map((t) => t.id), ['solo']);
  });
}
