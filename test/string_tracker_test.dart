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

  test('a single pitched frame does NOT acquire initial lock', () {
    final t = StringTracker(initialLockFrames: 3);
    final idx = t.update(110, strings); // would point at A2
    expect(idx, isNull,
        reason: 'we now require sustained pitch before locking');
  });

  test('three consistent frames acquire the initial lock', () {
    final t = StringTracker(initialLockFrames: 3);
    expect(t.update(110, strings), isNull);
    expect(t.update(110, strings), isNull);
    expect(t.update(110, strings), 1); // A2 (index 1)
  });

  test('inconsistent frames never acquire a lock', () {
    final t = StringTracker(initialLockFrames: 3);
    // Each frame points at a different string — typical noise pattern.
    for (final hz in [82.4, 110.0, 146.8, 196.0, 247.0, 330.0]) {
      expect(t.update(hz, strings), isNull);
    }
  });

  test('single stray frame does not switch a held lock', () {
    final t = StringTracker(initialLockFrames: 1, switchFrames: 4);
    t.update(82.4, strings); // E2 lock
    final idx = t.update(110, strings);
    expect(idx, 0);
  });

  test('sustained new string switches after switch hysteresis', () {
    final t = StringTracker(initialLockFrames: 1, switchFrames: 4);
    t.update(82.4, strings); // lock E2
    for (int i = 0; i < 3; i++) {
      expect(t.update(110, strings), 0); // still E2
    }
    expect(t.update(110, strings), 1); // now A2
  });

  test('silence does not break the lock', () {
    final t = StringTracker(initialLockFrames: 1);
    t.update(110, strings);
    t.update(0, strings);
    expect(t.update(0, strings), 1);
  });
}
