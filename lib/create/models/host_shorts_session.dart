enum HostShortsRole {
  hostDirector, // Cam A (Director controlling layout and multi-cam recording)
  remoteCamB,   // Cam B (Wireless secondary camera streaming to Host)
}

enum HostShortsStatus {
  idle,
  hosting,
  searching,
  connecting,
  connected,
  streaming,
}

enum HostShortsLayout {
  pip,            // Picture-in-picture floating overlay
  splitVertical,  // 50/50 vertical split
  splitHorizontal,// 50/50 side-by-side split
  soloCamA,       // Only Cam A fullscreen
  soloCamB,       // Only Cam B fullscreen
}

enum HostShortsAudioSource {
  hostCamA,
  remoteCamB,
  stereoMix,
}

class HostShortsDevice {
  final String deviceId;
  final String deviceName;
  final HostShortsRole role;
  final int batteryPercent;
  final int latencyMs;
  final bool isRecording;
  final String resolution;
  final int fps;

  const HostShortsDevice({
    required this.deviceId,
    required this.deviceName,
    required this.role,
    this.batteryPercent = 95,
    this.latencyMs = 18,
    this.isRecording = false,
    this.resolution = '1080p',
    this.fps = 60,
  });

  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'role': role.name,
      'batteryPercent': batteryPercent,
      'latencyMs': latencyMs,
      'isRecording': isRecording,
      'resolution': resolution,
      'fps': fps,
    };
  }

  factory HostShortsDevice.fromMap(Map<String, dynamic> map) {
    return HostShortsDevice(
      deviceId: map['deviceId'] as String? ?? 'dev_unknown',
      deviceName: map['deviceName'] as String? ?? 'Oneova Camera',
      role: HostShortsRole.values.firstWhere(
        (r) => r.name == map['role'],
        orElse: () => HostShortsRole.remoteCamB,
      ),
      batteryPercent: map['batteryPercent'] as int? ?? 90,
      latencyMs: map['latencyMs'] as int? ?? 22,
      isRecording: map['isRecording'] as bool? ?? false,
      resolution: map['resolution'] as String? ?? '1080p',
      fps: map['fps'] as int? ?? 60,
    );
  }
}

class HostShortsSession {
  final String sessionId;
  final String pairCode;
  final String hostUid;
  final HostShortsDevice hostDevice;
  final HostShortsDevice? remoteDevice;
  final HostShortsStatus status;
  final HostShortsLayout layout;
  final HostShortsAudioSource audioSource;
  final bool isSyncedRecording;
  final DateTime createdAt;

  const HostShortsSession({
    required this.sessionId,
    required this.pairCode,
    required this.hostUid,
    required this.hostDevice,
    this.remoteDevice,
    this.status = HostShortsStatus.idle,
    this.layout = HostShortsLayout.pip,
    this.audioSource = HostShortsAudioSource.stereoMix,
    this.isSyncedRecording = false,
    required this.createdAt,
  });

  bool get isConnected => status == HostShortsStatus.connected || status == HostShortsStatus.streaming;

  HostShortsSession copyWith({
    String? sessionId,
    String? pairCode,
    String? hostUid,
    HostShortsDevice? hostDevice,
    HostShortsDevice? remoteDevice,
    HostShortsStatus? status,
    HostShortsLayout? layout,
    HostShortsAudioSource? audioSource,
    bool? isSyncedRecording,
    DateTime? createdAt,
  }) {
    return HostShortsSession(
      sessionId: sessionId ?? this.sessionId,
      pairCode: pairCode ?? this.pairCode,
      hostUid: hostUid ?? this.hostUid,
      hostDevice: hostDevice ?? this.hostDevice,
      remoteDevice: remoteDevice ?? this.remoteDevice,
      status: status ?? this.status,
      layout: layout ?? this.layout,
      audioSource: audioSource ?? this.audioSource,
      isSyncedRecording: isSyncedRecording ?? this.isSyncedRecording,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'pairCode': pairCode,
      'hostUid': hostUid,
      'hostDevice': hostDevice.toMap(),
      if (remoteDevice != null) 'remoteDevice': remoteDevice!.toMap(),
      'status': status.name,
      'layout': layout.name,
      'audioSource': audioSource.name,
      'isSyncedRecording': isSyncedRecording,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory HostShortsSession.fromMap(Map<String, dynamic> map) {
    return HostShortsSession(
      sessionId: map['sessionId'] as String? ?? '',
      pairCode: map['pairCode'] as String? ?? '000000',
      hostUid: map['hostUid'] as String? ?? '',
      hostDevice: HostShortsDevice.fromMap(map['hostDevice'] as Map<String, dynamic>? ?? {}),
      remoteDevice: map['remoteDevice'] != null
          ? HostShortsDevice.fromMap(map['remoteDevice'] as Map<String, dynamic>)
          : null,
      status: HostShortsStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => HostShortsStatus.idle,
      ),
      layout: HostShortsLayout.values.firstWhere(
        (l) => l.name == map['layout'],
        orElse: () => HostShortsLayout.pip,
      ),
      audioSource: HostShortsAudioSource.values.firstWhere(
        (a) => a.name == map['audioSource'],
        orElse: () => HostShortsAudioSource.stereoMix,
      ),
      isSyncedRecording: map['isSyncedRecording'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
