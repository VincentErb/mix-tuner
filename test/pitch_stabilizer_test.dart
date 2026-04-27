import 'package:flutter_test/flutter_test.dart';
import 'package:mix_tuner/services/pitch_service.dart';
import 'package:mix_tuner/services/pitch_stabilizer.dart';

RawPitch raw(double hz, {double rms = 0.05, double clarity = 0.95}) =>
    RawPitch(frequencyHz: hz, pitched: hz > 0, clarity: clarity, rms: rms);

/// Feeds [n] frames at [hz] to bring the stabilizer to a settled, pitched
/// state. [n] needs to cover onset suppression (4 frames) + stability gate
/// (3 frames) + headroom — 12 is a safe default.
StablePitch settle(PitchStabilizer s, double hz, {int n = 12}) {
  StablePitch out = StablePitch.silent;
  for (int i = 0; i < n; i++) {
    out = s.process(raw(hz));
  }
  return out;
}

void main() {
  group('PitchStabilizer — basic gating', () {
    test('silence below RMS gate eventually returns unpitched', () {
      final s = PitchStabilizer();
      for (int i = 0; i < 15; i++) {
        s.process(raw(110, rms: 0.0005));
      }
      final out = s.process(raw(110, rms: 0.0005));
      expect(out.pitched, isFalse);
    });

    test('low-clarity frames eventually become unpitched', () {
      final s = PitchStabilizer();
      for (int i = 0; i < 15; i++) {
        s.process(raw(110, clarity: 0.3));
      }
      final out = s.process(raw(110, clarity: 0.3));
      expect(out.pitched, isFalse);
    });
  });

  group('PitchStabilizer — stability gate', () {
    test('a single pitched frame does NOT produce output (noise rejection)', () {
      final s = PitchStabilizer();
      // One isolated valid frame — should be rejected as "not yet stable".
      final out = s.process(raw(110.0));
      expect(out.pitched, isFalse,
          reason: 'one frame is not enough to overcome the stability gate');
    });

    test('three consistent frames cross the stability gate', () {
      // Disable attack suppression here — we're testing the stability gate
      // itself, not the onset path.
      final s = PitchStabilizer(stableFrames: 3, onsetSuppressFrames: 0);
      s.process(raw(110.0));
      s.process(raw(110.0));
      final out = s.process(raw(110.0));
      expect(out.pitched, isTrue);
      expect(out.frequencyHz, closeTo(110, 1));
    });

    test('inconsistent frames (random pitches) never lock', () {
      final s = PitchStabilizer(stableFrames: 3);
      // Wildly different frequencies on each frame — that's noise.
      final freqs = [110.0, 440.0, 220.0, 660.0, 90.0, 1200.0, 150.0];
      for (final f in freqs) {
        final out = s.process(raw(f));
        expect(out.pitched, isFalse,
            reason: 'noise should never produce pitched output');
      }
    });
  });

  group('PitchStabilizer — hold during decay', () {
    test('hold preserves last reading during a brief dropout', () {
      final s = PitchStabilizer();
      settle(s, 110.0);
      // One uncertain frame mid-note — should still report pitched.
      final held = s.process(raw(110, clarity: 0.2));
      expect(held.pitched, isTrue);
      expect(held.frequencyHz, closeTo(110, 2));
    });
  });

  group('PitchStabilizer — outlier and octave behavior', () {
    test('cents-space EMA suppresses single outlier', () {
      final s = PitchStabilizer();
      settle(s, 110.0);
      final out = s.process(raw(106.85)); // ~ -50¢ outlier
      expect(out.frequencyHz, closeTo(110, 2));
    });

    test('octave jump up is folded back to the running pitch', () {
      final s = PitchStabilizer();
      settle(s, 110.0);
      final out = s.process(raw(220.0));
      expect(out.frequencyHz, closeTo(110, 3));
    });
  });

  group('PitchStabilizer — silence reset', () {
    test('extended silence clears history so a new note starts fresh', () {
      final s = PitchStabilizer();
      settle(s, 110.0);
      // Long silence past hold window.
      for (int i = 0; i < 15; i++) {
        s.process(raw(0, rms: 0.0));
      }
      // New note at 220 Hz: needs onset suppression (4) + stability (3)
      // + EMA headroom to reach the new value.
      var out = StablePitch.silent;
      for (int i = 0; i < 12; i++) {
        out = s.process(raw(220.0));
      }
      expect(out.frequencyHz, closeTo(220, 5));
    });
  });

  group('PitchStabilizer — onset detection', () {
    test('onset snaps to a new pluck after silence', () {
      // Disable attack suppression for this test — we want to verify the
      // onset clears state and the pluck eventually shows up. Suppression
      // is tested separately below.
      final s = PitchStabilizer(onsetSuppressFrames: 0);
      for (int i = 0; i < 5; i++) {
        s.process(raw(0, rms: 0.0005));
      }
      var out = StablePitch.silent;
      for (int i = 0; i < 4; i++) {
        out = s.process(raw(440.0, rms: 0.1));
      }
      expect(out.frequencyHz, closeTo(440, 5));
    });

    test('attack transient is suppressed, only steady-state ring is shown', () {
      // The bug we want to fix: a pluck attack briefly produces a "consistent
      // wrong pitch" that slips through the stability gate. With suppression
      // enabled, those frames return silent.
      final s = PitchStabilizer(onsetSuppressFrames: 4);
      // Start from silence.
      for (int i = 0; i < 3; i++) {
        s.process(raw(0, rms: 0.0005));
      }
      // The attack: 4 loud, "wrong-pitch" frames simulating transient noise.
      for (int i = 0; i < 4; i++) {
        final out = s.process(raw(700.0, rms: 0.1)); // bogus pitch
        expect(out.pitched, isFalse,
            reason: 'attack-transient frames must not display');
      }
      // Now the string starts ringing cleanly at A4 — needs stableFrames
      // consistent frames to clear the gate.
      var out = StablePitch.silent;
      for (int i = 0; i < 4; i++) {
        out = s.process(raw(440.0, rms: 0.08));
      }
      expect(out.pitched, isTrue);
      expect(out.frequencyHz, closeTo(440, 5));
    });
  });
}
