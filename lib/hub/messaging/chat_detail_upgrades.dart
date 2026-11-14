part of 'chat_detail_screen.dart';

/// Message actions, highlights, forwarding, scroll helpers and the per-chat
/// AI assist for [ChatDetailScreen].
extension _ChatUpgrades on _ChatDetailScreenState {
  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  ChatPrefs get _prefs =>
      ref.read(chatPrefsProvider((uid: _myUid, chatId: widget.chatId))).value ?? const ChatPrefs();

  bool _isHighlighted(MessageModel m, ChatPrefs prefs) => prefs.highlights.containsKey(m.id) || m.isStarred;

  // ── Scrolling ──────────────────────────────────────────────────────────

  void _onListScroll() {
    if (!_listController.hasClients) return;
    final offset = _listController.offset;
    final collapsed = offset > 24;
    final away = offset > 320;
    if (collapsed != _bannerCollapsed || away != _awayFromBottom) {
      _refresh(() {
        _bannerCollapsed = collapsed;
        _awayFromBottom = away;
      });
    }
  }

  void _jumpToLatest() {
    if (!_listController.hasClients) return;
    HapticFeedback.selectionClick();
    _listController.animateTo(0, duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
  }

  /// Messages from others that arrived after you scrolled up.
  int _newSinceAway(List<MessageModel> list) {
    if (!_awayFromBottom || _latestSeenId == null) return 0;
    var n = 0;
    for (final m in list) {
      if (m.id == _latestSeenId) return n;
      if (m.senderId != _myUid) n++;
    }
    return 0;
  }

  String get _bannerText => _e2eeActive
      ? 'Messages and calls are end-to-end encrypted. Tap to learn more.'
      : _isSharedChat
          ? 'Group chats are encrypted in transit and at rest, not end-to-end yet.'
          : 'End-to-end encryption starts once you both use the latest Oneova.';

  String get _bannerChip => _e2eeActive
      ? 'End-to-end encrypted'
      : _isSharedChat
          ? 'Encrypted in transit'
          : 'E2EE pending';

  // ── Message actions ────────────────────────────────────────────────────

  void _showMessageActions(MessageModel message, bool isMe) {
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    final prefs = _prefs;
    final highlighted = _isHighlighted(message, prefs);
    final text = _getDisplayText(message);
    final hasText = text.isNotEmpty && (!message.isEncrypted || _decryptedCache.containsKey(message.id));
    final translation = _translations[message.id];

    Widget tile(IconData icon, String label, VoidCallback onTap, {Color? color, String? hint}) {
      final c = color ?? context.textPrimary;
      return ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon, color: color ?? AppColors.brandBlue, size: 20),
        title: Text(label, style: GoogleFonts.inter(color: c, fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: hint == null
            ? null
            : Text(hint, style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
        onTap: () {
          Navigator.pop(context);
          onTap();
        },
      );
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return Container(
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: context.border),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: ['👍', '❤️', '😂', '😮', '😢', '🔥', '🙏'].map((emoji) {
                        final mine = message.reactions?[_myUid] == emoji;
                        return GestureDetector(
                          onTap: () {
                            if (_myUid.isNotEmpty) {
                              ref.read(messagingRepositoryProvider).addReaction(widget.chatId, message.id, _myUid, emoji);
                            }
                            Navigator.pop(sheetCtx);
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: mine ? AppColors.brandPink.withValues(alpha: 0.18) : null,
                            ),
                            child: Text(emoji, style: const TextStyle(fontSize: 24)),
                          ),
                        ).animate().scale(duration: 180.ms);
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  tile(Icons.reply_rounded, 'Reply', () {
                    _refresh(() => _replyingTo = message.copyWith(text: text));
                    _composerFocus.requestFocus();
                  }),
                  if (hasText)
                    tile(Icons.copy_rounded, 'Copy text', () {
                      Clipboard.setData(ClipboardData(text: text));
                      _toast('Copied');
                    }),
                  if (hasText && !isMe)
                    translation != null && !translation.same
                        ? tile(Icons.translate_rounded, _hiddenTranslations.contains(message.id) ? 'Show translation' : 'Hide translation', () {
                            _refresh(() {
                              if (!_hiddenTranslations.remove(message.id)) _hiddenTranslations.add(message.id);
                            });
                          })
                        : tile(Icons.translate_rounded, 'Translate', () => _translateOne(message),
                            hint: prefs.aiEnabled ? null : 'Sends this message to Oneova AI'),
                  if (message.mediaType == 'audio')
                    tile(
                      Icons.record_voice_over_rounded,
                      'Translate in speaker voice',
                      () => VoiceAudioDiskCache.requestTranslate(message.id),
                      hint: prefs.aiEnabled ? null : 'Translates & speaks in speaker voice',
                    ),
                  tile(
                    highlighted ? Icons.star_rounded : Icons.star_outline_rounded,
                    highlighted ? 'Remove highlight' : 'Highlight',
                    () => _toggleHighlight(message, highlighted),
                    color: highlighted ? AppColors.brandPink : null,
                  ),
                  tile(Icons.shortcut_rounded, 'Forward', () => _forwardMessage(message)),
                  tile(Icons.visibility_off_outlined, 'Delete for me', () => _deleteForMe(message)),
                  if (isMe)
                    tile(Icons.delete_outline_rounded, 'Unsend for everyone', () => _confirmDeleteMessage(message),
                        color: AppColors.brandPink),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  Future<void> _toggleHighlight(MessageModel message, bool highlighted) async {
    if (_myUid.isEmpty) return;
    HapticFeedback.selectionClick();
    try {
      await ref.read(chatAssistServiceProvider).setHighlight(_myUid, widget.chatId, message.id, !highlighted);
      // Older chats starred messages on the shared doc; clear that too.
      if (highlighted && message.isStarred) {
        await ref.read(messagingRepositoryProvider).toggleMessageStarred(widget.chatId, message.id, false);
      }
      _toast(highlighted ? 'Highlight removed' : 'Added to Highlights');
    } catch (_) {
      _toast("Couldn't update highlights.");
    }
  }

  Future<void> _deleteForMe(MessageModel message) async {
    if (_myUid.isEmpty) return;
    try {
      await ref.read(chatAssistServiceProvider).hideForMe(_myUid, widget.chatId, message.id);
      _toast('Deleted for you');
    } catch (_) {
      _toast("Couldn't delete this message.");
    }
  }

  Future<void> _forwardMessage(MessageModel message) async {
    if (_myUid.isEmpty) return;
    if (message.mediaEncrypted) {
      _toast("End-to-end encrypted media can't be forwarded yet. Save it and share it instead.");
      return;
    }
    final text = message.isEncrypted ? (_decryptedCache[message.id] ?? '') : message.text;
    if (message.isEncrypted && text.isEmpty) {
      _toast('Still decrypting this message.');
      return;
    }
    final target = await showModalBottomSheet<ChatModel>(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => _ForwardPicker(myUid: _myUid, excludeChatId: widget.chatId),
    );
    if (target == null || !mounted) return;
    try {
      await ref.read(messagingRepositoryProvider).sendMessage(
            target.id,
            _myUid,
            text,
            mediaUrl: message.mediaUrl,
            mediaType: message.mediaType,
            fileName: message.fileName,
            mimeType: message.mimeType,
            fileSize: message.fileSize,
            voiceDuration: message.voiceDuration,
            voiceWaveform: message.voiceWaveform,
            location: message.mediaType == 'location' ? message.location : null,
            forwarded: true,
          );
      _toast('Forwarded to ${target.title?.isNotEmpty == true ? target.title : 'chat'}');
    } catch (_) {
      _toast("Couldn't forward this message.");
    }
  }

  /// Opens or shares a file: encrypted ones are decrypted on the phone first.
  Future<void> _saveFile(MessageModel message) async {
    final url = message.mediaUrl;
    if (url == null) return;
    try {
      if (url.startsWith('/')) {
        await SharePlus.instance.share(ShareParams(files: [XFile(url, name: message.fileName)]));
      } else if (message.mediaEncrypted) {
        final key = _chatPartnerPublicKey;
        if (key == null) return;
        final file = await PeerMediaCrypto.decryptToCache(
          ref.read(e2eEncryptionServiceProvider),
          url,
          key,
          fileName: message.fileName,
        );
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path, name: message.fileName)]));
      } else {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      _toast("Couldn't open this file.");
    }
  }

  // ── Highlights ─────────────────────────────────────────────────────────

  void _showHighlights() {
    final prefs = _prefs;
    final items = _lastMessages.where((m) => _isHighlighted(m, prefs)).toList()
      ..sort((a, b) {
        final ta = prefs.highlights[a.id] ?? a.timestamp;
        final tb = prefs.highlights[b.id] ?? b.timestamp;
        return tb.compareTo(ta);
      });
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.9,
        builder: (ctx, scroll) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Row(children: [
                const Icon(Icons.star_rounded, color: AppColors.brandPink, size: 18),
                const SizedBox(width: 8),
                Text('Highlights',
                    style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Text('${items.length}', style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 12.5)),
                const Spacer(),
                Text('Only you see these', style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11)),
              ]),
            ),
            Divider(height: 1, color: ctx.border),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Long-press a message and tap Highlight to keep it here.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 12.5),
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scroll,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(height: 1, indent: 16, color: ctx.border),
                      itemBuilder: (ctx, i) {
                        final m = items[i];
                        final isMe = m.senderId == _myUid;
                        final t = _getDisplayText(m);
                        final d = m.timestamp.toDate();
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            m.mediaType == null ? Icons.chat_bubble_outline_rounded : chatFileKind(m.fileName ?? '', m.mediaType).icon,
                            color: AppColors.brandBlue,
                            size: 18,
                          ),
                          title: Text(
                            t.isNotEmpty ? t : (m.fileName ?? m.mediaType ?? 'Attachment'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13),
                          ),
                          subtitle: Text(
                            '${isMe ? 'You' : 'Them'} · ${ChatDateSeparator.label(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                            style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove highlight',
                            icon: Icon(Icons.close_rounded, size: 18, color: ctx.textMuted),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _toggleHighlight(m, true);
                            },
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showMessageActions(m, isMe);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── AI assist (off by default, per chat) ───────────────────────────────

