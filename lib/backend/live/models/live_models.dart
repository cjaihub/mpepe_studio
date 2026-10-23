import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ENUMS
// ─────────────────────────────────────────────────────────────────────────────

enum LiveStreamStatus {
  scheduled,
  starting,
  live,
  reconnecting,
  ended,
  abandoned,
}

enum LiveStreamType {
  singleHost,
  coHost,
  multiGuest,
  interactiveRoom,
  eventStage,
  screenShare,
}

enum LiveStageScene {
  minimalStudio,
  multiCamGrid,
  holographicStage,
  eventHall,
  cinemaRoom,
}

enum LiveInputSourceMode {
  cameraOnly,
  screenShareWithCameraPip,
  multiInputHybrid,
}

enum LiveGuestRole {
  coHost,
  speaker,
  moderator,
  viewer,
}

enum LiveGuestRequestStatus {
  pending,
  approved,
  rejected,
  cancelled,
}

// ─────────────────────────────────────────────────────────────────────────────
// CHAT SETTINGS
// ─────────────────────────────────────────────────────────────────────────────

class LiveChatSettings {
  final bool subscriberOnly;
  final bool slowModeEnabled;
  final int slowModeDelaySeconds;
  final List<String> blockedWords;
  final bool giftsEnabled;

  const LiveChatSettings({
    this.subscriberOnly = false,
    this.slowModeEnabled = false,
    this.slowModeDelaySeconds = 0,
    this.blockedWords = const [],
    this.giftsEnabled = true,
  });

