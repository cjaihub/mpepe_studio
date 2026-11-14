import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/// Shared access to the device speech recognizer.
///
/// `SpeechToText()` is a process-wide singleton and only the FIRST
/// `initialize()` call registers status/error callbacks, so when several
/// features each kept their own "instance" one of them silently received
/// everyone's events. The hub initializes once and routes status, errors
/// and results to whichever feature is listening right now. Starting a new
/// listener stops the previous one first, and a busy recognizer
/// (`error_busy`, `error_recognizer_busy`, `error_audio`) is retried
/// automatically instead of leaving the UI stuck on "listening".
class SpeechHub {
  SpeechHub._();
  static final SpeechHub instance = SpeechHub._();

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _ready = false;
  Future<bool>? _initializing;

  Object? _owner;
  _Listen? _active;
  int _busyRetries = 0;

  static const _busyErrors = {'error_busy', 'error_recognizer_busy', 'error_audio', 'error_client'};

  bool get isReady => _ready;
  bool get isActive => _owner != null;
  bool isListeningFor(Object owner) => _owner == owner && _stt.isListening;

  /// Initializes the recognizer once. False when the device has none.
  Future<bool> ensureReady() {
    if (_ready) return Future.value(true);
    return _initializing ??= () async {
      try {
        _ready = await _stt.initialize(onStatus: _onStatus, onError: _onError);
      } catch (e) {
        debugPrint('[SpeechHub] init failed: $e');
        _ready = false;
      }
      _initializing = null;
      return _ready;
    }();
  }

  /// Starts listening for [owner]. Any other listener is stopped and told
  /// `preempted` through its [onStatus].
  Future<bool> listen({
    required Object owner,
    required void Function(SpeechRecognitionResult) onResult,
    void Function(String status)? onStatus,
    void Function(SpeechRecognitionError error)? onError,
    void Function(double level)? onSoundLevel,
    stt.SpeechListenOptions? options,
  }) async {
    if (!await ensureReady()) return false;
    final prev = _active;
    if (_owner != null && _owner != owner) {
      _owner = null;
      _active = null;
      try {
        await _stt.cancel();
      } catch (_) {}
      prev?.onStatus?.call('preempted');
    } else if (_stt.isListening) {
      try {
        await _stt.cancel();
      } catch (_) {}
    }
    _owner = owner;
    _busyRetries = 0;
    _active = _Listen(onResult, onStatus, onError, onSoundLevel, options);
    return _start();
  }

  Future<bool> _start() async {
    final a = _active;
    if (a == null) return false;
    try {
      await _stt.listen(
        onResult: a.onResult,
        onSoundLevelChange: a.onSoundLevel,
        listenOptions: a.options,
      );
      return true;
    } catch (e) {
      debugPrint('[SpeechHub] listen failed: $e');
      a.onError?.call(SpeechRecognitionError('error_listen_failed', true));
      return false;
    }
  }

  /// Languages the phone can dictate in (empty when unavailable).
  Future<List<stt.LocaleName>> locales() async {
    if (!await ensureReady()) return const [];
    try {
      return await _stt.locales();
    } catch (_) {
      return const [];
    }
  }

  /// The phone's default dictation language, or null.
  Future<String?> systemLocaleId() async {
    if (!await ensureReady()) return null;
    try {
      return (await _stt.systemLocale())?.localeId;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop(Object owner) async {
    if (_owner != owner) return;
    try {
      await _stt.stop();
    } catch (_) {}
  }

  Future<void> cancel(Object owner) async {
    if (_owner != owner) return;
    _owner = null;
    _active = null;
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  /// Releases the microphone from any active speech listener so the camera
  /// or video recorder can take exclusive hardware control of the mic.
  Future<void> preemptAll() async {
    final prev = _active;
    _owner = null;
    _active = null;
    try {
      if (_stt.isListening) {
        await _stt.cancel();
      }
    } catch (_) {}
    prev?.onStatus?.call('preempted');
  }

  void _onStatus(String status) {
    _active?.onStatus?.call(status);
  }

  void _onError(SpeechRecognitionError error) {
    final a = _active;
    if (a == null) return;
    // Another recognizer client (Google app, a previous session) still holds
    // the service: give it a moment and try again before reporting.
    if (_busyErrors.contains(error.errorMsg) && _busyRetries < 2) {
      _busyRetries++;
      final owner = _owner;
      debugPrint('[SpeechHub] ${error.errorMsg}, retry $_busyRetries');
      Future.delayed(Duration(milliseconds: 250 * _busyRetries), () async {
        if (_owner != owner || _active != a) return;
        try {
          await _stt.cancel();
        } catch (_) {}
        await _start();
      });
      return;
    }
    a.onError?.call(error);
  }
}

class _Listen {
  _Listen(this.onResult, this.onStatus, this.onError, this.onSoundLevel, this.options);
  final void Function(SpeechRecognitionResult) onResult;
  final void Function(String status)? onStatus;
  final void Function(SpeechRecognitionError error)? onError;
  final void Function(double level)? onSoundLevel;
  final stt.SpeechListenOptions? options;
}