  String get _aiPrivacyNote => _e2eeActive
      ? 'This chat is end-to-end encrypted. AI features send the decrypted text they work on to Oneova AI '
          '(Gemini on Google Cloud Vertex AI), outside the encryption. It is not stored or used to train models.'
      : 'AI features send the text they work on to Oneova AI (Gemini on Google Cloud Vertex AI). '
          'It is not stored or used to train models.';

  Future<bool> _confirmAi({required String title, required String body, required String cta}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border),
        ),
        title: Text(title, style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
        content: Text('$body\n\n$_aiPrivacyNote',
            style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(cta),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _setAiEnabled(bool on) async {
    if (_myUid.isEmpty) return;
    if (on) {
      final ok = await _confirmAi(
        title: 'Turn on AI in this chat?',
        body: 'While AI is on, Oneova suggests replies to new messages, can summarize the conversation and '
            'can translate incoming messages. It only applies to this chat, only you see the results, '
            'and nothing is sent to your contact unless you send it.',
        cta: 'Turn on',
      );
      if (!ok) return;
    }
    try {
      await ref.read(chatAssistServiceProvider).setAi(_myUid, widget.chatId, enabled: on);
      if (!on) {
        _refresh(() {
          _aiReplies = const [];
          _aiRepliesFor = null;
        });
      } else {
        _aiRepliesFor = null;
      }
    } catch (_) {
      _toast("Couldn't change the AI setting.");
    }
  }

  Future<void> _setAutoTranslate(bool on) async {
    if (_myUid.isEmpty) return;
    try {
      await ref.read(chatAssistServiceProvider).setAi(_myUid, widget.chatId, autoTranslate: on);
    } catch (_) {
      _toast("Couldn't change auto-translate.");
    }
  }

  Future<void> _setAutoTranslateVoice(bool on) async {
    if (_myUid.isEmpty) return;
    try {
      await ref.read(chatAssistServiceProvider).setAi(_myUid, widget.chatId, autoTranslateVoice: on);
    } catch (_) {
      _toast("Couldn't change voice note auto-translate.");
    }
  }

  Future<VoiceTranslationResult> _translateVoiceMessage(
    MessageModel message, {
    required String decryptedOrResolvedPath,
  }) async {
    if (!_prefs.aiEnabled) {
      final ok = await _confirmAi(
        title: 'Translate voice note in speaker voice?',
        body: 'Only this voice note is sent to Oneova AI to translate it into your language '
            'and synthesize audio matched to the speaker\'s voice. AI stays off for the rest of this chat.',
        cta: 'Translate',
      );
      if (!ok) {
        throw const ChatAssistException('Voice translation cancelled.');
      }
    }
    return ref.read(chatAssistServiceProvider).translateVoiceNote(
          cacheKey: message.id,
          audioPathOrUrl: decryptedOrResolvedPath,
          senderUid: message.senderId,
        );
  }

  /// Plain text lines for the AI, oldest first, skipping undecrypted ones.
  List<AssistLine> _assistLines(int count) {
    final out = <AssistLine>[];
    for (final m in _lastMessages.take(count).toList().reversed) {
      if (_prefs.hidden.contains(m.id)) continue;
      final t = _getDisplayText(m).trim();
      if (t.isEmpty || (m.isEncrypted && !_decryptedCache.containsKey(m.id))) continue;
      out.add((me: m.senderId == _myUid, text: t));
    }
    return out;
  }

  Future<void> _translateOne(MessageModel message) async {
    if (!_prefs.aiEnabled) {
      final ok = await _confirmAi(
        title: 'Translate this message?',
        body: 'Only this one message is sent to Oneova AI to translate it into your language. '
            'AI stays off for the rest of this chat.',
        cta: 'Translate',
      );
      if (!ok) return;
    }
    final text = _getDisplayText(message);
    _refresh(() => _translating.add(message.id));
    try {
      final res = await ref.read(chatAssistServiceProvider).translate([text]);
      if (!mounted) return;
      _refresh(() {
        _translating.remove(message.id);
        _hiddenTranslations.remove(message.id);
        if (res.isNotEmpty) _translations[message.id] = res.first;
      });
      if (res.isNotEmpty && res.first.same) _toast('Already in your language');
    } catch (e) {
      _refresh(() => _translating.remove(message.id));
      _toast(e is ChatAssistException ? e.message : "Couldn't translate this message.");
    }
  }

  /// Runs after each message update: smart replies and auto-translate, only
  /// when AI is on for this chat.
  void _runAiAssist(List<MessageModel> messages, ChatPrefs prefs) {
    if (!prefs.aiEnabled || messages.isEmpty || _myUid.isEmpty) return;
    final newest = messages.firstWhere((m) => !prefs.hidden.contains(m.id), orElse: () => messages.first);

    final newestText = _getDisplayText(newest).trim();
    final decrypted = !newest.isEncrypted || _decryptedCache.containsKey(newest.id);
    if (newest.senderId == _myUid) {
      if (_aiReplies.isNotEmpty || _aiRepliesFor != newest.id) {
        _refresh(() {
          _aiReplies = const [];
          _aiRepliesFor = newest.id;
        });
      }
    } else if (decrypted && newestText.isNotEmpty && _aiRepliesFor != newest.id && !_aiRepliesLoading) {
      _aiRepliesFor = newest.id;
      _refresh(() => _aiRepliesLoading = true);
      ref.read(chatAssistServiceProvider).smartReplies(_assistLines(12)).then((r) {
        if (!mounted || _aiRepliesFor != newest.id) return;
        _refresh(() => _aiReplies = r);
      }).catchError((_) {}).whenComplete(() {
        if (mounted) _refresh(() => _aiRepliesLoading = false);
      });
    }

    if (prefs.aiAutoTranslate) {
      final todo = messages
          .take(20)
          .where((m) =>
              m.senderId != _myUid &&
              !prefs.hidden.contains(m.id) &&
              !_translations.containsKey(m.id) &&
              !_translating.contains(m.id) &&
              (!m.isEncrypted || _decryptedCache.containsKey(m.id)) &&
              _getDisplayText(m).trim().isNotEmpty)
          .toList();
      if (todo.isEmpty) return;
      _refresh(() => _translating.addAll(todo.map((m) => m.id)));
      // Only messages in a language you don't read go to the AI.
      Future.wait([for (final m in todo) LanguageDetector.instance.foreignLanguageOf(_getDisplayText(m))]).then((codes) {
        final foreign = [for (var i = 0; i < todo.length; i++) if (codes[i] != null) todo[i]];
        for (var i = 0; i < todo.length; i++) {
          if (codes[i] == null) _translations.putIfAbsent(todo[i].id, () => ChatTranslation(_getDisplayText(todo[i]), '', true));
        }
        if (foreign.isEmpty) {
          if (mounted) _refresh(() => _translating.removeAll(todo.map((m) => m.id)));
          return;
        }
        _autoTranslate(foreign);
      });
    }
  }

  void _autoTranslate(List<MessageModel> todo) {
    {
      ref.read(chatAssistServiceProvider).translate([for (final m in todo) _getDisplayText(m)]).then((res) {
        if (!mounted) return;
        _refresh(() {
          for (var i = 0; i < todo.length && i < res.length; i++) {
            _translations[todo[i].id] = res[i];
          }
        });
      }).catchError((_) {
        // Don't retry these on every rebuild; Translate in the menu still works.
        for (final m in todo) {
          _translations.putIfAbsent(m.id, () => ChatTranslation(_getDisplayText(m), '', true));
        }
      }).whenComplete(() {
        if (mounted) _refresh(() => _translating.removeAll(todo.map((m) => m.id)));
      });
    }
  }

  Future<void> _summarizeChat() async {
    final lines = _assistLines(60);
    if (lines.isEmpty) {
      _toast('Nothing to summarize yet.');
      return;
    }
    _refresh(() => _aiSummarizing = true);
    try {
      final s = await ref.read(chatAssistServiceProvider).summarize(lines);
      if (!mounted) return;
      _refresh(() => _aiSummarizing = false);
      _showSummary(s, lines.length);
    } catch (e) {
      _refresh(() => _aiSummarizing = false);
      _toast(e is ChatAssistException ? e.message : "Couldn't summarize this chat.");
    }
  }

  void _showSummary(ChatSummary s, int count) {
    final copy = [
      s.summary,
      if (s.points.isNotEmpty) '\n${s.points.map((p) => '• $p').join('\n')}',
      if (s.todos.isNotEmpty) '\nTo do:\n${s.todos.map((p) => '• $p').join('\n')}',
    ].join('\n');
    Widget section(BuildContext ctx, String title, List<String> items, IconData icon) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
            const SizedBox(height: 4),
            for (final p in items)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 14, color: AppColors.brandBlue),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(p, style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 12.5, height: 1.35))),
                ]),
              ),
          ]),
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 18),
                const SizedBox(width: 8),
                Text('Chat summary',
                    style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy',
                  icon: Icon(Icons.copy_rounded, size: 18, color: ctx.textSecondary),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: copy));
                    Navigator.pop(ctx);
                    _toast('Summary copied');
                  },
                ),
              ]),
              Text('Last $count messages · by Oneova AI · only you see this',
                  style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11)),
              const SizedBox(height: 10),
              Text(s.summary, style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13, height: 1.4)),
              if (s.points.isNotEmpty) section(ctx, 'KEY POINTS', s.points, Icons.circle_outlined),
              if (s.todos.isNotEmpty) section(ctx, 'OPEN ITEMS', s.todos, Icons.check_box_outline_blank_rounded),
            ]),
          ),
        ),
      ),
    );
  }

  void _showAiControls() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => Consumer(builder: (ctx, cref, _) {
        final prefs = cref.watch(chatPrefsProvider((uid: _myUid, chatId: widget.chatId))).value ?? const ChatPrefs();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 18),
                const SizedBox(width: 8),
                Text('AI in this chat',
                    style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              Text(_aiPrivacyNote, style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11.5, height: 1.4)),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeTrackColor: AppColors.brandBlue,
                title: Text('AI assist',
                    style: GoogleFonts.inter(color: ctx.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                subtitle: Text('Smart replies and summaries. Off by default.',
                    style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11)),
                value: prefs.aiEnabled,
                onChanged: (v) => _setAiEnabled(v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeTrackColor: AppColors.brandBlue,
                title: Text('Auto-translate incoming',
                    style: GoogleFonts.inter(
                        color: prefs.aiEnabled ? ctx.textPrimary : ctx.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                subtitle: Text('Into ${ChatAssistService.deviceLanguage()}, shown under each message.',
                    style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11)),
                value: prefs.aiEnabled && prefs.aiAutoTranslate,
                onChanged: prefs.aiEnabled ? (v) => _setAutoTranslate(v) : null,
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeTrackColor: AppColors.brandPink,
                title: Text('Auto-translate voice notes',
                    style: GoogleFonts.inter(
                        color: prefs.aiEnabled ? ctx.textPrimary : ctx.textMuted,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                subtitle: Text(
                    'Translates incoming voice notes into ${ChatAssistService.deviceLanguage()} using the speaker\'s voice.',
                    style: GoogleFonts.inter(color: ctx.textMuted, fontSize: 11)),
                value: prefs.aiEnabled && prefs.aiAutoTranslateVoice,
                onChanged: prefs.aiEnabled ? (v) => _setAutoTranslateVoice(v) : null,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandBlue,
                    side: BorderSide(color: prefs.aiEnabled ? AppColors.brandBlue : ctx.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: prefs.aiEnabled
                      ? () {
                          Navigator.pop(ctx);
                          _summarizeChat();
                        }
                      : null,
                  icon: const Icon(Icons.summarize_outlined, size: 18),
                  label: const Text('Summarize conversation'),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }

  /// Slim strip above the composer while AI is on: status, summarize,
  /// translate toggle and smart replies.
  Widget _buildAiStrip(ChatPrefs prefs) {
    if (!prefs.aiEnabled) return const SizedBox.shrink();
    Widget chip(String label, IconData icon, VoidCallback? onTap, {bool selected = false, bool reply = false}) {
      final c = reply ? AppColors.brandBlue : (selected ? AppColors.brandWhite : AppColors.brandPink);
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Material(
          color: selected ? AppColors.brandPink : (reply ? AppColors.brandBlue.withValues(alpha: 0.1) : context.surfaceMid),
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.full),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 13, color: c),
                const SizedBox(width: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                          color: reply ? context.textPrimary : c, fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 30,
        child: Row(children: [
          Tooltip(
            message: 'AI is on for this chat',
            child: InkWell(
              onTap: _showAiControls,
              borderRadius: BorderRadius.circular(AppRadius.full),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.auto_awesome_rounded, size: 12, color: AppColors.brandPink),
                  const SizedBox(width: 4),
                  Text('AI on',
                      style: GoogleFonts.inter(
                          color: AppColors.brandPink, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final r in _aiReplies)
                  chip(r, Icons.reply_rounded, () {
                    HapticFeedback.selectionClick();
                    _insertIntoComposer(r);
                  }, reply: true),
                if (_aiRepliesLoading)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Center(
                      child: Text('Thinking…', style: GoogleFonts.inter(color: context.textMuted, fontSize: 11)),
                    ),
                  ),
                chip(_aiSummarizing ? 'Summarizing…' : 'Summarize', Icons.summarize_outlined,
                    _aiSummarizing ? null : _summarizeChat),
                chip('Translate', Icons.translate_rounded, () => _setAutoTranslate(!prefs.aiAutoTranslate),
                    selected: prefs.aiAutoTranslate),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Turn AI off for this chat',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            icon: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
            onPressed: () => _setAiEnabled(false),
          ),
        ]),
      ),
    );
  }

  /// "Translate from Swahili": shown when the phone detects a language you
  /// don't read. Detection runs on the phone; nothing is sent until you tap.
  Widget _translateChip(MessageModel message) {
    if (message.isEncrypted && !_decryptedCache.containsKey(message.id)) return const SizedBox.shrink();
    final text = _getDisplayText(message);
    if (text.trim().length < 12) return const SizedBox.shrink();
    if (!_foreignLang.containsKey(message.id)) {
      _foreignLang[message.id] = null;
      LanguageDetector.instance.foreignLanguageOf(text).then((code) {
        if (mounted && code != null) _refresh(() => _foreignLang[message.id] = code);
      });
      return const SizedBox.shrink();
    }
    final code = _foreignLang[message.id];
    if (code == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.full),
        onTap: () => _translateOne(message),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.translate_rounded, size: 12, color: AppColors.brandBlue),
          const SizedBox(width: 4),
          Text('Translate from ${LanguageDetector.nameOf(code)}',
              style: GoogleFonts.inter(color: AppColors.brandBlue, fontSize: 10.5, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// Translation under a bubble, with its source language.
  Widget _buildTranslation(MessageModel message, bool isMe) {
    if (_translating.contains(message.id) && !_translations.containsKey(message.id)) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('Translating…',
            style: GoogleFonts.inter(
                color: isMe ? AppColors.brandWhite.withValues(alpha: 0.7) : context.textMuted, fontSize: 10.5)),
      );
    }
    final t = _translations[message.id];
    if (t == null && !isMe) return _translateChip(message);
    if (t == null || t.same || _hiddenTranslations.contains(message.id)) return const SizedBox.shrink();
    final muted = isMe ? AppColors.brandWhite.withValues(alpha: 0.72) : context.textMuted;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.only(top: 5),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: isMe ? AppColors.brandWhite.withValues(alpha: 0.25) : context.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(
          t.text,
          style: GoogleFonts.inter(
            color: isMe ? AppColors.brandWhite : context.textPrimary,
            fontSize: _bubbleFontSize,
            height: 1.38,
          ),
        ),
        const SizedBox(height: 2),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.translate_rounded, size: 10, color: muted),
          const SizedBox(width: 3),
          Text(t.source.isEmpty ? 'Translated by Oneova AI' : 'Translated from ${t.source} · Oneova AI',
              style: GoogleFonts.inter(color: muted, fontSize: 9.5)),
        ]),
      ]),
    );
  }
}

