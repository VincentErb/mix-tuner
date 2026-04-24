import 'dart:math';
import '../models/note.dart';
import 'pitch_service.dart';

/// Stabilized pitch result — safe for UI consumption.
/// Drop-in compatible with screens: exposes [frequencyHz], [pitched],
/// [nearestNote], [centsOff].
class StablePitch {
  final double frequencyHz;
  final bool pitched;
  final Note? nearestNote;
  final double centsOff;

  /// Linear RMS of the analyzed frame (post HPF). Useful for debug/meter.
  final double signalLevel;

  const StablePitch({
    required this.frequencyHz,
    required this.pitched,
    required this.nearestNote,
    required this.centsOff,
    required this.signalLevel,
  });

  static const silent = StablePitch(
    frequencyHz: 0,
    pitched: false,
    nearestNote: null,
    centsOff: 0,
    signalLevel: 0,
  );
}

/// Smooths and gates the raw YIN output.
///
/// Pipeline:
///   1. RMS gate — below [silenceRms] we treat as silence and reset history.
///   2. Probability gate — YIN's own confidence must clear [minProbability].
///   3. Octave correction — if the new estimate is ~2× or ~0.5× the running
///      median, snap it back (YIN commonly jumps an octave on low notes like
///      A2/E2 when overtones dominate).
///   4. Median filter over the last [medianWindow] accepted frames.
///
/// Why median and not mean: a single rogue frame (mis-detected overtone) would
/// poison a mean but be ignored by a median. Window of 5 at ~21 Hz frame rate
/// = ~240 ms of lag, which feels responsive while killing jitter.
class PitchStabilizer {
  /// Minimum RMS (linear, 0..1) for a frame to count as "sound".
  /// ~0.008 ≈ -42 dBFS — above room noise, below a light pluck.
  final double silenceRms;

  /// Minimum YIN probability. YIN returns 0..1; 0.7+ is typically reliable.
  final double minProbability;

  /// Number of recent frames to median-filter over.
  final int medianWindow;

  /// Cents tolerance for octave-snap. If |cents(newFreq, medianFreq)| is
  /// within ±[octaveSnapCents] of ±1200, we treat it as an octave error.
  final double octaveSnapCents;

  final List<double> _history = [];

  PitchStabilizer({
    this.silenceRms = 0.002,
    this.minProbability = 0.7,
    this.medianWindow = 5,
    this.octaveSnapCents = 60,
  });

  /// Feed one raw frame. Returns a [StablePitch]:
  ///   - silent frame (below gate) → [StablePitch.silent]
  ///   - accepted frame → stabilized note + cents
  StablePitch process(RawPitch raw) {
    // Silence gate — also clears history so a new pluck starts fresh.
    if (raw.rms < silenceRms ||
        !raw.pitched ||
        raw.probability < minProbability ||
        raw.frequencyHz <= 0) {
      _history.clear();
      return StablePitch(
        frequencyHz: 0,
        pitched: false,
        nearestNote: null,
        centsOff: 0,
        signalLevel: raw.rms,
      );
    }

    double freq = raw.frequencyHz;

    // Octave correction against running median (if we have context).
    if (_history.isNotEmpty) {
      final med = _median(_history);
      final cents = 1200 * (log(freq / med) / ln2);
      if ((cents - 1200).abs() < octaveSnapCents) {
        freq = freq / 2;
      } else if ((cents + 1200).abs() < octaveSnapCents) {
        freq = freq * 2;
      }
    }

    _history.add(freq);
    if (_history.length > medianWindow) {
      _history.removeAt(0);
    }

    final smoothed = _median(_history);
    final (note, cents) = Note.fromFrequency(smoothed);

    return StablePitch(
      frequencyHz: smoothed,
      pitched: true,
      nearestNote: note,
      centsOff: cents,
      signalLevel: raw.rms,
    );
  }

  void reset() => _history.clear();

  static double _median(List<double> xs) {
    final sorted = [...xs]..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}
