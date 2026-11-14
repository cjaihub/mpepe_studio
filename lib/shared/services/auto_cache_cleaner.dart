import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../feed/services/reel_prefetcher.dart';

/// What the last clean-up did, for Settings → Storage.
class CacheCleanReport {
  final DateTime at;
  final int freedBytes;
  final int sizeAfterBytes;
  const CacheCleanReport(this.at, this.freedBytes, this.sizeAfterBytes);
}

/// Keeps Oneova light without losing anything that matters:
/// - deletes leftovers in the temp and cache folders that are older than a day
///   (never files still being written: a recording or an upload in progress);
/// - keeps the whole cache under [budgetBytes], emptying the Reels video cache
///   first, then thumbnails and images, which all download again when needed;
/// - runs a little after start and when the app goes to the background, at
///   most every 6 hours, and can be switched off in Settings → Storage.
/// Messages, drafts, downloads, encrypted vault files and settings are never touched.
class AutoCacheCleaner {
  AutoCacheCleaner._();
  static final AutoCacheCleaner instance = AutoCacheCleaner._();

  static const int budgetBytes = 400 * 1024 * 1024;
  static const Duration minAge = Duration(hours: 24);
  static const Duration every = Duration(hours: 6);
  static const String _enabledKey = 'auto_cache_clean_enabled';
  static const String _lastKey = 'auto_cache_clean_last';
  static const String _freedKey = 'auto_cache_clean_freed';
  static const String _sizeKey = 'auto_cache_clean_size';

  /// Folders other code manages itself; we only empty them through their manager.
  static const Set<String> _managed = {'oneova_reel_videos_v1', 'oneova_reel_thumbs_v1', 'libCachedImageData'};

  AppLifecycleListener? _life;
  bool _running = false;
  final ValueNotifier<CacheCleanReport?> lastReport = ValueNotifier(null);

  void start() {
    if (kIsWeb || _life != null) return;
    _life = AppLifecycleListener(onHide: () => unawaited(run()));
    unawaited(_loadReport());
    Timer(const Duration(seconds: 30), () => unawaited(run()));
  }

  Future<bool> enabled() async => (await SharedPreferences.getInstance()).getBool(_enabledKey) ?? true;

  Future<void> setEnabled(bool v) async => (await SharedPreferences.getInstance()).setBool(_enabledKey, v);

  Future<void> _loadReport() async {
    final p = await SharedPreferences.getInstance();
    final at = p.getInt(_lastKey);
    if (at != null) {
      lastReport.value = CacheCleanReport(DateTime.fromMillisecondsSinceEpoch(at), p.getInt(_freedKey) ?? 0, p.getInt(_sizeKey) ?? 0);
    }
  }

  /// [force] runs now (the "Clean up now" button) and also clears image caches.
  Future<CacheCleanReport?> run({bool force = false}) async {
    if (kIsWeb || _running) return null;
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      if (!(prefs.getBool(_enabledKey) ?? true)) return null;
      final last = prefs.getInt(_lastKey);
      if (last != null && DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(last)) < every) return null;
    }
    _running = true;
    try {
      final dirs = <Directory>[
        await getTemporaryDirectory(),
        if (!Platform.isIOS) await getApplicationCacheDirectory(),
      ];
      final before = await _sizeOf(dirs);
      final cutoff = DateTime.now().subtract(force ? const Duration(minutes: 10) : minAge);
      for (final d in dirs) {
        await _sweep(d, cutoff, top: true);
      }
      var size = await _sizeOf(dirs);
      if (size > budgetBytes || force) {
        await _empty(ReelPrefetcher.videoCache);
        size = await _sizeOf(dirs);
      }
      if (size > budgetBytes || force) {
        await _empty(ReelPrefetcher.thumbCache);
        await _empty(DefaultCacheManager());
        PaintingBinding.instance.imageCache.clear();
        size = await _sizeOf(dirs);
      }
      final report = CacheCleanReport(DateTime.now(), (before - size).clamp(0, before), size);
      await prefs.setInt(_lastKey, report.at.millisecondsSinceEpoch);
      await prefs.setInt(_freedKey, report.freedBytes);
      await prefs.setInt(_sizeKey, report.sizeAfterBytes);
      lastReport.value = report;
      debugPrint('[AutoCacheCleaner] freed ${report.freedBytes ~/ 1024} KB, now ${size ~/ 1024} KB');
      return report;
    } catch (e) {
      debugPrint('[AutoCacheCleaner] $e');
      return null;
    } finally {
      _running = false;
    }
  }

  Future<void> _empty(BaseCacheManager m) async {
    try {
      await m.emptyCache();
    } catch (_) {}
  }

  /// Deletes files older than [cutoff]; removes folders left empty.
  Future<void> _sweep(Directory dir, DateTime cutoff, {bool top = false}) async {
    if (!await dir.exists()) return;
    await for (final e in dir.list(followLinks: false)) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
      if (_managed.contains(name)) continue;
      try {
        if (e is File) {
          if ((await e.lastModified()).isBefore(cutoff)) await e.delete();
        } else if (e is Directory) {
          await _sweep(e, cutoff);
          if (await e.list().isEmpty) await e.delete();
        }
      } catch (_) {
        // In use or protected: leave it.
      }
    }
  }

  Future<int> _sizeOf(List<Directory> dirs) async {
    var total = 0;
    for (final d in dirs) {
      if (!await d.exists()) continue;
      try {
        await for (final e in d.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
    return total;
  }
}
