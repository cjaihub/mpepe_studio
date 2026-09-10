import 'dart:io';
import 'connected_destination.dart';

enum UploadStatus {
  pending,
  generatingMetadata,
  uploading,
  completed,
  failed,
}

class YouTubeSpecificMetadata {
  final String privacyStatus;
  final String categoryId;
  final bool madeForKids;
  final bool embeddable;
  final bool publicStatsViewable;
  final String? defaultLanguage;
  final String? defaultAudioLanguage;

  const YouTubeSpecificMetadata({
    this.privacyStatus = 'public',
    this.categoryId = '22', // People & Blogs default
    this.madeForKids = false,
    this.embeddable = true,
    this.publicStatsViewable = true,
    this.defaultLanguage,
    this.defaultAudioLanguage,
  });

  YouTubeSpecificMetadata copyWith({
    String? privacyStatus,
    String? categoryId,
    bool? madeForKids,
    bool? embeddable,
    bool? publicStatsViewable,
    String? defaultLanguage,
    String? defaultAudioLanguage,
  }) {
    return YouTubeSpecificMetadata(
      privacyStatus: privacyStatus ?? this.privacyStatus,
      categoryId: categoryId ?? this.categoryId,
      madeForKids: madeForKids ?? this.madeForKids,
      embeddable: embeddable ?? this.embeddable,
      publicStatsViewable: publicStatsViewable ?? this.publicStatsViewable,
      defaultLanguage: defaultLanguage ?? this.defaultLanguage,
      defaultAudioLanguage: defaultAudioLanguage ?? this.defaultAudioLanguage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'privacyStatus': privacyStatus,
      'categoryId': categoryId,
      'madeForKids': madeForKids,
      'embeddable': embeddable,
      'publicStatsViewable': publicStatsViewable,
      if (defaultLanguage != null) 'defaultLanguage': defaultLanguage,
      if (defaultAudioLanguage != null) 'defaultAudioLanguage': defaultAudioLanguage,
    };
  }
}

class OmnichannelUploadTask {
  final String id;
  final File file;
  
  // Destinations this task should be published to
  final List<ConnectedDestination> selectedDestinations;

  // Metadata (which could be AI generated)
  final String title;
  final String description;
  final List<String> tags;
  final File? customThumbnail;

  final UploadStatus status;
  final double progress;
  final String? errorMessage;
  
  // Destination specific metadata
  final YouTubeSpecificMetadata ytMetadata;

  // Resulting links after successful upload
  final Map<PlatformType, String> publishedLinks;

  OmnichannelUploadTask({
    required this.id,
    required this.file,
    this.selectedDestinations = const [],
    this.title = '',
    this.description = '',
    this.tags = const [],
    this.customThumbnail,
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.errorMessage,
    this.ytMetadata = const YouTubeSpecificMetadata(),
    this.publishedLinks = const {},
  });

  OmnichannelUploadTask copyWith({
    String? id,
    File? file,
    List<ConnectedDestination>? selectedDestinations,
    String? title,
    String? description,
    List<String>? tags,
    File? customThumbnail,
    UploadStatus? status,
    double? progress,
    String? errorMessage,
    YouTubeSpecificMetadata? ytMetadata,
    Map<PlatformType, String>? publishedLinks,
  }) {
    return OmnichannelUploadTask(
      id: id ?? this.id,
      file: file ?? this.file,
      selectedDestinations: selectedDestinations ?? this.selectedDestinations,
      title: title ?? this.title,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      customThumbnail: customThumbnail ?? this.customThumbnail,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      ytMetadata: ytMetadata ?? this.ytMetadata,
      publishedLinks: publishedLinks ?? this.publishedLinks,
    );
  }
}
