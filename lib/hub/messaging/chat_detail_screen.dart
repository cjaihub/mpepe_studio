import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/storage_service.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  final String chatId;
  
  const ChatDetailScreen({super.key, required this.chatId});

  @override
  ConsumerState<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  bool _isTyping = false;
  bool _isRecordingVoice = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _showAttachments = false;
  MessageModel? _replyingTo;
  
  late AnimationController _attachmentAnimController;
  late Animation<double> _attachmentAnimation;

  @override
  void initState() {
    super.initState();
    _attachmentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _attachmentAnimation = CurvedAnimation(
      parent: _attachmentAnimController,
      curve: Curves.easeOutBack,
    );

    _messageController.addListener(() {
      final isTyping = _messageController.text.trim().isNotEmpty;
      if (isTyping != _isTyping) {
        setState(() {
          _isTyping = isTyping;
          if (_showAttachments && isTyping) {
            _toggleAttachments(); // hide attachments when typing starts
          }
        });
        
        // Report typing status to backend
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
        if (currentUserId != null) {
          ref.read(messagingRepositoryProvider).setTypingStatus(widget.chatId, currentUserId, isTyping);
        }
      }
    });
  }

  void _toggleAttachments() {
    setState(() {
      _showAttachments = !_showAttachments;
      if (_showAttachments) {
        FocusScope.of(context).unfocus(); // hide keyboard
        _attachmentAnimController.forward();
      } else {
        _attachmentAnimController.reverse();
      }
    });
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    ref.read(messagingRepositoryProvider).sendMessage(widget.chatId, currentUserId, text, replyToMessageId: _replyingTo?.id);
    ref.read(messagingRepositoryProvider).setTypingStatus(widget.chatId, currentUserId, false); // clear typing
    _messageController.clear();
    setState(() {
      _replyingTo = null;
    });
  }
  
  Widget _buildMediaAttachment(MessageModel message) {
    if (message.mediaType == 'image') {
      return Container(
        margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        constraints: const BoxConstraints(maxHeight: 250, maxWidth: 250),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          image: DecorationImage(
            image: NetworkImage(message.mediaUrl!),
            fit: BoxFit.cover,
          ),
        ),
      );
    } else if (message.mediaType == 'document') {
      return Container(
        margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                message.fileName ?? 'Document',
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    } else if (message.mediaType == 'audio') {
      return Container(
        margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_arrow, color: Colors.white),
            const SizedBox(width: 8),
            // Mock waveform or duration
            Container(
              height: 20,
              width: 100,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(width: 8),
            const Text('0:00', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildLinkPreview(String text) {
    final RegExp urlRegExp = RegExp(
      r"(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+",
      caseSensitive: false,
    );
    final match = urlRegExp.firstMatch(text);
    if (match != null) {
      String url = text.substring(match.start, match.end);
      if (!url.startsWith('http')) {
        url = 'https://$url';
      }
      return Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(maxWidth: 250),
        child: AnyLinkPreview(
          link: url,
          displayDirection: UIDirection.uiDirectionVertical,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          bodyStyle: const TextStyle(color: Colors.white70, fontSize: 12),
          backgroundColor: Colors.black.withOpacity(0.2),
          borderRadius: 8,
          removeElevation: true,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  void _showActionMenu(MessageModel message, bool isMe) {
    FocusScope.of(context).unfocus();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reactions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['👍', '❤️', '😂', '😮', '😢'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                      if (currentUserId != null) {
                        ref.read(messagingRepositoryProvider).addReaction(widget.chatId, message.id, currentUserId, emoji);
                      }
                      Navigator.pop(context);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 32)),
                  ).animate().scale(duration: 200.ms);
                }).toList(),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.reply, color: Colors.white),
                title: const Text('Reply', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  setState(() {
                    _replyingTo = message;
                  });
                  FocusScope.of(context).requestFocus();
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy, color: Colors.white),
                title: const Text('Copy', style: TextStyle(color: Colors.white)),
                onTap: () {
                  // copy to clipboard...
                  Navigator.pop(context);
                },
              ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.redAccent),
                  title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    // delete message...
                    Navigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature coming soon!')));
    if (_showAttachments) _toggleAttachments();
  }
  
  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      _uploadFileAndSend(File(pickedFile.path), 'image', pickedFile.name);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.pickFiles();
    if (result.isNotEmpty && result.first.path != null) {
      _uploadFileAndSend(File(result.first.path!), 'document', result.first.name);
    }
  }
  
  Future<void> _uploadFileAndSend(File file, String type, String fileName) async {
    if (_showAttachments) _toggleAttachments();
    
    // Show loading
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploading $type...')));
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final repo = ref.read(messagingRepositoryProvider);
    final storage = ref.read(storageServiceProvider);
    
    final path = 'chats/${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final downloadUrl = await storage.uploadFile(file, path);
    
    if (downloadUrl != null) {
      repo.sendMessage(
        widget.chatId, 
        currentUserId, 
        '', // Empty text for just media, or 'Sent an attachment'
        mediaUrl: downloadUrl,
        mediaType: type,
        fileName: fileName,
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Upload failed')));
    }
  }

  Future<void> _toggleRecording() async {
    if (_isRecordingVoice) {
      // Stop recording
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecordingVoice = false;
      });
      if (path != null) {
        _uploadFileAndSend(File(path), 'audio', 'voice_note.m4a');
      }
    } else {
      // Start recording
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _audioRecorder.start(const RecordConfig(), path: filePath);
        setState(() {
          _isRecordingVoice = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _audioRecorder.dispose();
    _attachmentAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));

    // Mark as read when opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messagingRepositoryProvider).markMessagesAsRead(widget.chatId, currentUserId);
    });

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: _buildAppBar(currentUserId),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                FocusScope.of(context).unfocus();
                if (_showAttachments) _toggleAttachments();
              },
              child: _buildMessagesList(messagesAsync, currentUserId),
            ),
          ),
          
          // Typing Indicator from others
          _buildTypingIndicator(currentUserId),
          
          // Input Area
          _buildInputArea(),
          
          // Attachment Drawer
          SizeTransition(
            sizeFactor: _attachmentAnimation,
            child: _buildAttachmentDrawer(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(String currentUserId) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('chats').doc(widget.chatId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) return const SizedBox.shrink();
        
        final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
        final typingUsers = List<String>.from(data['typingUsers'] ?? []);
        final otherTyping = typingUsers.where((id) => id != currentUserId).toList();
        
        if (otherTyping.isEmpty) return const SizedBox.shrink();
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Someone is typing',
                style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                height: 10,
                child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white54).animate().scale(),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(String currentUserId) {
    return AppBar(
      backgroundColor: AppColors.darkBackground,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 0,
      title: FutureBuilder<ChatModel?>(
        future: ref.read(messagingRepositoryProvider).getChat(widget.chatId),
        builder: (context, chatSnapshot) {
          final chat = chatSnapshot.data;
          final otherUserId = chat?.participants.firstWhere(
            (id) => id != currentUserId,
            orElse: () => '',
          );

          if (otherUserId == null || otherUserId.isEmpty) {
            return const Text('Chat', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white));
          }

          return FutureBuilder<AppUser?>(
            future: ref.read(userProvider.notifier).getUser(otherUserId),
            builder: (context, userSnapshot) {
              final user = userSnapshot.data;
              final name = user?.fullName ?? '...';
              final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

              return Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.darkSurfaceHighlight,
                    child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent[400],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('Online', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.videocam_rounded, color: Colors.white),
          onPressed: () => _showComingSoon('Video calling'),
        ),
        IconButton(
          icon: const Icon(Icons.call_rounded, color: Colors.white),
          onPressed: () => _showComingSoon('Voice calling'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMessagesList(AsyncValue<List<MessageModel>> messagesAsync, String currentUserId) {
    return messagesAsync.when(
      data: (messages) {
        if (messages.isEmpty) {
          return const Center(child: Text('Say hello!', style: TextStyle(color: Colors.white54)));
        }
        
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.only(bottom: 16),
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == currentUserId;
            
            // Format time
            final timeStr = "${message.timestamp.toDate().hour.toString().padLeft(2, '0')}:${message.timestamp.toDate().minute.toString().padLeft(2, '0')}";
            
            // Find replied message if any
            final MessageModel? repliedMsg = message.replyToMessageId != null
                ? messages.where((m) => m.id == message.replyToMessageId).firstOrNull
                : null;
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: GestureDetector(
                onLongPress: () => _showActionMenu(message, isMe),
                child: Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                  if (!isMe) ...[
                    const CircleAvatar(
                      radius: 12,
                      backgroundColor: AppColors.darkSurfaceHighlight,
                      child: Icon(Icons.person, color: Colors.white54, size: 16),
                    ),
                    const SizedBox(width: 8),
                  ],
                  
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe ? AppColors.mpepeMaroon : AppColors.darkSurface,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(20),
                          topRight: const Radius.circular(20),
                          bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                          bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                        children: [
                          if (repliedMsg != null)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(left: BorderSide(color: isMe ? Colors.white : AppColors.mpepeMaroon, width: 4)),
                              ),
                              child: Text(
                                repliedMsg.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ),
                          if (message.mediaUrl != null && message.mediaType != null)
                            _buildMediaAttachment(message),
                          if (message.text.isNotEmpty)
                            Text(
                              message.text,
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          _buildLinkPreview(message.text),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(timeStr, style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 10)),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.done_all, 
                                  size: 14, 
                                  color: message.readBy.isNotEmpty ? Colors.blueAccent : Colors.white.withOpacity(0.6)
                                ),
                              ]
                            ],
                          ),
                          if (message.reactions != null && message.reactions!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: Wrap(
                                spacing: 4,
                                children: message.reactions!.entries.map((e) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(e.value, style: const TextStyle(fontSize: 12)),
                                  );
                                }).toList(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  if (isMe) const SizedBox(width: 20),
                ],
              ),
            ),
          ).animate().fade().slideY(begin: 0.1, end: 0);
        },
      );
      },
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.mpepeMaroon)),
      error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        border: Border(top: BorderSide(color: Colors.white12, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8, left: 40, right: 40),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.darkSurfaceHighlight,
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(left: BorderSide(color: AppColors.mpepeMaroon, width: 4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Replying to message', style: TextStyle(color: AppColors.mpepeMaroon, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _replyingTo!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                      onPressed: () {
                        setState(() {
                          _replyingTo = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
            GestureDetector(
              onTap: _toggleAttachments,
              child: AnimatedRotation(
                turns: _showAttachments ? 0.125 : 0, // 45 degree rotation
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _showAttachments ? AppColors.mpepeMaroon : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: _showAttachments ? Colors.white : Colors.white54, size: 28),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.darkBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _messageController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _isTyping
                ? GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(color: AppColors.mpepeMaroon, shape: BoxShape.circle),
                      child: const Icon(Icons.send, color: Colors.white, size: 20),
                    ).animate().scale(duration: 200.ms),
                  )
                : GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _isRecordingVoice ? Colors.redAccent : AppColors.darkSurfaceHighlight, 
                        shape: BoxShape.circle
                      ),
                      child: Icon(
                        _isRecordingVoice ? Icons.stop : Icons.mic, 
                        color: Colors.white, 
                        size: 20
                      ),
                    ).animate().scale(duration: 200.ms),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentDrawer() {
    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.only(bottom: 32, top: 16, left: 24, right: 24),
      child: Wrap(
        spacing: 32,
        runSpacing: 24,
        alignment: WrapAlignment.center,
        children: [
          _buildAttachOption(Icons.image, 'Gallery', Colors.purpleAccent, onTap: () => _pickImage(ImageSource.gallery)),
          _buildAttachOption(Icons.camera_alt, 'Camera', Colors.pinkAccent, onTap: () => _pickImage(ImageSource.camera)),
          _buildAttachOption(Icons.insert_drive_file, 'Document', Colors.indigoAccent, onTap: _pickDocument),
          _buildAttachOption(Icons.headphones, 'Audio', Colors.orangeAccent),
          _buildAttachOption(Icons.location_on, 'Location', Colors.greenAccent),
          _buildAttachOption(Icons.person, 'Contact', Colors.blueAccent),
        ],
      ),
    );
  }

  Widget _buildAttachOption(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap ?? () => _showComingSoon(label),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
