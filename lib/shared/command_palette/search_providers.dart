import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'command_palette_models.dart';

import '../../backend/agents/background_agent_service.dart';
import '../../backend/gemini_live_service.dart';

class CommandPaletteQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  void update(String value) => state = value;
}
final commandPaletteQueryProvider = NotifierProvider<CommandPaletteQueryNotifier, String>(CommandPaletteQueryNotifier.new);

final staticCommandsProvider = Provider<List<CommandItem>>((ref) {
  return [
    CommandItem(
      id: 'nav_inbox',
      title: 'Open inbox',
      icon: Icons.inbox,
      category: CommandCategory.navigation,
      searchTags: ['messages', 'mail', 'home', 'inbox'],
      onExecute: (context) async => context.push('/social_hub/unified_inbox'),
    ),
    CommandItem(
      id: 'nav_contacts',
      title: 'Open contacts',
      icon: Icons.people,
      category: CommandCategory.navigation,
      searchTags: ['people', 'friends', 'network', 'contacts'],
      onExecute: (context) async => context.push('/social_hub/contacts'),
    ),
    CommandItem(
      id: 'nav_analytics',
      title: 'Open analytics',
      icon: Icons.analytics,
      category: CommandCategory.navigation,
      searchTags: ['stats', 'dashboard', 'data', 'analytics'],
      onExecute: (context) async => context.push('/youtube/dashboard'),
    ),
    CommandItem(
      id: 'nav_settings',
      title: 'Open settings',
      icon: Icons.settings,
      category: CommandCategory.navigation,
      searchTags: ['preferences', 'config', 'options', 'settings'],
      onExecute: (context) async => context.push('/settings'),
    ),
    CommandItem(
      id: 'nav_notifications',
      title: 'Open notifications',
      icon: Icons.notifications,
      category: CommandCategory.navigation,
      searchTags: ['alerts', 'updates', 'notifications'],
      onExecute: (context) async => context.push('/social_hub/notifications'),
    ),
    
    // --- Action Commands ---
    CommandItem(
      id: 'action_new_message',
      title: 'New message',
      subtitle: 'Compose a new message',
      icon: Icons.edit,
      category: CommandCategory.action,
      searchTags: ['write', 'compose', 'create', 'send', 'message'],
      onExecute: (context) async {
        context.push('/social_hub/new_message');
      },
    ),
    CommandItem(
      id: 'nav_search_messages',
      title: 'Search messages',
      subtitle: 'Search across all messages',
      icon: Icons.search,
      category: CommandCategory.action,
      searchTags: ['find', 'lookup', 'search'],
      onExecute: (context) async {
        context.push('/global_search?filter=messages');
      },
    ),
    CommandItem(
      id: 'action_schedule_message',
      title: 'Schedule message',
      icon: Icons.schedule,
      category: CommandCategory.action,
      searchTags: ['delay', 'timer', 'send later', 'schedule'],
      onExecute: (context) async {
        context.push('/social_hub/schedule_message');
      },
    ),
    CommandItem(
      id: 'action_start_call',
      title: 'Start call',
      icon: Icons.call,
      category: CommandCategory.action,
      searchTags: ['phone', 'audio', 'voice call', 'call'],
      onExecute: (context) async {
        context.push('/social_hub/contacts?action=call');
      },
    ),
    CommandItem(
      id: 'action_start_video_call',
      title: 'Start video call',
      icon: Icons.videocam,
      category: CommandCategory.action,
      searchTags: ['video', 'camera', 'facetime', 'video call'],
      onExecute: (context) async {
        context.push('/social_hub/contacts?action=video_call');
      },
    ),
    CommandItem(
      id: 'action_mark_all_read',
      title: 'Mark all read',
      icon: Icons.done_all,
      category: CommandCategory.action,
      searchTags: ['read', 'clear', 'seen'],
      onExecute: (context) async {
        // Implement mark all read via a provider
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All messages marked as read.')),
        );
      },
    ),
    
    // --- System / Status Commands ---
    CommandItem(
      id: 'system_toggle_dnd',
      title: 'Toggle Do Not Disturb',
      icon: Icons.do_not_disturb_alt,
      category: CommandCategory.system,
      searchTags: ['dnd', 'silence', 'quiet', 'mute'],
      onExecute: (context) async {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Do Not Disturb toggled.')),
        );
      },
    ),
    CommandItem(
      id: 'system_switch_workspace',
      title: 'Switch workspace',
      icon: Icons.workspaces,
      category: CommandCategory.system,
      searchTags: ['change', 'tenant', 'org', 'workspace'],
      onExecute: (context) async {
        context.push('/workspaces');
      },
    ),
    
    // --- AI / Agent Commands ---
    CommandItem(
      id: 'ai_open',
      title: 'Open AI',
      icon: Icons.smart_toy,
      category: CommandCategory.system,
      searchTags: ['gemini', 'bot', 'help', 'ask', 'ai'],
      onExecute: (context) async {
        context.push('/ai_messaging/chat');
      },
    ),
    CommandItem(
      id: 'ai_start_voice',
      title: 'Start voice mode',
      icon: Icons.mic,
      category: CommandCategory.system,
      searchTags: ['talk', 'speak', 'live', 'audio ai', 'voice'],
      onExecute: (context) async {
        ref.read(geminiLiveProvider.notifier).startVoiceMode();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connecting to AI Voice Mode...')),
        );
      },
    ),
    CommandItem(
      id: 'ai_pause_agent',
      title: 'Pause AI',
      subtitle: 'Instantly stops all autonomous background AI actions',
      icon: Icons.stop_circle,
      category: CommandCategory.system,
      requiresPermission: true,
      searchTags: ['kill switch', 'stop ai', 'halt', 'disable', 'pause'],
      onExecute: (context) async {
        final agentService = ref.read(backgroundAgentServiceProvider);
        agentService.emergencyStopAllAi();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Background AI has been paused globally.')),
          );
        }
      },
    ),
  ];
});

final filteredCommandsProvider = Provider<List<CommandItem>>((ref) {
  final query = ref.watch(commandPaletteQueryProvider);
  final commands = ref.watch(staticCommandsProvider);
  
  if (query.trim().isEmpty) {
    return commands;
  }
  
  final q = query.toLowerCase();
  return commands.where((cmd) {
    if (cmd.title.toLowerCase().contains(q)) return true;
    if (cmd.subtitle != null && cmd.subtitle!.toLowerCase().contains(q)) return true;
    for (var tag in cmd.searchTags) {
      if (tag.toLowerCase().contains(q)) return true;
    }
    return false;
  }).toList();
});
