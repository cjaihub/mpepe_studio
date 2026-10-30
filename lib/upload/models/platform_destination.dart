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
