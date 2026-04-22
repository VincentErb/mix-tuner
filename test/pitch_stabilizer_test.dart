import 'package:flutter_test/flutter_test.dart';
import 'package:guitaleletuner/services/pitch_service.dart';
import 'package:guitaleletuner/services/pitch_stabilizer.dart';

RawPitch raw(double hz, {double rms = 0.05, double prob = 0.95}) =>
    RawPitch(frequencyHz: hz, pitched: hz > 0, probability: prob, rms: rms);

void main() {
  group('PitchStabilizer', () {
    test('silence below RMS gate returns unpitched', () {
      final s = PitchStabilizer();
      final out = s.process(raw(110, rms: 0.001));
      expect(out.pitched, isFalse);
      expect(out.frequencyHz, 0);
    });

    test('rejects low-probability frames', () {
      final s = PitchStabilizer();
      final out = s.process(raw(110, prob: 0.3));
      expect(out.pitched, isFalse);
    });

    test('median filter suppresses single outlier', () {
      final s = PitchStabilizer();
      // Seed with steady A2 ≈ 110 Hz.
      for (int i = 0; i < 4; i++) {
        s.process(raw(110.0));
      }
      // Rogue frame — but not octave-related (3rd harmonic area).
      final out = s.process(raw(165.0));
      // Median of [110,110,110,110,165] = 110.
      expect(out.frequencyHz, closeTo(110, 0.5));
    });

    test('octave jump up is corrected down', () {
      final s = PitchStabilizer();
      for (int i = 0; i < 4; i++) {
        s.process(raw(110.0));
      }
      // YIN mis-detects an octave up.
      final out = s.process(raw(220.0));
      // After halving, median stays near 110.
      expect(out.frequencyHz, closeTo(110, 1));
    });

    test('silence clears history', () {
      final s = PitchStabilizer();
      for (int i = 0; i < 5; i++) {
        s.process(raw(110.0));
      }
      s.process(raw(0, rms: 0.0)); // silent — should clear
      // Now a new note at 220 should NOT be octave-corrected.
      final out = s.process(raw(220.0));
      expect(out.frequencyHz, closeTo(220, 1));
    });
  });
}
