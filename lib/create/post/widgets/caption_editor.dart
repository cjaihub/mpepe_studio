import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../backend/social/models/social_profile.dart';
import '../../../backend/social/services/global_hashtag_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/oneova_voice_typing_button.dart';
import '../services/post_search_service.dart';

class CaptionEditor extends StatefulWidget {
  final TextEditingController titleController;
  final TextEditingController captionController;
  final PostSearchService searchService;
  final VoidCallback? onChanged;

  const CaptionEditor({
    super.key,
    required this.titleController,
    required this.captionController,
    required this.searchService,
    this.onChanged,
  });

  @override
  State<CaptionEditor> createState() => _CaptionEditorState();
}

class _CaptionEditorState extends State<CaptionEditor> {
  Timer? _debounceTimer;
  List<SocialProfile> _userSuggestions = [];
  List<GlobalHashtagModel> _hashtagSuggestions = [];
  bool _isSearchingUsers = false;
  bool _isSearchingTags = false;
  String _activeQuery = '';
  int _activeTriggerIndex = -1;
  String _activeTriggerChar = '';

  @override
  void initState() {
    super.initState();
    widget.captionController.addListener(_onCaptionChanged);
  }

  @override
  void dispose() {
    widget.captionController.removeListener(_onCaptionChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onCaptionChanged() {
    widget.onChanged?.call();
    final text = widget.captionController.text;
    final selection = widget.captionController.selection;
    if (selection.baseOffset < 0) return;

    final cursor = selection.baseOffset;
    final textBeforeCursor = text.substring(0, cursor);

    // Look for last @ or # token before cursor
    final atIndex = textBeforeCursor.lastIndexOf('@');
    final hashIndex = textBeforeCursor.lastIndexOf('#');

    final lastTriggerIndex = atIndex > hashIndex ? atIndex : hashIndex;
    final triggerChar = atIndex > hashIndex ? '@' : '#';

    if (lastTriggerIndex >= 0) {
      final token = textBeforeCursor.substring(lastTriggerIndex);
      // Valid trigger if it doesn't contain spaces or linebreaks
      if (!token.contains(' ') && !token.contains('\n') && token.length > 1) {
        _activeTriggerIndex = lastTriggerIndex;
        _activeTriggerChar = triggerChar;
        _activeQuery = token.substring(1);
        _triggerSearch();
        return;
      }
    }

    _clearSuggestions();
  }

  void _clearSuggestions() {
    if (_userSuggestions.isNotEmpty || _hashtagSuggestions.isNotEmpty) {
      setState(() {
        _userSuggestions = [];
        _hashtagSuggestions = [];
        _activeTriggerIndex = -1;
        _activeTriggerChar = '';
        _activeQuery = '';
      });
    }
  }

  void _triggerSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 250), () async {
      if (_activeTriggerChar == '@') {
        setState(() => _isSearchingUsers = true);
        final users = await widget.searchService.searchUsers(_activeQuery, limit: 6);
        if (mounted) {
          setState(() {
            _userSuggestions = users;
            _hashtagSuggestions = [];
            _isSearchingUsers = false;
          });
        }
      } else if (_activeTriggerChar == '#') {
        setState(() => _isSearchingTags = true);
        final tags = await widget.searchService.searchHashtags(_activeQuery, limit: 6);
        if (mounted) {
          setState(() {
            _hashtagSuggestions = tags;
            _userSuggestions = [];
            _isSearchingTags = false;
          });
        }
      }
    });
  }

  void _insertMention(String username) {
    HapticFeedback.lightImpact();
    final text = widget.captionController.text;
    final cursor = widget.captionController.selection.baseOffset;
    if (_activeTriggerIndex < 0 || _activeTriggerIndex > text.length) return;

    final before = text.substring(0, _activeTriggerIndex);
    final after = cursor <= text.length ? text.substring(cursor) : '';
    final newText = '$before@$username $after';

    widget.captionController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: before.length + username.length + 2),
    );
    _clearSuggestions();
  }

  void _insertHashtag(String tag) {
    HapticFeedback.lightImpact();
    final clean = tag.replaceAll('#', '');
    final text = widget.captionController.text;
    final cursor = widget.captionController.selection.baseOffset;

    if (_activeTriggerIndex >= 0 && _activeTriggerIndex <= text.length) {
      final before = text.substring(0, _activeTriggerIndex);
      final after = cursor <= text.length ? text.substring(cursor) : '';
      final newText = '$before#$clean $after';

      widget.captionController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: before.length + clean.length + 2),
      );
    } else {
      // Append to the end
      final newText = text.trim().isEmpty ? '#$clean ' : '${text.trim()} #$clean ';
      widget.captionController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    _clearSuggestions();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Reel Title (Single Line)
          Row(
            children: [
              Icon(Icons.title_rounded, size: 16, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'TITLE (OPTIONAL)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.titleController,
                builder: (context, value, _) {
                  return Text(
                    '${value.text.length}/90',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: value.text.length > 80 ? AppColors.brandPink : context.textMuted,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              OneovaVoiceTypingButton(
                controller: widget.titleController,
                onChanged: (_) => widget.onChanged?.call(),
                tooltip: 'Dictate title',
                iconSize: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                showTranslateAction: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: widget.titleController,
            maxLength: 90,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            style: GoogleFonts.inter(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Add a high-impact title (e.g. Masterclass Drop 🔥)',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          Divider(color: context.border, height: 16, thickness: 0.8),

          // 2. Reel Caption / Description (Multiline)
          Row(
            children: [
              Icon(Icons.notes_rounded, size: 16, color: AppColors.brandPink),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'DESCRIPTION & HASHTAGS',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: context.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.captionController,
                builder: (context, value, _) {
                  return Text(
                    '${value.text.length}/2200',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: value.text.length > 2000 ? AppColors.brandPink : context.textMuted,
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              OneovaVoiceTypingButton(
                controller: widget.captionController,
                onChanged: (_) => widget.onChanged?.call(),
                tooltip: 'Dictate caption & hashtags',
                iconSize: 15,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                showTranslateAction: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: widget.captionController,
            maxLines: 4,
            minLines: 3,
            maxLength: 2200,
            buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
            style: GoogleFonts.inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w400,
              height: 1.4,
              color: context.textPrimary,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Write a caption, use #hashtag for trends, or @creator to tag…',
              hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),

          // 3. Autocomplete Overlay Bar (Mentions / Hashtags)
          if (_userSuggestions.isNotEmpty || _isSearchingUsers) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.alternate_email, size: 14, color: AppColors.brandBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Tag Creators',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      if (_isSearchingUsers) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _userSuggestions.map((user) {
                      return InkWell(
                        onTap: () => _insertMention(user.username),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: context.surface,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            border: Border.all(color: context.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 9,
                                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                                backgroundImage: user.avatarUrl.isNotEmpty
                                    ? NetworkImage(user.avatarUrl)
                                    : null,
                                child: user.avatarUrl.isEmpty
                                    ? Text(
                                        user.username.isNotEmpty
                                            ? user.username[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(fontSize: 8, color: Colors.white),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '@${user.username}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                              if (user.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified, size: 12, color: AppColors.brandBlue),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          if (_hashtagSuggestions.isNotEmpty || _isSearchingTags) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tag_rounded, size: 14, color: AppColors.brandPink),
                      const SizedBox(width: 6),
                      Text(
                        'Trending Hashtags',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPink,
                        ),
                      ),
                      if (_isSearchingTags) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _hashtagSuggestions.map((tag) {
                      return InkWell(
                        onTap: () => _insertHashtag(tag.tag),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.surface,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: context.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '#${tag.tag}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.brandPink,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${tag.postCount}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: context.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

          // 4. Quick Trending Hashtags Strip
          const SizedBox(height: 10),
          StreamBuilder<List<GlobalHashtagModel>>(
            stream: widget.searchService.watchTrendingHashtags(limit: 8),
            builder: (context, snapshot) {
              final tags = snapshot.data ?? [];
              if (tags.isEmpty) {
                // Fallback default tags
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['oneova', 'viral', 'fyp', 'creator', 'trending'].map((t) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: context.surfaceMid,
                          side: BorderSide(color: context.border, width: 0.8),
                          label: Text(
                            '#$t',
                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: context.textSecondary),
                          ),
                          onPressed: () => _insertHashtag(t),
                        ),
                      );
                    }).toList(),
                  ),
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: tags.map((t) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: context.surfaceMid,
                        side: BorderSide(color: context.border, width: 0.8),
                        avatar: const Icon(Icons.trending_up, size: 12, color: AppColors.brandPink),
                        label: Text(
                          '#${t.tag}',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: context.textPrimary),
                        ),
                        onPressed: () => _insertHashtag(t.tag),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