/// Pick a chat to forward a message to.
class _ForwardPicker extends ConsumerWidget {
  final String myUid;
  final String excludeChatId;
  const _ForwardPicker({required this.myUid, required this.excludeChatId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(userChatsProvider(myUid));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (ctx, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Icon(Icons.shortcut_rounded, color: AppColors.brandBlue, size: 18),
            const SizedBox(width: 8),
            Text('Forward to…',
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        Divider(height: 1, color: context.border),
        Expanded(
          child: chats.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
            error: (_, _) => Center(
                child: Text("Couldn't load your chats.", style: GoogleFonts.inter(color: context.textMuted))),
            data: (list) {
              final items = list.where((c) => c.id != excludeChatId && c.category != 'channel').toList();
              if (items.isEmpty) {
                return Center(child: Text('No other chats yet.', style: GoogleFonts.inter(color: context.textMuted)));
              }
              return ListView.builder(
                controller: scroll,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final c = items[i];
                  final name = c.title?.isNotEmpty == true ? c.title! : 'Chat';
                  final avatar = c.avatarUrl;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 17,
                      backgroundColor: context.surfaceMid,
                      backgroundImage: avatar != null && avatar.isNotEmpty ? NetworkImage(avatar) : null,
                      child: avatar == null || avatar.isEmpty
                          ? Text(name[0].toUpperCase(),
                              style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w700))
                          : null,
                    ),
                    title: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600)),
                    trailing: const Icon(Icons.send_rounded, color: AppColors.brandBlue, size: 18),
                    onTap: () => Navigator.pop(ctx, c),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}
