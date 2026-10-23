import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../backend/firebase_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'chat_media_bubbles.dart';

/// A GIF chosen in the panel. Camera-made GIFs are short looping MP4s.
class GifPick {
  final String url;
  final bool isVideo;
  const GifPick(this.url, {this.isVideo = false});
}

/// The user's own GIFs (`users/{uid}/gifs`) plus Tenor search when a
/// `tenor_api_key` is set in Remote Config.
class ChatGifLibrary {
  static CollectionReference<Map<String, dynamic>>? _col() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('gifs');
  }

  static Stream<List<GifPick>> mine() {
    final col = _col();
    if (col == null) return Stream.value(const []);
    return col.orderBy('createdAt', descending: true).limit(60).snapshots().map((s) => s.docs
        .map((d) => GifPick(d.data()['url'] as String? ?? '', isVideo: d.data()['isVideo'] == true))
        .where((g) => g.url.isNotEmpty)
        .toList());
  }

  static Future<void> save(GifPick gif) async {
    final col = _col();
    if (col == null) return;
    // Doc id from the url keeps one copy per GIF.
    final id = base64Url.encode(utf8.encode(gif.url)).replaceAll('=', '');
    await col.doc(id.length > 400 ? id.substring(id.length - 400) : id).set({
      'url': gif.url,
      'isVideo': gif.isVideo,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static String get _tenorKey {
    try {
      return FirebaseService.instance.getString('tenor_api_key');
    } catch (_) {
      return '';
    }
  }

  static bool get searchAvailable => _tenorKey.isNotEmpty;

  /// Featured GIFs for an empty query, otherwise search results.
  static Future<List<GifPick>> search(String query) async {
    final key = _tenorKey;
    if (key.isEmpty) return const [];
    final q = query.trim();
    final uri = Uri.https('tenor.googleapis.com', q.isEmpty ? '/v2/featured' : '/v2/search', {
      if (q.isNotEmpty) 'q': q,
      'key': key,
      'client_key': 'oneova',
      'limit': '30',
      'media_filter': 'tinygif,gif',
      'contentfilter': 'medium',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return const [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final out = <GifPick>[];
    for (final r in (data['results'] as List? ?? const [])) {
      final formats = (r as Map)['media_formats'] as Map? ?? {};
      final url = (formats['gif'] as Map?)?['url'] ?? (formats['tinygif'] as Map?)?['url'];
      if (url is String) out.add(GifPick(url));
    }
    return out;
  }
}

/// Emoji + GIF panel that replaces the keyboard in the chat composer.
class ChatEmojiGifPanel extends StatefulWidget {
  final ValueChanged<String> onEmoji;
  final VoidCallback onBackspace;
  final ValueChanged<GifPick> onGif;

  /// Record a short clip with the camera and send it as your own GIF.
  final VoidCallback onCreateGif;
  final double height;

  const ChatEmojiGifPanel({
    super.key,
    required this.onEmoji,
    required this.onBackspace,
    required this.onGif,
    required this.onCreateGif,
    this.height = 300,
  });

  @override
  State<ChatEmojiGifPanel> createState() => _ChatEmojiGifPanelState();
}

class _ChatEmojiGifPanelState extends State<ChatEmojiGifPanel> with SingleTickerProviderStateMixin {
  static const _recentKey = 'oneova_recent_emojis';
  late final TabController _tabs = TabController(length: 2, vsync: this);
  int _category = 0;
  List<String> _recent = const [];
  final _gifQuery = TextEditingController();
  Timer? _debounce;
  Future<List<GifPick>>? _gifResults;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    }).catchError((_) {});
    if (ChatGifLibrary.searchAvailable) _gifResults = ChatGifLibrary.search('');
  }

  @override
  void dispose() {
    _tabs.dispose();
    _gifQuery.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _pickEmoji(String e) {
    HapticFeedback.selectionClick();
    widget.onEmoji(e);
    final next = [e, ..._recent.where((r) => r != e)].take(32).toList();
    setState(() => _recent = next);
    SharedPreferences.getInstance().then((p) => p.setStringList(_recentKey, next)).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 40,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabs,
                    indicatorColor: AppColors.brandBlue,
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: AppColors.brandBlue,
                    unselectedLabelColor: context.textSecondary,
                    dividerColor: Colors.transparent,
                    labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                    tabs: const [Tab(text: 'Emoji'), Tab(text: 'GIF')],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: Icon(Icons.backspace_outlined, size: 20, color: context.textSecondary),
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onBackspace();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_emojiTab(), _gifTab()],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Emoji ─────────────────────────

  Widget _emojiTab() {
    final cats = [
      if (_recent.isNotEmpty) (Icons.history_rounded, _recent),
      for (final c in _emojiCategories) (c.$1, c.$2),
    ];
    final idx = _category.clamp(0, cats.length - 1);
    return Column(
      children: [
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            children: [
              for (var i = 0; i < cats.length; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(cats[i].$1, size: 20, color: i == idx ? AppColors.brandBlue : context.textMuted),
                  onPressed: () => setState(() => _category = i),
                ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 44),
            itemCount: cats[idx].$2.length,
            itemBuilder: (_, i) {
              final e = cats[idx].$2[i];
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => _pickEmoji(e),
                child: Center(child: Text(e, style: const TextStyle(fontSize: 26))),
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────────────────────── GIF ─────────────────────────

  Widget _gifTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              if (ChatGifLibrary.searchAvailable)
                Expanded(
                  child: TextField(
                    controller: _gifQuery,
                    style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Search GIFs',
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: context.textMuted),
                      prefixIcon: Icon(Icons.search_rounded, size: 18, color: context.textMuted),
                      filled: true,
                      fillColor: context.surfaceMid,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border),
                      ),
                    ),
                    onChanged: (q) {
                      _debounce?.cancel();
                      _debounce = Timer(const Duration(milliseconds: 350), () {
                        if (mounted) setState(() => _gifResults = ChatGifLibrary.search(q));
                      });
                    },
                  ),
                )
              else
                Expanded(
                  child: Text('Your GIFs',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary)),
                ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                onPressed: widget.onCreateGif,
                icon: const Icon(Icons.videocam_rounded, size: 17),
                label: Text('Make GIF', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<GifPick>>(
            stream: ChatGifLibrary.mine(),
            builder: (context, mineSnap) {
              final mine = mineSnap.data ?? const <GifPick>[];
              return FutureBuilder<List<GifPick>>(
                future: _gifResults,
                builder: (context, searchSnap) {
                  final searching = _gifQuery.text.trim().isNotEmpty;
                  final found = searchSnap.data ?? const <GifPick>[];
                  final items = searching ? found : [...mine, ...found];
                  if (items.isEmpty) {
                    final loading = searchSnap.connectionState == ConnectionState.waiting;
                    return Center(
                      child: loading
                          ? const CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)
                          : Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                searching
                                    ? 'No GIFs found'
                                    : 'Tap Make GIF and hold to record a short looping clip with your camera. '
                                        'GIFs you send are saved here.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(fontSize: 12, color: context.textMuted, height: 1.4),
                              ),
                            ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 4,
                      crossAxisSpacing: 4,
                    ),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final g = items[i];
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onGif(g);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: g.isVideo
                              ? LoopingVideoGif(url: g.url)
                              : Image.network(
                                  g.url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid),
                                ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        if (ChatGifLibrary.searchAvailable)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('Powered by Tenor', style: GoogleFonts.inter(fontSize: 9.5, color: context.textMuted)),
          ),
      ],
    );
  }
}

const List<(IconData, List<String>)> _emojiCategories = [
  (Icons.emoji_emotions_outlined, [
    '😀', '😃', '😄', '😁', '😆', '😅', '🤣', '😂', '🙂', '🙃', '🫠', '😉', '😊', '😇', '🥰', '😍', '🤩', '😘',
    '😗', '☺️', '😚', '😙', '🥲', '😋', '😛', '😜', '🤪', '😝', '🤑', '🤗', '🤭', '🫢', '🫣', '🤫', '🤔', '🫡',
    '🤐', '🤨', '😐', '😑', '😶', '🫥', '😏', '😒', '🙄', '😬', '😮‍💨', '🤥', '😌', '😔', '😪', '🤤', '😴', '😷',
    '🤒', '🤕', '🤢', '🤮', '🤧', '🥵', '🥶', '🥴', '😵', '😵‍💫', '🤯', '🤠', '🥳', '🥸', '😎', '🤓', '🧐', '😕',
    '🫤', '😟', '🙁', '😮', '😯', '😲', '😳', '🥺', '🥹', '😦', '😧', '😨', '😰', '😥', '😢', '😭', '😱', '😖',
    '😣', '😞', '😓', '😩', '😫', '🥱', '😤', '😡', '😠', '🤬', '😈', '👿', '💀', '☠️', '💩', '🤡', '👻', '👽',
  ]),
  (Icons.waving_hand_outlined, [
    '👋', '🤚', '🖐️', '✋', '🖖', '🫱', '🫲', '👌', '🤌', '🤏', '✌️', '🤞', '🫰', '🤟', '🤘', '🤙', '👈', '👉',
    '👆', '👇', '☝️', '🫵', '👍', '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '🫶', '👐', '🤲', '🤝', '🙏', '✍️',
    '💅', '🤳', '💪', '🦾', '👀', '👁️', '👅', '👄', '🫦', '🧠', '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔',
    '👩', '🧓', '👴', '👵', '🙋', '🙆', '🙅', '🤷', '🤦', '💃', '🕺', '🧘', '🏃', '🚶', '👫', '👭', '👬', '💏',
  ]),
  (Icons.favorite_border_rounded, [
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❤️‍🔥', '❤️‍🩹', '❣️', '💕', '💞', '💓', '💗', '💖',
    '💘', '💝', '💟', '♥️', '💋', '💯', '💢', '💥', '💫', '💦', '💨', '🕳️', '💬', '🗨️', '💭', '💤', '✨', '⭐',
    '🌟', '🔥', '🌈', '☀️', '🌙', '⚡', '❄️', '🎉', '🎊', '🎈', '🎁', '🏆', '🥇', '🎯', '✅', '❌', '⚠️', '❓',
  ]),
  (Icons.pets_rounded, [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🙈', '🙉', '🙊',
    '🐔', '🐧', '🐦', '🐤', '🦆', '🦅', '🦉', '🐺', '🐗', '🐴', '🦄', '🐝', '🦋', '🐌', '🐞', '🐢', '🐍', '🦖',
    '🐙', '🦑', '🦀', '🐠', '🐬', '🐳', '🦈', '🐊', '🐅', '🦓', '🦍', '🐘', '🦒', '🐪', '🦘', '🐕', '🐈', '🦜',
    '🌵', '🎄', '🌲', '🌴', '🌱', '🌿', '☘️', '🍀', '🍁', '🍂', '🌷', '🌹', '🥀', '🌺', '🌸', '🌼', '🌻', '🌎',
  ]),
  (Icons.fastfood_outlined, [
    '🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🫐', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅', '🥑',
    '🌽', '🌶️', '🥕', '🥔', '🥐', '🍞', '🧀', '🥚', '🍳', '🥞', '🥓', '🍗', '🍖', '🌭', '🍔', '🍟', '🍕', '🥪',
    '🌮', '🌯', '🥗', '🍝', '🍜', '🍲', '🍛', '🍣', '🍱', '🥟', '🍤', '🍚', '🍦', '🍩', '🍪', '🎂', '🍰', '🧁',
    '🍫', '🍬', '🍭', '🍿', '☕', '🍵', '🧃', '🥤', '🧋', '🍺', '🍻', '🥂', '🍷', '🍸', '🍹', '🍾', '🧊', '🥄',
  ]),
  (Icons.sports_soccer_rounded, [
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🎱', '🏓', '🏸', '🥊', '🥋', '⛳', '🏹', '🎣', '🛹', '⛸️', '🎿',
    '🏂', '🏋️', '🤸', '⛹️', '🤾', '🏌️', '🏄', '🏊', '🚴', '🎮', '🕹️', '🎲', '♟️', '🎭', '🎨', '🎬', '🎤', '🎧',
    '🎼', '🎹', '🥁', '🎷', '🎺', '🎸', '🪕', '🎻', '🎟️', '🎫', '🏅', '🎖️', '📸', '🎥', '📺', '📻', '🎙️', '💡',
  ]),
  (Icons.directions_car_outlined, [
    '🚗', '🚕', '🚙', '🚌', '🏎️', '🚓', '🚑', '🚒', '🚐', '🛻', '🚚', '🏍️', '🛵', '🚲', '🛴', '🚨', '🚆', '🚇',
    '✈️', '🛫', '🛬', '🚀', '🛸', '🚁', '⛵', '🚤', '🛳️', '⚓', '🗺️', '🗽', '🗼', '🏰', '🏟️', '🎡', '🎢', '🏖️',
    '🏝️', '🏜️', '🌋', '⛰️', '🏔️', '🏠', '🏡', '🏢', '🏬', '🏥', '🏦', '🏨', '🕌', '⛪', '🌃', '🌆', '🌇', '🌉',
  ]),
  (Icons.lightbulb_outline_rounded, [
    '📱', '💻', '⌨️', '🖥️', '🖨️', '🖱️', '💾', '💿', '📷', '📹', '☎️', '📞', '📟', '📠', '🔋', '🔌', '💰', '💵',
    '💳', '💎', '⚖️', '🔧', '🔨', '⚙️', '🔫', '💣', '🔪', '🛡️', '🔮', '💊', '💉', '🧬', '🔬', '🔭', '🧹', '🧺',
    '🛒', '🎀', '🪄', '📦', '✉️', '📩', '📝', '📁', '📅', '📌', '📎', '✂️', '🔒', '🔓', '🔑', '🗝️', '❤️‍🔥', '🆗',
  ]),
];
