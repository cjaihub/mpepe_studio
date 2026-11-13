import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:path_provider/path_provider.dart';
import '../../backend/user_service.dart';
import '../../shared/audio/mic_coordinator.dart';
import 'package:flutter/foundation.dart';

enum VoiceEnrollmentState {
  initial,
  recording,
  processing,
  enrolled,
  error,
}

class VoicePersonalizationState {
  final VoiceEnrollmentState state;
  final String? errorMessage;
  final bool isEnrolled;
  final String? recordPath;

  VoicePersonalizationState({
    required this.state,
    this.errorMessage,
    this.isEnrolled = false,
    this.recordPath,
  });

  VoicePersonalizationState copyWith({
    VoiceEnrollmentState? state,
    String? errorMessage,
    bool? isEnrolled,
    String? recordPath,
  }) {
    return VoicePersonalizationState(
      state: state ?? this.state,
      errorMessage: errorMessage ?? this.errorMessage,
      isEnrolled: isEnrolled ?? this.isEnrolled,
      recordPath: recordPath ?? this.recordPath,
    );
  }
}

class AiVoicePersonalizationService extends Notifier<VoicePersonalizationState> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  MicLease? _micLease;

  @override
  VoicePersonalizationState build() {
    ref.onDispose(() {
      unawaited(_micLease?.release());
      _micLease = null;
      unawaited(_audioRecorder.dispose());
    });
    final authState = _auth.currentUser;
    if (authState != null) {
      try {
        final users = ref.read(userProvider).value ?? [];
        final user = users.firstWhere((u) => u.id == authState.uid);
        if (user.aiVoicePersonalization.enabled) {
          return VoicePersonalizationState(state: VoiceEnrollmentState.enrolled, isEnrolled: true);
        }
      } catch (e) {
        debugPrint('Error getting voice state: $e');
      }
    }
    return VoicePersonalizationState(state: VoiceEnrollmentState.initial);
  }

  Future<void> _releaseMic() async {
    final lease = _micLease;
    _micLease = null;
    await lease?.release();
  }

  Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final got = await MicCoordinator.instance.acquire(
          MicUser.voiceNote,
          onPreempted: () async {
            try {
              await _audioRecorder.stop();
            } catch (_) {}
            _micLease = null;
            if (ref.mounted && state.state == VoiceEnrollmentState.recording) {
              state = state.copyWith(
                state: VoiceEnrollmentState.error,
                errorMessage: 'Microphone was taken by another feature.',
              );
            }
          },
        );
        if (got is MicBusy) {
          state = state.copyWith(state: VoiceEnrollmentState.error, errorMessage: got.message);
          return;
        }
        _micLease = got as MicLease;

        final directory = await getApplicationDocumentsDirectory();
        final path = '${directory.path}/voice_sample.m4a';

        try {
          await _audioRecorder.start(
            const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 16000),
            path: path,
          );
        } catch (e) {
          await _releaseMic();
          rethrow;
        }

        state = state.copyWith(state: VoiceEnrollmentState.recording, recordPath: path);
      } else {
        state = state.copyWith(state: VoiceEnrollmentState.error, errorMessage: 'Microphone permission denied.');
      }
    } catch (e) {
      await _releaseMic();
      state = state.copyWith(state: VoiceEnrollmentState.error, errorMessage: e.toString());
    }
  }

  Future<void> stopRecordingAndEnroll() async {
    if (state.state != VoiceEnrollmentState.recording) return;

    try {
      state = state.copyWith(state: VoiceEnrollmentState.processing);
      
      final path = await _audioRecorder.stop();
      await _releaseMic();
      if (path == null) throw Exception('Recording failed to produce a file.');

      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated.');

      // Upload to Firebase Storage
      final storageRef = _storage.ref().child('voice_samples/$uid.m4a');
      await storageRef.putFile(File(path));

      // Update Firestore user document
      final consentTime = DateTime.now();
      await ref.read(userProvider.notifier).updateUserProfile(uid, {
        'aiVoicePersonalization': AiVoicePersonalizationMetadata(
          enabled: true,
          consentGrantedAt: consentTime,
          sampleStoragePath: storageRef.fullPath,
        ).toMap()
      });

      state = state.copyWith(state: VoiceEnrollmentState.enrolled, isEnrolled: true);
    } catch (e) {
      await _releaseMic();
      state = state.copyWith(state: VoiceEnrollmentState.error, errorMessage: e.toString());
    }
  }

  Future<void> disablePersonalization() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) throw Exception('Not authenticated.');

      state = state.copyWith(state: VoiceEnrollmentState.processing);

      await ref.read(userProvider.notifier).updateUserProfile(uid, {
        'aiVoicePersonalization': AiVoicePersonalizationMetadata(
          enabled: false,
          consentGrantedAt: null,
          sampleStoragePath: null,
        ).toMap()
      });

      // Optional: Delete the storage file as well for strict privacy
      try {
        final storageRef = _storage.ref().child('voice_samples/$uid.m4a');
        await storageRef.delete();
      } catch (e) {
        debugPrint('Voice sample not found or already deleted: $e');
      }

      state = state.copyWith(state: VoiceEnrollmentState.initial, isEnrolled: false);
    } catch (e) {
      state = state.copyWith(state: VoiceEnrollmentState.error, errorMessage: e.toString());
    }
  }
}

final voicePersonalizationProvider = NotifierProvider<AiVoicePersonalizationService, VoicePersonalizationState>(() {
  return AiVoicePersonalizationService();
});
