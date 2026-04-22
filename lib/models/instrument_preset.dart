import 'note.dart';
import 'tuning.dart';

class InstrumentPresets {
  static final standardGuitar = Tuning(
    name: 'Standard Guitar',
    strings: [
      Note.fromString('E2'),
      Note.fromString('A2'),
      Note.fromString('D3'),
      Note.fromString('G3'),
      Note.fromString('B3'),
      Note.fromString('E4'),
    ],
  );

  static final bass = Tuning(
    name: 'Bass',
    strings: [
      Note.fromString('E1'),
      Note.fromString('A1'),
      Note.fromString('D2'),
      Note.fromString('G2'),
    ],
  );

  static final ukulele = Tuning(
    name: 'Ukulele',
    strings: [
      Note.fromString('G4'),
      Note.fromString('C4'),
      Note.fromString('E4'),
      Note.fromString('A4'),
    ],
  );

  static final guitalele = Tuning(
    name: 'Guitalele',
    strings: [
      Note.fromString('A2'),
      Note.fromString('D3'),
      Note.fromString('G3'),
      Note.fromString('C4'),
      Note.fromString('E4'),
      Note.fromString('A4'),
    ],
  );

  static List<Tuning> get all => [standardGuitar, bass, ukulele, guitalele];
}
