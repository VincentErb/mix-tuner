import 'dart:math';

/// 1-pole IIR high-pass filter.
///
/// Removes DC offset and sub-cutoff rumble — crucial for clean
/// low-note detection (A2=110Hz, E2=82Hz). Mic handling noise,
/// AC hum, and breath sounds typically live below 70 Hz.
///
/// Transfer function: y[n] = α · (y[n-1] + x[n] - x[n-1])
/// where α = 1 / (1 + 2π · fc / fs)
class HighPassFilter {
  final double _alpha;
  double _prevX = 0;
  double _prevY = 0;

  HighPassFilter({required double sampleRate, required double cutoffHz})
      : _alpha = 1 / (1 + 2 * pi * cutoffHz / sampleRate);

  double process(double input) {
    final output = _alpha * (_prevY + input - _prevX);
    _prevX = input;
    _prevY = output;
    return output;
  }

  void reset() {
    _prevX = 0;
    _prevY = 0;
  }
}
