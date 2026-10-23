import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../backend/unified_inbox_provider.dart' show SocialPlatform;
import '../../backend/inbox/models/conversation_model.dart';
import '../../backend/inbox/models/message_model.dart';
import '../../backend/inbox/providers/realtime_chat_provider.dart';
import '../../backend/inbox/repositories/message_repository.dart';
import '../../backend/inbox/repositories/conversation_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// Inbox specific exact design system overrides
const Color inboxRed = Color(0xFFFF1F2D);
const Color inboxBlack = Color(0xFF080808);
const Color inboxWhite = Color(0xFFFFFFFF);
const Color inboxOutline = Color(0x33FFFFFF); // 20% white for borders
const Color inboxSurface = Color(0x0AFFFFFF); // Very subtle surface differentiation

class DesktopSidebar extends StatelessWidget {
  final SocialPlatform? selectedPlatform;
  final String selectedSection;
  final ValueChanged<SocialPlatform?> onPlatformSelected;
  final ValueChanged<String> onSectionSelected;

  const DesktopSidebar({
    super.key,
    required this.selectedPlatform,
    required this.selectedSection,
    required this.onPlatformSelected,
    required this.onSectionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: inboxBlack,
        border: Border(right: BorderSide(color: inboxOutline)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        children: [
          // Primary Sections
          _buildSectionHeader('Menu'),
          _buildSidebarItem('AI Chats', Icons.auto_awesome, isSelected: selectedSection == 'AI Chats', onTap: () => onSectionSelected('AI Chats')),
          _buildSidebarItem('Inbox', Icons.inbox, isSelected: selectedSection == 'Inbox', onTap: () => onSectionSelected('Inbox')),
          _buildSidebarItem('Contacts', Icons.people_outline, isSelected: selectedSection == 'Contacts', onTap: () => onSectionSelected('Contacts')),
          _buildSidebarItem('Channels', Icons.hub_outlined, isSelected: selectedSection == 'Channels', onTap: () => onSectionSelected('Channels')),
          _buildSidebarItem('Analytics', Icons.bar_chart, isSelected: selectedSection == 'Analytics', onTap: () => onSectionSelected('Analytics')),
          _buildSidebarItem('Files & Documents', Icons.folder_outlined, isSelected: selectedSection == 'Files & Documents', onTap: () => onSectionSelected('Files & Documents')),
          _buildSidebarItem('Settings', Icons.settings_outlined, isSelected: selectedSection == 'Settings', onTap: () => onSectionSelected('Settings')),
          
          const SizedBox(height: 24),
          
          // Main Services
          _buildSectionHeader('Main Services'),
          _buildServiceItem('WhatsApp', SocialPlatform.whatsapp, Icons.wechat),
          _buildServiceItem('Facebook', SocialPlatform.facebook, Icons.facebook),
          _buildServiceItem('Instagram', SocialPlatform.instagram, Icons.camera_alt),
          _buildServiceItem('Messenger', SocialPlatform.messenger, Icons.message),
          _buildServiceItem('Telegram', SocialPlatform.telegram, Icons.send),
          _buildServiceItem('Email', SocialPlatform.email, Icons.email_outlined),
          _buildServiceItem('SMS', null, Icons.sms_outlined),
          _buildServiceItem('Website Chat', SocialPlatform.system, Icons.laptop_mac_outlined),
          
          const SizedBox(height: 24),
          
          // Quick Access
          _buildSectionHeader('Quick Access'),
          _buildSidebarItem('Courses & Students', Icons.school_outlined, isSelected: selectedSection == 'Courses & Students', onTap: () => onSectionSelected('Courses & Students')),
          _buildSidebarItem('Sales & Enquiries', Icons.monetization_on_outlined, isSelected: selectedSection == 'Sales & Enquiries', onTap: () => onSectionSelected('Sales & Enquiries')),
          _buildSidebarItem('Team Chat', Icons.group_work_outlined, isSelected: selectedSection == 'Team Chat', onTap: () => onSectionSelected('Team Chat')),
          _buildSidebarItem('Help & Support', Icons.help_outline, isSelected: selectedSection == 'Help & Support', onTap: () => onSectionSelected('Help & Support')),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.caption(inboxWhite.withValues(alpha: 0.5)).copyWith(fontWeight: FontWeight.w900, letterSpacing: 1.2),
      ),
    );
  }

  Widget _buildSidebarItem(String label, IconData icon, {required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? inboxSurface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? inboxRed : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? inboxRed : inboxWhite.withValues(alpha: 0.7), size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTypography.navigation(isSelected ? inboxWhite : inboxWhite.withValues(alpha: 0.7)).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItem(String label, SocialPlatform? platform, IconData icon) {
    final isSelected = selectedPlatform == platform && selectedSection == 'Inbox';
    return InkWell(
      onTap: () {
        onSectionSelected('Inbox');
        onPlatformSelected(platform);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? inboxSurface : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? inboxRed : Colors.transparent,
              width: 4,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? inboxRed : inboxWhite.withValues(alpha: 0.6), size: 18),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: AppTypography.navigation(isSelected ? inboxWhite : inboxWhite.withValues(alpha: 0.6)).copyWith(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DesktopConversationView extends ConsumerStatefulWidget {
  final Conversation? selectedItem;

  const DesktopConversationView({super.key, this.selectedItem});

  @override
  ConsumerState<DesktopConversationView> createState() => _DesktopConversationViewState();
}

class _DesktopConversationViewState extends ConsumerState<DesktopConversationView> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _typingTimer;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onTextChanged(String text) {
    if (widget.selectedItem == null) return;
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final repo = ref.read(conversationRepositoryProvider);
    
    repo.updateTypingState(widget.selectedItem!.id, currentUserId);
    
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      repo.updateTypingState(widget.selectedItem!.id, null);
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.selectedItem == null) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final repo = ref.read(messageRepositoryProvider);

    final msg = InboxMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Temp ID until server overrides, or just use a generated one
      conversationId: widget.selectedItem!.id,
      senderId: currentUserId,
      content: text,
      status: MessageStatus.sending,
      timestamp: DateTime.now(),
    );

    repo.sendMessage(msg);
    _messageController.clear();
    
    // Clear typing state
    ref.read(conversationRepositoryProvider).updateTypingState(widget.selectedItem!.id, null);
    _typingTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedItem == null) {
      return Container(
        color: inboxBlack,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.forum_outlined, size: 64, color: inboxWhite.withValues(alpha: 0.2)),
              const SizedBox(height: 16),
              Text('Select a conversation', style: AppTypography.pageTitle(inboxWhite.withValues(alpha: 0.5))),
            ],
          ),
        ),
      );
    }

