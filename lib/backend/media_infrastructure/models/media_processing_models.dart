import 'package:cloud_firestore/cloud_firestore.dart';

enum MediaType {
  image,
  video,
  audio,
  document,
}

enum MediaProcessingStatus {
  uploaded,
  validating,
  processing,
  ready,
  failed,
  deleted,
}

enum MediaVisibility {
  public,
  private,
  unlisted,
}

class MediaResolution {
  final String label; // e.g. "240p", "1080p", "original"
  final int height;
  final int width;
  final int bitrateKbps;

  const MediaResolution({
    required this.label,
    required this.height,
    required this.width,
    required this.bitrateKbps,
  });

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'height': height,
      'width': width,
      'bitrateKbps': bitrateKbps,
    };
  }

  factory MediaResolution.fromMap(Map<String, dynamic> map) {
    return MediaResolution(
      label: map['label'] ?? '',
      height: map['height'] ?? 0,
      width: map['width'] ?? 0,
      bitrateKbps: map['bitrateKbps'] ?? 0,
    );
  }
}

class MediaVariant {
  final MediaResolution resolution;
  final String storagePath; // Path in bucket, NOT a raw public URL
  final int fileSize;

  const MediaVariant({
    required this.resolution,
    required this.storagePath,
    required this.fileSize,
  });

  Map<String, dynamic> toMap() {
    return {
      'resolution': resolution.toMap(),
      'storagePath': storagePath,
      'fileSize': fileSize,
    };
  }

  factory MediaVariant.fromMap(Map<String, dynamic> map) {
    return MediaVariant(
      resolution: MediaResolution.fromMap(map['resolution'] ?? {}),
      storagePath: map['storagePath'] ?? '',
      fileSize: map['fileSize'] ?? 0,
    );
  }
}

class MediaAsset {
  final String id;
  final String ownerId;
  final MediaType type;
  
  // File details
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;
  final Duration? duration;
  final String? dimensions; // e.g., "1920x1080"
  final String? checksum;
  
  // Storage & State
  final String storageLocation; // Private bucket path
  final MediaProcessingStatus processingState;
  final MediaVisibility visibility;
  
  // Rights & Permissions
  final String rights;
  final String license;
  final bool aiProcessingPermission;

  // Streaming/Variants
  final String? thumbnailUrl;
  final String? posterUrl;
  final String? hlsPlaylistPath; // m3u8 bucket path
  final List<MediaVariant> variants;
  
  final DateTime createdAt;
  final DateTime? updatedAt;

  const MediaAsset({
    required this.id,
    required this.ownerId,
    required this.type,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
    this.duration,
    this.dimensions,
    this.checksum,
    required this.storageLocation,
    required this.processingState,
    required this.visibility,
    this.rights = 'standard',
    this.license = 'proprietary',
    this.aiProcessingPermission = false,
    this.thumbnailUrl,
    this.posterUrl,
    this.hlsPlaylistPath,
    this.variants = const [],
    required this.createdAt,
    this.updatedAt,
  });

  factory MediaAsset.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MediaAsset(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      type: MediaType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => MediaType.video,
      ),
      originalFilename: data['originalFilename'] ?? '',
      mimeType: data['mimeType'] ?? 'application/octet-stream',
      sizeBytes: data['sizeBytes'] ?? 0,
      duration: data['durationMs'] != null ? Duration(milliseconds: data['durationMs']) : null,
      dimensions: data['dimensions'],
      checksum: data['checksum'],
      storageLocation: data['storageLocation'] ?? '',
      processingState: MediaProcessingStatus.values.firstWhere(
        (e) => e.name == data['processingState'],
        orElse: () => MediaProcessingStatus.failed,
      ),
      visibility: MediaVisibility.values.firstWhere(
        (e) => e.name == data['visibility'],
        orElse: () => MediaVisibility.private,
      ),
      rights: data['rights'] ?? 'standard',
      license: data['license'] ?? 'proprietary',
      aiProcessingPermission: data['aiProcessingPermission'] ?? false,
      thumbnailUrl: data['thumbnailUrl'],
      posterUrl: data['posterUrl'],
      hlsPlaylistPath: data['hlsPlaylistPath'],
      variants: (data['variants'] as List<dynamic>?)
              ?.map((e) => MediaVariant.fromMap(e))
              .toList() ??
          [],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null ? (data['updatedAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'type': type.name,
      'originalFilename': originalFilename,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'durationMs': duration?.inMilliseconds,
      'dimensions': dimensions,
      'checksum': checksum,
      'storageLocation': storageLocation,
      'processingState': processingState.name,
      'visibility': visibility.name,
      'rights': rights,
      'license': license,
      'aiProcessingPermission': aiProcessingPermission,
      'thumbnailUrl': thumbnailUrl,
      'posterUrl': posterUrl,
      'hlsPlaylistPath': hlsPlaylistPath,
      'variants': variants.map((e) => e.toMap()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }
}
