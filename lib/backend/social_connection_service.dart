import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PlatformCapability {
  static const String directChats = 'direct_chats';
  static const String comments = 'comments';
  static const String uploads = 'uploads';
  static const String analytics = 'analytics';

  static String getLabel(String cap) {
    switch (cap) {
      case directChats:
        return 'Direct Chats';
      case comments:
        return 'Comments Sync';
      case uploads:
        return 'Omnichannel Uploads';
      case analytics:
        return 'Live Analytics';
      default:
        return cap;
    }
  }

  static IconData getIcon(String cap) {
    switch (cap) {
      case directChats:
        return Icons.chat_bubble_outline_rounded;
      case comments:
        return Icons.forum_outlined;
      case uploads:
        return Icons.cloud_upload_outlined;
      case analytics:
        return Icons.insights_rounded;
      default:
        return Icons.check_circle_outline;
    }
  }
}

class PlatformIntegrationInfo {
  final String id;
  final String displayName;
  final String handleHint;
  final String badgeCode;
  final int badgeColorHex;
  final IconData icon;
  final String description;
  final List<String> capabilities;
  final bool isRecommended;

  const PlatformIntegrationInfo({
    required this.id,
    required this.displayName,
    required this.handleHint,
    required this.badgeCode,
    required this.badgeColorHex,
    required this.icon,
    required this.description,
    required this.capabilities,
    this.isRecommended = false,
  });
}

