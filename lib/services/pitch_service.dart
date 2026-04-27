import 'dart:math';
import 'dart:typed_data';
import 'filters.dart';
import 'mpm_detector.dart';

/// Raw output of a single MPM pass, before smoothing/gating.
class RawPitch {
  final double frequencyHz;
  final bool pitched;

  /// NSDF clarity in [0, 1] — confidence-style score from MPM. Tones
  /// produced by a real instrument cluster at 0.9+; noise at <0.5.
  final double clarity;

  /// RMS of the analyzed frame, normalized to 0..1 (post high-pass).
  /// Typical values:
  ///   silent room: ~0.001
  ///   light pluck: ~0.02–0.05
  ///   normal pluck: ~0.05–0.2
  final double rms;

  const RawPitch({
    required this.frequencyHz,
    required this.pitched,
    required this.clarity,
    required this.rms,
  });

  static const silent = RawPitch(
    frequencyHz: 0,
    pitched: false,
    clarity: 0,
    rms: 0,
  );
}

/// Captures PCM chunks, applies a high-pass filter, runs MPM with overlapping
/// analysis windows, and emits raw pitch + clarity + RMS per analysis frame.
///
/// Compared to the previous YIN implementation, this gives:
///   - Cleaner peak selection (MPM avoids octave errors better than YIN)
///   - Sub-cent resolution via parabolic interpolation
///   - ~4× higher refresh rate from overlapping windows (10 Hz → 43 Hz)
class PitchService {
  static const int sampleRate = 44100;

  /// Analysis window size — 4096 samples ≈ 93 ms @ 44.1 kHz.
  /// At E2 (82 Hz) that's ~7 periods, plenty for stable low-note detection.
  static const int bufferSize = 4096;

  /// Hop between successive analyses. 1024 samples ≈ 23 ms means we produce
  /// a new pitch reading every 23 ms (≈43 Hz refresh) while still using the
  /// full 4096-sample window for accuracy. 75% overlap.
  static const int hopSize = 1024;

  /// HPF cutoff. 70 Hz removes handling noise / mic rumble / AC hum
  /// without touching standard guitar lows (E2 = 82 Hz).
  static const double hpfCutoffHz = 70;

  late final MpmDetector _detector = MpmDetector(sampleRate: sampleRate);
  final HighPassFilter _hpf = HighPassFilter(
    sampleRate: sampleRate.toDouble(),
    cutoffHz: hpfCutoffHz,
  );

  /// Filtered float samples (-1.0 .. 1.0). We accumulate here, run analyses
  /// every [hopSize] samples once we have at least [bufferSize], and drop
  /// the oldest [hopSize] after each analysis.
  final List<double> _buffer = [];

  /// Returns a list of raw pitch results — typically 0 or 1 per chunk, but
  /// can be more if the chunk happens to span multiple hops. Returning a
  /// list (vs. a single nullable) lets callers keep up with the higher
  /// refresh rate without dropping frames.
  Future<List<RawPitch>> processChunk(Uint8List bytes) async {
    // Decode PCM16 little-endian → float [-1, 1], apply HPF inline.
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      _buffer.add(_hpf.process(sample / 32768.0));
    }

    final results = <RawPitch>[];
    while (_buffer.length >= bufferSize) {
      // Snapshot the analysis window into a typed buffer for MPM speed.
      final window = Float64List(bufferSize);
      for (int i = 0; i < bufferSize; i++) {
        window[i] = _buffer[i];
      }

      // RMS on the full window, post-HPF.
      double sumSq = 0;
      for (int i = 0; i < bufferSize; i++) {
        final x = window[i];
        sumSq += x * x;
      }
      final rms = sqrt(sumSq / bufferSize);

      final mpm = _detector.detect(window);

      results.add(RawPitch(
        frequencyHz: mpm.frequencyHz > 0 ? mpm.frequencyHz : 0,
        pitched: mpm.pitched,
        clarity: mpm.clarity,
        rms: rms,
      ));

      // Slide the window by hopSize.
      _buffer.removeRange(0, hopSize);
    }
    return results;
  }

  void reset() {
    _buffer.clear();
    _hpf.reset();
  }
}
