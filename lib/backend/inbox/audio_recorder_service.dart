import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

final audioRecorderServiceProvider = Provider<AudioRecorderService>((ref) {
  return AudioRecorderService();
});

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordPath;

  Future<bool> hasPermission() async {
    return await _audioRecorder.hasPermission();
  }

  Future<void> startRecording() async {
    if (await hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      _currentRecordPath = '${tempDir.path}/voice_message_${const Uuid().v4()}.m4a';
      
      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      );
      
      await _audioRecorder.start(
        config,
        path: _currentRecordPath!,
      );
    } else {
      throw Exception('Microphone permission denied');
    }
  }

  Future<File?> stopRecording() async {
    final path = await _audioRecorder.stop();
    if (path != null) {
      return File(path);
    }
    return null;
  }
  
  Future<void> cancelRecording() async {
    await _audioRecorder.stop();
    if (_currentRecordPath != null) {
      final file = File(_currentRecordPath!);
      if (await file.exists()) {
        await file.delete();
      }
      _currentRecordPath = null;
    }
  }

  void dispose() {
    _audioRecorder.dispose();
  }
}
