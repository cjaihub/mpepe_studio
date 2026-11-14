import 'package:flutter/material.dart';
import '../../inbox/calling/call_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/inbox/providers/presence_service.dart';
import '../../shared/widgets/live_user_presence_dot.dart';
import '../../backend/messaging_repository.dart';
import 'rooms/rooms_views.dart';
import '../../backend/security/e2e_encryption_service.dart';
import '../../backend/storage_service.dart';
import '../../backend/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/follow_button.dart';
import '../../widgets/oneova_assistant_overlay.dart';
import '../../providers/settings_provider.dart';
import '../../shared/services/oneova_sound_service.dart';
import '../../shared/widgets/advanced_voice_interface.dart';
import '../../shared/widgets/live_recording_waveform.dart';
import '../../shared/widgets/oneova_voice_typing_button.dart';
import 'widgets/chat_emoji_gif_panel.dart';
import 'widgets/chat_location_share.dart';
import 'widgets/chat_media_bubbles.dart';
import 'widgets/peer_encrypted_media.dart';
import '../../ova_assistant/media/ova_chat_suggestion_bar.dart';
import '../../ova_assistant/media/ova_media_brain.dart';
import '../../ova_assistant/media/ova_media_studio.dart';
import 'widgets/video_note_recorder.dart';
import '../../shared/services/draft_store.dart';
import 'dart:async';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chat_assist_service.dart';
import 'widgets/chat_compact_cards.dart';
import 'widgets/chat_background.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../security/widgets/link_safety_gate.dart';
import '../../shared/audio/mic_coordinator.dart';
import '../../shared/widgets/oneova_smart_status_banner.dart';
import '../../shared/language/language_detector.dart';

