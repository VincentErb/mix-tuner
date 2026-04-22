import 'dart:math';
import 'dart:typed_data';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'filters.dart';

/// Raw output of a single YIN pass, before smoothing/gating.
class RawPitch {
  final double frequencyHz;
  final bool pitched;
  final double probability;

  /// RMS of the analyzed frame, normalized to 0..1 (post high-pass).
  /// Typical values:
  ///   silent room: ~0.001–0.003
  ///   light pluck: ~0.02–0.05
  ///   normal pluck: ~0.05–0.2
  final double rms;

  const RawPitch({
    required this.frequencyHz,
    required this.pitched,
    required this.probability,
    required this.rms,
  });

  static const silent = RawPitch(
    frequencyHz: 0,
    pitched: false,
    probability: 0,
    rms: 0,
  );
}

/// Captures PCM chunks, applies a high-pass filter, runs YIN, and returns
/// raw pitch + RMS per analysis frame.
class PitchService {
  static const int sampleRate = 44100;

  /// 4096 samples @ 44.1kHz ≈ 93 ms window.
  /// At E2 (82 Hz, period = 537 samples), this gives ~7 periods — ample for YIN.
  /// At A2 (110 Hz), ~9 periods. Large enough for stable low-note detection.
  static const int bufferSize = 4096;

  /// Cutoff for the input high-pass filter. 70 Hz removes handling noise,
  /// AC hum (50/60 Hz), and mic rumble without eating into bass guitar range
  /// (lowest string B0=31 Hz is below this, but typical guitar E2=82 Hz passes).
  static const double hpfCutoffHz = 70;

  late final PitchDetector _detector = PitchDetector(
    audioSampleRate: sampleRate.toDouble(),
    bufferSize: bufferSize,
  );
  final HighPassFilter _hpf = HighPassFilter(
    sampleRate: sampleRate.toDouble(),
    cutoffHz: hpfCutoffHz,
  );

  /// Running buffer of filtered float samples (-1.0 .. 1.0).
  final List<double> _buffer = [];

  /// Returns null if not enough samples yet, else the latest RawPitch.
  Future<RawPitch?> processChunk(Uint8List bytes) async {
    // Decode PCM16 little-endian → float [-1, 1], apply HPF inline.
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      int sample = bytes[i] | (bytes[i + 1] << 8);
      if (sample > 32767) sample -= 65536;
      final f = sample / 32768.0;
      _buffer.add(_hpf.process(f));
    }

    if (_buffer.length < bufferSize) return null;

    // Analyze first bufferSize samples.
    // RMS on the filtered signal.
    double sumSq = 0;
    for (int i = 0; i < bufferSize; i++) {
      final x = _buffer[i];
      sumSq += x * x;
    }
    final rms = sqrt(sumSq / bufferSize);

    // Re-encode filtered floats to PCM16 bytes for the detector.
    // (pitch_detector_dart expects PCM16.)
    final inputBytes = Uint8List(bufferSize * 2);
    for (int i = 0; i < bufferSize; i++) {
      final clamped = _buffer[i].clamp(-1.0, 1.0);
      final s = (clamped * 32767).round();
      inputBytes[i * 2] = s & 0xFF;
      inputBytes[i * 2 + 1] = (s >> 8) & 0xFF;
    }

    _buffer.removeRange(0, bufferSize);

    final result = await _detector.getPitchFromIntBuffer(inputBytes);

    return RawPitch(
      frequencyHz: result.pitch,
      pitched: result.pitched && result.pitch > 0,
      probability: result.probability,
      rms: rms,
    );
  }

  void reset() {
    _buffer.clear();
    _hpf.reset();
  }
}
