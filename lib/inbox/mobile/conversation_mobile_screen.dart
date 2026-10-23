import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/inbox/providers/canonical_inbox_provider.dart';
import '../../backend/inbox/providers/conversation_state_provider.dart';
import 'widgets/message_bubble.dart';
import 'widgets/capability_aware_composer.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ConversationMobileScreen extends ConsumerWidget {
  final String conversationId;

  const ConversationMobileScreen({
    super.key,
    required this.conversationId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Top-level conversation metadata stream
    final conversationAsync = ref.watch(conversationStreamProvider(conversationId));
    
    // Paginated targeted message list state
    final messagesState = ref.watch(conversationStateProvider(conversationId));
    final messagesNotifier = ref.read(conversationStateProvider(conversationId).notifier);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: conversationAsync.when(
          data: (conv) {
            if (conv == null) return Text('Chat', style: TextStyle(color: context.textPrimary));
            return Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: context.surfaceMid,
                  child: Text(
                    conv.id.substring(0, 1).toUpperCase(),
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Participant', // Resolved in a real app
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        conv.connectorId ?? 'Internal',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
          loading: () => Text('Loading...', style: TextStyle(color: context.textPrimary)),
          error: (_, _) => Text('Error', style: TextStyle(color: context.textPrimary)),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: context.textPrimary),
            onPressed: () => _showConversationTools(context, ref, conversationId),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesState.isLoading && messagesState.messages.isEmpty
                ? const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue))
                : messagesState.error != null
                    ? Center(child: Text('Error: ${messagesState.error}', style: const TextStyle(color: Colors.red)))
                    : ListView.builder(
                        reverse: true, // Latest messages at the bottom
                        itemCount: messagesState.messages.length + (messagesState.isFetchingOlder ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == messagesState.messages.length) {
                            // Trigger load older
                            messagesNotifier.loadOlderMessages();
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16.0),
                              child: Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
                            );
                          }
                          
                          final message = messagesState.messages[index];
                          return MessageBubble(message: message);
                        },
                      ),
          ),
          
          // Capability-Aware Composer
          conversationAsync.when(
            data: (conv) {
              if (conv == null) return const SizedBox.shrink();
              return CapabilityAwareComposer(conversation: conv);
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  void _showConversationTools(BuildContext context, WidgetRef ref, String conversationId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 16),
                height: 4,
                width: 40,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              ListTile(
                leading: Icon(Icons.perm_media, color: context.textPrimary),
                title: Text('Media & Files', style: TextStyle(color: context.textPrimary)),
                onTap: () { Navigator.pop(ctx); },
              ),
              ListTile(
                leading: const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
                title: Text('AI Copilot', style: TextStyle(color: context.textPrimary)),
                onTap: () { Navigator.pop(ctx); },
              ),
              ListTile(
                leading: Icon(Icons.search, color: context.textPrimary),
                title: Text('Search Conversation', style: TextStyle(color: context.textPrimary)),
                onTap: () { Navigator.pop(ctx); },
              ),
            ],
          ),
        );
      },
    );
  }
}
