import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final int latestBuildNumber;
  final String channel;
  final String releaseNotes;
  final String downloadUrl;
  final bool isMandatory;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.channel,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.isMandatory,
  });
}

final oneOvaAutoUpdaterProvider = Provider<OneOvaAutoUpdater>((ref) {
  return OneOvaAutoUpdater();
});

/// Background OTA Application Updater for Oneova.
///
/// Monitors the release registry in Cloud Firestore, verifies the installed
/// version against server releases based on the update channel (stable/beta),
/// and coordinates background staging and notification.
class OneOvaAutoUpdater {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const String currentVersion = '1.0.0';
  static const int currentBuildNumber = 1;

  /// Retrieves the active update channel from `.env` or defaults to 'stable'.
  String get updateChannel {
    return dotenv.env['ONEOVA_SYSTEM_UPDATE_CHANNEL']?.trim() ?? 'stable';
  }

  /// Checks for an available update on the server.
  Future<AppUpdateInfo> checkForUpdates() async {
    try {
      final docRef = _firestore.collection('system_config').doc('app_version');
      final snapshot = await docRef.get();

      if (!snapshot.exists || snapshot.data() == null) {
        // Initialize default server document if missing
        await docRef.set({
          'latestVersion': '1.0.0',
          'latestBuildNumber': 1,
          'channel': updateChannel,
          'downloadUrl': 'https://oneova.app/download/latest.apk',
          'releaseNotes': 'First stable release with Ova and automatic account checks.',
          'isMandatory': false,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        return AppUpdateInfo(
          hasUpdate: false,
          currentVersion: currentVersion,
          latestVersion: currentVersion,
          latestBuildNumber: currentBuildNumber,
          channel: updateChannel,
          releaseNotes: 'You are on the latest official build.',
          downloadUrl: '',
          isMandatory: false,
        );
      }

      final data = snapshot.data()!;
      final serverVersion = (data['latestVersion'] as String?) ?? currentVersion;
      final serverBuild = (data['latestBuildNumber'] as num?)?.toInt() ?? currentBuildNumber;
      final notes = (data['releaseNotes'] as String?) ?? 'Performance optimizations & AI repairs.';
      final url = (data['downloadUrl'] as String?) ?? 'https://oneova.app/download/latest.apk';
      final isMandatory = (data['isMandatory'] as bool?) ?? false;

      // Compare versions
      final bool hasUpdate = serverBuild > currentBuildNumber ||
          _compareSemver(serverVersion, currentVersion) > 0;

      return AppUpdateInfo(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestVersion: serverVersion,
        latestBuildNumber: serverBuild,
        channel: updateChannel,
        releaseNotes: notes,
        downloadUrl: url,
        isMandatory: isMandatory,
      );
    } catch (e) {
      debugPrint('[OneOvaAutoUpdater] Check error: $e');
      return AppUpdateInfo(
        hasUpdate: false,
        currentVersion: currentVersion,
        latestVersion: currentVersion,
        latestBuildNumber: currentBuildNumber,
        channel: updateChannel,
        releaseNotes: 'Could not reach server to check for updates.',
        downloadUrl: '',
        isMandatory: false,
      );
    }
  }

  /// Simple semver comparison: returns 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  int _compareSemver(String v1, String v2) {
    final parts1 = v1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final parts2 = v2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }
    return 0;
  }
}
