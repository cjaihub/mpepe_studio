import 'dart:async';

enum ProxyJobState {
  queued,
  generating,
  ready,
  failed,
}

class ProxyJob {
  final String id;
  final String sourceMediaId;
  final String targetResolution; // e.g. "720p"
  final String targetCodec; // e.g. "h264"
  ProxyJobState state;
  double progress; // 0.0 to 1.0
  String? proxyFilePath;
  String? errorMessage;

  ProxyJob({
    required this.id,
    required this.sourceMediaId,
    required this.targetResolution,
    required this.targetCodec,
    this.state = ProxyJobState.queued,
    this.progress = 0.0,
    this.proxyFilePath,
    this.errorMessage,
  });
}

/// Service responsible for transcoding heavy source media (e.g., 4K H.265 / ProRes)
/// into edit-friendly lightweight proxies (e.g., 720p H.264) in the background.
class ProxyService {
  final Map<String, ProxyJob> _jobs = {};
  
  // Expose stream for UI to react to proxy progress
  final StreamController<ProxyJob> _jobStreamController = StreamController<ProxyJob>.broadcast();
  Stream<ProxyJob> get jobStream => _jobStreamController.stream;

  /// Returns the path to the proxy if it's ready, otherwise null
  String? getProxyPath(String sourceMediaId) {
    final job = _jobs.values.cast<ProxyJob?>().firstWhere(
      (j) => j?.sourceMediaId == sourceMediaId && j?.state == ProxyJobState.ready, 
      orElse: () => null
    );
    return job?.proxyFilePath;
  }

  /// Request a proxy generation job
  void requestProxyGeneration(String sourceMediaId, {String targetResolution = '720p', String targetCodec = 'h264'}) {
    // Check if already queued or processing
    if (_jobs.values.any((j) => j.sourceMediaId == sourceMediaId && (j.state == ProxyJobState.queued || j.state == ProxyJobState.generating || j.state == ProxyJobState.ready))) {
      return;
    }

    final jobId = 'proxy_\${DateTime.now().millisecondsSinceEpoch}_\$sourceMediaId';
    final job = ProxyJob(
      id: jobId,
      sourceMediaId: sourceMediaId,
      targetResolution: targetResolution,
      targetCodec: targetCodec,
    );
    
    _jobs[jobId] = job;
    _notifyJobUpdate(job);
    
    // Kick off background isolate processing (mocked here)
    _startTranscodingWorker(job);
  }

  Future<void> _startTranscodingWorker(ProxyJob job) async {
    job.state = ProxyJobState.generating;
    _notifyJobUpdate(job);

    // Simulate transcode time
    try {
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        job.progress = i / 10.0;
        _notifyJobUpdate(job);
      }
      
      job.state = ProxyJobState.ready;
      job.proxyFilePath = '/path/to/proxies/\${job.sourceMediaId}_720p.mp4';
      _notifyJobUpdate(job);
    } catch (e) {
      job.state = ProxyJobState.failed;
      job.errorMessage = e.toString();
      _notifyJobUpdate(job);
    }
  }

  void _notifyJobUpdate(ProxyJob job) {
    if (!_jobStreamController.isClosed) {
      _jobStreamController.add(job);
    }
  }

  void dispose() {
    _jobStreamController.close();
  }
}
