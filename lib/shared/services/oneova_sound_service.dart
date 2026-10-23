import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

/// Service responsible for playing the addictive, celestial OneOva notification chime
/// and tactile haptic feedback whenever a live interaction or alert occurs.
class OneOvaSoundService {
  static final OneOvaSoundService _instance = OneOvaSoundService._internal();
  factory OneOvaSoundService() => _instance;
  OneOvaSoundService._internal();

  Player? _player;
  bool _initialized = false;

  void _ensurePlayer() {
    if (_initialized) return;
    try {
      _player = Player();
      _initialized = true;
    } catch (e) {
      debugPrint('OneOvaSoundService: Player init notice: $e');
    }
  }

  /// Plays the signature OneOva notification chime or selected tone with synchronized tactile haptics
  Future<void> playNotificationChime([String tone = 'celestial']) async {
    try {
      switch (tone.toLowerCase()) {
        case 'mute':
        case 'silent':
          await HapticFeedback.selectionClick();
          return;

        case 'studio_pop':
          await HapticFeedback.heavyImpact();
          await SystemSound.play(SystemSoundType.click);
          return;

        case 'soft_bloom':
          await HapticFeedback.lightImpact();
          await SystemSound.play(SystemSoundType.alert);
          return;

        case 'executive':
          await HapticFeedback.selectionClick();
          await Future.delayed(const Duration(milliseconds: 60));
          await HapticFeedback.mediumImpact();
          await SystemSound.play(SystemSoundType.alert);
          return;

        case 'voice_cue':
          await HapticFeedback.mediumImpact();
          _ensurePlayer();
          if (_player != null) {
            await _player!.open(
              Media('asset:///assets/sounds/oneova_notification.wav'),
              play: true,
            );
          } else {
            await SystemSound.play(SystemSoundType.alert);
          }
          return;

        case 'celestial':
        default:
          await HapticFeedback.mediumImpact();
          _ensurePlayer();
          if (_player != null) {
            await _player!.open(
              Media('asset:///assets/sounds/oneova_notification.wav'),
              play: true,
            );
          } else {
            await SystemSound.play(SystemSoundType.alert);
          }
          return;
      }
    } catch (e) {
      debugPrint('OneOvaSoundService play error: $e');
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
    }
  }

  /// Auditions (previews) a notification chime
  Future<void> auditionTone(String tone) async {
    await playNotificationChime(tone);
  }

  /// Plays subtle tap/action haptic feedback
  static Future<void> playLightHaptic() async {
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Plays haptic feedback matching the user's configured intensity ('none', 'light', 'medium', 'heavy')
  static Future<void> playHaptic([String level = 'medium']) async {
    try {
      switch (level.toLowerCase()) {
        case 'none':
          break;
        case 'light':
          await HapticFeedback.lightImpact();
          break;
        case 'heavy':
          await HapticFeedback.heavyImpact();
          break;
        case 'medium':
        default:
          await HapticFeedback.mediumImpact();
          break;
      }
    } catch (_) {}
  }

  void dispose() {
    _player?.dispose();
    _player = null;
    _initialized = false;
  }
}
