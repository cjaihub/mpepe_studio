import 'package:flutter/material.dart';
import '../calling/call_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/unified_inbox_provider.dart';
import '../../backend/messaging_repository.dart';
import '../providers/selected_inbox_item_provider.dart';

import '../../ai_messaging/widgets/smart_reply_chips.dart';
import '../../ai_messaging/widgets/ai_composer_menu.dart';
import '../../backend/inbox/models/attachment_model.dart';
import '../../social_hub/components/attachment_bubble.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../../backend/attachment_picker_service.dart';
import '../../backend/storage_service.dart';
import '../../social_hub/components/attachment_picker_sheet.dart';
import '../../social_hub/components/voice_recorder_button.dart';
import '../../features/omni_command/omni_command_sheet.dart';
import '../../backend/ai_agents/omni_command/omni_context_resolver.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class ChatViewPanel extends ConsumerStatefulWidget {
  const ChatViewPanel({super.key});

  @override
  ConsumerState<ChatViewPanel> createState() => _ChatViewPanelState();
}

class _ChatViewPanelState extends ConsumerState<ChatViewPanel> {
  final TextEditingController _messageController = TextEditingController();
  final List<Attachment> _pendingAttachments = [];
  final Map<String, double> _uploadProgress = {};
  final Map<String, UploadTask> _activeUploads = {};

