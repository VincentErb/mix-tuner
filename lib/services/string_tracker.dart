import 'dart:math';
import '../models/note.dart';

/// Auto-detects which string of a tuning the player is currently tuning,
/// with hysteresis so transient overtones don't flip the selection.
///
/// Strategy:
///   - On each stable frame, compute the closest string by log-distance.
///   - Require [switchFrames] consecutive frames pointing at a *different*
///     string before switching away from the currently locked one.
///   - Require the candidate to beat the current string by at least
///     [switchMarginCents] cents in log-distance, so near-ties don't
///     bounce between adjacent strings (e.g. B3 vs E4 when a 4th overtone
///     sneaks in).
class StringTracker {
  final int switchFrames;
  final double switchMarginCents;

  int? _lockedIdx;
  int? _candidateIdx;
  int _candidateCount = 0;

  StringTracker({
    this.switchFrames = 4,
    this.switchMarginCents = 50,
  });

  /// Returns the index of the currently tracked string, or null if we
  /// haven't locked on yet. [hz] should be a stabilized frequency; pass
  /// null/0 for silent frames (which decay the candidate).
  int? update(double hz, List<Note> strings) {
    if (strings.isEmpty) return null;
    if (hz <= 0) {
      // Silent — hold the lock but reset any pending switch.
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    final closest = _closestIdx(hz, strings);

    // First lock-on: accept immediately so the UI responds to the first pluck.
    if (_lockedIdx == null) {
      _lockedIdx = closest;
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    if (closest == _lockedIdx) {
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    // Require candidate to beat the locked string by a clear margin.
    final dLocked = _centsDist(hz, strings[_lockedIdx!].frequency);
    final dCandidate = _centsDist(hz, strings[closest].frequency);
    if (dLocked - dCandidate < switchMarginCents) {
      // Too close to call — keep the lock, don't build up a candidate.
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    if (closest == _candidateIdx) {
      _candidateCount++;
    } else {
      _candidateIdx = closest;
      _candidateCount = 1;
    }

    if (_candidateCount >= switchFrames) {
      _lockedIdx = _candidateIdx;
      _candidateIdx = null;
      _candidateCount = 0;
    }
    return _lockedIdx;
  }

  void reset() {
    _lockedIdx = null;
    _candidateIdx = null;
    _candidateCount = 0;
  }

  static int _closestIdx(double hz, List<Note> strings) {
    double best = double.infinity;
    int bestIdx = 0;
    for (int i = 0; i < strings.length; i++) {
      // Consider the raw frequency AND one octave up/down so that a weak
      // fundamental (e.g. A2 on a guitalele where the 2nd harmonic dominates)
      // still matches the correct string rather than one an octave higher.
      final d = _octaveTolerantDist(hz, strings[i].frequency);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Returns the minimum |cents| between [a] and [b] after trying
  /// ±1 octave shifts of [a]. This lets a signal at 2× the fundamental
  /// still be attributed to the correct (lower) string.
  static double _octaveTolerantDist(double a, double b) {
    final d0 = _centsDist(a, b);
    final dDown = _centsDist(a / 2, b); // a is an octave too high
    final dUp = _centsDist(a * 2, b);   // a is an octave too low
    return [d0, dDown, dUp].reduce((x, y) => x < y ? x : y);
  }

  static double _centsDist(double a, double b) =>
      (1200 * log(a / b) / ln2).abs();
}