    final conversation = widget.selectedItem!;
    final messagesAsync = ref.watch(conversationMessagesProvider(conversation.id));
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    // Mark as read if there are unread messages and we are currently viewing it
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (conversation.unreadCount > 0) {
        ref.read(conversationRepositoryProvider).markAsRead(conversation.id);
      }
    });

    return Container(
      color: inboxBlack,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: inboxOutline)),
            ),
            child: Row(
              children: [
                OnerovaAvatar(text: conversation.participants.isNotEmpty ? 'U' : '?', size: 40, backgroundColor: inboxSurface),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Conversation', style: AppTypography.sectionTitle(inboxWhite).copyWith(fontWeight: FontWeight.w700)),
                      if (conversation.typingState != null && conversation.typingState != currentUserId)
                        Text('Typing...', style: AppTypography.caption(inboxRed))
                      else
                        Text(timeago.format(conversation.updatedAt), style: AppTypography.caption(inboxWhite.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                // Call Actions
                IconButton(icon: const Icon(Icons.call_outlined, color: inboxWhite), onPressed: () {}),
                IconButton(icon: const Icon(Icons.videocam_outlined, color: inboxWhite), onPressed: () {}),
                IconButton(icon: const Icon(Icons.more_vert, color: inboxWhite), onPressed: () {}),
              ],
            ),
          ),
          
          // Conversation Body
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: AnimatedLoadingIndicator(color: inboxRed)),
              error: (err, _) => Center(child: Text('Error: $err', style: AppTypography.body(inboxRed))),
              data: (messages) {
                if (messages.isEmpty) {
                  return Center(
                    child: Text('No messages yet.', style: AppTypography.body(inboxWhite.withValues(alpha: 0.5))),
                  );
                }
                
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Show latest at bottom
                  padding: const EdgeInsets.all(24),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == currentUserId;
                    
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        constraints: const BoxConstraints(maxWidth: 600),
                        decoration: BoxDecoration(
                          color: isMe ? inboxRed : inboxSurface,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                            bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                          ),
                          border: Border.all(color: isMe ? Colors.transparent : inboxOutline),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              msg.content, 
                              style: AppTypography.body(isMe ? inboxWhite : inboxWhite),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  timeago.format(msg.timestamp, locale: 'en_short'),
                                  style: AppTypography.caption(inboxWhite.withValues(alpha: 0.5)).copyWith(fontSize: 10),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    msg.status == MessageStatus.read ? Icons.done_all :
                                    msg.status == MessageStatus.delivered ? Icons.done_all :
                                    msg.status == MessageStatus.sent ? Icons.done :
                                    Icons.access_time,
                                    size: 12,
                                    color: msg.status == MessageStatus.read ? Colors.blue : inboxWhite.withValues(alpha: 0.5),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // Input area
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: inboxOutline)),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.add, color: inboxWhite), onPressed: () {}),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: inboxSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: inboxOutline),
                    ),
                    child: TextField(
                      controller: _messageController,
                      onChanged: _onTextChanged,
                      onSubmitted: (_) => _sendMessage(),
                      style: AppTypography.body(inboxWhite),
                      decoration: InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: AppTypography.body(inboxWhite.withValues(alpha: 0.5)),
                        border: InputBorder.none,
                        icon: Icon(Icons.attach_file, color: inboxWhite.withValues(alpha: 0.5), size: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  decoration: const BoxDecoration(
                    color: inboxRed,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: inboxWhite),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DesktopInfoPanel extends StatelessWidget {
  final Conversation? selectedItem;

  const DesktopInfoPanel({super.key, this.selectedItem});

  @override
  Widget build(BuildContext context) {
    if (selectedItem == null) {
      return Container(
        width: 320,
        decoration: const BoxDecoration(
          color: inboxBlack,
          border: Border(left: BorderSide(color: inboxOutline)),
        ),
      );
    }

    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: inboxBlack,
        border: Border(left: BorderSide(color: inboxOutline)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Column(
              children: [
                OnerovaAvatar(text: 'U', size: 96, backgroundColor: inboxSurface),
                const SizedBox(height: 16),
                Text('Conversation details', style: AppTypography.pageTitle(inboxWhite).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: inboxRed.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(selectedItem!.channel.name.toUpperCase(), style: AppTypography.caption(inboxRed).copyWith(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Text('AI Settings', style: AppTypography.sectionTitle(inboxWhite).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.auto_awesome, 'AI Policy', selectedItem!.aiAccessMode.name, inboxWhite.withValues(alpha: 0.6)),
          _buildInfoRow(Icons.shield_outlined, 'Privacy Policy', selectedItem!.privacyMode.name, inboxWhite),
          
          const SizedBox(height: 24),
          Text('Contact Details', style: AppTypography.sectionTitle(inboxWhite).copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.phone_outlined, 'Phone', '+1 234 567 8900', inboxWhite),
          _buildInfoRow(Icons.email_outlined, 'Email', 'user@example.com', inboxWhite),
          _buildInfoRow(Icons.location_on_outlined, 'Timezone', 'EST', inboxWhite),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Icon(icon, color: inboxWhite.withValues(alpha: 0.5), size: 18),
          const SizedBox(width: 12),
          Text(label, style: AppTypography.body(inboxWhite.withValues(alpha: 0.7))),
          const Spacer(),
          Text(value, style: AppTypography.bodyMedium(color).copyWith(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
