import 'dart:async';
import 'package:flutter/foundation.dart';

enum ProxyStatus {
  queued,
  generating,
  ready,
  failed,
  cancelled,
}

class ProxyProfile {
  final int targetWidth;
  final int targetHeight;
  final int bitrate;

  const ProxyProfile({
    required this.targetWidth,
    required this.targetHeight,
    required this.bitrate,
  });

  static const halfResolution = ProxyProfile(targetWidth: -1, targetHeight: -1, bitrate: 5000000);
  static const quarterResolution = ProxyProfile(targetWidth: -2, targetHeight: -2, bitrate: 2000000);
  static const proxy720p = ProxyProfile(targetWidth: 1280, targetHeight: 720, bitrate: 3000000);
  static const proxy1080p = ProxyProfile(targetWidth: 1920, targetHeight: 1080, bitrate: 8000000);
}

class ProxyJob {
  final String mediaId;
  final String sourcePath;
  final ProxyProfile profile;
  
  ProxyStatus status = ProxyStatus.queued;
  String? proxyPath;
  double progress = 0.0;

  ProxyJob({
    required this.mediaId,
    required this.sourcePath,
    required this.profile,
  });
}

class ProxyManager {
  final List<ProxyJob> _queue = [];
  final Map<String, String> _proxyRegistry = {}; // mediaId -> proxyPath
  bool _isProcessing = false;

  void enqueue(ProxyJob job) {
    _queue.add(job);
    _processNext();
  }

  String? getProxyPath(String mediaId) {
    return _proxyRegistry[mediaId];
  }

  Future<void> _processNext() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    final job = _queue.firstWhere((j) => j.status == ProxyStatus.queued, orElse: () => _queue.first);
    if (job.status != ProxyStatus.queued) {
      _isProcessing = false;
      return;
    }

    job.status = ProxyStatus.generating;
    
    // Simulate proxy generation (ffmpeg downscale)
    debugPrint('Generating proxy for \${job.sourcePath} at \${job.profile.targetWidth}x\${job.profile.targetHeight}');

    for (int i = 0; i <= 100; i += 20) {
      if (job.status == ProxyStatus.cancelled) break;
      await Future.delayed(const Duration(milliseconds: 100));
      job.progress = i / 100.0;
    }

    if (job.status != ProxyStatus.cancelled) {
      job.status = ProxyStatus.ready;
      job.proxyPath = '\${job.sourcePath}_proxy.mp4';
      _proxyRegistry[job.mediaId] = job.proxyPath!;
    }

    _queue.remove(job);
    _isProcessing = false;
    _processNext();
  }

  void cancelJob(String mediaId) {
    for (var job in _queue.where((j) => j.mediaId == mediaId)) {
      job.status = ProxyStatus.cancelled;
    }
  }
}
