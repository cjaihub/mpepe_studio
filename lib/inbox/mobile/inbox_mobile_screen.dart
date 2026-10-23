import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';

// Since the prompt asks to build the backend of this interface exactly as is,
// we define a robust Riverpod-based state management that serves these specific features.

class OneovaChat {
  final String id;
  final String name;
  final String time;
  final String avatarUrl;
  final String messageText;
  final String? tagText;
  final Color? tagColor;
  final Color? tagBg;
  final Color? tagBorder;
  final Color? timeColor;
  final Color? avatarRingColor;
  final Color? avatarBorder;
  final IconData? bottomRightIcon;
  final Color? bottomRightIconColor;
  final bool isVerified;
  final bool onlineDot;
  final String? messagePrefix;
  final bool isVoiceMessage;
  final String? voiceDuration;
  final bool isFileMessage;
  final bool isRead;
  final bool isDelivered;
  final int unreadCount;

  OneovaChat({
    required this.id,
    required this.name,
    required this.time,
    required this.avatarUrl,
    required this.messageText,
    this.tagText,
    this.tagColor,
    this.tagBg,
    this.tagBorder,
    this.timeColor,
    this.avatarRingColor,
    this.avatarBorder,
    this.bottomRightIcon,
    this.bottomRightIconColor,
    this.isVerified = false,
    this.onlineDot = false,
    this.messagePrefix,
    this.isVoiceMessage = false,
    this.voiceDuration,
    this.isFileMessage = false,
    this.isRead = false,
    this.isDelivered = false,
    this.unreadCount = 0,
  });
}

class OneovaInboxNotifier extends Notifier<List<OneovaChat>> {
  @override
  List<OneovaChat> build() {
    return _initialChats;
  }

  void markAsRead(String id) {
    state = [
      for (final chat in state)
        if (chat.id == id)
          OneovaChat(
            id: chat.id,
            name: chat.name,
            time: chat.time,
            avatarUrl: chat.avatarUrl,
            messageText: chat.messageText,
            tagText: chat.tagText,
            tagColor: chat.tagColor,
            tagBg: chat.tagBg,
            tagBorder: chat.tagBorder,
            timeColor: Colors.grey[500],
            avatarRingColor: null,
            avatarBorder: chat.avatarBorder,
            bottomRightIcon: chat.bottomRightIcon,
            bottomRightIconColor: chat.bottomRightIconColor,
            isVerified: chat.isVerified,
            onlineDot: chat.onlineDot,
            messagePrefix: chat.messagePrefix,
            isVoiceMessage: chat.isVoiceMessage,
            voiceDuration: chat.voiceDuration,
            isFileMessage: chat.isFileMessage,
            isRead: true,
            isDelivered: chat.isDelivered,
            unreadCount: 0,
          )
        else
          chat
    ];
  }
}

final oneovaInboxProvider = NotifierProvider<OneovaInboxNotifier, List<OneovaChat>>(OneovaInboxNotifier.new);

