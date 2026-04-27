/// McLeod Pitch Method (MPM) implementation.
///
/// Reference:
///   Philip McLeod, Geoff Wyvill — "A Smarter Way to Find Pitch" (2005)
///   University of Otago, Computer Science Dept.
///   https://www.cs.otago.ac.nz/research/publications/oucs-2005-03.pdf
///
/// Why MPM over YIN for guitar tuning:
///   - Fewer octave errors thanks to the "first peak ≥ k × max" rule
///   - Sub-cent accuracy via parabolic interpolation around the chosen peak
///   - Operates on the Normalized Square Difference Function (NSDF), which has
///     cleaner peaks than YIN's CMNDF
///
/// This is a pure-Dart, time-domain implementation. We bound the maximum lag
/// to keep the O(N·M) NSDF computation tractable on mobile.
library;

import 'dart:math';
import 'dart:typed_data';

class MpmResult {
  /// Detected fundamental frequency in Hz, or -1 if no pitch was found.
  final double frequencyHz;

  /// "Clarity" — the NSDF peak amplitude at the chosen lag, in [0, 1].
  /// Clean tones cluster around 0.95+; noise gets <0.5.
  final double clarity;

  const MpmResult({required this.frequencyHz, required this.clarity});

  bool get pitched => frequencyHz > 0;

  static const noPitch = MpmResult(frequencyHz: -1, clarity: 0);
}

class MpmDetector {
  final int sampleRate;

  /// "k" in the paper. The first NSDF peak whose amplitude is ≥ [cutoff] times
  /// the highest peak is chosen. 0.93 is the value used in sevagh/pitch-detection
  /// and works well for guitar; higher = more conservative, lower = snappier
  /// but more octave errors.
  final double cutoff;

  /// Peaks below this absolute NSDF value are ignored when finding the highest.
  /// Filters out tiny ripples that aren't real periodicity. Lower values are
  /// more permissive — needed for weaker mid-range strings like D3 on a
  /// guitar, which can have NSDF peaks closer to 0.4 than 0.6 in practice.
  final double smallCutoff;

  /// Frequencies below this are rejected (likely noise / sub-harmonic).
  /// 65 Hz sits just under the lowest standard guitar string (E2 = 82.4 Hz).
  final double lowerPitchCutoff;

  /// Frequencies above this are rejected. 1500 Hz covers up to ~F#6, plenty
  /// for any fretted note on guitar/uke/guitalele.
  final double upperPitchCutoff;

  /// Maximum lag (in samples) to compute. Bounds the inner loop. Lag = period
  /// in samples, so maxLag should cover the longest expected period:
  ///   period(E2 = 82.4 Hz) at 44.1 kHz ≈ 535 samples
  /// 1000 gives margin for B0 (31 Hz) on bass too.
  final int maxLag;

  MpmDetector({
    required this.sampleRate,
    this.cutoff = 0.93,
    this.smallCutoff = 0.3,
    this.lowerPitchCutoff = 65,
    this.upperPitchCutoff = 1500,
    this.maxLag = 1000,
  });

  /// Detect pitch from a buffer of float samples in [-1, 1].
  MpmResult detect(Float64List samples) {
    final n = samples.length;
    final lagLimit = min(maxLag, n ~/ 2);

    // ── 1. Compute NSDF ────────────────────────────────────────────────
    // NSDF[τ] = 2 · r[τ] / m[τ]
    //   r[τ] = Σ x[i]·x[i+τ]                (autocorrelation, type II)
    //   m[τ] = Σ (x[i]² + x[i+τ]²)          (squared-sum normalizer)
    final nsdf = Float64List(lagLimit);
    for (int tau = 0; tau < lagLimit; tau++) {
      double acorr = 0;
      double m = 0;
      final upper = n - tau;
      for (int i = 0; i < upper; i++) {
        final a = samples[i];
        final b = samples[i + tau];
        acorr += a * b;
        m += a * a + b * b;
      }
      nsdf[tau] = m > 0 ? 2 * acorr / m : 0;
    }

    // ── 2. Peak picking ────────────────────────────────────────────────
    // We want one peak per "positive lobe" between zero crossings.
    // Within each lobe, take the highest sample. Skip the initial positive
    // lobe (contains the τ=0 zero-lag peak).
    final peakPositions = <int>[];
    int pos = 0;
    int curMax = 0;

    // Skip first positive region (the τ=0 lobe).
    while (pos < (lagLimit - 1) ~/ 3 && nsdf[pos] > 0) {
      pos++;
    }
    // Skip the following negative region.
    while (pos < lagLimit - 1 && nsdf[pos] <= 0) {
      pos++;
    }
    if (pos == 0) pos = 1;

    while (pos < lagLimit - 1) {
      if (nsdf[pos] > nsdf[pos - 1] &&
          nsdf[pos] >= nsdf[pos + 1] &&
          (curMax == 0 || nsdf[pos] > nsdf[curMax])) {
        curMax = pos;
      }
      pos++;
      if (pos < lagLimit - 1 && nsdf[pos] <= 0) {
        if (curMax > 0) {
          peakPositions.add(curMax);
          curMax = 0;
        }
        // skip negative region
        while (pos < lagLimit - 1 && nsdf[pos] <= 0) {
          pos++;
        }
      }
    }
    if (curMax > 0) peakPositions.add(curMax);
    if (peakPositions.isEmpty) return MpmResult.noPitch;

    // ── 3. Parabolic interpolation around each peak ───────────────────
    // Refines the integer-lag peak to sub-sample resolution.
    double highestAmp = double.negativeInfinity;
    final peaks = <(double x, double y)>[];
    for (final i in peakPositions) {
      if (nsdf[i] > smallCutoff) {
        final (x, y) = _parabolicInterp(nsdf, i);
        peaks.add((x, y));
        if (y > highestAmp) highestAmp = y;
      } else if (nsdf[i] > highestAmp) {
        highestAmp = nsdf[i];
      }
    }
    if (peaks.isEmpty) return MpmResult.noPitch;

    // ── 4. Pick first peak ≥ k × highest_amp ──────────────────────────
    // This is the trick that avoids octave errors: the fundamental's peak
    // is always among the highest, and it's the FIRST significant peak.
    final actualCutoff = cutoff * highestAmp;
    double period = 0;
    double clarity = 0;
    for (final (x, y) in peaks) {
      if (y >= actualCutoff) {
        period = x;
        clarity = y;
        break;
      }
    }
    if (period <= 0) return MpmResult.noPitch;

    final freq = sampleRate / period;
    if (freq < lowerPitchCutoff || freq > upperPitchCutoff) {
      return MpmResult.noPitch;
    }

    return MpmResult(
      frequencyHz: freq,
      clarity: clarity.clamp(0.0, 1.0),
    );
  }

  /// Parabolic interpolation around a peak at integer index [x].
  /// Returns refined (x, y).
  (double, double) _parabolicInterp(Float64List a, int x) {
    if (x < 1) {
      return a[x] <= a[x + 1] ? (x.toDouble(), a[x]) : ((x + 1).toDouble(), a[x + 1]);
    }
    if (x >= a.length - 1) {
      return a[x] <= a[x - 1] ? (x.toDouble(), a[x]) : ((x - 1).toDouble(), a[x - 1]);
    }
    final den = a[x + 1] + a[x - 1] - 2 * a[x];
    final delta = a[x - 1] - a[x + 1];
    if (den == 0) return (x.toDouble(), a[x]);
    final dx = delta / (2 * den);
    final dy = delta * delta / (8 * den);
    return (x + dx, a[x] - dy);
  }
}
