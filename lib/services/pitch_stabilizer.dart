import 'dart:math';
import '../models/note.dart';
import 'pitch_service.dart';

/// Stabilized pitch output — what the UI consumes.
class StablePitch {
  final double frequencyHz;
  final bool pitched;
  final Note? nearestNote;
  final double centsOff;

  /// Linear RMS (post-HPF) of the analyzed frame. Useful for level meters.
  final double signalLevel;

  /// MPM clarity at the moment this frame was produced — 0 during holds.
  final double clarity;

  const StablePitch({
    required this.frequencyHz,
    required this.pitched,
    required this.nearestNote,
    required this.centsOff,
    required this.signalLevel,
    required this.clarity,
  });

  static const silent = StablePitch(
    frequencyHz: 0,
    pitched: false,
    nearestNote: null,
    centsOff: 0,
    signalLevel: 0,
    clarity: 0,
  );
}

/// Smooths and gates raw MPM output, treating noise as "anything brief or
/// inconsistent" and only emitting pitched output for sustained tones.
///
/// Pipeline (per frame):
///
///   1. **Onset detection** — sudden RMS jump (current ≥ [onsetRmsRatio] ×
///      previous). Resets all smoothing so a fresh pluck snaps immediately.
///
///   2. **Per-frame validity** — frame is "valid" if:
///        * RMS ≥ [silenceRms]
///        * MPM clarity ≥ [minClarity]
///        * frequency > 0
///
///   3. **Stability gate** — the headline noise filter. Even a "valid" frame
///      isn't shown until [stableFrames] (default 3) recent valid frames all
///      agree on the same pitch (within [stableToleranceCents], default
///      ±60¢). This is what turns transient noises (taps, breath, clicks)
///      into invisible blips while still letting real strings through:
///      a guitar string vibrates consistently for ≥1 sec; noise rarely
///      produces three consecutive identical-pitch frames.
///
///   4. **Hold-during-uncertainty** — when validity drops mid-note (clarity
///      dips during decay, brief environmental noise), hold the last good
///      reading for up to [holdFrames] frames before declaring silent.
///
///   5. **Octave correction** — fold ±1200¢ outliers back to the running
///      median (catches rare MPM octave slips on strong harmonics).
///
///   6. **Median pre-filter** — replace the raw frequency with the median
///      of the last few accepted frames. Kills single-frame outliers that
///      slipped past the stability gate.
///
///   7. **Cents-space adaptive EMA** — exponential smoothing in log-frequency
///      space. α ramps with clarity × proximity-to-current so stable notes
///      track snappily and outliers get heavily attenuated.
class PitchStabilizer {
  /// Below this RMS, frames are silent (after a hold).
  final double silenceRms;

  /// Below this MPM clarity, frames are uncertain. Set conservatively low so
  /// real instrument tones (which can dip to ~0.7 during decay) still pass.
  final double minClarity;

  /// Number of consecutive valid frames whose pitch must agree before we
  /// start showing pitched output. 3 frames at ~43 Hz refresh ≈ 70 ms — long
  /// enough to reject taps/clicks, short enough that a real pluck still
  /// shows up almost instantly.
  final int stableFrames;

  /// Tolerance for "pitch agreement" inside the stability gate, in cents.
  final double stableToleranceCents;

  /// Frames to hold the last reading after losing the signal.
  final int holdFrames;

  /// Cents tolerance for octave-snap detection.
  final double octaveSnapCents;

  /// Onset trigger ratio. Current RMS / previous RMS must exceed this AND
  /// current must be loud enough to count as a real onset.
  final double onsetRmsRatio;

  /// Frames to suppress *after* an onset fires. The attack transient of a
  /// guitar pluck (the percussive "tick" before the string rings) lasts
  /// ~50–100 ms and produces unstable, sometimes spuriously-consistent
  /// pitches. We just throw those frames away. 4 frames @ ~43 Hz ≈ 93 ms.
  final int onsetSuppressFrames;

  /// EMA coefficients. Higher = more responsive.
  final double alphaFast;
  final double alphaSlow;

  /// Median filter window for frequency, applied before the EMA.
  final int medianWindow;

  // ── Internal state ──────────────────────────────────────────────────
  double? _smoothedCents;

  /// All recent validated frames (post stability gate) for median filtering.
  final List<double> _freqHistory = [];

  /// Buffer of recent VALID frames (pre stability gate) used to compute
  /// "have the last N agreed?". Stores raw frequencies.
  final List<double> _candidateBuffer = [];

  int _heldFrames = 0;

  /// Counter ticking down through an attack-transient suppression window.
  int _suppressFramesRemaining = 0;

  StablePitch _last = StablePitch.silent;

  PitchStabilizer({
    this.silenceRms = 0.0015,
    this.minClarity = 0.7,
    this.stableFrames = 3,
    this.stableToleranceCents = 60,
    this.holdFrames = 10,
    this.octaveSnapCents = 60,
    this.onsetRmsRatio = 4.0,
    this.onsetSuppressFrames = 8,
    this.alphaFast = 0.45,
    this.alphaSlow = 0.05,
    this.medianWindow = 5,
  });