final _initialChats = [
  OneovaChat(
    id: '1',
    name: 'Wacha Washa',
    tagText: 'CHANNEL',
    tagColor: const Color(0xFF0066FF),
    tagBg: const Color(0xFF0066FF).withValues(alpha: 0.12),
    time: '5:26 AM',
    timeColor: const Color(0xFF0066FF),
    avatarUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=150&q=80',
    avatarRingColor: const Color(0xFF0066FF).withValues(alpha: 0.5),
    bottomRightIcon: Icons.music_note,
    bottomRightIconColor: const Color(0xFF0066FF),
    messagePrefix: 'DJ Kalonje: ',
    messageText: 'VIP roster confirmed for live broadcast tonight 🔥',
    unreadCount: 3,
  ),
  OneovaChat(
    id: '2',
    name: 'Young P On E Truq',
    isVerified: true,
    tagText: 'PRO',
    tagColor: Colors.cyan[300],
    tagBg: Colors.cyan[900]!.withValues(alpha: 0.6),
    tagBorder: Colors.cyan[500]!.withValues(alpha: 0.4),
    time: '4:51 AM',
    avatarUrl: 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150&q=80',
    avatarBorder: Colors.cyan[500]!.withValues(alpha: 0.4),
    onlineDot: true,
    isVoiceMessage: true,
    voiceDuration: '0:42',
    messageText: 'Iyi kitu ni mbaya Babu, drop the master!',
    isRead: true,
  ),
  OneovaChat(
    id: '3',
    name: 'Collins Director',
    tagText: 'DIR',
    tagColor: Colors.purple[300],
    tagBg: Colors.purple[900]!.withValues(alpha: 0.8),
    tagBorder: Colors.purple[800]!.withValues(alpha: 0.4),
    time: '4:43 AM',
    avatarUrl: 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150&q=80',
    avatarBorder: Colors.purple[500]!.withValues(alpha: 0.4),
    bottomRightIcon: Icons.videocam,
    bottomRightIconColor: Colors.purple[400],
    isRead: true,
    messageText: 'Niko salaama Mkubwa, 4K color grading is complete.',
  ),
  OneovaChat(
    id: '4',
    name: 'Nakayemo',
    time: '4:41 AM',
    timeColor: const Color(0xFF0066FF),
    avatarUrl: 'https://images.unsplash.com/photo-1531746020798-e6953c6e8e04?w=150&q=80',
    avatarRingColor: const Color(0xFF0066FF).withValues(alpha: 0.4),
    onlineDot: true,
    isVoiceMessage: true,
    messageText: 'Voice message (1:14)',
    unreadCount: 1,
  ),
  OneovaChat(
    id: '5',
    name: 'Bolo Sinai',
    tagText: 'ARTIST',
    tagColor: Colors.grey[400],
    tagBg: Colors.grey[800],
    time: '4:40 AM',
    avatarUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150&q=80',
    avatarBorder: Colors.lightBlue[800]!.withValues(alpha: 0.4),
    isDelivered: true,
    messageText: 'Natoa zile ma cover kwa studio kesho mapema.',
  ),
  OneovaChat(
    id: '6',
    name: 'John Mutumbu',
    tagText: 'WHATSAPP SYNC',
    tagColor: Colors.green[400],
    tagBg: Colors.green[500]!.withValues(alpha: 0.15),
    tagBorder: Colors.green[500]!.withValues(alpha: 0.3),
    time: '4:38 AM',
    avatarUrl: 'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=150&q=80',
    avatarBorder: Colors.grey[700]!.withValues(alpha: 0.6),
    bottomRightIcon: Icons.wechat,
    bottomRightIconColor: Colors.green[400],
    isFileMessage: true,
    messageText: 'Draft sequence ready for export (Final Cut XML)',
  ),
  OneovaChat(
    id: '7',
    name: 'Brenda Beats',
    tagText: 'PRODUCER',
    tagColor: Colors.orange[300],
    tagBg: Colors.orange[900]!.withValues(alpha: 0.7),
    tagBorder: Colors.orange[600]!.withValues(alpha: 0.3),
    time: 'Yesterday',
    avatarUrl: 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150&q=80',
    avatarBorder: Colors.orange[600]!.withValues(alpha: 0.3),
    bottomRightIcon: Icons.bolt,
    bottomRightIconColor: Colors.orange[300],
    isRead: true,
    messageText: 'Stems & MIDI files uploaded to Oneova Cloud Drive!',
  ),
];

class InboxMobileScreen extends ConsumerStatefulWidget {
  const InboxMobileScreen({super.key});

  @override
  ConsumerState<InboxMobileScreen> createState() => _InboxMobileScreenState();
}

class _InboxMobileScreenState extends ConsumerState<InboxMobileScreen> {
  final Color brandBlue = const Color(0xFF0066FF);
  final Color brandBlueSubtle = const Color(0xFF0066FF).withValues(alpha: 0.12);

  int _selectedTabIndex = 0;
  bool _bannerVisible = true;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = context.bg;
    final textColor = context.textPrimary;
    final surfaceColor = context.surface;
    final borderColor = context.border;
    final chats = ref.watch(oneovaInboxProvider);

