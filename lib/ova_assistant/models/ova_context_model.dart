import 'package:flutter/material.dart';

/// Available Ova Assistant personas
enum AssistantPersonaId {
  oneova,
  ova,
  onyx,
}

class AssistantPersona {
  final AssistantPersonaId id;
  final String name;
  final String tagline;
  final String description;
  final IconData icon;

  const AssistantPersona({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.icon,
  });

  static const List<AssistantPersona> all = [
    AssistantPersona(
      id: AssistantPersonaId.oneova,
      name: 'Oneova',
      tagline: 'All you need in your Pocket as a creative',
      description: 'Your intelligent creative studio and phone copilot with real-time tools.',
      icon: Icons.auto_awesome,
    ),
    AssistantPersona(
      id: AssistantPersonaId.ova,
      name: 'Ova',
      tagline: 'Oneova Studio & Phone Master',
      description: 'High-performance AI agent capable of orchestrating your phone, media, and creator studio tools.',
      icon: Icons.bolt_rounded,
    ),
    AssistantPersona(
      id: AssistantPersonaId.onyx,
      name: 'Onyx',
      tagline: 'Deep Strategy & Media Architect',
      description: 'Analytical mind for travel planning, content research, video scripting, and workflows.',
      icon: Icons.psychology_rounded,
    ),
  ];
}

/// Represents recent photo or media on the user's phone
class RecentPhotoItem {
  final String id;
  final String title;
  final String timeAgo;
  final String assetOrUrl;
  final int width;
  final int height;

  const RecentPhotoItem({
    required this.id,
    required this.title,
    required this.timeAgo,
    required this.assetOrUrl,
    this.width = 1080,
    this.height = 1350,
  });
}

/// Represents a WhatsApp status update from a contact
class WhatsAppStatusItem {
  final String contactName;
  final String timeAgo;
  final String previewText;
  final String? mediaThumbnail;
  final bool isUnseen;

  const WhatsAppStatusItem({
    required this.contactName,
    required this.timeAgo,
    required this.previewText,
    this.mediaThumbnail,
    this.isUnseen = true,
  });
}

/// Real-time phone state: "what's going on"
class PhoneContextState {
  final double batteryLevel; // 0.0 to 1.0
  final bool isCharging;
  final String networkType; // "4G LTE", "Wi-Fi 6", etc.
  final String currentTimeString;
  final int unreadWhatsAppCount;
  final int unreadNotificationsCount;
  final List<RecentPhotoItem> recentPhotos;
  final List<WhatsAppStatusItem> whatsappStatuses;
  final String activeApp;

  const PhoneContextState({
    this.batteryLevel = 1.0,
    this.isCharging = false,
    this.networkType = 'Unknown',
    this.currentTimeString = '5:51',
    this.unreadWhatsAppCount = 3,
    this.unreadNotificationsCount = 5,
    this.recentPhotos = const [],
    this.whatsappStatuses = const [],
    this.activeApp = 'Home Screen',
  });

  PhoneContextState copyWith({
    double? batteryLevel,
    bool? isCharging,
    String? networkType,
    String? currentTimeString,
    int? unreadWhatsAppCount,
    int? unreadNotificationsCount,
    List<RecentPhotoItem>? recentPhotos,
    List<WhatsAppStatusItem>? whatsappStatuses,
    String? activeApp,
  }) {
    return PhoneContextState(
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      networkType: networkType ?? this.networkType,
      currentTimeString: currentTimeString ?? this.currentTimeString,
      unreadWhatsAppCount: unreadWhatsAppCount ?? this.unreadWhatsAppCount,
      unreadNotificationsCount: unreadNotificationsCount ?? this.unreadNotificationsCount,
      recentPhotos: recentPhotos ?? this.recentPhotos,
      whatsappStatuses: whatsappStatuses ?? this.whatsappStatuses,
      activeApp: activeApp ?? this.activeApp,
    );
  }
}

/// Contextual quick-action chip (like the chips floating above the sheet in the screenshot)
class ContextChip {
  final String id;
  final IconData icon;
  final String? prefixBadge; // e.g. "NEW"
  final String label;
  final String prompt;

  const ContextChip({
    required this.id,
    required this.icon,
    this.prefixBadge,
    required this.label,
    required this.prompt,
  });
}

/// Message in Ova Assistant conversation
class OvaChatMessage {
  final String id;
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? actionType; // 'whatsapp_send', 'safari_plan', 'whatsapp_status', 'phone_control'
  final Map<String, dynamic>? actionData;

  const OvaChatMessage({
    required this.id,
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.actionType,
    this.actionData,
  });
}
