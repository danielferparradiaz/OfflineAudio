import 'dart:math' as math;

import 'package:offline_audio_app/src/rust/engine/models.dart';

/// Fraction of the track the playhead must reach to count a full listen.
const double kCompletionThreshold = 0.85;

/// Expert shuffle ("el clásico en su momento justo").
///
/// Not the most-played, not the least-played: the weight peaks on tracks
/// with a few full listens (1–4), long-unplayed, settled in the library a
/// while ago, and actually finished when started (low skip proxy). Ordering
/// is a weighted sample without replacement (Efraimidis–Spirakis), so every
/// shuffle surprises but the neglected classics come first on average.
///
/// All signals already live on [Track]: [Track.completedCount],
/// [Track.totalListenSeconds], [Track.playCount], [Track.lastPlayed],
/// [Track.downloadDate], [Track.durationSeconds].
List<Track> smartShuffleOrder(
  List<Track> tracks, {
  DateTime? now,
  math.Random? random,
}) {
  if (tracks.length <= 1) return List<Track>.of(tracks);
  final at = (now ?? DateTime.now()).toUtc();
  final rng = random ?? math.Random();
  final scored = [
    for (final t in tracks)
      (
        key: math.pow(rng.nextDouble(), 1 / smartWeight(t, at)),
        track: t,
      ),
  ];
  // nextDouble() can return 0 → pow(0, ·) = 0; still a valid total order.
  scored.sort((a, b) => (b.key as double).compareTo(a.key as double));
  return [for (final s in scored) s.track];
}

/// Raw weight for one track at time [now] (higher = should surface sooner).
/// Product of independent 0..~1.2 factors so each signal can veto.
double smartWeight(Track t, DateTime now) {
  final utc = now.toUtc();
  final completions = t.completedCount.toInt();
  final starts = t.playCount.toInt();

  // Familiarity curve: peaks at a few full listens, mild for the unplayed,
  // decays for the overplayed. (c+1)·e^(-(c+1)/3): c=0→0.72, 1→1.03,
  // 2→1.10, 5→0.81, 10→0.28, 30→~0.
  final familiarity =
      (completions + 1) * math.exp(-(completions + 1) / 3);

  // Recency: recently played → suppressed; long ago → ~1.
  final last = _tryParseDate(t.lastPlayed);
  final daysSincePlayed =
      last == null ? null : utc.difference(last).inDays.clamp(0, 3650);
  final recency = daysSincePlayed == null
      ? 0.85 // never played: warm, decided below by library age
      : 1 - math.exp(-daysSincePlayed / 30);

  // Settling: brand-new unplayed tracks wait their turn (the "least" we
  // don't push); forgotten unplayed classics get full weight.
  double settle = 1;
  if (last == null) {
    final downloaded = _tryParseDate(t.downloadDate);
    final ageDays = downloaded == null
        ? 30
        : utc.difference(downloaded).inDays.clamp(0, 3650);
    settle = ageDays < 14 ? 0.45 : 1.0;
  }

  // Finish ratio: many starts but few completions = skipped a lot.
  final ratio = completions / math.max(1, starts);
  final finish = 0.5 + 0.5 * ratio.clamp(0.0, 1.0);

  // Duration: favour the listenable middle (90 s – 10 min), taper the
  // extremes instead of vetoing them.
  final secs = t.durationSeconds?.toInt() ?? 240;
  final duration = secs < 90
      ? 0.6
      : secs <= 600
          ? 1.0
          : 0.8;

  return familiarity * recency * settle * finish * duration;
}

DateTime? _tryParseDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}
