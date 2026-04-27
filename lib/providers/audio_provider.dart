import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/audio_service.dart';
import '../services/pitch_service.dart';
import '../services/pitch_stabilizer.dart';

final audioServiceProvider = Provider<AudioService>((ref) {
  final service = AudioService();
  ref.onDispose(() => service.dispose());
  return service;
});

final pitchServiceProvider = Provider.autoDispose<PitchService>((ref) {
  return PitchService();
});

final pitchStabilizerProvider = Provider.autoDispose<PitchStabilizer>((ref) {
  return PitchStabilizer();
});

/// Emits [StablePitch] on each analyzed audio frame.
///
/// Yields `null` only when microphone permission is denied, so screens can
/// show the permission gate. While listening, every yielded value is a real
/// [StablePitch] — silent frames arrive as [StablePitch.silent] (pitched=false)
/// rather than null, so the UI can smoothly transition between notes.
final pitchStreamProvider =
    StreamProvider.autoDispose<StablePitch?>((ref) async* {
  final audioService = ref.read(audioServiceProvider);
  final pitchService = ref.read(pitchServiceProvider);
  final stabilizer = ref.read(pitchStabilizerProvider);

  ref.onDispose(() async {
    await audioService.stop();
    pitchService.reset();
    stabilizer.reset();
  });

  final hasPermission = await audioService.requestPermission();
  if (!hasPermission) {
    yield null;
    return;
  }

  // Seed the stream so the UI leaves the loading state immediately.
  yield StablePitch.silent;

  await for (final chunk in audioService.startStream()) {
    // PitchService now produces 0..N raw frames per audio chunk thanks to
    // overlapping analysis windows (~43 Hz refresh rate). Feed each one
    // through the stabilizer so the UI gets every frame.
    final rawFrames = await pitchService.processChunk(chunk);
    for (final raw in rawFrames) {
      yield stabilizer.process(raw);
    }
  }
});
