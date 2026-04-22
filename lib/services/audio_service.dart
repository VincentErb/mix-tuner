import 'dart:typed_data';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class AudioService {
  static const int sampleRate = 44100;
  static const int numChannels = 1;

  final _recorder = AudioRecorder();

  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// Returns a stream of raw PCM16 audio chunks from the microphone.
  Stream<Uint8List> startStream() async* {
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: numChannels,
      ),
    );
    yield* stream;
  }

  Future<void> stop() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
  }

  Future<void> dispose() async {
    await stop();
    _recorder.dispose();
  }
}
