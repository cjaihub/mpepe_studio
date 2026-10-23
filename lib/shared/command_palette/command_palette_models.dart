import 'package:flutter/material.dart';

enum CommandCategory {
  navigation,
  action,
  contact,
  message,
  channel,
  setting,
  system,
}

class CommandItem {
  final String id;
  final String title;
  final String? subtitle;
  final IconData icon;
  final CommandCategory category;
  final Future<void> Function(BuildContext context) onExecute;
  final List<String> searchTags;
  final bool requiresAuth;
  final bool requiresPermission; // Can be tied to AgentConfig or User role later

  const CommandItem({
    required this.id,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.category,
    required this.onExecute,
    this.searchTags = const [],
    this.requiresAuth = true,
    this.requiresPermission = false,
  });

  bool matches(String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    
    if (title.toLowerCase().contains(lowerQuery)) return true;
    if (subtitle?.toLowerCase().contains(lowerQuery) ?? false) return true;
    
    for (final tag in searchTags) {
      if (tag.toLowerCase().contains(lowerQuery)) return true;
    }
    
    if (category.name.toLowerCase().contains(lowerQuery)) return true;
    
    return false;
  }
}
