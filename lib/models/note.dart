import 'dart:math';

/// Represents a musical note with MIDI-based pitch logic.
/// A4 = MIDI 69 = 440 Hz
class Note {
  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'
  ];

  final int midiNumber;

  const Note(this.midiNumber);

  /// Create from note name (e.g. "E") and octave (e.g. 2)
  factory Note.fromNameOctave(String name, int octave) {
    final nameIndex = _noteNames.indexOf(name);
    if (nameIndex == -1) throw ArgumentError('Unknown note name: $name');
    return Note((octave + 1) * 12 + nameIndex);
  }

  /// Parse a string like "E2" or "A4"
  factory Note.fromString(String s) {
    if (s.length < 2) throw ArgumentError('Invalid note string: $s');
    // Handle sharps: "C#4" vs "C4"
    final hasSharp = s.length > 2 && s[1] == '#';
    final name = hasSharp ? s.substring(0, 2) : s.substring(0, 1);
    final octave = int.parse(hasSharp ? s.substring(2) : s.substring(1));
    return Note.fromNameOctave(name, octave);
  }

  String get name => _noteNames[midiNumber % 12];
  int get octave => (midiNumber ~/ 12) - 1;
  String get displayName => '$name$octave';

  double get frequency => 440.0 * pow(2, (midiNumber - 69) / 12);

  /// Returns the nearest Note and the cents deviation (-50 to +50).
  /// Positive cents = sharp, negative = flat.
  static (Note, double) fromFrequency(double hz) {
    if (hz <= 0) return (const Note(69), 0.0);
    final midi = (12 * log(hz / 440.0) / ln2 + 69).round();
    final clamped = midi.clamp(0, 127);
    final note = Note(clamped);
    final exactHz = note.frequency;
    final cents = 1200.0 * log(hz / exactHz) / ln2;
    return (note, cents);
  }

  Map<String, dynamic> toJson() => {'midi': midiNumber};
  factory Note.fromJson(Map<String, dynamic> json) => Note(json['midi'] as int);

  @override
  bool operator ==(Object other) => other is Note && other.midiNumber == midiNumber;

  @override
  int get hashCode => midiNumber.hashCode;

  @override
  String toString() => displayName;
}
