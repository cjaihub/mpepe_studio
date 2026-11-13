import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../desktop_agent/desktop_firebase_rest_client.dart';
import '../shared/audio/mic_coordinator.dart';

class OvaWisprResult {
  final String rawTranscript;
  final String polishedText;

  const OvaWisprResult({
    required this.rawTranscript,
    required this.polishedText,
  });

  bool get isEmpty => polishedText.trim().isEmpty;
}

class OvaWisprHistoryItem {
  final String id;
  final String text;
  final String targetLabel;
  final String activeApp;
  final DateTime createdAt;

  const OvaWisprHistoryItem({
    required this.id,
    required this.text,
    required this.targetLabel,
    required this.activeApp,
    required this.createdAt,
  });
}

/// Cross-platform (macOS `OneOva.app` + Android/iOS `Oneova`) Wispr-Flow-style
/// AI Voice Dictation, Live Waveform & Context-Aware Speech Polishing Engine.
class OvaWisprFlowService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  MicLease? _mobileLease;
  String? _recordingPath;

  bool _recording = false;
  bool _processing = false;

  bool get isRecording => _recording;
  bool get isProcessing => _processing;

  bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  Future<bool> _ensureMicPermission() async {
    if (_isDesktop) {
      try {
        return await _recorder.hasPermission();
      } catch (e) {
        debugPrint('[OvaWisprFlow] Desktop mic permission check notice: $e');
        return false;
      }
    }
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) return true;
    } catch (_) {}
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  /// Starts high-clarity 16 kHz voice capture with real-time amplitude updates
  /// (`0.0 .. 1.0`) and optional hands-free auto-commit on silence.
  Future<({bool started, String? error})> startRecording({
    void Function(double level)? onLevel,
    bool autoStopOnSilence = false,
    Duration silenceWindow = const Duration(milliseconds: 1250),
    Duration maxDuration = const Duration(seconds: 45),
    VoidCallback? onAutoSilenceCommit,
    VoidCallback? onPreemptedByCall,
  }) async {
    if (_recording) return (started: true, error: null);
    if (_processing) {
      return (started: false, error: 'Finishing previous voice polish…');
    }

    final permitted = await _ensureMicPermission();
    if (!permitted) {
      return (
        started: false,
        error: _isDesktop
            ? 'Enable Microphone access for OneOva in macOS System Settings → Privacy & Security → Microphone.'
            : 'Microphone permission is required for Wispr voice typing.',
      );
    }

    if (!_isDesktop) {
      final got = await MicCoordinator.instance.acquire(
        MicUser.voiceTyping,
        onPreempted: () async {
          await cancel();
          onPreemptedByCall?.call();
        },
        onInterruption: (interruption) {
          if (interruption == MicInterruption.heldByOtherApp && _recording) {
            unawaited(cancel());
            onPreemptedByCall?.call();
          }
        },
      );
      if (got is MicBusy) {
        return (started: false, error: got.message);
      }
      _mobileLease = got as MicLease;
    }

    try {
      final dir = await getTemporaryDirectory();
      _recordingPath =
          '${dir.path}/ova_wispr_${DateTime.now().microsecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 64000,
          noiseSuppress: true,
          autoGain: true,
          echoCancel: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceRecognition,
          ),
        ),
        path: _recordingPath!,
      );
      _recording = true;

      bool spoke = false;
      bool committed = false;
      DateTime? quietSince;
      final startedAt = DateTime.now();

      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((amp) {
        if (!_recording || committed) return;
        final normalized = ((amp.current + 55.0) / 55.0).clamp(0.04, 1.0);
        onLevel?.call(normalized);

        if (autoStopOnSilence && onAutoSilenceCommit != null) {
          final now = DateTime.now();
          if (normalized >= 0.30) {
            spoke = true;
            quietSince = null;
          } else if (spoke && normalized < 0.20) {
            quietSince ??= now;
            if (now.difference(quietSince!) >= silenceWindow) {
              committed = true;
              onAutoSilenceCommit();
              return;
            }
          }
          if (now.difference(startedAt) >= maxDuration) {
            committed = true;
            onAutoSilenceCommit();
          }
        }
      });

      return (started: true, error: null);
    } catch (e) {
      debugPrint('[OvaWisprFlow] startRecording failed: $e');
      _recording = false;
      await _ampSub?.cancel();
      _ampSub = null;
      await _mobileLease?.release();
      _mobileLease = null;
      return (started: false, error: 'Could not start microphone: $e');
    }
  }

  /// Stops recording, uploads the compact AAC clip to `ovaAgentExecuteTurn`
  /// (`mode: 'wispr_transcribe_and_tidy'`), and returns crisp, filler-free text.
  Future<OvaWisprResult> stopAndTranscribe({
    String style = 'auto',
    String activeWindow = '',
    String? deviceId,
    String? commandInstruction,
  }) async {
    final path = await _stopInternal();
    if (path == null) {
      return const OvaWisprResult(rawTranscript: '', polishedText: '');
    }

    final file = File(path);
    _processing = true;
    try {
      if (!await file.exists()) {
        return const OvaWisprResult(rawTranscript: '', polishedText: '');
      }
      final length = await file.length();
      if (length < 1200) {
        return const OvaWisprResult(rawTranscript: '', polishedText: '');
      }
      final bytes = await file.readAsBytes();
      final payload = <String, dynamic>{
        'mode': 'wispr_transcribe_and_tidy',
        'audioBase64': base64Encode(bytes),
        'mimeType': 'audio/mp4',
        'style': style,
        'activeWindow': activeWindow,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (commandInstruction != null && commandInstruction.trim().isNotEmpty)
          'commandInstruction': commandInstruction.trim(),
      };

      final resp = await _callWisprBackend(payload);
      final polished = (resp['polishedText'] ?? '').toString().trim();
      final raw = (resp['rawTranscript'] ?? polished).toString().trim();
      return OvaWisprResult(rawTranscript: raw, polishedText: polished);
    } finally {
      _processing = false;
      unawaited(file.delete().then((_) {}, onError: (_) {}));
    }
  }

  /// Polishes or rewrites existing text (e.g., clipboard or composer draft)
  /// using Wispr Flow rules or a natural-language transformation instruction.
  Future<String> tidyOrTransformText({
    required String text,
    String style = 'auto',
    String activeWindow = '',
    String? deviceId,
    String? commandInstruction,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return '';
    _processing = true;
    try {
      final resp = await _callWisprBackend({
        'mode': 'wispr_tidy',
        'text': trimmed,
        'style': style,
        'activeWindow': activeWindow,
        if (deviceId != null && deviceId.isNotEmpty) 'deviceId': deviceId,
        if (commandInstruction != null && commandInstruction.trim().isNotEmpty)
          'commandInstruction': commandInstruction.trim(),
      });
      final polished = (resp['polishedText'] ?? '').toString().trim();
      return polished.isNotEmpty ? polished : trimmed;
    } finally {
      _processing = false;
    }
  }

  Future<Map<String, dynamic>> _callWisprBackend(
    Map<String, dynamic> payload,
  ) async {
    if (_isDesktop) {
      return DesktopFirebaseRestClient.instance.callCallable(
        'ovaAgentExecuteTurn',
        payload,
        timeout: const Duration(seconds: 45),
      );
    }
    final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
        .httpsCallable(
      'ovaAgentExecuteTurn',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
    );
    final res = await callable.call<dynamic>(payload);
    final data = res.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const {};
  }

  Future<void> cancel() async {
    final path = await _stopInternal();
    if (path != null) {
      unawaited(File(path).delete().then((_) {}, onError: (_) {}));
    }
  }

  Future<String?> _stopInternal() async {
    final wasRecording = _recording;
    _recording = false;
    await _ampSub?.cancel();
    _ampSub = null;
    final lease = _mobileLease;
    _mobileLease = null;
    if (lease != null) {
      unawaited(lease.release());
    }
    if (!wasRecording) return null;
    try {
      return await _recorder.stop() ?? _recordingPath;
    } catch (_) {
      return _recordingPath;
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}

