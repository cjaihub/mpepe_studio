
enum AttachmentType {
  image,
  video,
  audio,
  document,
  pdf,
  link,
  voice,
  location,
  unknown,
}

enum AttachmentStatus {
  uploading,
  validating,
  ready,
  failed,
}

class Attachment {
  final String id;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final AttachmentType type;
  final String storagePath;
  final String? downloadUrl;
  final AttachmentStatus status;
  final String? encryptionKey; // For E2EE payloads
  final String? thumbnailUrl;
  final Map<String, dynamic>? metadata;

  Attachment({
    required this.id,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    required this.type,
    required this.storagePath,
    this.downloadUrl,
    this.status = AttachmentStatus.uploading,
    this.encryptionKey,
    this.thumbnailUrl,
    this.metadata,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id'] ?? '',
      fileName: json['fileName'] ?? 'unknown_file',
      fileSize: json['fileSize'] ?? 0,
      mimeType: json['mimeType'] ?? 'application/octet-stream',
      type: AttachmentType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => AttachmentType.unknown,
      ),
      storagePath: json['storagePath'] ?? '',
      downloadUrl: json['downloadUrl'],
      status: AttachmentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => AttachmentStatus.failed,
      ),
      encryptionKey: json['encryptionKey'],
      thumbnailUrl: json['thumbnailUrl'],
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fileName': fileName,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'type': type.name,
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'status': status.name,
      'encryptionKey': encryptionKey,
      'thumbnailUrl': thumbnailUrl,
      'metadata': metadata,
    };
  }

  Attachment copyWith({
    String? id,
    String? fileName,
    int? fileSize,
    String? mimeType,
    AttachmentType? type,
    String? storagePath,
    String? downloadUrl,
    AttachmentStatus? status,
    String? encryptionKey,
    String? thumbnailUrl,
    Map<String, dynamic>? metadata,
  }) {
    return Attachment(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      mimeType: mimeType ?? this.mimeType,
      type: type ?? this.type,
      storagePath: storagePath ?? this.storagePath,
      downloadUrl: downloadUrl ?? this.downloadUrl,
      status: status ?? this.status,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      metadata: metadata ?? this.metadata,
    );
  }
}
