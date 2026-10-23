import 'package:uuid/uuid.dart';

enum AudioType {
  originalSound,
  uploadedMusic,
  licensedMusic,
  soundEffect,
  voiceover,
  aiGenerated,
}

enum AudioLicenseType {
  commercial,
  nonCommercial,
  royalFree,
  custom,
}

class AudioUsagePermissions {
  final bool allowRemix;
  final bool allowDownload;
  final bool allowCommercialUse;

  const AudioUsagePermissions({
    this.allowRemix = true,
    this.allowDownload = true,
    this.allowCommercialUse = false,
  });
}

class AudioTrack {
  final String id;
  final String title;
  final String ownerId;
  final String ownerName;
  final AudioType type;
  final AudioLicenseType licenseType;
  final String? licenseMetadata;
  final int durationMs;
  final bool isAvailable;
  final AudioUsagePermissions permissions;
  final String attribution;
  final String contentUrl;
  final String coverImageUrl;

  const AudioTrack({
    required this.id,
    required this.title,
    required this.ownerId,
    required this.ownerName,
    required this.type,
    required this.licenseType,
    this.licenseMetadata,
    required this.durationMs,
    this.isAvailable = true,
    this.permissions = const AudioUsagePermissions(),
    required this.attribution,
    required this.contentUrl,
    required this.coverImageUrl,
  });

  factory AudioTrack.fromMap(Map<String, dynamic> data) {
    return AudioTrack(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? 'Unknown Title',
      ownerId: data['ownerId'] as String? ?? '',
      ownerName: data['ownerName'] as String? ?? 'Unknown Artist',
      type: AudioType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => AudioType.originalSound,
      ),
      licenseType: AudioLicenseType.values.firstWhere(
        (e) => e.name == data['licenseType'],
        orElse: () => AudioLicenseType.nonCommercial,
      ),
      licenseMetadata: data['licenseMetadata'] as String?,
      durationMs: data['durationMs'] as int? ?? 0,
      isAvailable: data['isAvailable'] as bool? ?? true,
      permissions: const AudioUsagePermissions(), // Expand if needed
      attribution: data['attribution'] as String? ?? '',
      contentUrl: data['contentUrl'] as String? ?? '',
      coverImageUrl: data['coverImageUrl'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'ownerId': ownerId,
      'ownerName': ownerName,
      'type': type.name,
      'licenseType': licenseType.name,
      'licenseMetadata': licenseMetadata,
      'durationMs': durationMs,
      'isAvailable': isAvailable,
      'attribution': attribution,
      'contentUrl': contentUrl,
      'coverImageUrl': coverImageUrl,
    };
  }

  factory AudioTrack.mock({
    String? title,
    AudioType? type,
  }) {
    return AudioTrack(
      id: const Uuid().v4(),
      title: title ?? 'Original Sound',
      ownerId: 'user_123',
      ownerName: 'ONEROVA Creator',
      type: type ?? AudioType.originalSound,
      licenseType: AudioLicenseType.nonCommercial,
      durationMs: 15000, // 15 seconds
      attribution: 'Original audio by ONEROVA Creator',
      contentUrl: '',
      coverImageUrl: '',
    );
  }
}