  StablePitch process(RawPitch raw) {
    // ── Onset: silence/quiet → loud transition ───────────────────────
    // Fires on RMS alone (no pitch requirement) so we catch the *actual*
    // attack — the percussive transient before the string rings, which
    // typically isn't cleanly pitched. We then suppress output for a
    // short window to skip past that transient.
    final wasQuiet = _last.signalLevel < silenceRms * 2;
    final prevRms = max(_last.signalLevel, silenceRms);
    final isOnset = wasQuiet &&
        raw.rms > silenceRms * 3 &&
        raw.rms > onsetRmsRatio * prevRms;
    if (isOnset) {
      _smoothedCents = null;
      _freqHistory.clear();
      _candidateBuffer.clear();
      _heldFrames = 0;
      _suppressFramesRemaining = onsetSuppressFrames;
    }

    // ── Attack-transient suppression ─────────────────────────────────
    // Throw away frames inside the suppression window. We return silent
    // (not held) so the UI doesn't briefly show a stale or attack-noise
    // pitch — the next pitch the user sees will be the steady-state ring.
    if (_suppressFramesRemaining > 0) {
      _suppressFramesRemaining--;
      _last = StablePitch(
        frequencyHz: 0,
        pitched: false,
        nearestNote: null,
        centsOff: 0,
        signalLevel: raw.rms,
        clarity: 0,
      );
      return _last;
    }

    // ── Per-frame validity ───────────────────────────────────────────
    final isValid = raw.rms >= silenceRms &&
        raw.pitched &&
        raw.clarity >= minClarity &&
        raw.frequencyHz > 0;

    if (!isValid) {
      // Frame failed the basic gate — nothing new to add to the candidate
      // buffer, but we may still hold the previous reading briefly.
      _candidateBuffer.clear();
      return _holdOrSilent(raw);
    }

    // ── Stability gate ───────────────────────────────────────────────
    // Push to candidate buffer; check that the last N frames agree.
    _candidateBuffer.add(raw.frequencyHz);
    if (_candidateBuffer.length > stableFrames) {
      _candidateBuffer.removeAt(0);
    }

    final stable = _isCandidateStable();
    if (!stable) {
      // Still building confidence — hold last reading instead of flickering.
      return _holdOrSilent(raw);
    }

    // ── Got a stable, valid frame: pass through to smoothing ─────────
    _heldFrames = 0;

    // Octave correction against running history.
    double freq = raw.frequencyHz;
    if (_freqHistory.isNotEmpty) {
      final med = _median(_freqHistory);
      final cents = 1200 * (log(freq / med) / ln2);
      if ((cents - 1200).abs() < octaveSnapCents) {
        freq = freq / 2;
      } else if ((cents + 1200).abs() < octaveSnapCents) {
        freq = freq * 2;
      }
    }

    _freqHistory.add(freq);
    if (_freqHistory.length > medianWindow) {
      _freqHistory.removeAt(0);
    }

    // Median pre-filter: feed the median of recent accepted frequencies
    // into the EMA, not the latest raw value. Catches single-frame outliers
    // that snuck past the stability gate.
    final medianFreq = _median(_freqHistory);
    final newCents = 1200 * (log(medianFreq / 440.0) / ln2);

    if (_smoothedCents == null) {
      _smoothedCents = newCents;
    } else {
      // Adaptive α: fast when confident & close, slow when not.
      final centsDelta = (newCents - _smoothedCents!).abs();
      final closeness = 1.0 - (centsDelta / 200).clamp(0.0, 1.0);
      final clarityWeight =
          ((raw.clarity - minClarity) / (1.0 - minClarity)).clamp(0.0, 1.0);
      final w = closeness * clarityWeight;
      final alpha = alphaSlow + (alphaFast - alphaSlow) * w;
      _smoothedCents = (1 - alpha) * _smoothedCents! + alpha * newCents;
    }

    final smoothedFreq = 440.0 * pow(2, _smoothedCents! / 1200);
    final (note, centsOff) = Note.fromFrequency(smoothedFreq.toDouble());

    _last = StablePitch(
      frequencyHz: smoothedFreq.toDouble(),
      pitched: true,
      nearestNote: note,
      centsOff: centsOff,
      signalLevel: raw.rms,
      clarity: raw.clarity,
    );
    return _last;
  }

  /// True when the candidate buffer has enough frames AND they all agree.
  bool _isCandidateStable() {
    if (_candidateBuffer.length < stableFrames) return false;
    final med = _median(_candidateBuffer);
    for (final f in _candidateBuffer) {
      final cents = (1200 * log(f / med) / ln2).abs();
      if (cents > stableToleranceCents) return false;
    }
    return true;
  }

  /// Holds the previous reading for up to [holdFrames] frames; otherwise
  /// returns silent state and clears smoothing.
  StablePitch _holdOrSilent(RawPitch raw) {
    _heldFrames++;
    if (_heldFrames <= holdFrames && _last.pitched) {
      _last = StablePitch(
        frequencyHz: _last.frequencyHz,
        pitched: true,
        nearestNote: _last.nearestNote,
        centsOff: _last.centsOff,
        signalLevel: raw.rms,
        clarity: 0,
      );
      return _last;
    }
    _smoothedCents = null;
    _freqHistory.clear();
    _last = StablePitch(
      frequencyHz: 0,
      pitched: false,
      nearestNote: null,
      centsOff: 0,
      signalLevel: raw.rms,
      clarity: 0,
    );
    return _last;
  }

  void reset() {
    _smoothedCents = null;
    _freqHistory.clear();
    _candidateBuffer.clear();
    _heldFrames = 0;
    _suppressFramesRemaining = 0;
    _last = StablePitch.silent;
  }

  static double _median(List<double> xs) {
    final sorted = [...xs]..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
  }
}