  factory LiveChatSettings.fromJson(Map<String, dynamic> json) {
    return LiveChatSettings(
      subscriberOnly: json['subscriberOnly'] as bool? ?? false,
      slowModeEnabled: json['slowModeEnabled'] as bool? ?? false,
      slowModeDelaySeconds: json['slowModeDelaySeconds'] as int? ?? 0,
      blockedWords: List<String>.from(json['blockedWords'] as List? ?? []),
      giftsEnabled: json['giftsEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() => {
        'subscriberOnly': subscriberOnly,
        'slowModeEnabled': slowModeEnabled,
        'slowModeDelaySeconds': slowModeDelaySeconds,
        'blockedWords': blockedWords,
        'giftsEnabled': giftsEnabled,
      };

  LiveChatSettings copyWith({
    bool? subscriberOnly,
    bool? slowModeEnabled,
    int? slowModeDelaySeconds,
    List<String>? blockedWords,
    bool? giftsEnabled,
  }) {
    return LiveChatSettings(
      subscriberOnly: subscriberOnly ?? this.subscriberOnly,
      slowModeEnabled: slowModeEnabled ?? this.slowModeEnabled,
      slowModeDelaySeconds: slowModeDelaySeconds ?? this.slowModeDelaySeconds,
      blockedWords: blockedWords ?? this.blockedWords,
      giftsEnabled: giftsEnabled ?? this.giftsEnabled,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BEAUTY CONFIG
// ─────────────────────────────────────────────────────────────────────────────

class LiveBeautyConfig {
  final double smoothSkinLevel;
  final double ringLightIntensity;
  final double warmToneLevel;
  final bool backgroundBlurEnabled;

  const LiveBeautyConfig({
    this.smoothSkinLevel = 0.0,
    this.ringLightIntensity = 0.5,
    this.warmToneLevel = 0.0,
    this.backgroundBlurEnabled = false,
  });

  factory LiveBeautyConfig.fromJson(Map<String, dynamic> json) {
    return LiveBeautyConfig(
      smoothSkinLevel: (json['smoothSkinLevel'] as num?)?.toDouble() ?? 0.0,
      ringLightIntensity:
          (json['ringLightIntensity'] as num?)?.toDouble() ?? 0.5,
      warmToneLevel: (json['warmToneLevel'] as num?)?.toDouble() ?? 0.0,
      backgroundBlurEnabled: json['backgroundBlurEnabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'smoothSkinLevel': smoothSkinLevel,
        'ringLightIntensity': ringLightIntensity,
        'warmToneLevel': warmToneLevel,
        'backgroundBlurEnabled': backgroundBlurEnabled,
      };

  LiveBeautyConfig copyWith({
    double? smoothSkinLevel,
    double? ringLightIntensity,
    double? warmToneLevel,
    bool? backgroundBlurEnabled,
  }) {
    return LiveBeautyConfig(
      smoothSkinLevel: smoothSkinLevel ?? this.smoothSkinLevel,
      ringLightIntensity: ringLightIntensity ?? this.ringLightIntensity,
      warmToneLevel: warmToneLevel ?? this.warmToneLevel,
      backgroundBlurEnabled:
          backgroundBlurEnabled ?? this.backgroundBlurEnabled,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDIA DESK CONFIG
// ─────────────────────────────────────────────────────────────────────────────

class LiveMediaDeskConfig {
  final String backgroundMusicTitle;
  final String backgroundMusicUrl;
  final bool isMusicPlaying;
  final double musicVolume;
  final String? activeGraphicOverlay;
  final String? lowerThirdText;
  final bool isYoutubeAudioEnabled;
  final String? youtubeVideoId;
  final String? activeSoundboardFx;

  const LiveMediaDeskConfig({
    this.backgroundMusicTitle = '',
    this.backgroundMusicUrl = '',
    this.isMusicPlaying = false,
    this.musicVolume = 0.4,
    this.activeGraphicOverlay,
    this.lowerThirdText,
    this.isYoutubeAudioEnabled = false,
    this.youtubeVideoId,
    this.activeSoundboardFx,
  });

  factory LiveMediaDeskConfig.fromJson(Map<String, dynamic> json) {
    return LiveMediaDeskConfig(
      backgroundMusicTitle: json['backgroundMusicTitle'] as String? ?? '',
      backgroundMusicUrl: json['backgroundMusicUrl'] as String? ?? '',
      isMusicPlaying: json['isMusicPlaying'] as bool? ?? false,
      musicVolume: (json['musicVolume'] as num?)?.toDouble() ?? 0.4,
      activeGraphicOverlay: json['activeGraphicOverlay'] as String?,
      lowerThirdText: json['lowerThirdText'] as String?,
      isYoutubeAudioEnabled: json['isYoutubeAudioEnabled'] as bool? ?? false,
      youtubeVideoId: json['youtubeVideoId'] as String?,
      activeSoundboardFx: json['activeSoundboardFx'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'backgroundMusicTitle': backgroundMusicTitle,
        'backgroundMusicUrl': backgroundMusicUrl,
        'isMusicPlaying': isMusicPlaying,
        'musicVolume': musicVolume,
        'activeGraphicOverlay': activeGraphicOverlay,
        'lowerThirdText': lowerThirdText,
        'isYoutubeAudioEnabled': isYoutubeAudioEnabled,
        'youtubeVideoId': youtubeVideoId,
        'activeSoundboardFx': activeSoundboardFx,
      };

  LiveMediaDeskConfig copyWith({
    String? backgroundMusicTitle,
    String? backgroundMusicUrl,
    bool? isMusicPlaying,
    double? musicVolume,
    String? activeGraphicOverlay,
    String? lowerThirdText,
    bool? isYoutubeAudioEnabled,
    String? youtubeVideoId,
    String? activeSoundboardFx,
  }) {
    return LiveMediaDeskConfig(
      backgroundMusicTitle: backgroundMusicTitle ?? this.backgroundMusicTitle,
      backgroundMusicUrl: backgroundMusicUrl ?? this.backgroundMusicUrl,
      isMusicPlaying: isMusicPlaying ?? this.isMusicPlaying,
      musicVolume: musicVolume ?? this.musicVolume,
      activeGraphicOverlay: activeGraphicOverlay ?? this.activeGraphicOverlay,
      lowerThirdText: lowerThirdText ?? this.lowerThirdText,
      isYoutubeAudioEnabled:
          isYoutubeAudioEnabled ?? this.isYoutubeAudioEnabled,
      youtubeVideoId: youtubeVideoId ?? this.youtubeVideoId,
      activeSoundboardFx: activeSoundboardFx ?? this.activeSoundboardFx,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEGAL COMPLIANCE
// ─────────────────────────────────────────────────────────────────────────────

class LiveLegalCompliance {
  final String contentRating;
  final bool hasCopyrightMusicConsent;
  final bool agreedToCommunityGuidelines;
  final String creatorConsentSignature;
  final DateTime? consentedAt;

  const LiveLegalCompliance({
    this.contentRating = 'all_ages',
    this.hasCopyrightMusicConsent = false,
    this.agreedToCommunityGuidelines = true,
    this.creatorConsentSignature = '',
    this.consentedAt,
  });

  factory LiveLegalCompliance.fromJson(Map<String, dynamic> json) {
    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return LiveLegalCompliance(
      contentRating: json['contentRating'] as String? ?? 'all_ages',
      hasCopyrightMusicConsent:
          json['hasCopyrightMusicConsent'] as bool? ?? false,
      agreedToCommunityGuidelines:
          json['agreedToCommunityGuidelines'] as bool? ?? true,
      creatorConsentSignature:
          json['creatorConsentSignature'] as String? ?? '',
      consentedAt: parseNullableDate(json['consentedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'contentRating': contentRating,
        'hasCopyrightMusicConsent': hasCopyrightMusicConsent,
        'agreedToCommunityGuidelines': agreedToCommunityGuidelines,
        'creatorConsentSignature': creatorConsentSignature,
        'consentedAt':
            consentedAt != null ? Timestamp.fromDate(consentedAt!) : null,
      };

  LiveLegalCompliance copyWith({
    String? contentRating,
    bool? hasCopyrightMusicConsent,
    bool? agreedToCommunityGuidelines,
    String? creatorConsentSignature,
    DateTime? consentedAt,
  }) {
    return LiveLegalCompliance(
      contentRating: contentRating ?? this.contentRating,
      hasCopyrightMusicConsent:
          hasCopyrightMusicConsent ?? this.hasCopyrightMusicConsent,
      agreedToCommunityGuidelines:
          agreedToCommunityGuidelines ?? this.agreedToCommunityGuidelines,
      creatorConsentSignature:
          creatorConsentSignature ?? this.creatorConsentSignature,
      consentedAt: consentedAt ?? this.consentedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI STAGE CONFIG
// ─────────────────────────────────────────────────────────────────────────────

class LiveStageConfig {
  final String? prompt;
  final String atmospherePreset;
  final String hologramEmblem;
  final String audioPreset;
  final String primaryColorHex;
  final String accentColorHex;
  final double ambientGlowIntensity;

  const LiveStageConfig({
    this.prompt,
    this.atmospherePreset = 'Cyber-Cinema',
    this.hologramEmblem = 'cube',
    this.audioPreset = 'Cinema Surround',
    this.primaryColorHex = '#0C4FA8',
    this.accentColorHex = '#FF2D87',
    this.ambientGlowIntensity = 0.85,
  });

  factory LiveStageConfig.fromJson(Map<String, dynamic> json) {
    return LiveStageConfig(
      prompt: json['prompt'] as String?,
      atmospherePreset:
          json['atmospherePreset'] as String? ?? 'Cyber-Cinema',
      hologramEmblem: json['hologramEmblem'] as String? ?? 'cube',
      audioPreset: json['audioPreset'] as String? ?? 'Cinema Surround',
      primaryColorHex: json['primaryColorHex'] as String? ?? '#0C4FA8',
      accentColorHex: json['accentColorHex'] as String? ?? '#FF2D87',
      ambientGlowIntensity:
          (json['ambientGlowIntensity'] as num?)?.toDouble() ?? 0.85,
    );
  }

  Map<String, dynamic> toJson() => {
        'prompt': prompt,
        'atmospherePreset': atmospherePreset,
        'hologramEmblem': hologramEmblem,
        'audioPreset': audioPreset,
        'primaryColorHex': primaryColorHex,
        'accentColorHex': accentColorHex,
        'ambientGlowIntensity': ambientGlowIntensity,
      };

  LiveStageConfig copyWith({
    String? prompt,
    String? atmospherePreset,
    String hologramEmblem = 'cube',
    String? audioPreset,
    String? primaryColorHex,
    String? accentColorHex,
    double? ambientGlowIntensity,
  }) {
    return LiveStageConfig(
      prompt: prompt ?? this.prompt,
      atmospherePreset: atmospherePreset ?? this.atmospherePreset,
      hologramEmblem: hologramEmblem,
      audioPreset: audioPreset ?? this.audioPreset,
      primaryColorHex: primaryColorHex ?? this.primaryColorHex,
      accentColorHex: accentColorHex ?? this.accentColorHex,
      ambientGlowIntensity:
          ambientGlowIntensity ?? this.ambientGlowIntensity,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 30-DAY PERSISTENT STREAM ENDPOINT
// ─────────────────────────────────────────────────────────────────────────────

class LiveStreamEndpoint {
  final String serverUrl;
  final String streamKey;
  final DateTime keyExpiresAt;
  final bool isKeyActive;
  final List<String> multiCastDestinations;

  const LiveStreamEndpoint({
    this.serverUrl = 'rtmps://live.oneova.com/live',
    this.streamKey = '',
    required this.keyExpiresAt,
    this.isKeyActive = true,
    this.multiCastDestinations = const [],
  });

  factory LiveStreamEndpoint.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now().add(const Duration(days: 30));
    }

    return LiveStreamEndpoint(
      serverUrl:
          json['serverUrl'] as String? ?? 'rtmps://live.oneova.com/live',
      streamKey: json['streamKey'] as String? ?? '',
      keyExpiresAt: parseDate(json['keyExpiresAt']),
      isKeyActive: json['isKeyActive'] as bool? ?? true,
      multiCastDestinations:
          List<String>.from(json['multiCastDestinations'] as List? ?? []),
    );
  }

  Map<String, dynamic> toJson() => {
        'serverUrl': serverUrl,
        'streamKey': streamKey,
        'keyExpiresAt': Timestamp.fromDate(keyExpiresAt),
        'isKeyActive': isKeyActive,
        'multiCastDestinations': multiCastDestinations,
      };

  LiveStreamEndpoint copyWith({
    String? serverUrl,
    String? streamKey,
    DateTime? keyExpiresAt,
    bool? isKeyActive,
    List<String>? multiCastDestinations,
  }) {
    return LiveStreamEndpoint(
      serverUrl: serverUrl ?? this.serverUrl,
      streamKey: streamKey ?? this.streamKey,
      keyExpiresAt: keyExpiresAt ?? this.keyExpiresAt,
      isKeyActive: isKeyActive ?? this.isKeyActive,
      multiCastDestinations:
          multiCastDestinations ?? this.multiCastDestinations,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AI MODERATOR SETTINGS
// ─────────────────────────────────────────────────────────────────────────────

class AIModeratorSettings {
  final bool isAutoModerationEnabled;
  final bool autoFilterToxicComments;
  final bool autoPinQuestions;
  final double sentimentScore;

  const AIModeratorSettings({
    this.isAutoModerationEnabled = true,
    this.autoFilterToxicComments = true,
    this.autoPinQuestions = true,
    this.sentimentScore = 0.95,
  });

  factory AIModeratorSettings.fromJson(Map<String, dynamic> json) {
    return AIModeratorSettings(
      isAutoModerationEnabled:
          json['isAutoModerationEnabled'] as bool? ?? true,
      autoFilterToxicComments:
          json['autoFilterToxicComments'] as bool? ?? true,
      autoPinQuestions: json['autoPinQuestions'] as bool? ?? true,
      sentimentScore: (json['sentimentScore'] as num?)?.toDouble() ?? 0.95,
    );
  }

  Map<String, dynamic> toJson() => {
        'isAutoModerationEnabled': isAutoModerationEnabled,
        'autoFilterToxicComments': autoFilterToxicComments,
        'autoPinQuestions': autoPinQuestions,
        'sentimentScore': sentimentScore,
      };

  AIModeratorSettings copyWith({
    bool? isAutoModerationEnabled,
    bool? autoFilterToxicComments,
    bool? autoPinQuestions,
    double? sentimentScore,
  }) {
    return AIModeratorSettings(
      isAutoModerationEnabled:
          isAutoModerationEnabled ?? this.isAutoModerationEnabled,
      autoFilterToxicComments:
          autoFilterToxicComments ?? this.autoFilterToxicComments,
      autoPinQuestions: autoPinQuestions ?? this.autoPinQuestions,
      sentimentScore: sentimentScore ?? this.sentimentScore,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE STREAM
// ─────────────────────────────────────────────────────────────────────────────

class LiveStream {
  final String id;
  final String hostId;
  final String hostDisplayName;
  final String hostAvatarUrl;
  final String title;
  final String category;
  final LiveStreamType type;
  final LiveStreamStatus status;
  final LiveStageScene stageScene;
  final LiveStageConfig stageConfig;
  final LiveStreamEndpoint endpoint;
  final AIModeratorSettings aiModerator;
  final int viewerCount;
  final int totalLikes;
  final int totalComments;
  final LiveChatSettings chatSettings;
  final List<String> coHostIds;
  final List<String> moderatorIds;
  final String? pinnedCommentId;
  final bool recordingEnabled;
  final bool liveCaptionsEnabled;
  final bool liveTranslationEnabled;
  final String audienceMode; // 'public', 'followers', 'subscribers'
  final String resolution; // '480p', '720p', '1080p'
  final int frameRate; // 30, 60
  final bool isMultiPlatform;
  final List<String> linkedPlatforms;
  final LiveInputSourceMode inputSourceMode;
  final LiveBeautyConfig beautyConfig;
  final LiveMediaDeskConfig mediaDeskConfig;
  final LiveLegalCompliance legalCompliance;
  final bool allowGuestRequests;

  /// How viewers watch: 'classic' (full-screen vertical live) or 'studio'
  /// (guests as video windows on the Live Studio walls).
  final String layoutMode;
  final DateTime createdAt;
  final DateTime? endedAt;

  const LiveStream({
    required this.id,
    required this.hostId,
    required this.hostDisplayName,
    required this.hostAvatarUrl,
    required this.title,
    required this.category,
    required this.type,
    required this.status,
    required this.stageScene,
    this.stageConfig = const LiveStageConfig(),
    required this.endpoint,
    this.aiModerator = const AIModeratorSettings(),
    this.viewerCount = 0,
    this.totalLikes = 0,
    this.totalComments = 0,
    this.chatSettings = const LiveChatSettings(),
    this.coHostIds = const [],
    this.moderatorIds = const [],
    this.pinnedCommentId,
    this.recordingEnabled = false,
    this.liveCaptionsEnabled = false,
    this.liveTranslationEnabled = false,
    this.audienceMode = 'public',
    this.resolution = '1080p',
    this.frameRate = 60,
    this.isMultiPlatform = false,
    this.linkedPlatforms = const [],
    this.inputSourceMode = LiveInputSourceMode.cameraOnly,
    this.beautyConfig = const LiveBeautyConfig(),
    this.mediaDeskConfig = const LiveMediaDeskConfig(),
    this.legalCompliance = const LiveLegalCompliance(),
    this.allowGuestRequests = true,
    this.layoutMode = 'classic',
    required this.createdAt,
    this.endedAt,
  });

  factory LiveStream.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return LiveStream(
      id: json['id'] as String? ?? '',
      hostId: json['hostId'] as String? ?? '',
      hostDisplayName: json['hostDisplayName'] as String? ?? 'Unknown',
      hostAvatarUrl: json['hostAvatarUrl'] as String? ?? '',
      title: json['title'] as String? ?? 'Live Stream',
      category: json['category'] as String? ?? 'Entertainment',
      type: LiveStreamType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => LiveStreamType.singleHost,
      ),
      status: LiveStreamStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LiveStreamStatus.live,
      ),
      stageScene: LiveStageScene.values.firstWhere(
        (e) => e.name == json['stageScene'],
        orElse: () => LiveStageScene.minimalStudio,
      ),
      stageConfig: json['stageConfig'] is Map
          ? LiveStageConfig.fromJson(
              Map<String, dynamic>.from(json['stageConfig'] as Map))
          : const LiveStageConfig(),
      endpoint: json['endpoint'] is Map
          ? LiveStreamEndpoint.fromJson(
              Map<String, dynamic>.from(json['endpoint'] as Map))
          : LiveStreamEndpoint(
              keyExpiresAt: DateTime.now().add(const Duration(days: 30)),
              streamKey: 'ov_live_${json['id'] ?? 'stream'}',
            ),
      aiModerator: json['aiModerator'] is Map
          ? AIModeratorSettings.fromJson(
              Map<String, dynamic>.from(json['aiModerator'] as Map))
          : const AIModeratorSettings(),
      viewerCount: json['viewerCount'] as int? ?? 0,
      totalLikes: json['totalLikes'] as int? ?? 0,
      totalComments: json['totalComments'] as int? ?? 0,
      chatSettings: json['chatSettings'] is Map
          ? LiveChatSettings.fromJson(
              Map<String, dynamic>.from(json['chatSettings'] as Map))
          : const LiveChatSettings(),
      coHostIds: List<String>.from(json['coHostIds'] as List? ?? []),
      moderatorIds: List<String>.from(json['moderatorIds'] as List? ?? []),
      pinnedCommentId: json['pinnedCommentId'] as String?,
      recordingEnabled: json['recordingEnabled'] as bool? ?? false,
      liveCaptionsEnabled: json['liveCaptionsEnabled'] as bool? ?? false,
      liveTranslationEnabled: json['liveTranslationEnabled'] as bool? ?? false,
      audienceMode: json['audienceMode'] as String? ?? 'public',
      resolution: json['resolution'] as String? ?? '1080p',
      frameRate: json['frameRate'] as int? ?? 60,
      isMultiPlatform: json['isMultiPlatform'] as bool? ?? false,
      linkedPlatforms:
          List<String>.from(json['linkedPlatforms'] as List? ?? []),
      inputSourceMode: LiveInputSourceMode.values.firstWhere(
        (e) => e.name == json['inputSourceMode'],
        orElse: () => LiveInputSourceMode.cameraOnly,
      ),
      beautyConfig: json['beautyConfig'] is Map
          ? LiveBeautyConfig.fromJson(
              Map<String, dynamic>.from(json['beautyConfig'] as Map))
          : const LiveBeautyConfig(),
      mediaDeskConfig: json['mediaDeskConfig'] is Map
          ? LiveMediaDeskConfig.fromJson(
              Map<String, dynamic>.from(json['mediaDeskConfig'] as Map))
          : const LiveMediaDeskConfig(),
      legalCompliance: json['legalCompliance'] is Map
          ? LiveLegalCompliance.fromJson(
              Map<String, dynamic>.from(json['legalCompliance'] as Map))
          : const LiveLegalCompliance(),
      allowGuestRequests: json['allowGuestRequests'] as bool? ?? true,
      layoutMode: json['layoutMode'] as String? ?? 'classic',
      createdAt: parseDate(json['createdAt']),
      endedAt: json['endedAt'] != null ? parseDate(json['endedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostId': hostId,
        'hostDisplayName': hostDisplayName,
        'hostAvatarUrl': hostAvatarUrl,
        'title': title,
        'category': category,
        'type': type.name,
        'status': status.name,
        'stageScene': stageScene.name,
        'stageConfig': stageConfig.toJson(),
        'endpoint': endpoint.toJson(),
        'aiModerator': aiModerator.toJson(),
        'viewerCount': viewerCount,
        'totalLikes': totalLikes,
        'totalComments': totalComments,
        'chatSettings': chatSettings.toJson(),
        'coHostIds': coHostIds,
        'moderatorIds': moderatorIds,
        'pinnedCommentId': pinnedCommentId,
        'recordingEnabled': recordingEnabled,
        'liveCaptionsEnabled': liveCaptionsEnabled,
        'liveTranslationEnabled': liveTranslationEnabled,
        'audienceMode': audienceMode,
        'resolution': resolution,
        'frameRate': frameRate,
        'isMultiPlatform': isMultiPlatform,
        'linkedPlatforms': linkedPlatforms,
        'inputSourceMode': inputSourceMode.name,
        'beautyConfig': beautyConfig.toJson(),
        'mediaDeskConfig': mediaDeskConfig.toJson(),
        'legalCompliance': legalCompliance.toJson(),
        'allowGuestRequests': allowGuestRequests,
        'layoutMode': layoutMode,
        'createdAt': Timestamp.fromDate(createdAt),
        'endedAt': endedAt != null ? Timestamp.fromDate(endedAt!) : null,
      };

  LiveStream copyWith({
    String? id,
    String? hostId,
    String? hostDisplayName,
    String? hostAvatarUrl,
    String? title,
    String? category,
    LiveStreamType? type,
    LiveStreamStatus? status,
    LiveStageScene? stageScene,
    LiveStageConfig? stageConfig,
    LiveStreamEndpoint? endpoint,
    AIModeratorSettings? aiModerator,
    int? viewerCount,
    int? totalLikes,
    int? totalComments,
    LiveChatSettings? chatSettings,
    List<String>? coHostIds,
    List<String>? moderatorIds,
    String? pinnedCommentId,
    bool? recordingEnabled,
    bool? liveCaptionsEnabled,
    bool? liveTranslationEnabled,
    String? audienceMode,
    String? resolution,
    int? frameRate,
    bool? isMultiPlatform,
    List<String>? linkedPlatforms,
    LiveInputSourceMode? inputSourceMode,
    LiveBeautyConfig? beautyConfig,
    LiveMediaDeskConfig? mediaDeskConfig,
    LiveLegalCompliance? legalCompliance,
    bool? allowGuestRequests,
    String? layoutMode,
    DateTime? createdAt,
    DateTime? endedAt,
  }) {
    return LiveStream(
      id: id ?? this.id,
      hostId: hostId ?? this.hostId,
      hostDisplayName: hostDisplayName ?? this.hostDisplayName,
      hostAvatarUrl: hostAvatarUrl ?? this.hostAvatarUrl,
      title: title ?? this.title,
      category: category ?? this.category,
      type: type ?? this.type,
      status: status ?? this.status,
      stageScene: stageScene ?? this.stageScene,
      stageConfig: stageConfig ?? this.stageConfig,
      endpoint: endpoint ?? this.endpoint,
      aiModerator: aiModerator ?? this.aiModerator,
      viewerCount: viewerCount ?? this.viewerCount,
      totalLikes: totalLikes ?? this.totalLikes,
      totalComments: totalComments ?? this.totalComments,
      chatSettings: chatSettings ?? this.chatSettings,
      coHostIds: coHostIds ?? this.coHostIds,
      moderatorIds: moderatorIds ?? this.moderatorIds,
      pinnedCommentId: pinnedCommentId ?? this.pinnedCommentId,
      recordingEnabled: recordingEnabled ?? this.recordingEnabled,
      liveCaptionsEnabled: liveCaptionsEnabled ?? this.liveCaptionsEnabled,
      liveTranslationEnabled:
          liveTranslationEnabled ?? this.liveTranslationEnabled,
      audienceMode: audienceMode ?? this.audienceMode,
      resolution: resolution ?? this.resolution,
      frameRate: frameRate ?? this.frameRate,
      isMultiPlatform: isMultiPlatform ?? this.isMultiPlatform,
      linkedPlatforms: linkedPlatforms ?? this.linkedPlatforms,
      inputSourceMode: inputSourceMode ?? this.inputSourceMode,
      beautyConfig: beautyConfig ?? this.beautyConfig,
      mediaDeskConfig: mediaDeskConfig ?? this.mediaDeskConfig,
      legalCompliance: legalCompliance ?? this.legalCompliance,
      allowGuestRequests: allowGuestRequests ?? this.allowGuestRequests,
      layoutMode: layoutMode ?? this.layoutMode,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE GUEST REQUEST
// ─────────────────────────────────────────────────────────────────────────────

class LiveGuestRequest {
  final String requestId;
  final String streamId;
  final String userId;
  final String displayName;
  final String avatarUrl;
  final LiveGuestRole requestedRole;
  final LiveGuestRequestStatus status;
  final DateTime requestedAt;
  final DateTime? respondedAt;

  const LiveGuestRequest({
    required this.requestId,
    required this.streamId,
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    this.requestedRole = LiveGuestRole.speaker,
    this.status = LiveGuestRequestStatus.pending,
    required this.requestedAt,
    this.respondedAt,
  });

  factory LiveGuestRequest.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return LiveGuestRequest(
      requestId: json['requestId'] as String? ?? json['id'] as String? ?? '',
      streamId: json['streamId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Guest',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      requestedRole: LiveGuestRole.values.firstWhere(
        (e) => e.name == json['requestedRole'],
        orElse: () => LiveGuestRole.speaker,
      ),
      status: LiveGuestRequestStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => LiveGuestRequestStatus.pending,
      ),
      requestedAt: parseDate(json['requestedAt']),
      respondedAt: parseNullableDate(json['respondedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'requestId': requestId,
        'streamId': streamId,
        'userId': userId,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'requestedRole': requestedRole.name,
        'status': status.name,
        'requestedAt': Timestamp.fromDate(requestedAt),
        'respondedAt':
            respondedAt != null ? Timestamp.fromDate(respondedAt!) : null,
      };

  LiveGuestRequest copyWith({
    String? requestId,
    String? streamId,
    String? userId,
    String? displayName,
    String? avatarUrl,
    LiveGuestRole? requestedRole,
    LiveGuestRequestStatus? status,
    DateTime? requestedAt,
    DateTime? respondedAt,
  }) {
    return LiveGuestRequest(
      requestId: requestId ?? this.requestId,
      streamId: streamId ?? this.streamId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      requestedRole: requestedRole ?? this.requestedRole,
      status: status ?? this.status,
      requestedAt: requestedAt ?? this.requestedAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE COMMENT
// ─────────────────────────────────────────────────────────────────────────────

class LiveComment {
  final String id;
  final String streamId;
  final String authorId;
  final String authorDisplayName;
  final String authorAvatarUrl;
  final String text;
  final bool isGift;
  final String? giftType; // 'heart', 'star', 'crown', 'rocket'
  final int? giftCount;
  final bool isModerator;
  final bool isPinned;
  final bool isHighlighted;
  final DateTime createdAt;

  const LiveComment({
    required this.id,
    required this.streamId,
    required this.authorId,
    required this.authorDisplayName,
    required this.authorAvatarUrl,
    required this.text,
    this.isGift = false,
    this.giftType,
    this.giftCount,
    this.isModerator = false,
    this.isPinned = false,
    this.isHighlighted = false,
    required this.createdAt,
  });

  factory LiveComment.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return LiveComment(
      id: json['id'] as String? ?? '',
      streamId: json['streamId'] as String? ?? '',
      authorId: json['authorId'] as String? ?? '',
      authorDisplayName: json['authorDisplayName'] as String? ?? 'Unknown',
      authorAvatarUrl: json['authorAvatarUrl'] as String? ?? '',
      text: json['text'] as String? ?? '',
      isGift: json['isGift'] as bool? ?? false,
      giftType: json['giftType'] as String?,
      giftCount: json['giftCount'] as int?,
      isModerator: json['isModerator'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      isHighlighted: json['isHighlighted'] as bool? ?? false,
      createdAt: parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'authorId': authorId,
        'authorDisplayName': authorDisplayName,
        'authorAvatarUrl': authorAvatarUrl,
        'text': text,
        'isGift': isGift,
        'giftType': giftType,
        'giftCount': giftCount,
        'isModerator': isModerator,
        'isPinned': isPinned,
        'isHighlighted': isHighlighted,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE PARTICIPANT
// ─────────────────────────────────────────────────────────────────────────────

class LiveParticipant {
  final String userId;
  final String displayName;
  final String avatarUrl;
  final bool isCoHost;
  final bool hasRequestedToJoin;
  final bool isMuted;
  final bool isCameraOn;
  final LiveGuestRole role;
  final DateTime joinedAt;

  const LiveParticipant({
    required this.userId,
    required this.displayName,
    required this.avatarUrl,
    this.isCoHost = false,
    this.hasRequestedToJoin = false,
    this.isMuted = false,
    this.isCameraOn = false,
    this.role = LiveGuestRole.viewer,
    required this.joinedAt,
  });

  factory LiveParticipant.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return LiveParticipant(
      userId: json['userId'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Unknown',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      isCoHost: json['isCoHost'] as bool? ?? false,
      hasRequestedToJoin: json['hasRequestedToJoin'] as bool? ?? false,
      isMuted: json['isMuted'] as bool? ?? false,
      isCameraOn: json['isCameraOn'] as bool? ?? false,
      role: LiveGuestRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => (json['isCoHost'] as bool? ?? false)
            ? LiveGuestRole.coHost
            : LiveGuestRole.viewer,
      ),
      joinedAt: parseDate(json['joinedAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': userId,
        'displayName': displayName,
        'avatarUrl': avatarUrl,
        'isCoHost': isCoHost,
        'hasRequestedToJoin': hasRequestedToJoin,
        'isMuted': isMuted,
        'isCameraOn': isCameraOn,
        'role': role.name,
        'joinedAt': Timestamp.fromDate(joinedAt),
      };

  LiveParticipant copyWith({
    bool? isCoHost,
    bool? hasRequestedToJoin,
    bool? isMuted,
    bool? isCameraOn,
    LiveGuestRole? role,
  }) {
    return LiveParticipant(
      userId: userId,
      displayName: displayName,
      avatarUrl: avatarUrl,
      isCoHost: isCoHost ?? this.isCoHost,
      hasRequestedToJoin: hasRequestedToJoin ?? this.hasRequestedToJoin,
      isMuted: isMuted ?? this.isMuted,
      isCameraOn: isCameraOn ?? this.isCameraOn,
      role: role ?? this.role,
      joinedAt: joinedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LIVE REACTION
// ─────────────────────────────────────────────────────────────────────────────

class LiveReaction {
  final String id;
  final String streamId;
  final String userId;
  final String type; // 'heart', 'fire', 'star'
  final DateTime createdAt;

  const LiveReaction({
    required this.id,
    required this.streamId,
    required this.userId,
    required this.type,
    required this.createdAt,
  });

  factory LiveReaction.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    return LiveReaction(
      id: json['id'] as String? ?? '',
      streamId: json['streamId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      type: json['type'] as String? ?? 'heart',
      createdAt: parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'streamId': streamId,
        'userId': userId,
        'type': type,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
