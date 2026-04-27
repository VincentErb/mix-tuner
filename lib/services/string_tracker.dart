import 'dart:math';
import '../models/note.dart';

/// Auto-detects which string of a tuning the player is currently tuning,
/// with hysteresis so transient overtones don't flip the selection.
///
/// Strategy:
///   - On each pitched frame, compute the closest string by log-distance
///     (with octave tolerance so a weak fundamental still matches).
///   - On the **initial** lock, require [initialLockFrames] consecutive
///     frames pointing at the same string. This stops auto-mode from
///     latching onto rogue noise pitches the moment we wake up.
///   - To **switch** strings later, require [switchFrames] consecutive
///     frames pointing at a *different* string AND that the candidate
///     beats the current lock by at least [switchMarginCents] in log
///     distance.
class StringTracker {
  /// Frames needed to acquire the very first lock (cold start).
  final int initialLockFrames;

  /// Frames needed to switch from one locked string to another.
  final int switchFrames;

  /// Minimum cents margin a candidate must beat the current lock by.
  final double switchMarginCents;

  int? _lockedIdx;
  int? _candidateIdx;
  int _candidateCount = 0;

  StringTracker({
    this.initialLockFrames = 3,
    this.switchFrames = 4,
    this.switchMarginCents = 50,
  });

  /// Returns the index of the currently tracked string, or null if we
  /// haven't locked on yet. Pass `0` for silent frames.
  int? update(double hz, List<Note> strings) {
    if (strings.isEmpty) return null;
    if (hz <= 0) {
      // Silent — hold the lock but cancel any pending switch / initial lock.
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    final closest = _closestIdx(hz, strings);

    // ── Cold start: build initial lock with hysteresis ───────────────
    if (_lockedIdx == null) {
      if (closest == _candidateIdx) {
        _candidateCount++;
      } else {
        _candidateIdx = closest;
        _candidateCount = 1;
      }
      if (_candidateCount >= initialLockFrames) {
        _lockedIdx = _candidateIdx;
        _candidateIdx = null;
        _candidateCount = 0;
      }
      return _lockedIdx; // null until lock acquired
    }

    if (closest == _lockedIdx) {
      _candidateIdx = null;
      _candidateCount = 0;
      return _lockedIdx;
    }

    // Switching: candidate must beat the locked string by a margin.
    final dLocked = _centsDist(hz, strings[_lockedIdx!].frequency);
    final dCandidate = _centsDist(hz, strings[closest].frequency);
    if (dLocked - dCandidate < switchMarginCents) {
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
      final d = _octaveTolerantDist(hz, strings[i].frequency);
      if (d < best) {
        best = d;
        bestIdx = i;
      }
    }
    return bestIdx;
  }

  /// Min |cents| between [a] and [b] after trying ±1 octave shifts of [a].
  /// Lets a signal at 2× the fundamental still be attributed to the right
  /// (lower) string.
  static double _octaveTolerantDist(double a, double b) {
    final d0 = _centsDist(a, b);
    final dDown = _centsDist(a / 2, b);
    final dUp = _centsDist(a * 2, b);
    return [d0, dDown, dUp].reduce((x, y) => x < y ? x : y);
  }

  static double _centsDist(double a, double b) =>
      (1200 * log(a / b) / ln2).abs();
}
