import 'package:flutter/material.dart';

enum PlatformCategory { video, audio, social, storage }

class PlatformDestination {
  final String id;
  final String name;
  final IconData icon;
  final PlatformCategory category;
  final bool isConnected;

  const PlatformDestination({
    required this.id,
    required this.name,
    required this.icon,
    required this.category,
    this.isConnected = false,
  });
}

// Dummy data for 50+ platforms based on the user's request.
final List<PlatformDestination> kAvailablePlatforms = [
  // Video Platforms
  const PlatformDestination(id: 'yt', name: 'YouTube', icon: Icons.smart_display_rounded, category: PlatformCategory.video, isConnected: true),
  const PlatformDestination(id: 'tt', name: 'TikTok', icon: Icons.music_note_rounded, category: PlatformCategory.video, isConnected: true),
  const PlatformDestination(id: 'ig', name: 'Instagram Reels', icon: Icons.camera_alt_rounded, category: PlatformCategory.video),
  const PlatformDestination(id: 'vimeo', name: 'Vimeo', icon: Icons.video_library_rounded, category: PlatformCategory.video),
  const PlatformDestination(id: 'twitch', name: 'Twitch', icon: Icons.live_tv_rounded, category: PlatformCategory.video),
  
  // Audio Platforms
  const PlatformDestination(id: 'spotify', name: 'Spotify', icon: Icons.headset_rounded, category: PlatformCategory.audio, isConnected: true),
  const PlatformDestination(id: 'apple_music', name: 'Apple Music', icon: Icons.music_video_rounded, category: PlatformCategory.audio),
  const PlatformDestination(id: 'soundcloud', name: 'SoundCloud', icon: Icons.cloud_rounded, category: PlatformCategory.audio),
  const PlatformDestination(id: 'audiomack', name: 'Audiomack', icon: Icons.album_rounded, category: PlatformCategory.audio),
  const PlatformDestination(id: 'tidal', name: 'Tidal', icon: Icons.waves_rounded, category: PlatformCategory.audio),
  
  // Social
  const PlatformDestination(id: 'x', name: 'X (Twitter)', icon: Icons.chat_rounded, category: PlatformCategory.social, isConnected: true),
  const PlatformDestination(id: 'fb', name: 'Facebook', icon: Icons.facebook_rounded, category: PlatformCategory.social),
  const PlatformDestination(id: 'li', name: 'LinkedIn', icon: Icons.work_rounded, category: PlatformCategory.social),
  const PlatformDestination(id: 'pinterest', name: 'Pinterest', icon: Icons.push_pin_rounded, category: PlatformCategory.social),
  const PlatformDestination(id: 'snap', name: 'Snapchat', icon: Icons.camera_front_rounded, category: PlatformCategory.social),
  
  // Storage
  const PlatformDestination(id: 'drive', name: 'Google Drive', icon: Icons.add_to_drive_rounded, category: PlatformCategory.storage, isConnected: true),
  const PlatformDestination(id: 'dropbox', name: 'Dropbox', icon: Icons.folder_shared_rounded, category: PlatformCategory.storage),
  const PlatformDestination(id: 'aws', name: 'AWS S3', icon: Icons.storage_rounded, category: PlatformCategory.storage),
  
  // Note: Representing 50+ platforms with these core groups for the UI mockup.
];