const List<PlatformIntegrationInfo> kSupportedPlatforms = [
  PlatformIntegrationInfo(
    id: 'whatsapp',
    displayName: 'WhatsApp Biz',
    handleHint: '+254 719... Active',
    badgeCode: 'WA',
    badgeColorHex: 0xFF25D366,
    icon: Icons.chat_rounded,
    description: 'WhatsApp Business API for direct chats, status updates, and catalog messaging.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
    isRecommended: true,
  ),
  PlatformIntegrationInfo(
    id: 'tiktok',
    displayName: 'TikTok Direct',
    handleHint: '@oneova_official',
    badgeCode: 'TT',
    badgeColorHex: 0xFFFF2D87,
    icon: Icons.music_note_rounded,
    description: 'TikTok for Business API for direct messages, video comments sync, and instant publishing.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
    isRecommended: true,
  ),
  PlatformIntegrationInfo(
    id: 'instagram',
    displayName: 'Instagram DMs',
    handleHint: '@oneova_live',
    badgeCode: 'IG',
    badgeColorHex: 0xFFE1306C,
    icon: Icons.camera_alt_rounded,
    description: 'Instagram Graph API for direct inbox messages, reel comments, and cross-posting.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
    isRecommended: true,
  ),
  PlatformIntegrationInfo(
    id: 'youtube',
    displayName: 'YouTube Studio',
    handleHint: 'OneOva Studio Channel',
    badgeCode: 'YT',
    badgeColorHex: 0xFFFF0000,
    icon: Icons.smart_display_rounded,
    description: 'YouTube Data API for Shorts uploads, community posts, and video comment streams.',
    capabilities: [
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
  ),
  PlatformIntegrationInfo(
    id: 'x',
    displayName: 'X (Twitter)',
    handleHint: '@oneova_hq',
    badgeCode: 'X',
    badgeColorHex: 0xFF1DA1F2,
    icon: Icons.alternate_email_rounded,
    description: 'X API v2 for direct messages, mentions, quote-reposts, and media publishing.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
  ),
  PlatformIntegrationInfo(
    id: 'facebook',
    displayName: 'Facebook Pages',
    handleHint: 'Oneova Global Page',
    badgeCode: 'FB',
    badgeColorHex: 0xFF1877F2,
    icon: Icons.facebook_rounded,
    description: 'Meta Graph API for Page messenger conversations, reel publishing, and comments.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ],
  ),
  PlatformIntegrationInfo(
    id: 'telegram',
    displayName: 'Telegram Channel',
    handleHint: '@oneova_broadcast',
    badgeCode: 'TG',
    badgeColorHex: 0xFF0088CC,
    icon: Icons.send_rounded,
    description: 'Telegram Bot API for high-frequency channel audio drops and subscriber queries.',
    capabilities: [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
    ],
  ),
];

class SocialConnection {
  final String platform;
  final String accountName;
  final String displayName;
  final int unreadCount;
  final String badgeCode;
  final int badgeColorHex;
  final String status; // 'synced', 'active', 'offline'
  final List<String> capabilities;
  final DateTime connectedAt;

  SocialConnection({
    required this.platform,
    required this.accountName,
    String? displayName,
    this.unreadCount = 0,
    String? badgeCode,
    int? badgeColorHex,
    this.status = 'synced',
    List<String>? capabilities,
    required this.connectedAt,
  })  : displayName = displayName ?? _resolveDisplayName(platform),
        badgeCode = badgeCode ?? _resolveBadgeCode(platform),
        badgeColorHex = badgeColorHex ?? _resolveBadgeColor(platform),
        capabilities = capabilities ?? _resolveCapabilities(platform);

  static String _resolveDisplayName(String p) {
    final match = kSupportedPlatforms.where((sp) => sp.id == p.toLowerCase()).firstOrNull;
    if (match != null) return match.displayName;
    if (p.isEmpty) return 'Connected Platform';
    return p[0].toUpperCase() + p.substring(1);
  }

  static String _resolveBadgeCode(String p) {
    final match = kSupportedPlatforms.where((sp) => sp.id == p.toLowerCase()).firstOrNull;
    if (match != null) return match.badgeCode;
    return p.length >= 2 ? p.substring(0, 2).toUpperCase() : p.toUpperCase();
  }

  static int _resolveBadgeColor(String p) {
    final match = kSupportedPlatforms.where((sp) => sp.id == p.toLowerCase()).firstOrNull;
    if (match != null) return match.badgeColorHex;
    return 0xFF0C4FA8;
  }

  static List<String> _resolveCapabilities(String p) {
    final match = kSupportedPlatforms.where((sp) => sp.id == p.toLowerCase()).firstOrNull;
    if (match != null) return match.capabilities;
    return [
      PlatformCapability.directChats,
      PlatformCapability.comments,
      PlatformCapability.uploads,
      PlatformCapability.analytics,
    ];
  }

  factory SocialConnection.fromMap(Map<String, dynamic> data) {
    final platformStr = data['platform']?.toString().toLowerCase() ?? '';
    return SocialConnection(
      platform: platformStr,
      accountName: data['accountName']?.toString() ?? '',
      displayName: data['displayName']?.toString(),
      unreadCount: (data['unreadCount'] is num) ? (data['unreadCount'] as num).toInt() : 0,
      badgeCode: data['badgeCode']?.toString(),
      badgeColorHex: (data['badgeColorHex'] is num) ? (data['badgeColorHex'] as num).toInt() : null,
      status: data['status']?.toString() ?? 'synced',
      capabilities: (data['capabilities'] is List)
          ? List<String>.from(data['capabilities'])
          : null,
      connectedAt: (data['connectedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'platform': platform.toLowerCase(),
      'accountName': accountName,
      'displayName': displayName,
      'unreadCount': unreadCount,
      'badgeCode': badgeCode,
      'badgeColorHex': badgeColorHex,
      'status': status,
      'capabilities': capabilities,
      'connectedAt': FieldValue.serverTimestamp(),
    };
  }

  SocialConnection copyWith({
    String? platform,
    String? accountName,
    String? displayName,
    int? unreadCount,
    String? badgeCode,
    int? badgeColorHex,
    String? status,
    List<String>? capabilities,
    DateTime? connectedAt,
  }) {
    return SocialConnection(
      platform: platform ?? this.platform,
      accountName: accountName ?? this.accountName,
      displayName: displayName ?? this.displayName,
      unreadCount: unreadCount ?? this.unreadCount,
      badgeCode: badgeCode ?? this.badgeCode,
      badgeColorHex: badgeColorHex ?? this.badgeColorHex,
      status: status ?? this.status,
      capabilities: capabilities ?? this.capabilities,
      connectedAt: connectedAt ?? this.connectedAt,
    );
  }
}

class SocialConnectionService extends AsyncNotifier<List<SocialConnection>> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Future<List<SocialConnection>> build() async {
    return _loadConnections();
  }

  String? get _userId => _auth.currentUser?.uid;

  Future<List<SocialConnection>> _loadConnections() async {
    final uid = _userId;
    if (uid == null) return [];

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .collection('social_connections')
          .get();

      return snapshot.docs
          .map((doc) => SocialConnection.fromMap(doc.data()))
          .toList();
    } catch (e) {
      debugPrint('Error loading connections: $e');
      return [];
    }
  }

  Stream<List<SocialConnection>> streamConnections() {
    final uid = _userId;
    if (uid == null) return Stream.value([]);

    return _firestore
        .collection('users')
        .doc(uid)
        .collection('social_connections')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => SocialConnection.fromMap(doc.data()))
            .toList());
  }

  Future<void> addConnection(
    String platform,
    String accountName, {
    String? displayName,
    int? unreadCount,
    String? badgeCode,
    int? badgeColorHex,
    List<String>? capabilities,
    String? status,
  }) async {
    final uid = _userId;
    final conn = SocialConnection(
      platform: platform.toLowerCase(),
      accountName: accountName,
      displayName: displayName,
      unreadCount: unreadCount ?? 0,
      badgeCode: badgeCode,
      badgeColorHex: badgeColorHex,
      capabilities: capabilities,
      status: status ?? 'synced',
      connectedAt: DateTime.now(),
    );

    if (uid != null) {
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('social_connections')
            .doc(platform.toLowerCase())
            .set(conn.toMap());
      } catch (e) {
        debugPrint('Error writing connection to Firestore: $e');
      }
    }

    if (state.hasValue) {
      final current = state.value!;
      final filtered = current.where((c) => c.platform.toLowerCase() != platform.toLowerCase()).toList();
      state = AsyncValue.data([...filtered, conn]);
    } else {
      state = AsyncValue.data([conn]);
    }
  }

  Future<void> disconnectPlatform(String platform) async {
    final uid = _userId;
    final pKey = platform.toLowerCase();

    if (uid != null) {
      try {
        await _firestore
            .collection('users')
            .doc(uid)
            .collection('social_connections')
            .doc(pKey)
            .delete();
      } catch (e) {
        debugPrint('Error disconnecting platform: $e');
      }
    }

    if (state.hasValue) {
      final current = state.value!;
      state = AsyncValue.data(current.where((c) => c.platform.toLowerCase() != pKey).toList());
    }
  }

  Future<void> seedDefaultConnections() async {
    // Conveniently seed the standard 3 omni platforms if the user chooses instant connect
    await addConnection('whatsapp', '+254 719... Active', unreadCount: 24, badgeColorHex: 0xFF25D366, badgeCode: 'WA');
    await addConnection('tiktok', '@oneova_official', unreadCount: 14, badgeColorHex: 0xFFFF2D87, badgeCode: 'TT');
    await addConnection('instagram', '@oneova_live', unreadCount: 10, badgeColorHex: 0xFFE1306C, badgeCode: 'IG');
  }
}

final socialConnectionProvider = AsyncNotifierProvider<SocialConnectionService, List<SocialConnection>>(() {
  return SocialConnectionService();
});

final userSocialConnectionsStreamProvider = StreamProvider<List<SocialConnection>>((ref) {
  final service = ref.watch(socialConnectionProvider.notifier);
  return service.streamConnections();
});
