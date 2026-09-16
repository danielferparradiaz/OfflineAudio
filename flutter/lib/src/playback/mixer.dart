import 'dart:math' as math;

/// DJ-style crossfade between consecutive tracks (Apple Music feel):
/// song B enters while song A still sounds, overlapping [kMixCrossfadeSeconds]
/// with an equal-power curve. Always on for audio queues; video tracks,
/// previews and single-track playback keep the stock gap.
const double kMixCrossfadeSeconds = 12;

/// Equal-power gains for the crossfade position [t] in 0..1.
///
/// `cos`/`sin` keep the perceived loudness flat through the middle of the
/// transition, unlike a linear ramp whose centre sounds dipped.
/// Returns `(outGain, inGain)` in 0..1.
({double outGain, double inGain}) equalPowerGains(double t) {
  final c = t.clamp(0.0, 1.0) * math.pi / 2;
  return (outGain: math.cos(c), inGain: math.sin(c));
}

/// Whether the queue must be driven track-by-track (manual advance with two
/// players) instead of letting media_kit auto-advance a playlist: only for
/// crossfade over 2+ local audio tracks.
bool isManualQueueEligible({
  required bool playingPlaylist,
  required int queueLength,
  required bool hasVideo,
  required bool preview,
}) =>
    playingPlaylist && queueLength > 1 && !hasVideo && !preview;

/// Seconds remaining at which the overlap starts, or null when no mixer
/// action applies right now (no next track or not an eligible queue).
double? mixTriggerRemaining({required bool hasNext, required bool eligible}) {
  if (!eligible || !hasNext) return null;
  return kMixCrossfadeSeconds;
}
