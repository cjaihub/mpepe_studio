import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../backend/storage_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../chat_assist_service.dart';

/// A chat background: a preset built from brand colors, or your own photo
/// with a dim and blur so bubbles stay readable.
class ChatBackground {
  /// 'preset' or 'photo'.
  final String type;
  final String preset;
  final String? photoUrl;

  /// 0..0.85: how much of the theme background is laid over the photo.
  final double dim;

  /// 0..20: blur sigma for the photo.
  final double blur;

  const ChatBackground({this.type = 'preset', this.preset = 'default', this.photoUrl, this.dim = 0.35, this.blur = 0});

  static const fallback = ChatBackground();

  bool get isPhoto => type == 'photo' && (photoUrl?.isNotEmpty ?? false);

  static ChatBackground? fromMap(Object? v) {
    if (v is! Map) return null;
    double num0(Object? x, double d) => x is num ? x.toDouble() : d;
    return ChatBackground(
      type: v['type'] == 'photo' ? 'photo' : 'preset',
      preset: (v['preset'] as String?) ?? 'default',
      photoUrl: v['photoUrl'] as String?,
      dim: num0(v['dim'], 0.35).clamp(0.0, 0.85),
      blur: num0(v['blur'], 0).clamp(0.0, 20.0),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type,
        'preset': preset,
        if (photoUrl != null) 'photoUrl': photoUrl,
        'dim': dim,
        'blur': blur,
      };

  ChatBackground copyWith({String? type, String? preset, String? photoUrl, double? dim, double? blur}) => ChatBackground(
        type: type ?? this.type,
        preset: preset ?? this.preset,
        photoUrl: photoUrl ?? this.photoUrl,
        dim: dim ?? this.dim,
        blur: blur ?? this.blur,
      );
}

/// Preset backgrounds, all from brand and theme colors.
const chatBackgroundPresets = <(String, String)>[
  ('default', 'Default'),
  ('blue_glow', 'Blue glow'),
  ('pink_glow', 'Pink glow'),
  ('blue_pink', 'Duo'),
  ('soft', 'Soft'),
  ('brand_blue', 'Brand blue'),
  ('oled', 'OLED'),
];

BoxDecoration chatPresetDecoration(BuildContext context, String key) {
  final bg = context.bg;
  switch (key) {
    case 'blue_glow':
      return BoxDecoration(
        color: bg,
        gradient: RadialGradient(
          center: const Alignment(0, -0.5),
          radius: 1.2,
          colors: [AppColors.brandBlue.withValues(alpha: 0.28), bg],
          stops: const [0, 0.85],
        ),
      );
    case 'pink_glow':
      return BoxDecoration(
        color: bg,
        gradient: RadialGradient(
          center: const Alignment(0, -0.4),
          radius: 1.1,
          colors: [AppColors.brandPink.withValues(alpha: 0.18), bg],
          stops: const [0, 0.85],
        ),
      );
    case 'blue_pink':
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(AppColors.brandBlue.withValues(alpha: 0.22), bg),
            bg,
            Color.alphaBlend(AppColors.brandPink.withValues(alpha: 0.14), bg),
          ],
        ),
      );
    case 'soft':
      return BoxDecoration(color: context.surfaceMid);
    case 'brand_blue':
      return BoxDecoration(color: Color.alphaBlend(AppColors.brandBlue.withValues(alpha: 0.12), bg));
    case 'oled':
      return const BoxDecoration(color: AppColors.brandBlack);
    default:
      return BoxDecoration(color: bg);
  }
}

/// Fills its area with [background].
class ChatBackgroundView extends StatelessWidget {
  final ChatBackground background;
  const ChatBackgroundView({super.key, required this.background});

  @override
  Widget build(BuildContext context) {
    final b = background;
    if (!b.isPhoto) return DecoratedBox(decoration: chatPresetDecoration(context, b.preset));
    final image = CachedNetworkImage(
      imageUrl: b.photoUrl!,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, _) => ColoredBox(color: context.bg),
      errorWidget: (_, _, _) => ColoredBox(color: context.bg),
    );
    return Stack(fit: StackFit.expand, children: [
      ColoredBox(color: context.bg),
      if (b.blur > 0.5)
        ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: b.blur, sigmaY: b.blur, tileMode: TileMode.clamp),
            child: image,
          ),
        )
      else
        image,
      ColoredBox(color: context.bg.withValues(alpha: b.dim)),
    ]);
  }
}

/// Bottom sheet to pick a background for this chat or for all chats.
Future<void> showChatBackgroundSheet(BuildContext context, {required String uid, required String chatId}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _ChatBackgroundSheet(uid: uid, chatId: chatId),
  );
}

class _ChatBackgroundSheet extends ConsumerStatefulWidget {
  final String uid;
  final String chatId;
  const _ChatBackgroundSheet({required this.uid, required this.chatId});

  @override
  ConsumerState<_ChatBackgroundSheet> createState() => _ChatBackgroundSheetState();
}

class _ChatBackgroundSheetState extends ConsumerState<_ChatBackgroundSheet> {
  bool _allChats = false;
  ChatBackground? _draft;
  bool _uploading = false;
  bool _seeded = false;

  String get _docId => _allChats ? ChatAssistService.allChatsDoc : widget.chatId;

  ChatBackground? _saved(ChatPrefs chat, ChatPrefs all) => _allChats ? all.background : chat.background;

