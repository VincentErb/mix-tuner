import 'package:flutter_test/flutter_test.dart';
import 'package:mix_tuner/models/note.dart';
import 'package:mix_tuner/services/string_tracker.dart';

void main() {
  // Standard guitar E2 A2 D3 G3 B3 E4.
  final strings = [
    Note.fromString('E2'),
    Note.fromString('A2'),
    Note.fromString('D3'),
    Note.fromString('G3'),
    Note.fromString('B3'),
    Note.fromString('E4'),
  ];

  test('first pluck locks immediately', () {
    final t = StringTracker();
    expect(t.update(110, strings), 1); // A2
  });

  test('single stray frame does not switch string', () {
    final t = StringTracker(switchFrames: 4);
    t.update(82.4, strings); // E2 lock
    // One stray frame toward A2 — should not flip.
    final idx = t.update(110, strings);
    expect(idx, 0);
  });

  test('sustained new string switches after hysteresis', () {
    final t = StringTracker(switchFrames: 4);
    t.update(82.4, strings); // lock E2
    for (int i = 0; i < 3; i++) {
      expect(t.update(110, strings), 0); // still E2
    }
    expect(t.update(110, strings), 1); // now A2
  });

  test('silence does not break the lock', () {
    final t = StringTracker();
    t.update(110, strings); // A2
    t.update(0, strings); // silent
    expect(t.update(0, strings), 1); // still A2
  });
}
