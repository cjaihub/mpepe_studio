import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

import '../../backend/notifications/services/system_notices_service.dart';

/// Google Play in-app updates for store builds.
///
/// On launch and resume we ask Play whether a newer version is published to
/// this user's track. High-priority releases (`inAppUpdatePriority` >= 4 in
/// the Play Developer API) use the full-screen immediate flow; everything
/// else downloads in the background (flexible) and installs the next time the
/// app goes to the background. Does nothing outside Play-installed release
/// builds (debug, sideloaded APKs, iOS).
class PlayUpdateService {
  PlayUpdateService._();
  static final PlayUpdateService instance = PlayUpdateService._();

  static const int _immediatePriority = 4;

  bool _checking = false;
  bool _downloaded = false;
  StreamSubscription<InstallStatus>? _installSub;

  Future<void> check() async {
    if (!Platform.isAndroid || !kReleaseMode || _checking) return;
    _checking = true;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        _downloaded = true;
        return;
      }
      final available = info.updateAvailability == UpdateAvailability.updateAvailable ||
          info.updateAvailability == UpdateAvailability.developerTriggeredUpdateInProgress;
      if (!available) return;
      // Also leave a friendly note in the notification centre with an Update button.
      unawaited(SystemNoticesService.instance.appUpdateAvailable(info.availableVersionCode ?? 0));

      if (info.immediateUpdateAllowed && info.updatePriority >= _immediatePriority) {
        await InAppUpdate.performImmediateUpdate();
      } else if (info.flexibleUpdateAllowed) {
        _installSub ??= InAppUpdate.installUpdateListener.listen((status) {
          if (status == InstallStatus.downloaded) _downloaded = true;
        });
        await InAppUpdate.startFlexibleUpdate();
      }
    } catch (e) {
      // Not installed from Play, no network, or Play Store unavailable.
      debugPrint('[PlayUpdate] check skipped: $e');
    } finally {
      _checking = false;
    }
  }

  /// "Update" tapped on an update notification: install what is downloaded,
  /// otherwise start Play's update flow now.
  Future<void> updateNow() async {
    if (_downloaded) return installIfDownloaded();
    if (!Platform.isAndroid || !kReleaseMode) return;
    try {
      final info = await InAppUpdate.checkForUpdate();
      if (info.installStatus == InstallStatus.downloaded) {
        await InAppUpdate.completeFlexibleUpdate();
      } else if (info.immediateUpdateAllowed) {
        await InAppUpdate.performImmediateUpdate();
      } else {
        await check();
      }
    } catch (e) {
      debugPrint('[PlayUpdate] update now failed: $e');
    }
  }

  /// Installs a downloaded flexible update. Call when the app is backgrounded
  /// so the restart happens out of the user's way.
  Future<void> installIfDownloaded() async {
    if (!_downloaded) return;
    _downloaded = false;
    try {
      await InAppUpdate.completeFlexibleUpdate();
    } catch (e) {
      debugPrint('[PlayUpdate] complete failed: $e');
    }
  }
}