  Future<void> _save(ChatBackground? b) async {
    try {
      await ref.read(chatAssistServiceProvider).setBackground(widget.uid, _docId, b);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't save the background.")));
      }
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2160,
      maxHeight: 2160,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    final scope = _allChats ? 'all' : widget.chatId;
    final url = await ref.read(storageServiceProvider).uploadFile(
          File(picked.path),
          'users/${widget.uid}/files/chat_backgrounds/${scope}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't upload that photo.")));
      return;
    }
    final next = (_draft ?? ChatBackground.fallback).copyWith(type: 'photo', photoUrl: url);
    setState(() => _draft = next);
    await _save(next);
  }

  @override
  Widget build(BuildContext context) {
    final chatPrefs = ref.watch(chatPrefsProvider((uid: widget.uid, chatId: widget.chatId))).value ?? const ChatPrefs();
    final allPrefs =
        ref.watch(chatPrefsProvider((uid: widget.uid, chatId: ChatAssistService.allChatsDoc))).value ?? const ChatPrefs();
    if (!_seeded && ref.read(chatPrefsProvider((uid: widget.uid, chatId: widget.chatId))).hasValue) {
      _seeded = true;
      _draft = chatPrefs.background ?? allPrefs.background;
    }
    final saved = _saved(chatPrefs, allPrefs);
    final current = _draft ?? saved ?? allPrefs.background ?? ChatBackground.fallback;
    final hasOverride = chatPrefs.background != null;

    Widget label(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(t,
              style: GoogleFonts.inter(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Icon(Icons.wallpaper_rounded, color: AppColors.brandBlue, size: 18),
            const SizedBox(width: 8),
            Text('Chat background',
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.brandBlue,
                selectedForegroundColor: AppColors.brandWhite,
                foregroundColor: context.textSecondary,
                side: BorderSide(color: context.border),
                visualDensity: VisualDensity.compact,
              ),
              segments: const [
                ButtonSegment(value: false, label: Text('This chat'), icon: Icon(Icons.chat_bubble_outline_rounded, size: 16)),
                ButtonSegment(value: true, label: Text('All chats'), icon: Icon(Icons.forum_outlined, size: 16)),
              ],
              selected: {_allChats},
              onSelectionChanged: (s) => setState(() {
                _allChats = s.first;
                _draft = _allChats ? allPrefs.background : (chatPrefs.background ?? allPrefs.background);
              }),
            ),
          ),
          const SizedBox(height: 12),
          // Preview with sample bubbles.
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              height: 150,
              child: Stack(fit: StackFit.expand, children: [
                ChatBackgroundView(background: current),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    _SampleBubble(text: 'This is how your chat looks', mine: false),
                    const SizedBox(height: 6),
                    _SampleBubble(text: 'Looks great 👌', mine: true),
                  ]),
                ),
                if (_uploading)
                  ColoredBox(
                    color: context.bg.withValues(alpha: 0.6),
                    child: const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
                  ),
              ]),
            ),
          ),
          label('PRESETS'),
          SizedBox(
            height: 64,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              _Swatch(
                selected: false,
                label: 'Photo',
                onTap: _uploading ? null : _pickPhoto,
                child: Icon(Icons.add_photo_alternate_outlined, color: AppColors.brandBlue, size: 20),
              ),
              for (final (key, name) in chatBackgroundPresets)
                _Swatch(
                  selected: !current.isPhoto && current.preset == key,
                  label: name,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    final next = ChatBackground(preset: key, dim: current.dim, blur: current.blur);
                    setState(() => _draft = next);
                    _save(next);
                  },
                  child: DecoratedBox(decoration: chatPresetDecoration(context, key), child: const SizedBox.expand()),
                ),
            ]),
          ),
          if (current.isPhoto) ...[
            label('READABILITY'),
            _SliderRow(
              icon: Icons.brightness_6_outlined,
              label: 'Dim',
              value: current.dim,
              max: 0.85,
              onChanged: (v) => setState(() => _draft = current.copyWith(dim: v)),
              onChangeEnd: (v) => _save(current.copyWith(dim: v)),
            ),
            _SliderRow(
              icon: Icons.blur_on_rounded,
              label: 'Blur',
              value: current.blur,
              max: 20,
              onChanged: (v) => setState(() => _draft = current.copyWith(blur: v)),
              onChangeEnd: (v) => _save(current.copyWith(blur: v)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _allChats
                ? 'Used in every chat that has no background of its own.'
                : hasOverride
                    ? 'Only this chat. Your other chats keep the all-chats background.'
                    : 'This chat uses your all-chats background. Pick one to set it for this chat only.',
            style: GoogleFonts.inter(color: context.textMuted, fontSize: 11, height: 1.35),
          ),
          if (!_allChats && hasOverride)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.brandPink, padding: EdgeInsets.zero),
                onPressed: () {
                  setState(() => _draft = allPrefs.background);
                  _save(null);
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Use all-chats background'),
              ),
            ),
        ]),
      ),
    );
  }
}

class _SampleBubble extends StatelessWidget {
  final String text;
  final bool mine;
  const _SampleBubble({required this.text, required this.mine});

  @override
  Widget build(BuildContext context) => Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: mine ? AppColors.brandBlue : context.surface,
            border: mine ? null : Border.all(color: context.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(text,
              style: GoogleFonts.inter(color: mine ? AppColors.brandWhite : context.textPrimary, fontSize: 12)),
        ),
      );
}

class _Swatch extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback? onTap;
  final Widget child;
  const _Swatch({required this.selected, required this.label, required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 44,
              height: 44,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: selected ? AppColors.brandPink : context.border,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Center(child: child),
            ),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.inter(
                  color: selected ? AppColors.brandPink : context.textSecondary,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          ]),
        ),
      );
}

class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;
  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    required this.onChangeEnd,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 16, color: context.textSecondary),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(label, style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12.5)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            max: max,
            activeColor: AppColors.brandBlue,
            inactiveColor: context.border,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ]);
}
