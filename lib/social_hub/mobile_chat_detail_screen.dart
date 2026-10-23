import 'package:flutter/material.dart';
import '../inbox/calling/call_launcher.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../backend/unified_inbox_provider.dart';
import '../shared/theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../ai_messaging/widgets/smart_reply_chips.dart';
import '../ai_messaging/widgets/ai_composer_menu.dart';
import '../backend/messaging_repository.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/inbox/models/attachment_model.dart';
import '../backend/attachment_picker_service.dart';
import 'package:flutter/services.dart';
import '../backend/security/e2e_encryption_service.dart';
import '../widgets/oneova_assistant_overlay.dart';
import 'components/attachment_picker_sheet.dart';
import 'components/voice_recorder_button.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
class MobileChatDetailScreen extends ConsumerStatefulWidget {
  final String itemId;

  const MobileChatDetailScreen({super.key, required this.itemId});

  @override
  ConsumerState<MobileChatDetailScreen> createState() => _MobileChatDetailScreenState();
}

class _MobileChatDetailScreenState extends ConsumerState<MobileChatDetailScreen> {
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

  void _openOvaAssistantOverlay() {
    HapticFeedback.lightImpact();
    OneOvaAssistantOverlay.show(
      context,
      userId: FirebaseAuth.instance.currentUser?.uid,
      screenContextLabel: 'Chat Screen (${widget.itemId})',
      initialPrompt: _messageController.text.isNotEmpty ? _messageController.text : null,
      activeChatId: widget.itemId,
      onInsertIntoChat: (text) {
        setState(() {
          _messageController.text = text;
        });
      },
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
    }
    
    if (file != null) {
      _uploadFile(file, type);
    }
  }

