import 'package:flutter_test/flutter_test.dart';
import 'package:guitaleletuner/models/note.dart';

void main() {
  test('Note.fromFrequency returns A4 for 440 Hz', () {
    final (note, cents) = Note.fromFrequency(440.0);
    expect(note.name, 'A');
    expect(note.octave, 4);
    expect(cents.abs(), lessThan(0.01));
  });

  test('Note.fromFrequency detects sharp note', () {
    // 450 Hz is slightly sharp of A4
    final (note, cents) = Note.fromFrequency(450.0);
    expect(note.name, 'A');
    expect(cents, greaterThan(0));
  });

  test('Note.fromString parses E2 correctly', () {
    final note = Note.fromString('E2');
    expect(note.name, 'E');
    expect(note.octave, 2);
  });
}