    SystemChrome.setSystemUIOverlayStyle(
      isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          context.go('/hub/home');
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  _buildTopHeader(isDark, textColor, surfaceColor, borderColor),
                  _buildSearchBar(isDark, surfaceColor, borderColor),
                  _buildFilterPills(isDark, surfaceColor, borderColor),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 100),
                      children: [
                        if (_bannerVisible) _buildPromoBanner(isDark),
                        const SizedBox(height: 8),
                        ...chats.map((chat) => _buildChatItem(chat, isDark)),
                      ],
                    ),
                  ),
                ],
              ),
              _buildFloatingActionButtons(isDark),
              _buildBottomNavigationBar(isDark, borderColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isDark, Color textColor, Color surfaceColor, Color borderColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: isDark ? Colors.white : Colors.black),
                onPressed: () => context.go('/hub/home'),
                splashRadius: 20,
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: brandBlue,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: brandBlue.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'O',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Oneova',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isDark ? brandBlueSubtle : brandBlue.withValues(alpha: 0.1),
                  border: Border.all(color: brandBlue.withValues(alpha: 0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: brandBlue,
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              _buildIconButton(Icons.camera_alt_outlined, isDark, surfaceColor, borderColor),
              const SizedBox(width: 8),
              _buildIconButton(Icons.auto_awesome, isDark, surfaceColor, borderColor, iconColor: brandBlue, showPulse: true),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.more_vert, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                onPressed: () {},
                splashRadius: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, bool isDark, Color surfaceColor, Color borderColor, {Color? iconColor, bool showPulse = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: surfaceColor,
        shape: BoxShape.circle,
        border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 18, color: iconColor ?? (isDark ? Colors.grey[300] : Colors.grey[700])),
          if (showPulse)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: brandBlue,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, Color surfaceColor, Color borderColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(Icons.search, size: 20, color: Colors.grey[500]),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: 14, color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: 'Search chats, creators, channels...',
                  hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            Icon(Icons.tune, size: 18, color: Colors.grey[500]),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPills(bool isDark, Color surfaceColor, Color borderColor) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _buildPill('All', isActive: true, isDark: isDark, surfaceColor: surfaceColor, borderColor: borderColor),
          const SizedBox(width: 8),
          _buildPill('Unread', badge: '48', isDark: isDark, surfaceColor: surfaceColor, borderColor: borderColor),
          const SizedBox(width: 8),
          _buildPill('Favorites', isDark: isDark, surfaceColor: surfaceColor, borderColor: borderColor),
          const SizedBox(width: 8),
          _buildPill('Groups', suffix: '6', isDark: isDark, surfaceColor: surfaceColor, borderColor: borderColor),
          const SizedBox(width: 8),
          _buildPill('Channels', icon: Icons.campaign, isDark: isDark, surfaceColor: surfaceColor, borderColor: borderColor),
        ],
      ),
    );
  }

  Widget _buildPill(String text, {bool isActive = false, String? badge, String? suffix, IconData? icon, required bool isDark, required Color surfaceColor, required Color borderColor}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? brandBlue : surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? brandBlue : borderColor),
        boxShadow: isActive ? [BoxShadow(color: brandBlue.withValues(alpha: 0.2), blurRadius: 4, offset: const Offset(0, 2))] : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: isActive ? Colors.white : brandBlue),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : (isDark ? Colors.grey[300] : Colors.grey[800]),
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(10)),
              child: Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ],
          if (suffix != null) ...[
            const SizedBox(width: 6),
            Text(suffix, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[500])),
          ],
        ],
      ),
    );
  }

  Widget _buildPromoBanner(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF000817), Color(0xFF18181c), Color(0xFF000512)],
        ),
        border: Border.all(color: brandBlue.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: brandBlue.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [brandBlue, Colors.blue[900]!],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: brandBlue.withValues(alpha: 0.4), blurRadius: 8),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.bolt, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Oneova One AI Studio',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(color: brandBlue, borderRadius: BorderRadius.circular(4)),
                      child: const Text('PRO', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Advanced AI audio dubbing, multi-cam stream sync & unlimited 4K cloud.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[300], height: 1.2),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Unlock Creator Perks',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: brandBlue),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 12, color: brandBlue),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _bannerVisible = false),
            child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem(OneovaChat chat, bool isDark) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(oneovaInboxProvider.notifier).markAsRead(chat.id);
        },
        highlightColor: isDark ? AppColors.darkSurface : Colors.grey[200],
        splashColor: isDark ? AppColors.darkSurface.withValues(alpha: 0.5) : Colors.grey[300],
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Avatar
              SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: chat.avatarBorder != null ? Border.all(color: chat.avatarBorder!) : null,
                        boxShadow: chat.avatarRingColor != null ? [BoxShadow(color: chat.avatarRingColor!, spreadRadius: 2)] : null,
                      ),
                      child: ClipOval(
                        child: Image.network(
                          chat.avatarUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: Colors.grey[800]),
                        ),
                      ),
                    ),
                    if (chat.bottomRightIcon != null)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
                            shape: BoxShape.circle,
                            border: Border.all(color: isDark ? AppColors.outline : AppColors.lightBorder),
                          ),
                          alignment: Alignment.center,
                          child: Icon(chat.bottomRightIcon, size: 8, color: chat.bottomRightIconColor),
                        ),
                      ),
                    if (chat.onlineDot)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.green[500],
                            shape: BoxShape.circle,
                            border: Border.all(color: isDark ? AppColors.darkBackground : AppColors.lightBackground, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  chat.name,
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (chat.isVerified) ...[
                                const SizedBox(width: 4),
                                Icon(Icons.check_circle, size: 11, color: Colors.cyan[400]),
                              ],
                              if (chat.tagText != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: chat.tagBg,
                                    border: chat.tagBorder != null ? Border.all(color: chat.tagBorder!) : null,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    chat.tagText!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: chat.tagColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Text(
                          chat.time,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: chat.timeColor != null ? FontWeight.w600 : FontWeight.normal,
                            color: chat.timeColor ?? (isDark ? Colors.grey[500] : Colors.grey[600]),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (chat.isRead) ...[
                          Icon(Icons.done_all, size: 12, color: Colors.cyan[400]),
                          const SizedBox(width: 4),
                        ] else if (chat.isDelivered) ...[
                          Icon(Icons.check, size: 12, color: Colors.grey[500]),
                          const SizedBox(width: 4),
                        ],
                        if (chat.isVoiceMessage) ...[
                          Icon(Icons.play_circle_outline, size: 11, color: brandBlue),
                          const SizedBox(width: 4),
                          if (chat.voiceDuration != null) ...[
                            Text(chat.voiceDuration!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[400])),
                            const SizedBox(width: 4),
                          ],
                        ] else if (chat.isFileMessage) ...[
                          Icon(Icons.insert_drive_file, size: 10, color: brandBlue),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: RichText(
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[300] : Colors.grey[800]),
                              children: [
                                if (chat.messagePrefix != null)
                                  TextSpan(text: chat.messagePrefix, style: const TextStyle(fontWeight: FontWeight.w500)),
                                TextSpan(
                                  text: chat.messageText,
                                  style: TextStyle(
                                    fontWeight: chat.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                                    color: isDark ? (chat.unreadCount > 0 ? Colors.grey[200] : Colors.grey[400]) : Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (chat.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: brandBlue,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(color: brandBlue.withValues(alpha: 0.5), blurRadius: 4),
                              ],
                            ),
                            child: Text(
                              chat.unreadCount.toString(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButtons(bool isDark) {
    return Positioned(
      bottom: 80,
      right: 16,
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: (isDark ? AppColors.darkSurface : AppColors.lightSurface).withValues(alpha: 0.9),
              border: Border.all(color: Colors.purple[500]!.withValues(alpha: 0.4)),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(Icons.donut_large, color: Colors.purple[400], size: 20),
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: brandBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: brandBlue,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blue[400]!.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: brandBlue.withValues(alpha: 0.45), blurRadius: 20, offset: const Offset(0, 4)),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.add, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigationBar(bool isDark, Color borderColor) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, top: 10, left: 16, right: 16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
          border: Border(top: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, 'Chats', Icons.chat_bubble, badge: '48', isDark: isDark),
            _buildNavItem(1, 'Updates', Icons.play_circle_outline, dotColor: Colors.green[500], isDark: isDark),
            _buildNavItem(2, 'Communities', Icons.groups, isDark: isDark),
            _buildNavItem(3, 'Calls', Icons.videocam, dotColor: brandBlue, isDark: isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String label, IconData icon, {String? badge, Color? dotColor, required bool isDark}) {
    final isSelected = _selectedTabIndex == index;
    final color = isSelected ? brandBlue : (isDark ? Colors.grey[400] : Colors.grey[600]);
    
    return GestureDetector(
      onTap: () => setState(() => _selectedTabIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? brandBlue.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge != null)
                Positioned(
                  top: -4,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: brandBlue,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isDark ? AppColors.darkBackground : Colors.white, width: 2),
                    ),
                    child: Text(badge, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
              if (dotColor != null)
                Positioned(
                  top: 2,
                  right: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: isDark ? AppColors.darkBackground : Colors.white, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              color: isSelected ? (isDark ? Colors.white : brandBlue) : (isDark ? Colors.grey[400] : Colors.grey[600]),
            ),
          ),
        ],
      ),
    );
  }
}