part 'chat_detail_upgrades.dart';

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
  MicLease? _voiceMicLease;
  MessagingRepository? _messagingRepo;
  bool _showAttachments = false;
  MessageModel? _replyingTo;

  // Chat Wallpaper & Customization State
  String _selectedWallpaperKey = 'default_obsidian';
  double _bubbleFontSize = 13.0;
  String _chatSoundTone = 'default_chime';

  // Advanced Voice Recording & Waveform State
  int _recordingDurationSeconds = 0;
  Timer? _recordingTimer;
  Timer? _amplitudeTimer;
  Timer? _micHoldTimer;

  // Emoji / GIF panel and round video messages
  bool _showEmojiPanel = false;
  bool _videoNoteMode = false;
  VideoNoteSession? _videoSession;
  final FocusNode _composerFocus = FocusNode();
  final List<double> _recordedWaveformSamples = [];
  // Rolling levels for the live strip, plus lock / pause / slide state.
  final List<double> _liveLevels = [];
  bool _voiceLocked = false;
  bool _voicePaused = false;
  Offset _voiceSlide = Offset.zero;
  Offset? _voiceHoldOrigin;
  String? _recordedFilePath;

  // In-Chat History Search
  bool _isSearchingInChat = false;
  final TextEditingController _inChatSearchController = TextEditingController();
  String _inChatSearchQuery = '';

  // E2EE State & In-Memory Decryption Cache
  final Map<String, String> _decryptedCache = {};
  String? _chatPartnerId;
  String? _chatPartnerPublicKey;
  String? _myPublicKey;
  bool _isSharedChat = false;

  /// True when this chat is 1:1 and both sides have published keys, i.e.
  /// text and media are end-to-end encrypted.
  bool get _e2eeActive =>
      !_isSharedChat &&
      (_myPublicKey?.isNotEmpty ?? false) &&
      (_chatPartnerPublicKey?.isNotEmpty ?? false);
  
  late AnimationController _attachmentAnimController;
  late Animation<double> _attachmentAnimation;

  // Scrolling, translations and per-chat AI assist (chat_detail_upgrades.dart)
  final ScrollController _listController = ScrollController();
  bool _bannerCollapsed = true;
  bool _awayFromBottom = false;
  String? _latestSeenId;
  List<MessageModel> _lastMessages = const [];
  final Map<String, ChatTranslation> _translations = {};
  final Set<String> _translating = {};
  final Set<String> _hiddenTranslations = {};
  /// Message id → detected foreign language (null: your language or unsure). On the phone only.
  final Map<String, String?> _foreignLang = {};
  List<String> _aiReplies = const [];
  bool _aiRepliesLoading = false;
  String? _aiRepliesFor;
  bool _aiSummarizing = false;
  final List<MessageModel> _pendingLocalMessages = [];
  String? _uploadingFileName;
  double? _uploadProgress;
  UploadTask? _activeUploadTask;
  StreamSubscription<TaskSnapshot>? _uploadProgressSub;

  void _refresh(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  final Map<String, Future<AppUser?>> _userFutures = {};

  Future<AppUser?> _getUserCached(String uid) {
    return _userFutures.putIfAbsent(uid, () => ref.read(userProvider.notifier).getUser(uid));
  }

  Future<void> _loadChatPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedWallpaper = prefs.getString('chat_wallpaper_${widget.chatId}');
      if (savedWallpaper != null && mounted) {
        setState(() {
          _selectedWallpaperKey = savedWallpaper;
        });
      }
      final savedTextSize = prefs.getDouble('chat_text_size_${widget.chatId}');
      if (savedTextSize != null && mounted) {
        setState(() {
          _bubbleFontSize = savedTextSize;
        });
      }
      final savedSound = prefs.getString('chat_sound_${widget.chatId}');
      if (savedSound != null && mounted) {
        setState(() {
          _chatSoundTone = savedSound;
        });
      }
    } catch (e) {
      debugPrint('Error loading chat wallpaper preference: $e');
    }
  }

  Future<void> _saveTextSizePreference(double size) async {
    setState(() {
      _bubbleFontSize = size;
    });
    HapticFeedback.selectionClick();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('chat_text_size_${widget.chatId}', size);
    } catch (e) {
      debugPrint('Error saving text size preference: $e');
    }
  }

  Future<void> _saveSoundPreference(String tone) async {
    setState(() {
      _chatSoundTone = tone;
    });
    HapticFeedback.selectionClick();
    OneOvaSoundService().playNotificationChime(tone);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('chat_sound_${widget.chatId}', tone);
    } catch (e) {
      debugPrint('Error saving sound preference: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initE2EE();
    _loadChatPreferences();
    _listController.addListener(_onListScroll);
    _attachmentAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _attachmentAnimation = CurvedAnimation(
      parent: _attachmentAnimController,
      curve: Curves.easeOutBack,
    );

    // Restore draft if any exists for this chat
    final savedDraft = DraftStore.instance.getDraft(DraftStore.chatKey(widget.chatId));
    if (savedDraft != null && savedDraft.isNotEmpty) {
      _messageController.text = savedDraft;
      _isTyping = true;
    }

    _messageController.addListener(() {
      DraftStore.instance.setDraft(DraftStore.chatKey(widget.chatId), _messageController.text);
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
        if (mounted && currentUserId != null) {
          (_messagingRepo ?? ref.read<MessagingRepository>(messagingRepositoryProvider))
              .setTypingStatus(widget.chatId, currentUserId, isTyping);
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messagingRepo = ref.read(messagingRepositoryProvider);
  }

  void _toggleEmojiPanel() {
    HapticFeedback.selectionClick();
    if (_showEmojiPanel) {
      setState(() => _showEmojiPanel = false);
      _composerFocus.requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    if (_showAttachments) _toggleAttachments();
    setState(() => _showEmojiPanel = true);
  }

  void _insertEmoji(String emoji) {
    final v = _messageController.value;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, emoji);
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + emoji.length),
    );
  }

  void _emojiBackspace() {
    final v = _messageController.value;
    if (v.text.isEmpty) return;
    final sel = v.selection.isValid ? v.selection : TextSelection.collapsed(offset: v.text.length);
    if (sel.start != sel.end) {
      _messageController.value = TextEditingValue(
        text: v.text.replaceRange(sel.start, sel.end, ''),
        selection: TextSelection.collapsed(offset: sel.start),
      );
      return;
    }
    if (sel.start == 0) return;
    // Remove one whole grapheme (emoji can be several code units).
    final before = v.text.substring(0, sel.start).characters;
    final kept = before.skipLast(1).toString();
    _messageController.value = TextEditingValue(
      text: kept + v.text.substring(sel.start),
      selection: TextSelection.collapsed(offset: kept.length),
    );
  }

  Future<void> _sendGif(GifPick gif) async {
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    setState(() => _showEmojiPanel = false);
    await ref.read(messagingRepositoryProvider).sendMessage(
          widget.chatId,
          me,
          '',
          mediaUrl: gif.url,
          mediaType: 'gif',
          fileName: gif.isVideo ? 'oneova_gif.mp4' : 'gif',
        );
    unawaited(ChatGifLibrary.save(gif).catchError((_) {}));
  }

  /// Attachment drawer "Location": a pin, or live location for 15 min / 1 h / 8 h.
  Future<void> _shareLocation() async {
    if (_showAttachments) _toggleAttachments();
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me == null) return;
    final choice = await showShareLocationSheet(context);
    if (choice == null) return;
    try {
      final id = await ref.read(messagingRepositoryProvider).sendMessage(
            widget.chatId,
            me,
            '',
            mediaUrl: choice.mapsUrl,
            mediaType: 'location',
            location: choice.toMessageLocation(),
          );
      if (choice.live != null) LiveLocationSharer.instance.start(widget.chatId, id, choice.live!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not share location: $e'),
          backgroundColor: AppColors.brandPink,
        ));
      }
    }
  }

  /// "Make GIF": record a short silent clip and send it as a looping GIF.
  void _createCameraGif() {
    HapticFeedback.lightImpact();
    VideoNoteSession.start(
      context,
      gifMode: true,
      onDone: (r) async {
        final me = FirebaseAuth.instance.currentUser?.uid;
        if (me == null) return;
        final name = 'gif_${DateTime.now().millisecondsSinceEpoch}.mp4';
        final url = await ref
            .read(storageServiceProvider)
            .uploadFile(r.file, 'chats/${widget.chatId}/attachments/$name');
        if (url == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('GIF upload failed. Check your connection.'),
              backgroundColor: AppColors.brandPink,
            ));
          }
          return;
        }
        await _sendGif(GifPick(url, isVideo: true));
      },
    );
  }

  void _startVideoNote(Offset globalStart) {
    if (_videoSession != null) return;
    if (_showEmojiPanel) setState(() => _showEmojiPanel = false);
    FocusScope.of(context).unfocus();
    final me = FirebaseAuth.instance.currentUser?.uid;
    if (me != null) ref.read(messagingRepositoryProvider).setRecordingStatus(widget.chatId, me, true);
    _videoSession = VideoNoteSession.start(
      context,
      onDone: (r) {
        _videoSession = null;
        if (me != null) ref.read(messagingRepositoryProvider).setRecordingStatus(widget.chatId, me, false);
        final secs = r.duration.inSeconds.clamp(1, 600);
        _uploadFileAndSend(
          r.file,
          'video_note',
          'video_note_${DateTime.now().millisecondsSinceEpoch}.mp4',
          voiceDuration: '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
        );
      },
      onCancelled: () {
        _videoSession = null;
        if (me != null) ref.read(messagingRepositoryProvider).setRecordingStatus(widget.chatId, me, false);
      },
    );
  }

  void _toggleRecordMode() {
    HapticFeedback.selectionClick();
    setState(() => _videoNoteMode = !_videoNoteMode);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(_videoNoteMode
            ? 'Video message: hold to record, slide up to lock, slide left to cancel'
            : 'Voice message: hold to record'),
        duration: const Duration(milliseconds: 1600),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
      ));
  }

  void _toggleAttachments() {
    if (!_showAttachments && _showEmojiPanel) _showEmojiPanel = false;
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

  Future<void> _initE2EE() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;
    try {
      final e2ee = ref.read(e2eEncryptionServiceProvider);
      await e2ee.ensureUserE2eeKeys(currentUserId);
      final myKey = await e2ee.getMyPublicKey();

      final chat = await ref.read(messagingRepositoryProvider).getChat(widget.chatId);
      final partnerId = chat?.participants.firstWhere(
        (p) => p != currentUserId,
        orElse: () => '',
      );

      const sharedCategories = {'group', 'room', 'vip_room', 'channel'};
      final isShared = (chat?.participants.length ?? 0) > 2 ||
          sharedCategories.contains(chat?.category);

      String? partnerKey;
      if (!isShared && partnerId != null && partnerId.isNotEmpty) {
        partnerKey = await e2ee.getRecipientPublicKey(partnerId);
      }

      if (mounted) {
        setState(() {
          _isSharedChat = isShared;
          _chatPartnerId = partnerId;
          _chatPartnerPublicKey = partnerKey;
          _myPublicKey = myKey;
        });
      }
    } catch (e) {
      debugPrint('Error initializing E2EE in chat screen: $e');
    }
  }

  void _decryptPendingMessages(List<MessageModel> messages) async {
    if (_chatPartnerPublicKey == null || _chatPartnerPublicKey!.isEmpty) {
      if (_chatPartnerId != null && _chatPartnerId!.isNotEmpty) {
        _chatPartnerPublicKey = await ref.read(e2eEncryptionServiceProvider).getRecipientPublicKey(_chatPartnerId!);
      }
    }
    final peerKey = _chatPartnerPublicKey;
    if (peerKey == null || peerKey.isEmpty) return;

    final e2ee = ref.read(e2eEncryptionServiceProvider);
    bool updated = false;

    for (final msg in messages) {
      if (msg.isEncrypted && !_decryptedCache.containsKey(msg.id)) {
        final decrypted = await e2ee.decryptMessage(msg.text, peerKey);
        _decryptedCache[msg.id] = decrypted;
        updated = true;
      }
    }

    if (updated && mounted) {
      setState(() {});
    }
  }

  String _getDisplayText(MessageModel message) {
    if (!message.isEncrypted) return message.text;
    return _decryptedCache[message.id] ?? '🔒 Decrypting...';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chatSettings = ref.read(settingsProvider).value?['chat'] as Map<String, dynamic>? ?? {};
    if (chatSettings['chatSoundEffects'] ?? true) {
      OneOvaSoundService.playHaptic(chatSettings['hapticIntensity'] ?? 'medium');
    }

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    ref.read(messagingRepositoryProvider).sendMessage(
      widget.chatId, 
      currentUserId, 
      text, 
      recipientId: _chatPartnerId,
      replyToMessageId: _replyingTo?.id,
    );
    ref.read(messagingRepositoryProvider).setTypingStatus(widget.chatId, currentUserId, false); // clear typing
    _messageController.clear();
    DraftStore.instance.clearDraft(DraftStore.chatKey(widget.chatId));
    setState(() {
      _replyingTo = null;
    });
    if (_awayFromBottom) _jumpToLatest();
  }

  void _openOvaAssistantOverlay() async {
    HapticFeedback.lightImpact();
    final currentDraft = _messageController.text.trim();
    final insertedText = await OneOvaAssistantOverlay.show<String>(
      context,
      initialPrompt: currentDraft.isNotEmpty ? currentDraft : null,
      activeChatId: widget.chatId,
      onInsertIntoChat: (textToInsert) {
        if (mounted) {
          setState(() {
            _messageController.text = textToInsert;
            _messageController.selection = TextSelection.fromPosition(
              TextPosition(offset: textToInsert.length),
            );
          });
        }
      },
    );

    if (insertedText != null && insertedText.isNotEmpty && mounted) {
      setState(() {
        _messageController.text = insertedText;
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: insertedText.length),
        );
      });
    }
  }
  
  /// Opens a photo, video, voice note or file in Ova Media Studio (reader +
  /// Ova Vision). Encrypted media is decrypted on the phone first.
  Future<void> _openMediaStudio(MessageModel message) async {
    var source = message.mediaUrl;
    if (source == null) return;
    if (message.mediaEncrypted && !source.startsWith('/')) {
      final key = _chatPartnerPublicKey;
      if (key == null) return;
      try {
        source = (await PeerMediaCrypto.decryptToCache(
          ref.read(e2eEncryptionServiceProvider),
          source,
          key,
          fileName: message.fileName,
        ))
            .path;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't decrypt this file on this phone."),
            backgroundColor: AppColors.brandPink,
          ));
        }
        return;
      }
    }
    if (!mounted) return;
    await OvaMediaStudio.open(
      context,
      source: source,
      kind: ovaMediaKindFor(message.mediaType, message.fileName),
      fileName: message.fileName,
      fromEncryptedChat: _e2eeActive,
      onInsertIntoChat: _insertIntoComposer,
    );
  }

  void _insertIntoComposer(String text) {
    setState(() {
      _messageController.text = text;
      _messageController.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  Widget _buildMediaAttachment(
    MessageModel message, {
    bool isMe = false,
    ChatPrefs prefs = const ChatPrefs(),
  }) {
    if (message.mediaEncrypted && message.mediaUrl != null && !message.mediaUrl!.startsWith('/')) {
      // Decrypt to a local file, then render the plaintext copy.
      return PeerEncryptedMedia(
        url: message.mediaUrl!,
        peerPublicKey: _chatPartnerPublicKey,
        fileName: message.fileName,
        builder: (context, localPath) =>
            _buildMediaAttachment(message.copyWith(mediaUrl: localPath), isMe: isMe, prefs: prefs),
      );
    }
    if (message.mediaType == 'image') {
      return GestureDetector(
        onTap: () => _openMediaStudio(message),
        child: Container(
          margin: EdgeInsets.only(bottom: message.text.isNotEmpty ? 6 : 0),
          width: 220,
          height: 220,
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: isMe ? AppColors.brandWhite.withValues(alpha: 0.2) : context.border),
            image: DecorationImage(
              image: chatMediaImage(message.mediaUrl!),
              fit: BoxFit.cover,
            ),
          ),
        ),
      );
    } else if (message.mediaType == 'video_note' && message.mediaUrl != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        child: GestureDetector(
          onLongPress: () => _openMediaStudio(message),
          child: VideoNoteBubble(url: message.mediaUrl!, duration: message.voiceDuration),
        ),
      );
    } else if (message.mediaType == 'location') {
      return Padding(
        padding: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        child: ChatLocationBubble(
          chatId: widget.chatId,
          messageId: message.id,
          location: message.location,
          isMe: isMe,
        ),
      );
    } else if (message.mediaType == 'gif' && message.mediaUrl != null) {
      final isVideo = (message.fileName ?? '').endsWith('.mp4') || message.mediaUrl!.contains('.mp4');
      return Padding(
        padding: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        child: GifBubble(url: message.mediaUrl!, isVideo: isVideo),
      );
    } else if (message.mediaType == 'video' && message.mediaUrl != null) {
      return Padding(
        padding: EdgeInsets.only(bottom: message.text.isNotEmpty ? 8 : 0),
        child: GestureDetector(
          onLongPress: () => _openMediaStudio(message),
          child: ChatVideoBubble(url: message.mediaUrl!, title: message.fileName),
        ),
      );
    } else if (message.mediaType == 'document' ||
        message.mediaType == 'file' ||
        message.mediaType == 'archive' ||
        message.mediaType == 'code' ||
        message.mediaType == 'video') {
      return Padding(
        padding: EdgeInsets.only(bottom: message.text.isNotEmpty ? 6 : 0),
        child: ChatFileCard(
          fileName: message.fileName ?? (message.mediaType == 'video' ? 'Video' : 'Document'),
          fileSize: message.fileSize,
          mediaType: message.mediaType,
          onBlue: isMe,
          encrypted: message.mediaEncrypted,
          onOpen: message.mediaUrl == null ? null : () => _openMediaStudio(message),
          onSave: message.mediaUrl == null ? null : () => _saveFile(message),
        ),
      );
    } else if (message.mediaType == 'audio' && message.mediaUrl != null) {
      final resolvedUrl = message.mediaUrl!;
      return GestureDetector(
        onLongPress: () => _openMediaStudio(message),
        child: InteractiveVoiceNotePlayer(
          audioUrl: resolvedUrl,
          initialDuration: message.voiceDuration,
          waveformSamples: message.voiceWaveform,
          isMe: isMe,
          embedded: true,
          messageId: message.id,
          senderUid: message.senderId,
          autoTranslateVoice: !isMe && prefs.aiEnabled && prefs.aiAutoTranslateVoice,
          onTranslateVoice: () => _translateVoiceMessage(
            message,
            decryptedOrResolvedPath: resolvedUrl,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildLinkPreview(String text, {bool isMe = false, Map<String, dynamic>? safety}) {
    final url = firstLinkIn(text);
    if (url == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: LinkSafetyGate(
        key: ValueKey('link-$url'),
        url: url,
        serverSafety: safety,
        onBlue: isMe,
        child: ChatLinkCard(url: url, onBlue: isMe),
      ),
    );
  }

  void _confirmDeleteMessage(MessageModel message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.border, width: 1),
        ),
        title: Text(
          'Unsend message?',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This removes the message for everyone in the chat. This can\'t be undone.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(messagingRepositoryProvider).deleteMessage(widget.chatId, message.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Message unsent'),
                    backgroundColor: context.surfaceMid,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text('Unsend', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _startCall({required bool isVideo}) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    final chat = await ref.read(messagingRepositoryProvider).getChat(widget.chatId);
    final others = chat?.participants.where((id) => id != currentUserId).toList() ?? const <String>[];
    if (others.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot initiate call: recipient not found')),
        );
      }
      return;
    }
    if (!mounted) return;
    await startOneovaCall(
      context,
      ref,
      targetUserIds: others,
      isVideo: isVideo,
      chatId: widget.chatId,
      title: others.length > 1 ? chat?.title : null,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);
    if (pickedFile != null) {
      _uploadFileAndSend(File(pickedFile.path), 'image', pickedFile.name);
    }
  }

  Future<void> _pickVideo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      _uploadFileAndSend(File(pickedFile.path), 'video', pickedFile.name);
    }
  }

  Future<void> _pickDocument() async {
    final result = await FilePicker.pickFiles();
    if (result.isNotEmpty && result.first.path != null) {
      final item = result.first;
      final fileName = item.name.isNotEmpty ? item.name : item.path!.split('/').last;
      _uploadFileAndSend(File(item.path!), 'document', fileName);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (result.isNotEmpty && result.first.path != null) {
      final item = result.first;
      final fileName = item.name.isNotEmpty ? item.name : item.path!.split('/').last;
      _uploadFileAndSend(File(item.path!), 'audio', fileName);
    }
  }

  Future<void> _pickSpreadsheetFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv', 'numbers', 'tsv'],
    );
    if (result.isNotEmpty && result.first.path != null) {
      final item = result.first;
      final fileName = item.name.isNotEmpty ? item.name : item.path!.split('/').last;
      _uploadFileAndSend(File(item.path!), 'file', fileName);
    }
  }

  Future<void> _pickArchiveFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'rar', '7z', 'tar', 'gz', 'bz2'],
    );
    if (result.isNotEmpty && result.first.path != null) {
      final item = result.first;
      final fileName = item.name.isNotEmpty ? item.name : item.path!.split('/').last;
      _uploadFileAndSend(File(item.path!), 'archive', fileName);
    }
  }

  Future<void> _pickCodeFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'dart', 'js', 'ts', 'py', 'json', 'html', 'css', 'swift', 'kt', 'cpp', 'c', 'sql', 'sh', 'yaml', 'yml'
      ],
    );
    if (result.isNotEmpty && result.first.path != null) {
      final item = result.first;
      final fileName = item.name.isNotEmpty ? item.name : item.path!.split('/').last;
      _uploadFileAndSend(File(item.path!), 'code', fileName);
    }
  }
  
  Future<void> _confirmCancelActiveUpload() async {
    final task = _activeUploadTask;
    if (task == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Cancel upload?',
          style: AppTypography.sectionTitle(ctx.textPrimary),
        ),
        content: Text(
          'Stop uploading "${_uploadingFileName ?? 'attachment'}"?',
          style: AppTypography.body(ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Keep uploading', style: AppTypography.small(ctx.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop upload'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _uploadProgressSub?.cancel();
      _uploadProgressSub = null;
      await task.cancel();
      if (mounted) {
        setState(() {
          _activeUploadTask = null;
          _uploadingFileName = null;
          _uploadProgress = null;
        });
        OneovaSmartStatus.show(
          context,
          title: 'Upload canceled',
          source: 'Chat Media',
          kind: OneovaStatusKind.info,
        );
      }
    }
  }

  Future<void> _uploadFileAndSend(
    File file, 
    String type, 
    String fileName, {
    String? voiceDuration,
    List<double>? voiceWaveform,
    bool silent = false,
    String? optimisticId,
  }) async {
    if (_showAttachments) _toggleAttachments();

    int? fileSize;
    try {
      fileSize = file.lengthSync();
    } catch (_) {}

    if (!silent && mounted) {
      setState(() {
        _uploadingFileName = fileName;
        _uploadProgress = 0.02;
      });
    }
    
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final repo = ref.read(messagingRepositoryProvider);
    final storage = ref.read(storageServiceProvider);

    try {
      // 1:1 chats: upload only ciphertext under the per-chat key, and keep the
      // original file name out of the storage path.
      final peerKey = _e2eeActive ? _chatPartnerPublicKey : null;
      File toUpload = file;
      String path = 'chats/${widget.chatId}/attachments/${DateTime.now().millisecondsSinceEpoch}_$fileName';
      if (peerKey != null) {
        try {
          toUpload = await PeerMediaCrypto.encryptForUpload(ref.read(e2eEncryptionServiceProvider), file, peerKey);
          path = 'chats/${widget.chatId}/attachments/${DateTime.now().millisecondsSinceEpoch}.enc';
        } catch (e) {
          debugPrint('Media encryption failed: $e');
          if (mounted) {
            OneovaSmartStatus.show(
              context,
              title: 'Could not encrypt this file',
              subtitle: 'For your privacy, the attachment was not sent.',
              source: 'Chat Security',
              kind: OneovaStatusKind.error,
            );
          }
          return;
        }
      }

      await _uploadProgressSub?.cancel();
      final uploadTask = storage.uploadFileWithProgress(toUpload, path);
      _activeUploadTask = uploadTask;
      _uploadProgressSub = uploadTask.snapshotEvents.listen((snap) {
        if (!silent && mounted && snap.totalBytes > 0) {
          setState(() {
            _uploadProgress = (snap.bytesTransferred / snap.totalBytes).clamp(0.02, 0.99);
          });
        }
      });

      final snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();

      if (!identical(toUpload, file)) {
        toUpload.delete().catchError((_) => toUpload);
      }

      if (downloadUrl.isNotEmpty) {
        if (type == 'audio' && peerKey == null) {
          VoiceAudioDiskCache.seedLocalFile(downloadUrl, file.path);
        }
        await repo.sendMessage(
          widget.chatId, 
          currentUserId, 
          '', 
          mediaUrl: downloadUrl,
          mediaEncrypted: peerKey != null,
          mediaType: type,
          fileName: fileName,
          fileSize: fileSize,
          voiceDuration: voiceDuration,
          voiceWaveform: voiceWaveform,
          hasVoiceMemo: type == 'audio',
        );
        if (!silent && mounted) {
          OneovaSmartStatus.show(
            context,
            title: 'Sent $fileName',
            source: 'Chat Media',
            kind: OneovaStatusKind.success,
            duration: const Duration(milliseconds: 2400),
          );
        }
      } else {
        if (mounted) {
          OneovaSmartStatus.show(
            context,
            title: 'Upload failed',
            subtitle: 'Check your connection and tap Retry.',
            source: 'Chat Media',
            kind: OneovaStatusKind.error,
            actionLabel: 'Retry',
            onAction: () => _uploadFileAndSend(
              file,
              type,
              fileName,
              voiceDuration: voiceDuration,
              voiceWaveform: voiceWaveform,
              silent: silent,
            ),
          );
        }
      }
    } on FirebaseException catch (e) {
      if (e.code == 'canceled') return;
      debugPrint('Chat upload FirebaseException: $e');
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Could not upload $fileName',
          subtitle: e.message ?? 'Connection interrupted.',
          source: 'Chat Media',
          kind: OneovaStatusKind.error,
          actionLabel: 'Retry',
          onAction: () => _uploadFileAndSend(
            file,
            type,
            fileName,
            voiceDuration: voiceDuration,
            voiceWaveform: voiceWaveform,
            silent: silent,
          ),
        );
      }
    } catch (e) {
      debugPrint('Chat upload error: $e');
      if (mounted) {
        OneovaSmartStatus.show(
          context,
          title: 'Could not send $fileName',
          subtitle: 'Tap Retry to send again.',
          source: 'Chat Media',
          kind: OneovaStatusKind.error,
          actionLabel: 'Retry',
          onAction: () => _uploadFileAndSend(
            file,
            type,
            fileName,
            voiceDuration: voiceDuration,
            voiceWaveform: voiceWaveform,
            silent: silent,
          ),
        );
      }
    } finally {
      await _uploadProgressSub?.cancel();
      _uploadProgressSub = null;
      _activeUploadTask = null;
      if (mounted) {
        setState(() {
          _uploadingFileName = null;
          _uploadProgress = null;
          if (optimisticId != null) {
            _pendingLocalMessages.removeWhere((m) => m.id == optimisticId);
          }
        });
      }
    }
  }

  Future<void> _releaseVoiceMic() async {
    final lease = _voiceMicLease;
    _voiceMicLease = null;
    await lease?.release();
  }

  Future<void> _startRecording() async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_isRecordingVoice) return;
    if (await _audioRecorder.hasPermission()) {
      final got = await MicCoordinator.instance.acquire(
        MicUser.voiceNote,
        onPreempted: () async {
          _voiceMicLease = null;
          if (_isRecordingVoice) {
            await _cancelRecording(releaseLease: false);
          }
        },
        onInterruption: (i) {
          if (i == MicInterruption.heldByOtherApp && _isRecordingVoice && !_voicePaused && mounted) {
            unawaited(_toggleVoicePause());
          }
        },
      );
      if (got is MicBusy) {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text(got.message), behavior: SnackBarBehavior.floating),
          );
        }
        return;
      }
      _voiceMicLease = got as MicLease;
      if (!mounted) {
        await _releaseVoiceMic();
        return;
      }

      final dir = await getTemporaryDirectory();
      _recordedFilePath = '${dir.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _recordedWaveformSamples.clear();
      _liveLevels.clear();
      _voiceLocked = false;
      _voicePaused = false;
      _voiceSlide = Offset.zero;
      _recordingDurationSeconds = 0;

      // Zero-cost hardware DSP (AEC + Noise Suppression + Auto-Gain) + compact
      // 48kbps 24kHz mono AAC-LC (~3x smaller & faster upload than 128kbps stereo).
      try {
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 48000,
            sampleRate: 24000,
            numChannels: 1,
            echoCancel: true,
            noiseSuppress: true,
            autoGain: true,
            androidConfig: AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceCommunication,
            ),
          ),
          path: _recordedFilePath!,
        );
      } catch (e) {
        await _releaseVoiceMic();
        rethrow;
      }

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (mounted && !_voicePaused) {
          setState(() => _recordingDurationSeconds++);
        }
      });

      _amplitudeTimer?.cancel();
      _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 65), (t) async {
        try {
          if (_voicePaused) return;
          final amp = await _audioRecorder.getAmplitude();
          if (mounted) {
            setState(() {
              final level = levelFromDb(amp.current);
              _liveLevels.add(level);
              if (_liveLevels.length > 120) _liveLevels.removeRange(0, _liveLevels.length - 120);
              if (_recordedWaveformSamples.length < 12000) _recordedWaveformSamples.add(level);
            });
          }
        } catch (_) {}
      });

      setState(() {
        _isRecordingVoice = true;
      });
      HapticFeedback.mediumImpact();
      if (currentUserId != null) {
        (_messagingRepo ?? ref.read<MessagingRepository>(messagingRepositoryProvider))
            .setRecordingStatus(widget.chatId, currentUserId, true);
      }
    }
  }

  Future<void> _cancelRecording({bool releaseLease = true}) async {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    try {
      await _audioRecorder.stop();
      if (_recordedFilePath != null) {
        final f = File(_recordedFilePath!);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
    if (releaseLease) {
      await _releaseVoiceMic();
    }
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDurationSeconds = 0;
        _voiceLocked = false;
        _voicePaused = false;
        _voiceSlide = Offset.zero;
      });
    }
    HapticFeedback.lightImpact();
    if (currentUserId != null) {
      (_messagingRepo ?? (mounted ? ref.read(messagingRepositoryProvider) : null))
          ?.setRecordingStatus(widget.chatId, currentUserId, false);
    }
  }

  Future<void> _stopRecordingAndSend() async {
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (!_isRecordingVoice) {
      await _releaseVoiceMic();
      return;
    }
    String? path;
    try {
      if (await _audioRecorder.isRecording()) {
        path = await _audioRecorder.stop();
      }
    } catch (e) {
      debugPrint('[Chat] audioRecorder stop error: $e');
    }
    await _releaseVoiceMic();
    final durationSecs = _recordingDurationSeconds > 0 ? _recordingDurationSeconds : 1;
    final samples = downsampleLevels(_recordedWaveformSamples, 24);

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingDurationSeconds = 0;
        _voiceLocked = false;
        _voicePaused = false;
        _voiceSlide = Offset.zero;
      });
    }
    HapticFeedback.lightImpact();
    if (currentUserId != null) {
      (_messagingRepo ?? (mounted ? ref.read(messagingRepositoryProvider) : null))
          ?.setRecordingStatus(widget.chatId, currentUserId, false);
    }
    if (path != null && File(path).existsSync()) {
      final m = durationSecs ~/ 60;
      final s = (durationSecs % 60).toString().padLeft(2, '0');
      final durationStr = '$m:$s';
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'voice_note_$stamp.m4a';
      final optimisticId = 'local_vn_$stamp';

      if (mounted) {
        setState(() {
          _pendingLocalMessages.insert(
            0,
            MessageModel(
              id: optimisticId,
              senderId: currentUserId ?? 'guest',
              text: '',
              timestamp: Timestamp.now(),
              readBy: const [],
              mediaUrl: path,
              mediaType: 'audio',
              fileName: fileName,
              voiceDuration: durationStr,
              voiceWaveform: samples,
            ),
          );
        });
      }

      unawaited(
        _uploadFileAndSend(
          File(path),
          'audio',
          fileName,
          voiceDuration: durationStr,
          voiceWaveform: samples,
          silent: true,
          optimisticId: optimisticId,
        ),
      );
    }
  }

  Future<void> _toggleVoicePause() async {
    HapticFeedback.selectionClick();
    try {
      if (_voicePaused) {
        await _audioRecorder.resume();
      } else {
        await _audioRecorder.pause();
      }
      if (mounted) setState(() => _voicePaused = !_voicePaused);
    } catch (_) {}
  }

  Future<void> _toggleRecording() async {
    if (_isRecordingVoice) {
      await _stopRecordingAndSend();
    } else {
      await _startRecording();
    }
  }

  @override
  void dispose() {
    _uploadProgressSub?.cancel();
    _micHoldTimer?.cancel();
    _recordingTimer?.cancel();
    _amplitudeTimer?.cancel();
    _inChatSearchController.dispose();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId != null && _isRecordingVoice) {
      _messagingRepo?.setRecordingStatus(widget.chatId, currentUserId, false);
    }
    unawaited(_voiceMicLease?.release());
    _voiceMicLease = null;
    _videoSession?.cancel();
    _composerFocus.dispose();
    _messageController.dispose();
    try {
      if (_isRecordingVoice) {
        _audioRecorder.stop().catchError((_) => null);
      }
      _audioRecorder.dispose();
    } catch (_) {}
    _attachmentAnimController.dispose();
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final messagesAsync = ref.watch(chatMessagesProvider(widget.chatId));
    final chat = ref.watch(chatStreamProvider((chatId: widget.chatId, currentUserId: currentUserId))).value;
    final isChannelReader = chat?.category == 'channel' && chat?.ownerId != null && chat!.ownerId != currentUserId;
    final isVipHost = chat?.category == 'vip_room' && chat?.ownerId == currentUserId;

    // Mark as read when opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(messagingRepositoryProvider).markMessagesAsRead(widget.chatId, currentUserId);
    });

    // Background: this chat's own, else the all-chats default, else the
    // older per-device wallpaper.
    final chatPrefs = ref.watch(chatPrefsProvider((uid: currentUserId, chatId: widget.chatId))).value;
    final allChatsPrefs =
        ref.watch(chatPrefsProvider((uid: currentUserId, chatId: ChatAssistService.allChatsDoc))).value;
    final background = chatPrefs?.background ??
        allChatsPrefs?.background ??
        ChatBackground(
          preset: switch (_selectedWallpaperKey) {
            'cobalt_blue' => 'blue_glow',
            'cyber_pink' => 'pink_glow',
            'slate_executive' => 'soft',
            'monochrome_oled' => 'oled',
            _ => 'default',
          },
        );

    return Scaffold(
      backgroundColor: context.bg,
      appBar: _buildAppBar(currentUserId),
      body: Stack(
        fit: StackFit.expand,
        children: [
          ChatBackgroundView(background: background),
          Column(
          children: [
            if (isVipHost) RoomJoinRequestsBanner(chatId: widget.chatId, roomTitle: chat?.title ?? 'your room'),
            _buildFollowStrip(chat, currentUserId),
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
            
            // Input Area (channel members read only)
            if (isChannelReader) const ChannelReadOnlyBar() else _buildInputArea(),
            
            // Attachment Drawer
            SizeTransition(
              sizeFactor: _attachmentAnimation,
              child: _buildAttachmentDrawer(),
            ),

            // Emoji & GIF panel (replaces the keyboard)
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: _showEmojiPanel && !isChannelReader
                  ? ChatEmojiGifPanel(
                      onEmoji: _insertEmoji,
                      onBackspace: _emojiBackspace,
                      onGif: _sendGif,
                      onCreateGif: _createCameraGif,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
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
        final recordingUsers = List<String>.from(data['recordingUsers'] ?? []);
        final otherTyping = typingUsers.where((id) => id != currentUserId).toList();
        final otherRecording = recordingUsers.where((id) => id != currentUserId).toList();
        
        if (otherTyping.isEmpty && otherRecording.isEmpty) return const SizedBox.shrink();
        
        final isRecording = otherRecording.isNotEmpty;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isRecording) ...[
                const Icon(Icons.mic_rounded, color: AppColors.brandPink, size: 16)
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.25, 1.25), duration: 600.ms),
                const SizedBox(width: 8),
                Text(
                  'Recording audio...',
                  style: GoogleFonts.inter(
                    color: AppColors.brandPink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ] else ...[
                Text(
                  'Typing...',
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (dotIndex) => Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: const BoxDecoration(
                        color: AppColors.brandPink,
                        shape: BoxShape.circle,
                      ),
                    ).animate(onPlay: (c) => c.repeat(reverse: true)).scale(
                          delay: Duration(milliseconds: dotIndex * 180),
                          duration: 500.ms,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ).animate().fadeIn(duration: 200.ms);
      },
    );
  }

  PreferredSizeWidget _buildAppBar(String currentUserId) {
    if (_isSearchingInChat) {
      return AppBar(
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        iconTheme: IconThemeData(color: context.topBarFg),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.topBarFg, size: 19),
          tooltip: 'Close search',
          onPressed: () {
            setState(() {
              _isSearchingInChat = false;
              _inChatSearchQuery = '';
              _inChatSearchController.clear();
            });
          },
        ),
        title: TextField(
          controller: _inChatSearchController,
          autofocus: true,
          style: GoogleFonts.inter(color: context.topBarFg, fontSize: 13.5),
          cursorColor: context.topBarFg,
          decoration: InputDecoration(
            hintText: 'Search in conversation...',
            hintStyle: GoogleFonts.inter(color: context.topBarFg.withValues(alpha: 0.65), fontSize: 13.5),
            border: InputBorder.none,
          ),
          onChanged: (val) {
            setState(() {
              _inChatSearchQuery = val.trim().toLowerCase();
            });
          },
        ),
        actions: [
          if (_inChatSearchQuery.isNotEmpty)
            IconButton(
              icon: Icon(Icons.clear_rounded, color: context.topBarFg, size: 19),
              tooltip: 'Clear',
              onPressed: () {
                setState(() {
                  _inChatSearchController.clear();
                  _inChatSearchQuery = '';
                });
              },
            ),
          const SizedBox(width: 8),
        ],
      );
    }

    final chat = ref.watch(chatStreamProvider((chatId: widget.chatId, currentUserId: currentUserId))).value;
    final others = chat?.participants.where((id) => id != currentUserId).toList() ?? const <String>[];
    final isGroup = others.length > 1 || chat?.category == 'group' || chat?.category == 'channel';
    final otherUserId = others.length == 1 ? others.first : '';
    final fg = context.topBarFg;

    Future<void> openInfo() async {
      final otherUser = otherUserId.isEmpty ? null : await _getUserCached(otherUserId);
      if (mounted) _showChatSettingsSheet(context, chat, otherUser, otherUserId);
    }

    return AppBar(
      backgroundColor: AppColors.brandBlue,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 58,
      iconTheme: IconThemeData(color: fg),
      titleSpacing: 0,
      leadingWidth: 44,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: fg, size: 19),
        tooltip: 'Back',
        onPressed: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/hub/messages');
          }
        },
      ),
      title: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.1,
        child: FutureBuilder<AppUser?>(
          future: otherUserId.isEmpty ? null : _getUserCached(otherUserId),
          builder: (context, userSnapshot) {
            final user = userSnapshot.data;
            final name = isGroup
                ? (chat?.title?.isNotEmpty == true ? chat!.title! : 'Group chat')
                : (user != null && user.fullName.isNotEmpty)
                    ? user.fullName
                    : (user?.username?.isNotEmpty == true ? user!.username! : (chat?.title ?? 'Chat'));
            final avatarUrl = isGroup ? chat?.avatarUrl : (user?.profilePhotoUrl ?? chat?.avatarUrl);
            final verified = chat?.isVerified == true || user?.isVerified == true;
            final presence = otherUserId.isEmpty
                ? const UserPresence()
                : (ref.watch(userPresenceDetailsProvider(otherUserId)).value ?? const UserPresence());
            final typing = chat?.typingUsers.where((id) => id != currentUserId).isNotEmpty ?? false;
            final recording = chat?.recordingUsers.where((id) => id != currentUserId).isNotEmpty ?? false;
            final relation = otherUserId.isEmpty
                ? null
                : ref.watch(followStateProvider((me: currentUserId, them: otherUserId))).value;

            final Widget subWidget;
            if (recording) {
              subWidget = Text('recording audio…', style: GoogleFonts.inter(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600));
            } else if (typing) {
              subWidget = Text('typing…', style: GoogleFonts.inter(color: fg, fontSize: 11.5, fontWeight: FontWeight.w600));
            } else if (isGroup) {
              subWidget = Text('${chat?.participants.length ?? 0} members', style: GoogleFonts.inter(color: fg.withValues(alpha: 0.8), fontSize: 11.5));
            } else {
              subWidget = LivePresencePill(presence: presence, textColor: fg);
            }

            return InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: openInfo,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: fg.withValues(alpha: 0.16),
                          backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty) ? NetworkImage(avatarUrl) : null,
                          child: (avatarUrl == null || avatarUrl.isEmpty)
                              ? (isGroup
                                  ? Icon(Icons.groups_rounded, color: fg, size: 18)
                                  : Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                                      style: GoogleFonts.inter(color: fg, fontWeight: FontWeight.w700, fontSize: 14),
                                    ))
                              : null,
                        ),
                        if (!isGroup)
                          Positioned(
                            bottom: -1,
                            right: -1,
                            child: LiveUserPresenceDot(
                              presence: presence,
                              size: 11,
                              borderColor: AppColors.brandBlue,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                    color: fg,
                                    fontSize: 15,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (verified) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.verified_rounded, color: fg, size: 14),
                              ],
                              if (relation == FollowState.mutual) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: 'You follow each other',
                                  child: Icon(Icons.people_alt_rounded, color: fg.withValues(alpha: 0.85), size: 13),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Flexible(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: KeyedSubtree(
                                    key: ValueKey('${presence.status.name}_${typing}_$recording'),
                                    child: subWidget,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.lock_rounded, size: 10, color: fg.withValues(alpha: 0.75)),
                              if (chat != null && chat.disappearingDuration > 0) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.timer_outlined, size: 11, color: fg.withValues(alpha: 0.85)),
                              ],
                              if (chat?.mutedUsers.contains(currentUserId) == true) ...[
                                const SizedBox(width: 5),
                                Icon(Icons.notifications_off_rounded, size: 11, color: fg.withValues(alpha: 0.6)),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(Icons.videocam_outlined, color: fg, size: 23),
          tooltip: 'Video call',
          visualDensity: VisualDensity.compact,
          onPressed: () => _startCall(isVideo: true),
        ),
        IconButton(
          icon: Icon(Icons.call_outlined, color: fg, size: 21),
          tooltip: 'Voice call',
          visualDensity: VisualDensity.compact,
          onPressed: () => _startCall(isVideo: false),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded, color: fg, size: 21),
          tooltip: 'More',
          color: context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: context.border, width: 1),
          ),
          onOpened: HapticFeedback.lightImpact,
          onSelected: (value) {
            switch (value) {
              case 'search':
                setState(() => _isSearchingInChat = true);
                break;
              case 'highlights':
                _showHighlights();
                break;
              case 'ai':
                _showAiControls();
                break;
              case 'background':
                showChatBackgroundSheet(context, uid: currentUserId, chatId: widget.chatId);
                break;
              case 'info':
                openInfo();
                break;
              case 'profile':
                if (otherUserId.isNotEmpty) context.push('/profile/$otherUserId');
                break;
            }
          },
          itemBuilder: (ctx) => [
            _menuItem('search', Icons.search_rounded, 'Search in chat'),
            _menuItem('highlights', Icons.star_outline_rounded, 'Highlights'),
            _menuItem('background', Icons.wallpaper_rounded, 'Chat background'),
            _menuItem(
              'ai',
              Icons.auto_awesome_outlined,
              (ref.read(chatPrefsProvider((uid: currentUserId, chatId: widget.chatId))).value?.aiEnabled ?? false)
                  ? 'AI in this chat · On'
                  : 'AI in this chat · Off',
            ),
            if (!isGroup && otherUserId.isNotEmpty) _menuItem('profile', Icons.person_outline_rounded, 'View profile'),
            _menuItem('info', Icons.info_outline_rounded, isGroup ? 'Group info & settings' : 'Chat info & settings'),
          ],
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.brandBlue),
          const SizedBox(width: 10),
          Text(label, style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
        ],
      ),
    );
  }

  /// Slim bar under the top bar for 1:1 chats with someone you're not
  /// following yet: "Abdoul follows you · Follow back".
  Widget _buildFollowStrip(ChatModel? chat, String currentUserId) {
    final others = chat?.participants.where((id) => id != currentUserId).toList() ?? const <String>[];
    if (others.length != 1 || chat?.category == 'group' || chat?.category == 'channel') {
      return const SizedBox.shrink();
    }
    final otherUserId = others.first;
    final relation = ref.watch(followStateProvider((me: currentUserId, them: otherUserId))).value;
    if (relation == null ||
        relation == FollowState.following ||
        relation == FollowState.mutual ||
        relation == FollowState.self ||
        relation == FollowState.blocked) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<AppUser?>(
      future: _getUserCached(otherUserId),
      builder: (context, snap) {
        final full = snap.data?.fullName.isNotEmpty == true ? snap.data!.fullName : (chat?.title ?? 'They');
        final first = full.split(' ').first;
        final text = switch (relation) {
          FollowState.followsYou => '$first follows you',
          FollowState.requested => 'Follow request sent to $first',
          _ => 'You don\'t follow $first yet',
        };
        return MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.1,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
            decoration: BoxDecoration(
              color: context.surface,
              border: Border(bottom: BorderSide(color: context.border, width: 1)),
            ),
            child: Row(
              children: [
                Icon(
                  relation == FollowState.followsYou ? Icons.waving_hand_rounded : Icons.person_outline_rounded,
                  size: 16,
                  color: AppColors.brandBlue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500, color: context.textPrimary),
                  ),
                ),
                FollowButton(
                  targetUserId: otherUserId,
                  targetName: full,
                  size: FollowButtonSize.compact,
                ),
              ],
            ),
          ),
        ).animate().fadeIn(duration: 220.ms).slideY(begin: -0.2, end: 0);
      },
    );
  }

  void _showChatSettingsSheet(BuildContext context, ChatModel? chat, AppUser? otherUser, String otherUserId) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final name = (otherUser != null && otherUser.fullName.isNotEmpty)
        ? otherUser.fullName
        : (chat?.title ?? 'Oneova Creator');
    final avatarUrl = otherUser?.profilePhotoUrl ?? chat?.avatarUrl;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final isOnline = ref.read(userPresenceProvider(otherUserId)).value ?? false;
    final isMuted = chat?.mutedUsers.contains(currentUserId) ?? false;
    final disappearingSecs = chat?.disappearingDuration ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.88,
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(top: BorderSide(color: context.border, width: 1)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: context.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Chat Info & Settings',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 22),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      children: [
                        // Profile Hero
                        Center(
                          child: Column(
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isOnline ? AppColors.brandPink : AppColors.brandBlue,
                                        width: 2.5,
                                      ),
                                    ),
                                    child: CircleAvatar(
                                      radius: 40,
                                      backgroundColor: context.surfaceMid,
                                      backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                                          ? NetworkImage(avatarUrl)
                                          : null,
                                      child: (avatarUrl == null || avatarUrl.isEmpty)
                                          ? Text(
                                              initial,
                                              style: GoogleFonts.inter(
                                                color: context.textPrimary,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 28,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  if (isOnline)
                                    Positioned(
                                      bottom: 2,
                                      right: 2,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: AppColors.brandPink,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: context.surface, width: 3),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name,
                                    style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  if (chat?.isVerified == true || otherUser?.isVerified == true) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 18),
                                  ],
                                ],
                              ),
                              if (otherUser?.username != null && otherUser!.username!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@${otherUser.username}',
                                  style: GoogleFonts.inter(
                                    color: context.textMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: AppColors.brandPink.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 0.8),
                                ),
                                child: Text(
                                  isOnline ? 'Active Now' : 'End-to-End Encrypted',
                                  style: GoogleFonts.inter(
                                    color: AppColors.brandPink,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Quick Actions Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildQuickActionBtn(
                              icon: Icons.call_rounded,
                              label: 'Voice',
                              onTap: () {
                                Navigator.pop(ctx);
                                _startCall(isVideo: false);
                              },
                            ),
                            _buildQuickActionBtn(
                              icon: Icons.videocam_rounded,
                              label: 'Video',
                              onTap: () {
                                Navigator.pop(ctx);
                                _startCall(isVideo: true);
                              },
                            ),
                            _buildQuickActionBtn(
                              icon: Icons.search_rounded,
                              label: 'Search',
                              onTap: () {
                                Navigator.pop(ctx);
                                setState(() => _isSearchingInChat = true);
                              },
                            ),
                            _buildQuickActionBtn(
                              icon: isMuted ? Icons.notifications_off_rounded : Icons.notifications_active_rounded,
                              label: isMuted ? 'Muted' : 'Mute',
                              isActive: isMuted,
                              onTap: () async {
                                if (currentUserId.isNotEmpty) {
                                  final newMute = !isMuted;
                                  final messenger = ScaffoldMessenger.of(context);
                                  final bg = context.surfaceMid;
                                  await ref.read(messagingRepositoryProvider).setChatMuted(widget.chatId, currentUserId, newMute);
                                  setModalState(() {});
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(newMute ? 'Chat muted' : 'Chat unmuted'),
                                        duration: const Duration(seconds: 2),
                                        backgroundColor: bg,
                                      ),
                                    );
                                  }
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Section 1: Chat Themes & Wallpaper
                        _buildSectionHeader('Chat Wallpaper & Mood', Icons.palette_outlined),
                        const SizedBox(height: 10),
                        _buildSettingsTile(
                          icon: Icons.wallpaper_rounded,
                          title: 'Chat background',
                          subtitle: 'Colors or a photo, for this chat or all chats',
                          onTap: () => showChatBackgroundSheet(
                            context,
                            uid: FirebaseAuth.instance.currentUser?.uid ?? '',
                            chatId: widget.chatId,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Text Size & Density',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: context.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildDensitySelector(setModalState),
                        const SizedBox(height: 24),

                        // Section 2: Privacy & Oneova Shield
                        _buildSectionHeader('Privacy & Oneova Shield', Icons.security_rounded),
                        const SizedBox(height: 10),
                        _buildOneovaShieldCard(context),
                        const SizedBox(height: 12),
                        _buildDisappearingMessagesTile(context, disappearingSecs, setModalState),
                        const SizedBox(height: 12),
                        _buildSoundSelectorTile(context, setModalState),
                        const SizedBox(height: 24),

                        // Section 3: Shared Media & Starred
                        _buildSectionHeader('Shared Content', Icons.perm_media_outlined),
                        const SizedBox(height: 10),
                        _buildSettingsTile(
                          icon: Icons.photo_library_outlined,
                          title: 'Media, Files & Links',
                          subtitle: 'View shared photos, videos, and documents',
                          onTap: () {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Opening shared media gallery...'),
                                backgroundColor: context.surfaceMid,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildSettingsTile(
                          icon: Icons.star_outline_rounded,
                          title: 'Starred Messages',
                          subtitle: 'Messages saved with a star in this conversation',
                          onTap: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _isSearchingInChat = true;
                            });
                          },
                        ),
                        const SizedBox(height: 24),

                        // Section 4: Chat Management & Safeguards
                        _buildSectionHeader('Chat Management', Icons.admin_panel_settings_outlined),
                        const SizedBox(height: 10),
                        _buildSettingsTile(
                          icon: Icons.download_rounded,
                          iconColor: AppColors.brandBlue,
                          title: 'Export Chat Transcript',
                          titleColor: context.textPrimary,
                          subtitle: 'Copy formatted conversation history to clipboard',
                          onTap: () => _exportChatTranscript(ctx, name),
                        ),
                        const SizedBox(height: 8),
                        _buildSettingsTile(
                          icon: Icons.delete_sweep_rounded,
                          iconColor: AppColors.brandPink,
                          title: 'Clear Chat History',
                          titleColor: AppColors.brandPink,
                          subtitle: 'Permanently remove all messages for this chat',
                          onTap: () => _confirmClearChat(ctx),
                        ),
                        const SizedBox(height: 8),
                        _buildSettingsTile(
                          icon: Icons.block_rounded,
                          iconColor: AppColors.brandPink,
                          title: 'Block Contact',
                          titleColor: AppColors.brandPink,
                          subtitle: 'Stop receiving messages and calls from this user',
                          onTap: () => _confirmBlockContact(ctx, currentUserId, otherUserId, name),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmClearChat(BuildContext bottomSheetContext) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.border, width: 1),
        ),
        title: Text(
          'Clear Chat History?',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'This will permanently delete all messages in this conversation. This action cannot be undone.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(bottomSheetContext);
              await ref.read(messagingRepositoryProvider).clearChatHistory(widget.chatId);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Chat history cleared'),
                    backgroundColor: context.surfaceMid,
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: Text('Clear All Messages', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmBlockContact(BuildContext bottomSheetContext, String currentUserId, String otherUserId, String otherUserName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: context.border, width: 1),
        ),
        title: Text(
          'Block $otherUserName?',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'You will no longer receive messages or calls from $otherUserName. They will not be notified that you blocked them.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 13, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textMuted, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(bottomSheetContext);
              try {
                await ref.read(relationshipRepositoryProvider).blockUser(currentUserId, otherUserId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$otherUserName has been blocked'),
                      backgroundColor: context.surfaceMid,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error blocking user: $e')),
                  );
                }
              }
            },
            child: Text('Block User', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDisappearingMessagesTile(BuildContext context, int currentSecs, void Function(void Function()) setModalState) {
    String durationLabel = 'Off';
    if (currentSecs == 86400) durationLabel = '24 Hours';
    if (currentSecs == 604800) durationLabel = '7 Days';
    if (currentSecs == 7776000) durationLabel = '90 Days';

    return _buildSettingsTile(
      icon: Icons.timer_outlined,
      iconColor: AppColors.brandPink,
      title: 'Disappearing Messages',
      subtitle: 'Automatically delete new messages after timer',
      trailingText: durationLabel,
      onTap: () {
        _showDisappearingMessagesPicker(context, currentSecs, (newSecs) {
          setModalState(() {});
        });
      },
    );
  }

  void _showDisappearingMessagesPicker(BuildContext context, int currentSecs, Function(int) onSelected) {
    final options = [
      {'label': 'Off', 'seconds': 0},
      {'label': '24 Hours', 'seconds': 86400},
      {'label': '7 Days', 'seconds': 604800},
      {'label': '90 Days', 'seconds': 7776000},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: context.border, width: 1)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Disappearing Messages Timer',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'When enabled, new messages sent in this conversation disappear after the selected duration.',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 16),
              ...options.map((opt) {
                final label = opt['label'] as String;
                final secs = opt['seconds'] as int;
                final isSelected = currentSecs == secs;

                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    label,
                    style: GoogleFonts.inter(
                      color: isSelected ? AppColors.brandPink : context.textPrimary,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle_rounded, color: AppColors.brandPink, size: 20)
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    final messenger = ScaffoldMessenger.of(context);
                    final bg = context.surfaceMid;
                    await ref.read(messagingRepositoryProvider).setDisappearingDuration(widget.chatId, secs);
                    onSelected(secs);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Disappearing messages set to: $label'),
                          backgroundColor: bg,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDensitySelector(void Function(void Function()) setModalState) {
    final options = [
      {'label': 'Compact', 'size': 12.0, 'desc': '12px High Density'},
      {'label': 'Classic', 'size': 13.0, 'desc': '13px Executive'},
      {'label': 'Spacious', 'size': 14.5, 'desc': '14.5px Comfort'},
    ];
    return Row(
      children: options.map((opt) {
        final size = opt['size'] as double;
        final isSelected = (_bubbleFontSize - size).abs() < 0.1;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              _saveTextSizePreference(size);
              setModalState(() {});
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.25) : context.surfaceMid,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? AppColors.brandBlue : context.border,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    opt['label'] as String,
                    style: GoogleFonts.inter(
                      color: isSelected ? context.textPrimary : context.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    opt['desc'] as String,
                    style: GoogleFonts.inter(
                      color: isSelected ? AppColors.brandPink : context.textMuted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSoundSelectorTile(BuildContext context, void Function(void Function()) setModalState) {
    String soundLabel = 'Oneova Chime';
    if (_chatSoundTone == 'pink_pulse') soundLabel = 'Pink Pulse';
    if (_chatSoundTone == 'cyber_ping') soundLabel = 'Cyber Ping';
    if (_chatSoundTone == 'executive_pop') soundLabel = 'Executive Pop';
    if (_chatSoundTone == 'silent') soundLabel = 'Silent';

    return _buildSettingsTile(
      icon: Icons.notifications_none_rounded,
      iconColor: AppColors.brandBlue,
      title: 'Notification Tone',
      subtitle: 'Custom alert sound for this chat',
      trailingText: soundLabel,
      onTap: () {
        _showSoundPicker(context, (newTone) {
          setModalState(() {});
        });
      },
    );
  }

  void _showSoundPicker(BuildContext context, Function(String) onSelected) {
    final sounds = [
      {'key': 'default_chime', 'name': 'Oneova Chime (Default)', 'icon': Icons.music_note_rounded},
      {'key': 'pink_pulse', 'name': 'Pink Pulse Aura', 'icon': Icons.graphic_eq_rounded},
      {'key': 'cyber_ping', 'name': 'Cyber Ping', 'icon': Icons.bolt_rounded},
      {'key': 'executive_pop', 'name': 'Executive Pop', 'icon': Icons.touch_app_rounded},
      {'key': 'silent', 'name': 'Mute / Silent', 'icon': Icons.volume_off_rounded},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setSheetState) {
            return Container(
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(top: BorderSide(color: context.border, width: 1)),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chat Notification Sound',
                    style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Choose the audio tone triggered when new messages arrive from this contact.',
                    style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5),
                  ),
                  const SizedBox(height: 16),
                  ...sounds.map((snd) {
                    final key = snd['key'] as String;
                    final name = snd['name'] as String;
                    final icon = snd['icon'] as IconData;
                    final isSelected = _chatSoundTone == key;

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      leading: Icon(icon, color: isSelected ? AppColors.brandPink : context.textSecondary, size: 20),
                      title: Text(
                        name,
                        style: GoogleFonts.inter(
                          color: isSelected ? context.textPrimary : context.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13.5,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle_rounded, color: AppColors.brandPink, size: 20)
                          : null,
                      onTap: () {
                        _saveSoundPreference(key);
                        onSelected(key);
                        setSheetState(() {});
                      },
                    );
                  }),
                  const SizedBox(height: 12),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _exportChatTranscript(BuildContext sheetCtx, String contactName) async {
    Navigator.pop(sheetCtx);
    try {
      final messages = await ref.read(messagingRepositoryProvider).getChatMessages(widget.chatId).first;
      final buffer = StringBuffer();
      buffer.writeln('=== Oneova Chat Export (decrypted copy) ===');
      buffer.writeln('Conversation with: $contactName');
      buffer.writeln('Chat ID: ${widget.chatId}');
      buffer.writeln('Export Date: ${DateTime.now().toLocal()}');
      buffer.writeln('--------------------------------------------\n');
      for (var m in messages.reversed) {
        final time = m.timestamp.toDate().toLocal().toString().substring(0, 16);
        final sender = m.senderId == FirebaseAuth.instance.currentUser?.uid ? 'You' : contactName;
        final text = _getDisplayText(m);
        buffer.writeln('[$time] $sender: $text');
      }
      await Clipboard.setData(ClipboardData(text: buffer.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat transcript copied to clipboard'),
            backgroundColor: AppColors.brandBlue,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export chat: $e')),
        );
      }
    }
  }

  Widget _buildOneovaShieldCard(BuildContext context) {
    final e2ee = ref.read(e2eEncryptionServiceProvider);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'user';
    final safetyNumber = (_myPublicKey != null && _chatPartnerPublicKey != null)
        ? e2ee.generateSafetyNumber(_myPublicKey!, _chatPartnerPublicKey!)
        : e2ee.generateSafetyNumber(widget.chatId, currentUserId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: AppColors.brandBlue, size: 18),
              const SizedBox(width: 8),
              Text(
                'Oneova Shield E2EE',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5), width: 0.8),
                ),
                child: Text(
                  _e2eeActive ? 'ACTIVE' : 'OFF',
                  style: GoogleFonts.inter(
                    color: AppColors.brandPink,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _shieldSummary,
            style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12, height: 1.35),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.border),
                  ),
                  child: Text(
                    safetyNumber.length > 24 ? '${safetyNumber.substring(0, 23)}...' : safetyNumber,
                    style: TextStyle(
                      color: context.textSecondary,
                      fontFamily: 'monospace',
                      fontSize: 11,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _showOneovaShieldSheet(context),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Verify',
                    style: GoogleFonts.inter(
                      color: AppColors.brandBlue,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isActive ? AppColors.brandPink : context.surfaceMid,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? AppColors.brandPink : context.border,
                width: 1,
              ),
            ),
            child: Icon(
              icon,
              color: isActive ? context.textPrimary : context.textSecondary,
              size: 20,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isActive ? AppColors.brandPink : context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.brandBlue, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    Color? titleColor,
    required String subtitle,
    String? trailingText,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? context.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      color: titleColor ?? context.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            if (trailingText != null) ...[
              Text(
                trailingText,
                style: GoogleFonts.inter(
                  color: AppColors.brandPink,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  void _showOneovaShieldSheet(BuildContext context) {
    final e2ee = ref.read(e2eEncryptionServiceProvider);
    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? 'user';
    final safetyNumber = (_myPublicKey != null && _chatPartnerPublicKey != null)
        ? e2ee.generateSafetyNumber(_myPublicKey!, _chatPartnerPublicKey!)
        : e2ee.generateSafetyNumber(widget.chatId, currentUserId);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandBlue, width: 2),
                  ),
                  child: const Icon(Icons.verified_user_rounded, color: AppColors.brandBlue, size: 36),
                ),
                const SizedBox(height: 16),
                Text(
                  'Oneova Shield',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _e2eeActive ? 'End-to-end encryption on' : 'Not end-to-end encrypted',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brandPink,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_rounded, color: AppColors.brandBlue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _e2eeActive ? 'X25519 + AES-256-GCM' : 'Encrypted in transit and at rest',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _shieldDetail,
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 12,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      const Icon(Icons.fingerprint, color: AppColors.brandPink, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Safety Number / Chat Fingerprint',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Compare these safety numbers with your contact to verify cryptographic integrity.',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
                  ),
                  child: Center(
                    child: SelectableText(
                      safetyNumber,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Safety Number', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: safetyNumber));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Safety number copied to clipboard')),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Honest one-line description of what Oneova Shield covers in this chat.
  String get _shieldSummary => _e2eeActive
      ? '🔒 Messages, photos, videos and voice notes in this chat are end-to-end encrypted with Oneova Shield. Calls add frame encryption on top of DTLS-SRTP.'
      : _isSharedChat
          ? '🔒 Group chats are encrypted in transit (TLS) and at rest, but are not end-to-end encrypted yet.'
          : '🔒 End-to-end encryption starts once both of you have opened Oneova on an up-to-date app. Until then messages are encrypted in transit and at rest.';

  String get _shieldDetail => _e2eeActive
      ? 'Text and media are encrypted on your phone with a key only you and your contact share (X25519 + AES-256-GCM). Oneova stores ciphertext only. Not covered: shared locations, file names, and who you talk to and when.'
      : 'This chat is protected by TLS in transit and Google Cloud encryption at rest. Oneova servers can technically access it.';

  Widget _buildSecurityBanner() {
    return Center(
      child: GestureDetector(
        onTap: () => _showOneovaShieldSheet(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: context.surfaceMid.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.lock_rounded, color: AppColors.brandBlue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _shieldSummary,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList(AsyncValue<List<MessageModel>> messagesAsync, String currentUserId) {
    return messagesAsync.when(
      data: (allMessages) {
        final prefs = ref.watch(chatPrefsProvider((uid: currentUserId, chatId: widget.chatId))).value ?? const ChatPrefs();
        _lastMessages = allMessages;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _decryptPendingMessages(allMessages);
          if (mounted) _runAiAssist(allMessages, prefs);
        });
        // Merge optimistic local voice notes until their Firestore counterpart arrives.
        final remoteFileNames = <String>{
          for (final m in allMessages)
            if (m.fileName != null && m.fileName!.isNotEmpty) m.fileName!,
        };
        final activeOptimistic = _pendingLocalMessages
            .where((p) => p.fileName == null || !remoteFileNames.contains(p.fileName))
            .toList();
        final combinedMessages = activeOptimistic.isEmpty
            ? allMessages
            : <MessageModel>[...activeOptimistic, ...allMessages];

        // "Delete for me" hides a message on this account only.
        final messages = prefs.hidden.isEmpty
            ? combinedMessages
            : combinedMessages.where((m) => !prefs.hidden.contains(m.id)).toList();
        if (!_awayFromBottom && messages.isNotEmpty) _latestSeenId = messages.first.id;

        // Filter messages if search query is active
        final isSearching = _inChatSearchQuery.isNotEmpty;
        final displayMessages = isSearching
            ? messages.where((m) {
                final text = _getDisplayText(m).toLowerCase();
                final fileName = (m.fileName ?? '').toLowerCase();
                final mediaType = (m.mediaType ?? '').toLowerCase();
                return text.contains(_inChatSearchQuery) ||
                    fileName.contains(_inChatSearchQuery) ||
                    mediaType.contains(_inChatSearchQuery);
              }).toList()
            : messages;

        if (displayMessages.isEmpty) {
          if (isSearching) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.search_off_rounded, color: AppColors.brandPink, size: 36),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No messages found',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No results for "$_inChatSearchQuery" in this chat',
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSecurityBanner(),
                const SizedBox(height: 16),
                Text('Say hello!', style: TextStyle(color: context.textMuted)),
              ],
            ),
          );
        }
        
        return Column(
          children: [
            if (isSearching)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.15),
                  border: Border(
                    bottom: BorderSide(
                      color: AppColors.brandBlue.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.manage_search_rounded, color: AppColors.brandPink, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${displayMessages.length} message${displayMessages.length == 1 ? '' : 's'} matching "$_inChatSearchQuery"',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Stack(
                children: [
              ListView.builder(
                controller: _listController,
                reverse: true,
                padding: const EdgeInsets.only(top: 48, bottom: 16),
                itemCount: displayMessages.length,
                itemBuilder: (context, index) {
                  final message = displayMessages[index];
                  final day = message.timestamp.toDate();
                  final olderDay = index + 1 < displayMessages.length
                      ? displayMessages[index + 1].timestamp.toDate()
                      : null;
                  final startsDay = olderDay == null ||
                      olderDay.year != day.year ||
                      olderDay.month != day.month ||
                      olderDay.day != day.day;
                  final highlighted = _isHighlighted(message, prefs);
                  final isMe = message.senderId == currentUserId;
                  final timeStr = "${message.timestamp.toDate().hour.toString().padLeft(2, '0')}:${message.timestamp.toDate().minute.toString().padLeft(2, '0')}";
                  final MessageModel? repliedMsg = message.replyToMessageId != null
                      ? messages.where((m) => m.id == message.replyToMessageId).firstOrNull
                      : null;
                  final displayText = _getDisplayText(message);

                  final bubble = Dismissible(
                    key: ValueKey('swipe_msg_${message.id}'),
                    direction: DismissDirection.startToEnd,
                    confirmDismiss: (direction) async {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _replyingTo = message.copyWith(text: displayText);
                      });
                      return false;
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.brandPink, width: 1.2),
                        ),
                        child: const Icon(Icons.reply_rounded, color: AppColors.brandPink, size: 16),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 3.5),
                    child: GestureDetector(
                      onDoubleTap: () {
                        HapticFeedback.lightImpact();
                        final currentUserId = FirebaseAuth.instance.currentUser?.uid;
                        if (currentUserId != null) {
                          ref.read(messagingRepositoryProvider).addReaction(widget.chatId, message.id, currentUserId, '❤️');
                        }
                      },
                      onLongPress: () => _showMessageActions(message, isMe),
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe) ...[
                            CircleAvatar(
                              radius: 13,
                              backgroundColor: context.surfaceMid,
                              child: Text(
                                message.senderId.isNotEmpty ? message.senderId[0].toUpperCase() : '?',
                                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 7),
                          ],
                          Flexible(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.76,
                              ),
                              child: Container(
                                padding: message.mediaType == 'audio' && displayText.isEmpty
                                    ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5.0)
                                    : const EdgeInsets.symmetric(horizontal: 13, vertical: 8.0),
                                decoration: BoxDecoration(
                                  color: isMe ? AppColors.brandBlue : context.surface,
                                  border: isMe
                                      ? null
                                      : Border.all(color: context.border, width: 1.0),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(message.mediaType == 'audio' ? 14 : 16),
                                    topRight: Radius.circular(message.mediaType == 'audio' ? 14 : 16),
                                    bottomLeft: isMe
                                        ? Radius.circular(message.mediaType == 'audio' ? 14 : 16)
                                        : const Radius.circular(3),
                                    bottomRight: isMe
                                        ? const Radius.circular(3)
                                        : Radius.circular(message.mediaType == 'audio' ? 14 : 16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isMe ? 0.25 : 0.08),
                                      blurRadius: 4,
                                      offset: const Offset(0, 1.5),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (repliedMsg != null)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: isMe ? Colors.black.withValues(alpha: 0.22) : context.surfaceMid,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border(
                                            left: BorderSide(
                                              color: isMe ? Colors.white : AppColors.brandPink,
                                              width: 2.5,
                                            ),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              repliedMsg.senderId == currentUserId ? 'You' : 'Replying',
                                              style: GoogleFonts.inter(
                                                color: isMe ? Colors.white : AppColors.brandPink,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 1),
                                            Text(
                                              _getDisplayText(repliedMsg),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.inter(
                                                color: isMe ? Colors.white70 : context.textSecondary,
                                                fontSize: 11.5,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (message.forwarded)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 3),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(Icons.shortcut_rounded, size: 11, color: isMe ? Colors.white70 : context.textMuted),
                                          const SizedBox(width: 3),
                                          Text('Forwarded',
                                              style: GoogleFonts.inter(
                                                color: isMe ? Colors.white70 : context.textMuted,
                                                fontSize: 10.5,
                                                fontStyle: FontStyle.italic,
                                              )),
                                        ]),
                                      ),
                                    if (message.mediaUrl != null && message.mediaType != null)
                                      _buildMediaAttachment(message, isMe: isMe, prefs: prefs),
                                    if (displayText.isNotEmpty)
                                      Text(
                                        displayText,
                                        style: GoogleFonts.inter(
                                          color: isMe ? Colors.white : context.textPrimary,
                                          fontSize: _bubbleFontSize,
                                          fontWeight: FontWeight.w400,
                                          height: 1.38,
                                          letterSpacing: -0.15,
                                        ),
                                      ),
                                    if (!isMe) _buildTranslation(message, isMe),
                                    _buildLinkPreview(displayText, isMe: isMe, safety: message.safety),
                                    SizedBox(height: message.mediaType == 'audio' && displayText.isEmpty ? 1.5 : 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (highlighted) ...[
                                          const Icon(
                                            Icons.star_rounded,
                                            size: 11,
                                            color: AppColors.brandPink,
                                          ),
                                          const SizedBox(width: 3),
                                        ],
                                        if (message.isEncrypted) ...[
                                          Icon(
                                            Icons.lock_rounded,
                                            size: 10,
                                            color: isMe ? Colors.white60 : context.textMuted,
                                          ),
                                          const SizedBox(width: 3),
                                        ],
                                        Text(
                                          timeStr,
                                          style: GoogleFonts.inter(
                                            color: isMe ? Colors.white70 : context.textMuted,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            message.id.startsWith('local_vn_')
                                                ? Icons.schedule_rounded
                                                : (message.readBy.isNotEmpty
                                                    ? Icons.done_all_rounded
                                                    : Icons.done_rounded),
                                            size: message.id.startsWith('local_vn_') ? 11.5 : 13.0,
                                            color: message.readBy.isNotEmpty
                                                ? AppColors.brandPink
                                                : Colors.white60,
                                          ),
                                        ],
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
                                                color: context.surfaceMid,
                                                borderRadius: BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: AppColors.brandPink.withValues(alpha: 0.3),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Text(e.value, style: const TextStyle(fontSize: 11.5)),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (isMe) const SizedBox(width: 4),
                        ],
                      ),
                    ),
                  ).animate().fade().slideY(begin: 0.08, end: 0),
                );
                  if (!startsDay) return bubble;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [ChatDateSeparator(day: day), bubble],
                  );
                },
              ),
                  // Sticky encryption banner; shrinks to a lock chip on scroll.
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ChatEncryptionBanner(
                        collapsed: _bannerCollapsed,
                        endToEnd: _e2eeActive,
                        text: _bannerText,
                        chipText: _bannerChip,
                        onTap: () => _showOneovaShieldSheet(context),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 12,
                    child: AnimatedScale(
                      scale: _awayFromBottom ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutBack,
                      child: ChatJumpToLatest(unread: _newSinceAway(messages), onTap: _jumpToLatest),
                    ),
                  ),
                ],
              ),
    ),
  ],
);
},
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
      error: (err, stack) => Center(child: Text('Error: $err', style: TextStyle(color: AppColors.brandPink))),
    );
  }

  Widget _buildInputArea() {
    final settingsAsync = ref.watch(settingsProvider);
    final chatSettings = settingsAsync.value?['chat'] as Map<String, dynamic>? ?? {};
    final String voiceMode = chatSettings['voiceRecordMode'] ?? 'hold';
    final bool enterIsSend = chatSettings['enterIsSend'] ?? false;
    final int holdDurationMs = chatSettings['holdDurationMs'] ?? 350;
    final String hapticIntensity = chatSettings['hapticIntensity'] ?? 'medium';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_uploadingFileName != null)
              OneovaInlineStatusBanner(
                title: 'Uploading $_uploadingFileName',
                subtitle: 'Encrypted cloud delivery in progress',
                kind: OneovaStatusKind.uploading,
                progress: _uploadProgress,
                onClose: _confirmCancelActiveUpload,
              ),
            OvaChatSuggestionBar(
              chatId: widget.chatId,
              myUid: FirebaseAuth.instance.currentUser?.uid ?? '',
              textOf: _getDisplayText,
              encryptedChat: _e2eeActive,
              onReply: _insertIntoComposer,
              onAskOva: (prompt) => OneOvaAssistantOverlay.show<void>(context, initialPrompt: prompt),
              onOpenMedia: _openMediaStudio,
            ),
            _buildAiStrip(
              ref.watch(chatPrefsProvider((uid: _myUid, chatId: widget.chatId))).value ?? const ChatPrefs(),
            ),
            if (_replyingTo != null)
              Container(
                margin: const EdgeInsets.only(bottom: 8, left: 40, right: 40),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(12),
                  border: const Border(left: BorderSide(color: AppColors.brandBlue, width: 4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Replying to message', style: TextStyle(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                            _replyingTo!.text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: context.textMuted, size: 20),
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
                    color: _showAttachments ? AppColors.brandBlue : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: _showAttachments ? Colors.white : context.textSecondary, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Dedicated, premium Ova AI button in the message composer bar (38px compact with glow)
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
            const SizedBox(width: 6),
            Expanded(
              child: _isRecordingVoice
                  ? _buildVoiceRecordingStrip()
                  : Container(
                      constraints: const BoxConstraints(maxHeight: 120),
                      padding: const EdgeInsets.only(left: 8, right: 16),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: TextField(
                        controller: _messageController,
                        focusNode: _composerFocus,
                        onTap: () {
                          if (_showEmojiPanel) setState(() => _showEmojiPanel = false);
                        },
                        style: TextStyle(color: context.textPrimary),
                        maxLines: enterIsSend ? 1 : null,
                        keyboardType: enterIsSend ? TextInputType.text : TextInputType.multiline,
                        textInputAction: enterIsSend ? TextInputAction.send : TextInputAction.newline,
                        onSubmitted: enterIsSend ? (_) => _sendMessage() : null,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(color: context.textMuted),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          prefixIcon: GestureDetector(
                            onTap: _toggleEmojiPanel,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                _showEmojiPanel ? Icons.keyboard_rounded : Icons.emoji_emotions_outlined,
                                size: 22,
                                color: _showEmojiPanel ? AppColors.brandBlue : context.textSecondary,
                              ),
                            ),
                          ),
                          suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          suffixIcon: OneovaVoiceTypingButton(
                            controller: _messageController,
                            onChanged: (_) {
                              setState(() {
                                _isTyping = _messageController.text.trim().isNotEmpty;
                              });
                            },
                            tooltip: 'Voice typing message',
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            showTranslateAction: true,
                          ),
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
                      decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle),
                      child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ).animate().scale(duration: 200.ms),
                  )
                : _isRecordingVoice && _voiceLocked
                    ? GestureDetector(
                        onTap: () {
                          OneOvaSoundService.playHaptic(hapticIntensity);
                          _stopRecordingAndSend();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle),
                          child: const Icon(Icons.send_rounded, color: AppColors.brandWhite, size: 20),
                        ).animate().scale(duration: 200.ms),
                      )
                : _videoNoteMode
                    ? _buildVideoNoteButton()
                    : voiceMode == 'hold'
                    ? Listener(
                        onPointerDown: (e) {
                          if (_isRecordingVoice) return;
                          _voiceHoldOrigin = e.position;
                          _micHoldTimer?.cancel();
                          _micHoldTimer = Timer(Duration(milliseconds: holdDurationMs), () {
                            if (mounted) {
                              OneOvaSoundService.playHaptic(hapticIntensity);
                              _startRecording();
                            }
                          });
                        },
                        onPointerMove: (e) {
                          final origin = _voiceHoldOrigin;
                          if (!_isRecordingVoice || _voiceLocked || origin == null) return;
                          final d = e.position - origin;
                          if (d.dx < -120) {
                            _voiceHoldOrigin = null;
                            _cancelRecording();
                            return;
                          }
                          if (d.dy < -90) {
                            HapticFeedback.heavyImpact();
                            setState(() {
                              _voiceLocked = true;
                              _voiceSlide = Offset.zero;
                            });
                            return;
                          }
                          setState(() => _voiceSlide = d);
                        },
                        onPointerUp: (_) {
                          _voiceHoldOrigin = null;
                          if (_voiceLocked) return; // keeps recording; send from the strip
                          if (_micHoldTimer?.isActive == true) {
                            _micHoldTimer?.cancel();
                            // Quick tap switches between voice and video messages.
                            if (!_isRecordingVoice) _toggleRecordMode();
                          } else if (_isRecordingVoice) {
                            OneOvaSoundService.playHaptic(hapticIntensity);
                            _stopRecordingAndSend();
                          }
                        },
                        onPointerCancel: (_) {
                          _micHoldTimer?.cancel();
                          if (_isRecordingVoice && !_voiceLocked) {
                            _cancelRecording();
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isRecordingVoice ? AppColors.brandPink : context.surfaceMid,
                            shape: BoxShape.circle,
                            boxShadow: _isRecordingVoice
                                ? [
                                    BoxShadow(
                                      color: AppColors.brandPink.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                            color: _isRecordingVoice ? Colors.white : context.textPrimary,
                            size: 20
                          ),
                        ).animate().scale(duration: 200.ms),
                      )
                    : GestureDetector(
                        onTap: () {
                          OneOvaSoundService.playHaptic(hapticIntensity);
                          _toggleRecording();
                        },
                        onLongPress: _isRecordingVoice ? null : _toggleRecordMode,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _isRecordingVoice ? AppColors.brandPink : context.surfaceMid,
                            shape: BoxShape.circle,
                            boxShadow: _isRecordingVoice
                                ? [
                                    BoxShadow(
                                      color: AppColors.brandPink.withValues(alpha: 0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    )
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _isRecordingVoice ? Icons.stop_rounded : Icons.mic_rounded,
                            color: _isRecordingVoice ? Colors.white : context.textPrimary,
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

  /// Live voice-recording strip: pulsing dot, timer and a scrolling waveform
  /// from the mic. While holding: slide left to cancel, up to lock. Locked:
  /// delete, pause/resume, and the mic turns into Send.
  Widget _buildVoiceRecordingStrip() {
    final secs = _recordingDurationSeconds;
    final time = '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}';
    final cancelHint = (-_voiceSlide.dx / 120).clamp(0.0, 1.0);
    final lockHint = (-_voiceSlide.dy / 90).clamp(0.0, 1.0);
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: Color.lerp(context.surfaceMid, AppColors.brandPink.withValues(alpha: 0.18), cancelHint),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _voiceLocked ? AppColors.brandBlue.withValues(alpha: 0.6) : AppColors.brandPink.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          if (_voiceLocked)
            GestureDetector(
              onTap: _cancelRecording,
              child: const Padding(
                padding: EdgeInsets.all(3),
                child: Icon(Icons.delete_outline_rounded, color: AppColors.brandPink, size: 18),
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.55), blurRadius: 4)],
              ),
            ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeOut(duration: 600.ms, begin: 1),
          const SizedBox(width: 4),
          Text(
            time,
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Opacity(
              opacity: 1 - cancelHint * 0.7,
              child: LiveRecordingWaveform(levels: _liveLevels, paused: _voicePaused, height: 18),
            ),
          ),
          const SizedBox(width: 6),
          if (_voiceLocked)
            GestureDetector(
              onTap: _toggleVoicePause,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(_voicePaused ? Icons.mic_rounded : Icons.pause_rounded,
                    color: AppColors.brandPink, size: 16),
              ),
            )
          else
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline_rounded,
                    size: 13, color: Color.lerp(context.textMuted, AppColors.brandBlue, lockHint)),
                Text(
                  cancelHint > 0.15 ? '‹ cancel' : '↑ lock',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
                    color: cancelHint > 0.15 ? AppColors.brandPink : context.textMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Camera button in video-message mode: hold to record a round video,
  /// slide up to lock, slide left to cancel, tap to switch back to voice.
  Widget _buildVideoNoteButton() {
    Offset? origin;
    return GestureDetector(
      onTap: _toggleRecordMode,
      onLongPressStart: (d) {
        origin = d.globalPosition;
        HapticFeedback.mediumImpact();
        _startVideoNote(d.globalPosition);
      },
      onLongPressMoveUpdate: (d) {
        if (origin != null) _videoSession?.drag(d.globalPosition - origin!);
      },
      onLongPressEnd: (_) => _videoSession?.release(),
      onLongPressCancel: () => _videoSession?.release(),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: context.surfaceMid, shape: BoxShape.circle),
        child: Icon(Icons.radio_button_checked_rounded, color: AppColors.brandPink, size: 20),
      ).animate().scale(duration: 200.ms),
    );
  }

  Widget _buildAttachmentDrawer() {
    final options = <(IconData, String, Color, VoidCallback)>[
      (Icons.image_outlined, 'Gallery', AppColors.brandBlue, () => _pickImage(ImageSource.gallery)),
      (Icons.photo_camera_outlined, 'Camera', AppColors.brandBlue, () => _pickImage(ImageSource.camera)),
      (Icons.videocam_outlined, 'Video', AppColors.brandPink, _pickVideo),
      (Icons.headphones_outlined, 'Audio', AppColors.brandPink, _pickAudioFile),
      (Icons.description_outlined, 'Document', AppColors.brandBlue, _pickDocument),
      (Icons.table_chart_outlined, 'Sheet', AppColors.brandBlue, _pickSpreadsheetFile),
      (Icons.code_rounded, 'Code', AppColors.brandBlue, _pickCodeFile),
      (Icons.folder_zip_outlined, 'Archive', AppColors.brandPink, _pickArchiveFile),
      (Icons.location_on_outlined, 'Location', AppColors.brandPink, _shareLocation),
    ];
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 8,
        childAspectRatio: 0.95,
        children: [
          for (var i = 0; i < options.length; i++)
            _buildAttachOption(options[i].$1, options[i].$2, options[i].$3, onTap: options[i].$4)
                .animate()
                .fadeIn(duration: 200.ms, delay: (i * 20).ms)
                .slideY(begin: 0.1, end: 0),
        ],
      ),
    );
  }

  Widget _buildAttachOption(IconData icon, String label, Color color, {required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: color.withValues(alpha: 0.25), width: 1.0),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
