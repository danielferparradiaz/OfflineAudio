import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio_app/src/playback/mixer.dart';

void main() {
  test('crossfade length is fixed at 12 s', () {
    expect(kMixCrossfadeSeconds, 12);
    expect(
      mixTriggerRemaining(hasNext: true, eligible: true),
      kMixCrossfadeSeconds,
    );
  });

  test('equalPowerGains endpoints and flat middle', () {
    final start = equalPowerGains(0);
    expect(start.outGain, closeTo(1.0, 1e-9));
    expect(start.inGain, closeTo(0.0, 1e-9));

    final end = equalPowerGains(1);
    expect(end.outGain, closeTo(0.0, 1e-9));
    expect(end.inGain, closeTo(1.0, 1e-9));

    // Equal-power: no dip in the middle (both ~0.707, power sums to 1).
    final mid = equalPowerGains(0.5);
    expect(mid.outGain, closeTo(0.7071, 1e-3));
    expect(mid.inGain, closeTo(0.7071, 1e-3));
    expect(
      mid.outGain * mid.outGain + mid.inGain * mid.inGain,
      closeTo(1.0, 1e-9),
    );

    // Clamped outside 0..1.
    expect(equalPowerGains(-2).outGain, closeTo(1.0, 1e-9));
    expect(equalPowerGains(42).inGain, closeTo(1.0, 1e-9));
  });

  test('mixTriggerRemaining gates on next/eligibility', () {
    expect(
      mixTriggerRemaining(hasNext: false, eligible: true),
      isNull,
    );
    expect(
      mixTriggerRemaining(hasNext: true, eligible: false),
      isNull,
    );
  });

  test('isManualQueueEligible requires audio-only playlist queue', () {
    expect(
      isManualQueueEligible(
        playingPlaylist: true,
        queueLength: 3,
        hasVideo: false,
        preview: false,
      ),
      isTrue,
    );
    expect(
      isManualQueueEligible(
        playingPlaylist: false,
        queueLength: 3,
        hasVideo: false,
        preview: false,
      ),
      isFalse,
    );
    expect(
      isManualQueueEligible(
        playingPlaylist: true,
        queueLength: 1,
        hasVideo: false,
        preview: false,
      ),
      isFalse,
    );
    expect(
      isManualQueueEligible(
        playingPlaylist: true,
        queueLength: 3,
        hasVideo: true,
        preview: false,
      ),
      isFalse,
    );
    expect(
      isManualQueueEligible(
        playingPlaylist: true,
        queueLength: 3,
        hasVideo: false,
        preview: true,
      ),
      isFalse,
    );
  });
}
