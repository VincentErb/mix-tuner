import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mix_tuner/services/mpm_detector.dart';

const sampleRate = 44100;
const bufferSize = 4096;

/// Generates a buffer of N samples of a pure sine wave at [freqHz].
Float64List sine(double freqHz, {double amplitude = 0.5, double phase = 0}) {
  final out = Float64List(bufferSize);
  final twoPi = 2 * pi;
  for (int i = 0; i < bufferSize; i++) {
    out[i] = amplitude * sin(twoPi * freqHz * i / sampleRate + phase);
  }
  return out;
}

/// Mixes a fundamental + harmonics — closer to a real instrument tone.
Float64List harmonic(double f0, {List<double>? amps}) {
  final harmonics = amps ?? [1.0, 0.5, 0.3, 0.2, 0.1];
  final out = Float64List(bufferSize);
  final twoPi = 2 * pi;
  for (int i = 0; i < bufferSize; i++) {
    double v = 0;
    for (int h = 0; h < harmonics.length; h++) {
      v += harmonics[h] * sin(twoPi * f0 * (h + 1) * i / sampleRate);
    }
    out[i] = v * 0.5;
  }
  return out;
}

void main() {
  group('MpmDetector — pure sine waves', () {
    final det = MpmDetector(sampleRate: sampleRate);

    final tests = {
      'A4 (440 Hz)': 440.0,
      'A2 (110 Hz)': 110.0,
      'E2 (82.4 Hz)': 82.4,
      'E4 (329.6 Hz)': 329.6,
      'C4 (261.6 Hz)': 261.63,
    };

    for (final entry in tests.entries) {
      test('detects ${entry.key}', () {
        final result = det.detect(sine(entry.value));
        expect(result.pitched, isTrue, reason: 'should detect a pitch');
        // Sub-cent accuracy expected on pure sines.
        final cents =
            1200 * (log(result.frequencyHz / entry.value) / ln2).abs();
        expect(cents, lessThan(2.0),
            reason: 'within 2 cents of true pitch ($cents¢ off)');
        expect(result.clarity, greaterThan(0.9));
      });
    }
  });

  group('MpmDetector — harmonic-rich tones', () {
    final det = MpmDetector(sampleRate: sampleRate);

    test('detects A2 fundamental even with strong harmonics', () {
      // Like a guitalele where the 2nd harmonic can dominate.
      final buf = harmonic(110.0, amps: [0.3, 1.0, 0.5, 0.2, 0.1]);
      final result = det.detect(buf);
      expect(result.pitched, isTrue);
      // Critical: NOT 220 Hz! MPM's "first peak ≥ k×max" rule should pick
      // the fundamental period.
      expect(result.frequencyHz, closeTo(110, 2));
    });

    test('detects E2 with typical guitar harmonic series', () {
      final buf = harmonic(82.4);
      final result = det.detect(buf);
      expect(result.pitched, isTrue);
      expect(result.frequencyHz, closeTo(82.4, 1));
    });
  });

  group('MpmDetector — rejects non-pitched input', () {
    final det = MpmDetector(sampleRate: sampleRate);

    test('returns no pitch on silence', () {
      final result = det.detect(Float64List(bufferSize));
      expect(result.pitched, isFalse);
    });

    test('returns no pitch on white noise', () {
      final rng = Random(42);
      final buf = Float64List(bufferSize);
      for (int i = 0; i < bufferSize; i++) {
        buf[i] = (rng.nextDouble() - 0.5) * 0.5;
      }
      final result = det.detect(buf);
      // White noise either yields no pitch or very low clarity.
      if (result.pitched) {
        expect(result.clarity, lessThan(0.85));
      }
    });
  });
}