  void _uploadFile(File file, AttachmentType type) async {
    final e2e = ref.read(e2eEncryptionServiceProvider);
    final ext = file.path.split('.').last;
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    
    setState(() {
      _pendingAttachments.add(Attachment(
        id: tempId,
        fileName: file.path.split('/').last,
        fileSize: file.lengthSync(),
        mimeType: 'application/$ext',
        type: type,
        storagePath: '',
        status: AttachmentStatus.uploading,
      ));
      _uploadProgress[tempId] = 0.0;
    });

    final symmetricKey = await e2e.generateSymmetricKey();
    final exportedKey = await e2e.exportSymmetricKey(symmetricKey);
    final fileBytes = await file.readAsBytes();
    final encryptedBytes = await e2e.encryptBytes(fileBytes, symmetricKey);

    final storageRef = FirebaseStorage.instance.ref().child('chats/${widget.itemId}/attachments/$tempId.$ext');
    final task = storageRef.putData(Uint8List.fromList(encryptedBytes));
    _activeUploads[tempId] = task;

    task.snapshotEvents.listen((snapshot) {
      setState(() {
        _uploadProgress[tempId] = snapshot.bytesTransferred / snapshot.totalBytes;
      });
    }, onError: (e) {
      setState(() {
        _uploadProgress.remove(tempId);
        _activeUploads.remove(tempId);
        final idx = _pendingAttachments.indexWhere((a) => a.id == tempId);
        if (idx != -1) {
          _pendingAttachments[idx] = _pendingAttachments[idx].copyWith(status: AttachmentStatus.failed);
        }
      });
    });

    task.then((snapshot) async {
      final downloadUrl = await snapshot.ref.getDownloadURL();
      final path = snapshot.ref.fullPath;
      
      if (!mounted) return;
      setState(() {
        _uploadProgress.remove(tempId);
        _activeUploads.remove(tempId);
        final idx = _pendingAttachments.indexWhere((a) => a.id == tempId);
        if (idx != -1) {
          _pendingAttachments[idx] = _pendingAttachments[idx].copyWith(
            status: AttachmentStatus.ready,
            downloadUrl: downloadUrl,
            storagePath: path,
            encryptionKey: exportedKey,
          );
        }
      });
    });
  }
  IconData _getPlatformIcon(SocialPlatform platform) {
    switch (platform) {
      case SocialPlatform.youtube:
        return Icons.play_circle_fill;
      case SocialPlatform.instagram:
        return Icons.camera_alt;
      case SocialPlatform.meta:
      case SocialPlatform.facebook:
        return Icons.facebook;
      case SocialPlatform.messenger:
        return Icons.message;
      case SocialPlatform.whatsapp:
        return Icons.chat_bubble;
      case SocialPlatform.telegram:
        return Icons.send;
      case SocialPlatform.email:
        return Icons.email_outlined;
      case SocialPlatform.tiktok:
        return Icons.music_note;
      case SocialPlatform.system:
        return Icons.info;
      case SocialPlatform.sms:
        return Icons.sms;
      case SocialPlatform.website:
        return Icons.language;
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inboxItems = ref.watch(unifiedInboxProvider);
    final item = inboxItems.firstWhere(
      (i) => i.id == widget.itemId,
      orElse: () => UnifiedItem(
        id: widget.itemId,
        platform: SocialPlatform.system,
        type: UnifiedItemType.message,
        senderName: 'Unknown',
        senderAvatarUrl: '',
        content: '',
        timestamp: DateTime.now(),
      ),
    );

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.textPrimary, size: 20),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
              backgroundImage: item.senderAvatarUrl.isNotEmpty ? NetworkImage(item.senderAvatarUrl) : null,
              child: item.senderAvatarUrl.isEmpty ? const Icon(Icons.person, color: AppColors.brandBlue, size: 20) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.senderName,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Icon(_getPlatformIcon(item.platform), size: 12, color: context.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        "Online", // Simplified placeholder for presence
                        style: TextStyle(fontSize: 12, color: context.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
            onPressed: () => context.push('/gemini_live'),
          ),
          IconButton(
            icon: Icon(Icons.videocam, color: context.textPrimary),
            onPressed: () async {
              final items = ref.read(unifiedInboxProvider);
              final itm = items.where((i) => i.id == widget.itemId).firstOrNull;
              if (itm != null && itm.platform == SocialPlatform.system) {
                final chat = await ref.read(messagingRepositoryProvider).getChat(itm.id);
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
          IconButton(
            icon: Icon(Icons.call_rounded, color: context.textPrimary),
            onPressed: () async {
              final items = ref.read(unifiedInboxProvider);
              final itm = items.where((i) => i.id == widget.itemId).firstOrNull;
              if (itm != null && itm.platform == SocialPlatform.system) {
                final chat = await ref.read(messagingRepositoryProvider).getChat(itm.id);
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
            icon: Icon(Icons.more_vert, color: context.textPrimary),
            onPressed: () {
              // Action sheet
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Render the initial message
                _buildMessageBubble(item),
              ],
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(UnifiedItem item) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16, right: 40),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.content,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 15,
                height: 1.4,
              ),
            ),
            // NO-OP: UnifiedItem doesn't expose attachments yet. We need to cast back to InboxMessage if we want to show real message attachments, 
            // but for now we'll just handle pending UI above input box. Wait, I should show them here if we have them. 
            // We'll update UnifiedItem.content or wait till we migrate completely. I'll add a check.
            const SizedBox(height: 8),
            Text(
              timeago.format(item.timestamp),
              style: TextStyle(color: context.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // AI Smart Replies
        if (widget.itemId.isNotEmpty)
          Consumer(
            builder: (context, ref, _) {
              final inboxItems = ref.watch(unifiedInboxProvider);
              final item = inboxItems.where((i) => i.id == widget.itemId).firstOrNull;
              if (item == null) return const SizedBox.shrink();
              return SmartReplyChips(
                conversationId: item.id,
                lastMessageText: item.content,
                onSelectReply: (reply) {
                  _messageController.text = reply;
                },
              );
            },
          ),
        Container(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 32), // bottom padding for safe area
          decoration: BoxDecoration(
            color: context.surface,
            border: Border(top: BorderSide(color: context.border, width: 1.0)),
          ),
          child: Column(
            children: [
              _buildPendingAttachments(),
              Row(
                children: [
                  GestureDetector(
                    onTap: _showAttachmentPicker,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: Icon(Icons.add, color: context.textPrimary, size: 20),
                    ),
                  ).animate().scaleXY(begin: 1.0, end: 1.0, curve: Curves.easeInOut),
                  const SizedBox(width: 6),
                  // Dedicated Ova AI & Computer Command button (38px compact with glow)
                  GestureDetector(
                    onTap: _openOvaAssistantOverlay,
                    child: Tooltip(
                      message: 'Ova AI & Computer Command Agent',
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [AppColors.brandBlue, AppColors.brandPink],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.brandBlue.withValues(alpha: 0.35),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                            BoxShadow(
                              color: AppColors.brandPink.withValues(alpha: 0.25),
                              blurRadius: 10,
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.auto_awesome_rounded,
                            color: Colors.white,
                            size: 19,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: context.border, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _messageController,
                        style: TextStyle(color: context.textPrimary, fontSize: 15),
                        decoration: InputDecoration(
                          hintText: 'Message...',
                          hintStyle: TextStyle(color: context.textMuted),
                          border: InputBorder.none,
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
                            onPressed: () {
                              if (_messageController.text.trim().isEmpty) return;
                              AiComposerMenu.show(
                                context,
                                conversationId: widget.itemId,
                                currentText: _messageController.text,
                                onSuggestionAccepted: (text) {
                                  _messageController.text = text;
                                },
                              );
                            },
                          ),
                        ),
                        maxLines: null,
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  VoiceRecorderButton(
                    onRecordingComplete: (file, duration) {
                      _uploadFile(file, AttachmentType.voice);
                    },
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
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
                            repo.sendMessage(widget.itemId, currentUserId, text);
                          }
                        } else {
                          bool isFirst = true;
                          for (var att in _pendingAttachments) {
                            if (att.status == AttachmentStatus.ready) {
                              repo.sendMessage(
                                widget.itemId,
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
                            repo.sendMessage(widget.itemId, currentUserId, text);
                          }
                        }

                        _messageController.clear();
                        setState(() {
                          _pendingAttachments.clear();
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandBlue.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingAttachments() {
    if (_pendingAttachments.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 80,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingAttachments.length,
        itemBuilder: (context, index) {
          final attachment = _pendingAttachments[index];
          final progress = _uploadProgress[attachment.id] ?? 0.0;
          final isUploading = attachment.status == AttachmentStatus.uploading;
          final isFailed = attachment.status == AttachmentStatus.failed;

          return Container(
            width: 80,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isFailed ? Colors.red : context.border, width: 1.0),
            ),
            child: Stack(
              children: [
                Center(
                  child: attachment.type == AttachmentType.image && attachment.downloadUrl != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(attachment.downloadUrl!, fit: BoxFit.cover, width: 80, height: 80),
                        )
                      : Icon(
                          attachment.type == AttachmentType.video ? Icons.videocam : Icons.insert_drive_file_outlined,
                          color: context.textSecondary,
                        ),
                ),
                if (isUploading)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: AnimatedLoadingIndicator(
                          value: progress,
                          color: AppColors.brandBlue,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (isUploading) {
                        _activeUploads[attachment.id]?.cancel();
                      }
                      setState(() {
                        _pendingAttachments.removeAt(index);
                        _uploadProgress.remove(attachment.id);
                        _activeUploads.remove(attachment.id);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.black87,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
