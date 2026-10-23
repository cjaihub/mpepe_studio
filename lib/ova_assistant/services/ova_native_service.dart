import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

class OvaNativeService {
  static const MethodChannel _channel = MethodChannel('com.oneova.app/ova_assistant');

  /// Fetches real-time device info (battery, charging, network, etc.)
  Future<Map<String, dynamic>> getDeviceInfo() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
        if (result != null) {
          return Map<String, dynamic>.from(result);
        }
      } catch (e) {
        debugPrint('[OvaNativeService] Error getting native device info: $e');
      }
    }
    // No native channel here (iOS, web) or it failed: report nothing rather than invented values.
    return <String, dynamic>{'networkType': 'Unknown'};
  }

  /// Opens WhatsApp, optionally targeting a phone number with a pre-filled message
  Future<bool> openWhatsApp({String? phone, String? message}) async {
    final queryText = message != null ? Uri.encodeComponent(message) : '';
    
    // First attempt native channel if on Android
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('openWhatsApp', {
          'phone': phone ?? '',
          'message': message ?? '',
        });
        if (success == true) return true;
      } catch (e) {
        debugPrint('[OvaNativeService] Native WhatsApp intent failed: $e');
      }
    }

    // Direct URL scheme fallback
    final targetPhone = phone?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
    final Uri url;
    if (targetPhone.isNotEmpty) {
      url = Uri.parse('whatsapp://send?phone=$targetPhone&text=$queryText');
    } else {
      url = Uri.parse('whatsapp://send?text=$queryText');
    }

    try {
      if (await canLaunchUrl(url)) {
        return await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        // Universal web/app link fallback
        final webUrl = Uri.parse(
          targetPhone.isNotEmpty
              ? 'https://wa.me/$targetPhone?text=$queryText'
              : 'https://wa.me/?text=$queryText',
        );
        return await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[OvaNativeService] Error launching WhatsApp URL: $e');
      return false;
    }
  }

  /// Launches any installed app on Android by package or common alias
  Future<bool> launchApp(String packageOrAlias) async {
    String packageName = packageOrAlias;
    final aliasMap = {
      'whatsapp': 'com.whatsapp',
      'camera': 'android.hardware.camera',
      'youtube': 'com.google.android.youtube',
      'settings': 'com.android.settings',
      'gallery': 'com.google.android.apps.photos',
      'maps': 'com.google.android.apps.maps',
    };

    if (aliasMap.containsKey(packageOrAlias.toLowerCase())) {
      packageName = aliasMap[packageOrAlias.toLowerCase()]!;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('launchApp', {'packageName': packageName});
        if (success == true) return true;
      } catch (e) {
        debugPrint('[OvaNativeService] Error launching app: $e');
      }
    }

    // Common web/scheme fallback
    if (packageOrAlias.toLowerCase() == 'youtube') {
      return await launchUrl(Uri.parse('https://youtube.com'), mode: LaunchMode.externalApplication);
    }
    return false;
  }

  /// Opens the device camera
  Future<bool> openCamera() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('openCamera');
        if (success == true) return true;
      } catch (e) {
        debugPrint('[OvaNativeService] Error opening native camera: $e');
      }
    }
    return false;
  }

  /// Opens system settings
  Future<bool> openSettings([String? settingType]) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final success = await _channel.invokeMethod<bool>('openSettings', {'settingType': settingType ?? 'main'});
        if (success == true) return true;
      } catch (e) {
        debugPrint('[OvaNativeService] Error opening native settings: $e');
      }
    }
    return false;
  }

  /// Triggers phone dialer for a given contact or number
  Future<bool> makePhoneCall(String phoneNumber) async {
    final cleaned = phoneNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$cleaned');
    try {
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('[OvaNativeService] Error launching call: $e');
    }
    return false;
  }

  /// Shares a photo or file to WhatsApp or any chosen app
  Future<bool> shareMediaFile(String filePath, {String? text}) async {
    try {
      final xFile = XFile(filePath);
      await SharePlus.instance.share(
        ShareParams(
          text: text ?? '',
          files: [xFile],
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[OvaNativeService] Error sharing file: $e');
      return false;
    }
  }

  /// Triggers a haptic pulse or vibration duration in milliseconds
  Future<void> triggerHapticPulse(int durationMs) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod('triggerHapticPulse', {'durationMs': durationMs});
        return;
      } catch (_) {}
    }
    // Fallback to framework haptic
    if (durationMs > 100) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.selectionClick();
    }
  }

  /// Checks if app has permission to draw floating overlays over other apps
  Future<bool> canDrawOverlays() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('canDrawOverlays');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error checking overlay permission: $e');
      }
    }
    return true;
  }

  /// Opens Android Settings screen to grant draw-over-other-apps permission
  Future<bool> requestOverlayPermission() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('requestOverlayPermission');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error requesting overlay permission: $e');
      }
    }
    return true;
  }

  /// Wakes the screen even when the phone is locked or in sleep mode
  Future<bool> wakeScreen() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('wakeScreen');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error waking screen: $e');
      }
    }
    return true;
  }

  /// Starts persistent background listening & notification for system-wide commands
  Future<bool> startBackgroundAssistant() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('startBackgroundAssistant');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error starting background assistant: $e');
      }
    }
    return true;
  }

  /// Stops background assistant service
  Future<bool> stopBackgroundAssistant() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('stopBackgroundAssistant');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error stopping background assistant: $e');
      }
    }
    return true;
  }

  /// Launches the floating interactive system overlay window over any active application
  Future<bool> startSystemOverlay() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('startSystemOverlay');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error starting system overlay: $e');
      }
    }
    return true;
  }

  /// Dismisses the system overlay window
  Future<bool> stopSystemOverlay() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('stopSystemOverlay');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error stopping system overlay: $e');
      }
    }
    return true;
  }

  /// Checks if the system overlay window is currently active
  Future<bool> isSystemOverlayActive() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('isSystemOverlayActive');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error checking system overlay: $e');
      }
    }
    return false;
  }

  /// Opens Android Default Digital Assistant settings to set Oneova as default assistant
  Future<bool> openAssistantSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('openAssistantSettings');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error opening assistant settings: $e');
      }
    }
    return false;
  }

  /// Opens Android Power Button / Gesture settings for side-key mapping guidance
  Future<bool> openPowerButtonSettings() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>('openPowerButtonSettings');
        return result ?? false;
      } catch (e) {
        debugPrint('[OvaNativeService] Error opening power button settings: $e');
      }
    }
    return false;
  }

  /// Registers callback when background wake intent is received
  void initBackgroundWakeReceiver(Function onWake) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onBackgroundWake') {
        final args = call.arguments;
        String? query;
        if (args is Map && args['query'] is String) {
          query = args['query'] as String;
        }
        if (onWake is void Function(String?)) {
          onWake(query);
        } else if (onWake is VoidCallback) {
          onWake();
        } else {
          try {
            Function.apply(onWake, [query]);
          } catch (_) {
            Function.apply(onWake, []);
          }
        }
      }
    });
  }

  /// Fetches recent system notifications captured by accessibility service
  Future<List<Map<String, dynamic>>> getRecentNotifications() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<List<dynamic>>('getRecentNotifications');
        if (result != null) {
          return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      } catch (e) {
        debugPrint('[OvaNativeService] Error fetching notifications: $e');
      }
    }
    return [];
  }
}