  void _showAttachmentPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => AttachmentPickerSheet(
        onPickImage: () => _handlePick(AttachmentType.image),
        onPickVideo: () => _handlePick(AttachmentType.video),
        onPickDocument: () => _handlePick(AttachmentType.document),
        onPickLocation: () => _handlePick(AttachmentType.location),
      ),
    );
  }

  Future<void> _handlePick(AttachmentType type) async {
    final picker = ref.read(attachmentPickerServiceProvider);
    File? file;
    if (type == AttachmentType.image) {
      file = await picker.pickImage(fromCamera: false);
    } else if (type == AttachmentType.video) {
      file = await picker.pickVideo(fromCamera: false);
    } else if (type == AttachmentType.document) {
      file = await picker.pickDocument();
    } else {
      // Locations etc.
    }
    
    if (file != null) {
      _uploadFile(file, type);
    }
  }

  void _uploadFile(File file, AttachmentType type) {
    final storage = ref.read(storageServiceProvider);
    final fileName = file.path.split('/').last;
    final attId = const Uuid().v4();
    final att = Attachment(
      id: attId,
      type: type,
      storagePath: file.path,
      downloadUrl: file.path,
      fileSize: 0,
      mimeType: 'application/octet-stream',
      fileName: fileName,
      status: AttachmentStatus.uploading,
    );
    
    setState(() {
      _pendingAttachments.add(att);
    });

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final task = storage.uploadFileWithProgress(file, 'chats/$currentUserId/$attId/$fileName');
    
    _activeUploads[attId] = task;

    task.snapshotEvents.listen((snapshot) {
      if (snapshot.state == TaskState.success) {
        snapshot.ref.getDownloadURL().then((url) {
          setState(() {
            final index = _pendingAttachments.indexWhere((a) => a.id == attId);
            if (index != -1) {
              _pendingAttachments[index] = _pendingAttachments[index].copyWith(
                status: AttachmentStatus.ready,
                downloadUrl: url,
              );
            }
          });
        });
      } else if (snapshot.state == TaskState.running) {
        setState(() {
          _uploadProgress[attId] = snapshot.bytesTransferred / snapshot.totalBytes;
        });
      } else if (snapshot.state == TaskState.error) {
        setState(() {
          final index = _pendingAttachments.indexWhere((a) => a.id == attId);
          if (index != -1) {
            _pendingAttachments[index] = _pendingAttachments[index].copyWith(status: AttachmentStatus.failed);
          }
        });
      }
    });
  }

  void _removeAttachment(String id) {
    final task = _activeUploads[id];
    if (task != null) {
      task.cancel();
      _activeUploads.remove(id);
    }
    setState(() {
      _pendingAttachments.removeWhere((a) => a.id == id);
      _uploadProgress.remove(id);
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = ref.watch(selectedInboxItemProvider);

    if (selectedItem == null) {
      return Container(
        color: AppColors.darkBackground,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox, size: 64, color: AppColors.outline),
              const SizedBox(height: 16),
              Text('No conversation selected', style: AppTypography.pageTitle(AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: AppColors.darkBackground,
      child: Column(
        children: [
          // 1. Header
          _buildHeader(selectedItem),
          
          // 2. Chat Area
          Expanded(
            child: _buildChatArea(context, ref, selectedItem),
          ),
          
          // 3. Input Area
          _buildInputArea(selectedItem),
        ],
      ),
    );
  }

  Widget _buildHeader(UnifiedItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.darkSurface,
            backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
            radius: 20,
            child: item.senderAvatarUrl.isEmpty 
              ? Text(item.senderName.isNotEmpty ? item.senderName[0].toUpperCase() : '?', style: AppTypography.bodyMedium(AppColors.brandWhite))
              : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.senderName, style: AppTypography.sectionTitle(AppColors.textPrimary)),
                Row(
                  children: [
                    Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.brandWhite, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('Platform: ${item.platform.name}', style: AppTypography.small(AppColors.textSecondary)),
                    if (item.handledByAI) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.brandBlue),
                        ),
                        child: Text('AI Handled', style: AppTypography.caption(AppColors.brandBlue).copyWith(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          OmniCommandButton(
            omniContext: OmniContext(
              sessionId: 'chat_session',
              conversationId: item.id,
              platformId: item.platform.name,
              userId: 'local_user', // Provide basic dummy to satisfy requirements
            ),
          ),
          IconButton(
            icon: const Icon(Icons.phone, color: AppColors.textSecondary),
            onPressed: () async {
              if (item.platform == SocialPlatform.system) {
                final chat = await ref.read(messagingRepositoryProvider).getChat(item.id);
                final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                final otherUserId = chat?.participants.firstWhere(
                  (id) => id != currentUserId,
                  orElse: () => '',
                );
                if (otherUserId != null && otherUserId.isNotEmpty) {
                  if (!context.mounted) return;
                  await startOneovaCall(context, ref, targetUserIds: [otherUserId], isVideo: false, chatId: chat?.id);
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.textSecondary),
            onPressed: () async {
              if (item.platform == SocialPlatform.system) {
                final chat = await ref.read(messagingRepositoryProvider).getChat(item.id);
                final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                final otherUserId = chat?.participants.firstWhere(
                  (id) => id != currentUserId,
                  orElse: () => '',
                );
                if (otherUserId != null && otherUserId.isNotEmpty) {
                  if (!context.mounted) return;
                  await startOneovaCall(context, ref, targetUserIds: [otherUserId], isVideo: true, chatId: chat?.id);
                }
              }
            },
          ),
          IconButton(icon: const Icon(Icons.more_vert, color: AppColors.textSecondary), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildChatArea(BuildContext context, WidgetRef ref, UnifiedItem item) {
    if (item.platform != SocialPlatform.system) {
      // Non-system chat (e.g. social comment) where we don't have full thread in real-time
      return ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Text(_formatDate(item.timestamp), style: AppTypography.small(AppColors.textMuted).copyWith(fontWeight: FontWeight.bold)),
            ),
          ),
          _buildMessage(item.content, _formatTime(item.timestamp), false),
        ],
      );
    }

    final messagesAsync = ref.watch(chatMessagesProvider(item.id));
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;

    return messagesAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return Center(child: Text('Start a conversation', style: AppTypography.body(AppColors.textMuted)));
        }
        
        // Reverse because list view might need to build bottom-up or just map it 
        // Actually, stream is usually orderBy descending, so we need reverse: true in ListView to show at bottom
        return ListView.builder(
          padding: const EdgeInsets.all(24.0),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final msg = messages[index];
            final timeStr = _formatTime(msg.timestamp.toDate());
            
            Attachment? attachment;
            if (msg.mediaUrl != null && msg.mediaType != null) {
              AttachmentType t = AttachmentType.image;
              if (msg.mediaType == 'video') t = AttachmentType.video;
              if (msg.mediaType == 'document') t = AttachmentType.document;
              if (msg.mediaType == 'location') t = AttachmentType.location;
              attachment = Attachment(
                id: const Uuid().v4(),
                type: t,
                storagePath: '',
                downloadUrl: msg.mediaUrl!,
                fileSize: 0,
                mimeType: msg.mimeType ?? 'application/octet-stream',
                fileName: msg.fileName ?? 'attachment',
                status: AttachmentStatus.ready,
              );
            }

            if (msg.senderId == currentUserUid) {
              return _buildMessage(msg.text, timeStr, true, attachment: attachment);
            } else {
              return _buildMessage(msg.text, timeStr, false, attachment: attachment);
            }
          },
        );
      },
      loading: () => const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      error: (err, stack) => Center(child: Text('Error loading messages', style: AppTypography.body(AppColors.brandBlue))),
    );
  }

  Widget _buildMessage(String text, String time, bool isOutgoing, {Attachment? attachment}) {
    return Align(
      alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 450),
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOutgoing ? AppColors.brandBlue : AppColors.darkSurface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: isOutgoing ? const Radius.circular(16) : const Radius.circular(4),
            bottomRight: isOutgoing ? const Radius.circular(4) : const Radius.circular(16),
          ),
          border: isOutgoing ? null : Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (attachment != null) ...[
              SizedBox(
                width: 300,
                child: AttachmentBubble(attachment: attachment, isMine: isOutgoing),
              ),
              const SizedBox(height: 8),
            ],
            if (text.isNotEmpty)
              Text(
                text,
                style: AppTypography.body(isOutgoing ? AppColors.brandWhite : AppColors.textPrimary),
              ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  time,
                  style: AppTypography.caption(isOutgoing ? AppColors.brandWhite.withValues(alpha: 0.7) : AppColors.textMuted),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.done_all, color: AppColors.brandWhite.withValues(alpha: 0.7), size: 14),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildInputArea(UnifiedItem selectedItem) {
    // Get last message text from the current state (if we want to use it for smart replies)
    // Actually, we could just pass selectedItem.content since it is the latest message content
    return Container(
      padding: const EdgeInsets.all(24.0),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.outline, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Smart Replies
          SmartReplyChips(
            conversationId: selectedItem.id,
            lastMessageText: selectedItem.content,
            onSelectReply: (reply) {
              _messageController.text = reply;
            },
          ),
          const SizedBox(height: 12),
          if (_pendingAttachments.isNotEmpty)
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _pendingAttachments.length,
                itemBuilder: (context, index) {
                  final att = _pendingAttachments[index];
                  final progress = _uploadProgress[att.id] ?? 0.0;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0, bottom: 12.0),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: 80,
                          child: AttachmentBubble(attachment: att, isMine: true),
                        ),
                        if (att.status == AttachmentStatus.uploading)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black54,
                              child: Center(
                                child: AnimatedLoadingIndicator(value: progress, color: AppColors.brandBlue),
                              ),
                            ),
                          ),
                        Positioned(
                          top: -4,
                          right: -4,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.white, size: 20),
                            onPressed: () => _removeAttachment(att.id),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Row(
            children: [
              IconButton(icon: const Icon(Icons.attach_file, color: AppColors.textSecondary), onPressed: _showAttachmentPicker),
              IconButton(icon: const Icon(Icons.emoji_emotions_outlined, color: AppColors.textSecondary), onPressed: () {}),
              IconButton(icon: const Icon(Icons.image_outlined, color: AppColors.textSecondary), onPressed: () => _handlePick(AttachmentType.image)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: AppTypography.body(AppColors.textMuted),
                      border: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
                        onPressed: () {
                          if (_messageController.text.trim().isEmpty) return;
                          AiComposerMenu.show(
                            context,
                            conversationId: selectedItem.id,
                            currentText: _messageController.text,
                            onSuggestionAccepted: (text) {
                              _messageController.text = text;
                            },
                          );
                        },
                      ),
                    ),
                    style: AppTypography.body(AppColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              VoiceRecorderButton(
                onRecordingComplete: (file, duration) {
                  _uploadFile(file, AttachmentType.voice);
                },
              ),
              const SizedBox(width: 12),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.brandBlue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send, color: AppColors.brandWhite),
                  onPressed: () {
                    final bool hasUploading = _pendingAttachments.any((a) => a.status == AttachmentStatus.uploading);
                    if (hasUploading) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please wait for attachments to finish uploading')),
                      );
                      return;
                    }

                    if (_messageController.text.trim().isNotEmpty || _pendingAttachments.isNotEmpty) {
                      final text = _messageController.text.trim();
                      final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
                      final repo = ref.read(messagingRepositoryProvider);

                      if (_pendingAttachments.isEmpty) {
                        if (text.isNotEmpty) {
                          repo.sendMessage(selectedItem.id, currentUserId, text);
                        }
                      } else {
                        bool isFirst = true;
                        for (var att in _pendingAttachments) {
                          if (att.status == AttachmentStatus.ready) {
                            repo.sendMessage(
                              selectedItem.id,
                              currentUserId,
                              isFirst ? text : '',
                              mediaUrl: att.downloadUrl,
                              mediaType: att.type.name,
                              fileName: att.fileName,
                              mimeType: att.mimeType,
                            );
                            isFirst = false;
                          }
                        }
                        if (isFirst && text.isNotEmpty) {
                          repo.sendMessage(selectedItem.id, currentUserId, text);
                        }
                      }

                      _messageController.clear();
                      setState(() {
                        _pendingAttachments.clear();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Quick Replies', style: AppTypography.small(AppColors.textSecondary).copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              _buildQuickReplyChip('Course Info'),
              const SizedBox(width: 8),
              _buildQuickReplyChip('Past Papers'),
              const SizedBox(width: 8),
              _buildQuickReplyChip('Payment'),
              const SizedBox(width: 8),
              _buildQuickReplyChip('Live Classes'),
              const SizedBox(width: 8),
              _buildQuickReplyChip('Support'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickReplyChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Text(label, style: AppTypography.caption(AppColors.textSecondary)),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'Today';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
