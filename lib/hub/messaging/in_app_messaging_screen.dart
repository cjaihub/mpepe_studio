import 'package:oneova/shared/widgets/smooth_load.dart';
import 'package:flutter/material.dart';
import '../../shared/widgets/follow_button.dart';
import '../../inbox/calling/call_launcher.dart';
import 'rooms/rooms_views.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:io';
import 'dart:math' as math;
import 'package:image_picker/image_picker.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../backend/social/services/story_service.dart';
import '../../backend/social/models/story.dart';
import '../../backend/storage_service.dart';
import '../../feed/widgets/story_viewer_screen.dart';
import 'connected_inboxes_dropdown.dart';
import 'platform_inbox_view.dart';
import '../../backend/connections/linked_accounts.dart' show LinkedPlatform;
import 'user_search_screen.dart';
import 'create_group_screen.dart';
import '../../providers/settings_provider.dart';
import '../../backend/social/providers/unread_chat_count_provider.dart';
import '../../backend/inbox/providers/presence_service.dart';
import '../../shared/widgets/live_user_presence_dot.dart';
import '../../ova_assistant/widgets/ova_assistant_sheet.dart';
import '../../backend/social/models/creator_engagement_level.dart';

/// The single Oneova inbox (`/hub/messages`): Oneova chats plus the
/// messages and comments of every linked platform. Every inbox entry point
/// routes here; `?platform=<id>` opens one linked platform's inbox.
class InAppMessagingScreen extends ConsumerStatefulWidget {
  final String? initialPlatform;

  const InAppMessagingScreen({super.key, this.initialPlatform});

  @override
  ConsumerState<InAppMessagingScreen> createState() =>
      _InAppMessagingScreenState();
}

class _InAppMessagingScreenState extends ConsumerState<InAppMessagingScreen> {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Active filter pill: 'all', 'unread', 'favorites', 'groups', 'channels', 'rooms', 'vip'
  String _activeFilter = 'all';

  // Bottom navigation tab: 0: Chats, 1: Updates, 2: Communities, 3: Calls
  int _activeBottomTab = 0;

  // Creator Pro Banner dismissed state
  bool _isBannerDismissed = false;

  // Inbox shown: 'all' (Oneova chats) or a LinkedPlatform id.
  late String _selectedPlatform = _platformOrAll(widget.initialPlatform);

  static String _platformOrAll(String? id) => LinkedPlatform.fromId(id)?.id ?? 'all';

  final Map<String, Future<AppUser?>> _userFutures = {};
  Future<AppUser?>? _currentUserFuture;

  Future<AppUser?> _getUserCached(String uid) {
    return _userFutures.putIfAbsent(
      uid,
      () => ref.read(userProvider.notifier).getUser(uid),
    );
  }

  @override
  void initState() {
    super.initState();
    if (currentUserId != null) {
      _currentUserFuture = ref
          .read(userProvider.notifier)
          .getUser(currentUserId!);
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void didUpdateWidget(covariant InAppMessagingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialPlatform != oldWidget.initialPlatform && widget.initialPlatform != null) {
      setState(() => _selectedPlatform = _platformOrAll(widget.initialPlatform));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openNewChatSearch() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const UserSearchScreen(),
    );
  }

  void _openCreateGroup() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CreateGroupScreen(),
    );
  }

  void _openNewBroadcast() {
    showCreateBroadcastSheet(context, ref);
  }

  void _openStarredMessagesSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: AppColors.brandPink,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Starred Messages',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.description_outlined,
                      color: AppColors.brandBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OneOva XML Sequence',
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Draft sequence ready for export (OneOva XML)',
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '4:38 AM',
                      style: GoogleFonts.inter(
                        color: context.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.border),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: AppColors.brandBlue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Young P Audio Master',
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '0:42 Iyi kitu ni mbaya Babu, drop the master!',
                            style: GoogleFonts.inter(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '4:51 AM',
                      style: GoogleFonts.inter(
                        color: context.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _openAiStudioCompanion() {
    HapticFeedback.lightImpact();
    OvaAssistantSheet.show(context);
  }

  void _showContextMenu(BuildContext context) {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: context.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.border, width: 1),
      ),
      elevation: 16,
      items: [
        PopupMenuItem(
          value: 'new_group',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'New group',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Icon(
                Icons.person_outline_rounded,
                size: 16,
                color: context.textMuted,
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'new_broadcast',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'New broadcast',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Icon(Icons.campaign_outlined, size: 16, color: context.textMuted),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'linked_devices',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Linked devices',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'SYNC',
                  style: TextStyle(
                    color: AppColors.brandBlue,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'starred',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Starred messages',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: AppColors.brandPink,
              ),
            ],
          ),
        ),
        PopupMenuDivider(height: 1),
        PopupMenuItem(
          value: 'chat_settings',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Chat settings',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Icon(
                Icons.tune_rounded,
                size: 16,
                color: AppColors.brandBlue,
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'settings',
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'All settings',
                style: GoogleFonts.inter(
                  color: context.textSecondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Icon(Icons.settings_outlined, size: 16, color: context.textMuted),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted || value == null) return;
      switch (value) {
        case 'new_group':
          _openCreateGroup();
          break;
        case 'new_broadcast':
          _openNewBroadcast();
          break;
        case 'linked_devices':
          context.push('/connect');
          break;
        case 'starred':
          _openStarredMessagesSheet();
          break;
        case 'chat_settings':
          context.push('/settings/chat');
          break;
        case 'settings':
          context.push('/settings/main');
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final chatsAsync = currentUserId != null
        ? ref.watch(userChatsProvider(currentUserId!))
        : const AsyncValue<List<ChatModel>>.data([]);

    final settingsAsync = ref.watch(settingsProvider);
    final chatSettings =
        settingsAsync.value?['chat'] as Map<String, dynamic>? ?? {};

    final bool showAiStudioFab = chatSettings['showAiStudioFab'] ?? true;
    final bool showComposeFab = chatSettings['showComposeFab'] ?? true;
    final String fabAlignment = chatSettings['fabAlignment'] ?? 'right';
    final int quickCreatorsLimit = chatSettings['quickCreatorsLimit'] ?? 5;
    final bool showCreatorProBanner =
        chatSettings['showCreatorProBanner'] ?? true;

    return Scaffold(
      backgroundColor: context.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top App Header
                _buildTopAppHeader(),

                // Top Section Tabs: Chats | Calls | Updates | Communities
                // Placed at top so when in the chat panel there are no other menus under it
                _buildTopSectionTabs(chatsAsync),

                // Chat-list chrome (search, platform banner, filter pills) is hidden
                // on the Status tab so it stays a clean WhatsApp-style status list.
                if (_activeBottomTab != 1) ...[
                  // Search Bar
                  _buildSearchBar(),

                  // Filter chips only make sense for the Oneova chat list
                  if (_activeBottomTab == 0 && _selectedPlatform == 'all') _buildFilterPillsBar(chatsAsync),
                ],

                // Main Content Body (Chats list, Communities/Rooms, or Updates/Calls)
                Expanded(
                  child: _buildMainContent(
                    chatsAsync,
                    quickCreatorsLimit: quickCreatorsLimit,
                    showCreatorProBanner: showCreatorProBanner,
                  ),
                ),
              ],
            ),

            // Two-Tiered Floating Action Buttons (compact 20px bottom offset, no menus below)
            if (_activeBottomTab == 0 &&
                _activeFilter != 'rooms' &&
                _activeFilter != 'vip' &&
                (showAiStudioFab || showComposeFab))
              Positioned(
                bottom: 20,
                left: fabAlignment == 'left' ? 16 : null,
                right: fabAlignment == 'right' ? 16 : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: fabAlignment == 'left' ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                  children: [
                    // Top AI Studio Companion circular widget
                    if (showAiStudioFab) _buildAiStudioFab(),
                    if (showAiStudioFab && showComposeFab)
                      const SizedBox(height: 10),
                    // Primary Compose New DM blue + button
                    if (showComposeFab) _buildComposeFab(),
                  ],
                ),
              ),

            // Calls tab: start a new call
            if (_activeBottomTab == 3)
              Positioned(
                bottom: 20,
                left: fabAlignment == 'left' ? 16 : null,
                right: fabAlignment == 'right' ? 16 : null,
                child: _buildComposeFab(forCall: true),
              ),

            // Status tab: WhatsApp-style text (pencil) + camera buttons
            if (_activeBottomTab == 1)
              Positioned(
                bottom: 20,
                left: fabAlignment == 'left' ? 16 : null,
                right: fabAlignment == 'right' ? 16 : null,
                child: _buildStatusFabs(),
              ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. TOP APP HEADER
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTopAppHeader() {
    final unreadCount = ref.watch(unreadChatCountProvider).value ?? 0;
    final fg = context.topBarFg;
    final title = switch (_activeBottomTab) {
      1 => 'Updates',
      2 => 'Communities',
      3 => 'Calls',
      _ => 'Chats',
    };

    Widget action(IconData icon, String tooltip, VoidCallback onTap) =>
        IconButton(
          icon: Icon(icon, color: fg, size: 20),
          tooltip: tooltip,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          onPressed: () {
            HapticFeedback.lightImpact();
            onTap();
          },
        );

    // Large system font sizes used to push this row past the screen edge.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Container(
        height: 52,
        padding: const EdgeInsets.only(left: 4, right: 4),
        color: AppColors.brandBlue,
        child: Row(
          children: [
            action(Icons.arrow_back_ios_new_rounded, 'Back', () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              } else {
                context.go('/hub/home');
              }
            }),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: fg,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: GoogleFonts.inter(
                          color: AppColors.brandWhite,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Ova AI: compact gradient chip
            Tooltip(
              message: 'Ova AI Assistant',
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  OvaAssistantSheet.show(context);
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: fg.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, color: fg, size: 16),
                ),
              ),
            ),
            const SizedBox(width: 2),
            action(
              Icons.camera_alt_outlined,
              'Camera',
              () => context.push('/create/camera'),
            ),
            // Inbox source (Omni / connected platforms)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                ConnectedInboxesDropdown.show(
                  context,
                  totalUnreadCount: unreadCount,
                  selectedPlatform: _selectedPlatform,
                  onSelectPlatform: (platform) =>
                      setState(() => _selectedPlatform = platform),
                );
              },
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: fg.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.grid_view_rounded, size: 13, color: fg),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 64),
                      child: Text(
                        _resolveSelectedPlatformName(_selectedPlatform),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: fg,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 14,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ],
                ),
              ),
            ),
            Builder(
              builder: (menuContext) => action(
                Icons.more_vert,
                'More',
                () => _showContextMenu(menuContext),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _resolveSelectedPlatformName(String platform) =>
      LinkedPlatform.fromId(platform)?.label ?? 'All chats';

  // ──────────────────────────────────────────────────────────────────────────
  // 2. SEARCH BAR
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildSearchBar() {
    final filtered = _activeFilter != 'all';
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: context.border, width: 1),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(
                      Icons.search_rounded,
                      color: context.textMuted,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 13,
                        ),
                        cursorColor: AppColors.brandBlue,
                        decoration: InputDecoration(
                          hintText: _activeBottomTab == 3
                              ? 'Search calls'
                              : 'Search chats and people',
                          hintStyle: GoogleFonts.inter(
                            color: context.textMuted,
                            fontSize: 13,
                          ),
                          // The app input theme adds its own fill/border.
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: context.textMuted,
                        ),
                        tooltip: 'Clear',
                        onPressed: () => _searchController.clear(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            if (_activeBottomTab == 0) ...[
              const SizedBox(width: 8),
              Tooltip(
                message: 'Filters',
                child: GestureDetector(
                  onTap: _showFilterSheet,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: filtered
                          ? AppColors.brandBlue
                          : context.surfaceMid,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: filtered ? AppColors.brandBlue : context.border,
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: filtered
                              ? AppColors.brandWhite
                              : context.textSecondary,
                        ),
                        if (filtered)
                          Positioned(
                            top: 7,
                            right: 7,
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.brandPink,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 3. FILTER PILLS HORIZONTAL BAR
  // ──────────────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _filterDefs(
    AsyncValue<List<ChatModel>> chatsAsync,
  ) {
    final uid = currentUserId ?? '';
    final chats = chatsAsync.value ?? const <ChatModel>[];
    var totalUnread = 0;
    for (final c in chats) {
      totalUnread += c.unreadCounts[uid] ?? 0;
    }
    final groupCount = chats
        .where((c) => c.category == 'group' || c.participants.length > 2)
        .length;
    final requestCount = chats
        .where(
          (c) =>
              !c.isMutual &&
              c.participants.length == 2 &&
              c.category != 'group' &&
              c.category != 'channel',
        )
        .length;
    return [
      {'id': 'all', 'label': 'All', 'icon': Icons.forum_rounded},
      {
        'id': 'unread',
        'label': 'Unread',
        'icon': Icons.mark_chat_unread_rounded,
        if (totalUnread > 0) 'badge': '$totalUnread',
      },
      {
        'id': 'requests',
        'label': 'Requests',
        'icon': Icons.mark_email_unread_rounded,
        if (requestCount > 0) 'badge': '$requestCount',
      },
      {
        'id': 'groups',
        'label': 'Groups',
        'icon': Icons.groups_rounded,
        if (groupCount > 0) 'badge': '$groupCount',
      },
      {'id': 'favorites', 'label': 'Favorites', 'icon': Icons.star_rounded},
      {'id': 'verified', 'label': 'Verified', 'icon': Icons.verified_rounded},
      {'id': 'channels', 'label': 'Channels', 'icon': Icons.campaign_rounded},
      {
        'id': 'voicenotes',
        'label': 'Voice memos',
        'icon': Icons.graphic_eq_rounded,
      },
      {
        'id': 'files',
        'label': 'Files & media',
        'icon': Icons.attach_file_rounded,
      },
      {'id': 'rooms', 'label': 'Rooms', 'icon': Icons.meeting_room_rounded},
      {
        'id': 'vip',
        'label': 'VIP private',
        'icon': Icons.workspace_premium_rounded,
      },
    ];
  }

  void _setFilter(String id) {
    HapticFeedback.selectionClick();
    setState(() => _activeFilter = id);
  }

  void _showFilterSheet() {
    HapticFeedback.lightImpact();
    final defs = _filterDefs(
      currentUserId != null
          ? ref.read(userChatsProvider(currentUserId!))
          : const AsyncValue<List<ChatModel>>.data([]),
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ctx.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter chats',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ctx.textPrimary,
                      ),
                    ),
                  ),
                  if (_activeFilter != 'all')
                    TextButton(
                      onPressed: () {
                        _setFilter('all');
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        'Reset',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final d in defs)
                    _filterChip(
                      d,
                      onTap: () {
                        _setFilter(d['id'] as String);
                        Navigator.of(ctx).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(Map<String, dynamic> pill, {required VoidCallback onTap}) {
    final id = pill['id'] as String;
    final selected = _activeFilter == id;
    final badge = pill['badge'] as String?;
    final icon = pill['icon'] as IconData?;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? AppColors.brandBlue : context.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: selected ? AppColors.brandWhite : AppColors.brandBlue,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              pill['label'] as String,
              style: GoogleFonts.inter(
                color: selected ? AppColors.brandWhite : context.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 12,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: selected ? AppColors.brandWhite : AppColors.brandPink,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: selected
                        ? AppColors.brandPink
                        : AppColors.brandWhite,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPillsBar(AsyncValue<List<ChatModel>> chatsAsync) {
    final pills = _filterDefs(chatsAsync);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: SizedBox(
        height: 40,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          itemCount: pills.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) => _filterChip(
            pills[index],
            onTap: () => _setFilter(pills[index]['id'] as String),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4. MAIN CONTENT ROUTER
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMainContent(
    AsyncValue<List<ChatModel>> chatsAsync, {
    required int quickCreatorsLimit,
    required bool showCreatorProBanner,
  }) {
    // Bottom tabs win; chat filters only apply on the Chats tab.
    if (_activeBottomTab == 1) {
      return _buildUpdatesTab();
    } else if (_activeBottomTab == 2) {
      return _buildRoomsList();
    } else if (_activeBottomTab == 3) {
      return _buildCallsTab();
    } else if (_activeFilter == 'rooms') {
      return _buildRoomsList();
    } else if (_activeFilter == 'vip') {
      return _buildVipPrivateRoomsList();
    } else if (_activeFilter == 'verified') {
      return _buildVerifiedCreatorsView();
    } else if (_activeFilter == 'requests') {
      return _buildMessageRequestsView(chatsAsync);
    }

    // A linked platform's messages and comments.
    if (_selectedPlatform != 'all') {
      return PlatformInboxView(
        key: ValueKey(_selectedPlatform),
        platformId: _selectedPlatform,
        onShowAll: () => setState(() => _selectedPlatform = 'all'),
      );
    }

    // Default: Chats Inbox List with following creators quick message bar
    return Column(
      children: [
        if (quickCreatorsLimit > 0)
          _buildFollowingCreatorsBar(quickCreatorsLimit),
        Expanded(child: _buildChatsList(chatsAsync)),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 4B. MESSAGE REQUESTS VIEW (NON-MUTUAL FOLLOWERS)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildMessageRequestsView(AsyncValue<List<ChatModel>> chatsAsync) {
    return chatsAsync.smoothWhen(
      data: (chats) {
        final requests = chats
            .where(
              (c) =>
                  !c.isMutual &&
                  c.participants.length == 2 &&
                  c.category != 'group' &&
                  c.category != 'channel',
            )
            .toList();

        if (requests.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.brandBlue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.mark_email_read_rounded,
                      color: AppColors.brandBlue,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Pending Message Requests',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When people you don’t follow send you a message, their requests will appear here. To see them in your primary inbox, follow each other to become mutual connections.',
                    style: GoogleFonts.inter(
                      color: context.textMuted,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _openNewChatSearch,
                    icon: const Icon(
                      Icons.person_search_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Discover Creators & Follow',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final chat = requests[index];
            final otherUserId = chat.participants.firstWhere(
              (id) => id != currentUserId,
              orElse: () => chat.participants.first,
            );
            final tier = CreatorTier.fromLevel(chat.creatorLevel);

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildAvatarWithBadge(chat, otherUserId),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chat.title ?? 'Creator Contact',
                                    style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (chat.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.brandBlue,
                                    size: 13,
                                  ),
                                ],
                                const SizedBox(width: 6),
                                CreatorLevelBadge(
                                  tier: tier,
                                  isCompact: true,
                                  onTap: () {
                                    CreatorLevelDetailModal.show(
                                      context,
                                      tier: tier,
                                      username: chat.title,
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              chat.lastMessage.isNotEmpty
                                  ? chat.lastMessage
                                  : 'Wants to send you a message',
                              style: GoogleFonts.inter(
                                color: context.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            context.push('/hub/messages/${chat.id}');
                          },
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                          child: Text(
                            'Preview Chat',
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FollowButton(
                          targetUserId: otherUserId,
                          targetName: chat.title,
                          expand: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const OneovaSkeleton(),
      error: (e, _) => Center(
        child: Text('Error: $e', style: TextStyle(color: AppColors.brandPink)),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5. PROMOTIONAL BANNER: ONEOVA ONE AI STUDIO
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCreatorProBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandBlue.withValues(alpha: 0.10),
            context.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.brandBlue.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withOpacity(0.2),
            blurRadius: 18,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Badge
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.brandBlue, Color(0xFF083B82)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withOpacity(0.4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.bolt_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'VIP private rooms',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Host members-only rooms for your community and approve who joins.',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _activeFilter = 'vip');
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Browse VIP rooms',
                        style: TextStyle(
                          color: AppColors.brandBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: AppColors.brandBlue,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Dismiss Button
          GestureDetector(
            onTap: () {
              setState(() {
                _isBannerDismissed = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(Icons.close, size: 16, color: context.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 5B. FOLLOWING CREATORS · QUICK MESSAGE HORIZONTAL BAR
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildFollowingCreatorsBar([int limit = 5]) {
    final creatorsAsync = ref.watch(
      followedCreatorsProvider(currentUserId ?? ''),
    );

    return creatorsAsync.when(
      data: (creators) {
        if (creators.isEmpty) return const SizedBox.shrink();
        final displayedCreators = creators.take(limit).toList();

        return Container(
          height: 104,
          padding: const EdgeInsets.symmetric(vertical: 8),
          margin: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Following Creators · Quick Message',
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    GestureDetector(
                      onTap: _openNewChatSearch,
                      child: Text(
                        'Find People',
                        style: GoogleFonts.inter(
                          color: AppColors.brandBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: displayedCreators.length,
                  itemBuilder: (context, index) {
                    final creator = displayedCreators[index];
                    final targetId =
                        (creator['id'] as String?) ??
                        (creator['uid'] as String?) ??
                        '';
                    final name =
                        (creator['displayName'] as String?)?.isNotEmpty == true
                        ? creator['displayName'] as String
                        : ((creator['fullName'] as String?)?.isNotEmpty == true
                              ? creator['fullName'] as String
                              : ((creator['username'] as String?) ??
                                    'Creator'));
                    final avatarUrl =
                        (creator['profilePhotoUrl'] as String?) ??
                        (creator['photoUrl'] as String?);
                    final isVerified =
                        (creator['isVerified'] as bool?) ?? false;

                    return GestureDetector(
                      onTap: () => _openChatWithTarget(targetId),
                      child: Container(
                        width: 68,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.brandBlue,
                                      width: 2,
                                    ),
                                  ),
                                  child: ClipOval(
                                    child:
                                        (avatarUrl != null &&
                                            avatarUrl.isNotEmpty)
                                        ? Image.network(
                                            avatarUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                _avatarInitialFallback(name),
                                          )
                                        : _avatarInitialFallback(name),
                                  ),
                                ),
                                if (isVerified)
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: context.bg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.check_circle,
                                        color: AppColors.brandBlue,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  bottom: -1,
                                  left: 0,
                                  right: 0,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 0.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: CreatorTier.fromLevel(
                                          creator['creatorLevel'] as int? ?? 1,
                                        ).primaryColor,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: context.bg,
                                          width: 1,
                                        ),
                                      ),
                                      child: Text(
                                        CreatorTier.fromLevel(
                                          creator['creatorLevel'] as int? ?? 1,
                                        ).shortCode,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 8,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _openChatWithTarget(String targetUserId) async {
    final uid = currentUserId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || targetUserId.isEmpty) return;

    // Show loading indicator dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
    );

    try {
      final chatId = await ref
          .read(messagingRepositoryProvider)
          .getOrCreateDirectChat(uid, targetUserId);
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      context.push('/hub/messages/$chatId');
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error starting chat: $e')));
    }
  }

  Widget _avatarInitialFallback(String name) {
    final letter = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      color: context.surfaceMid,
      alignment: Alignment.center,
      child: Text(
        letter,
        style: TextStyle(
          color: context.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildEmptyChatsState() {
    final creatorsAsync = ref.watch(
      followedCreatorsProvider(currentUserId ?? ''),
    );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.brandBlue.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 32,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Conversations Yet',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Message real creators you follow or start a conversation with Oneova platform creators.',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 13,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            creatorsAsync.when(
              data: (creators) {
                if (creators.isEmpty) {
                  return ElevatedButton.icon(
                    onPressed: _openNewChatSearch,
                    icon: const Icon(
                      Icons.search,
                      color: Colors.white,
                      size: 18,
                    ),
                    label: const Text(
                      'Find Creators to Message',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Suggested Creators to Message:',
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...creators.take(4).map((c) {
                      final targetId =
                          (c['id'] as String?) ?? (c['uid'] as String?) ?? '';
                      final name =
                          (c['displayName'] as String?)?.isNotEmpty == true
                          ? c['displayName'] as String
                          : ((c['fullName'] as String?)?.isNotEmpty == true
                                ? c['fullName'] as String
                                : ((c['username'] as String?) ?? 'Creator'));
                      final avatarUrl =
                          (c['profilePhotoUrl'] as String?) ??
                          (c['photoUrl'] as String?);
                      final isVerified = (c['isVerified'] as bool?) ?? false;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.border),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.brandBlue,
                              backgroundImage:
                                  (avatarUrl != null && avatarUrl.isNotEmpty)
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            color: context.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isVerified) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.verified,
                                          color: AppColors.brandBlue,
                                          size: 14,
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (c['username'] != null &&
                                      (c['username'] as String).isNotEmpty)
                                    Text(
                                      '@${c['username']}',
                                      style: TextStyle(
                                        color: context.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () => _openChatWithTarget(targetId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.brandBlue,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Message',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: _openNewChatSearch,
                        icon: Icon(
                          Icons.search,
                          color: AppColors.brandBlue,
                          size: 16,
                        ),
                        label: Text(
                          'Search More People',
                          style: TextStyle(
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: AppColors.brandBlue),
              ),
              error: (_, __) => ElevatedButton.icon(
                onPressed: _openNewChatSearch,
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                label: const Text(
                  'Start New Conversation',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6. CHAT INBOX CONVERSATION LIST
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildChatsList(AsyncValue<List<ChatModel>> chatsAsync) {
    return chatsAsync.when(
      data: (chats) {
        // Apply filter logic
        var filtered = chats;

        // Strict Mutual Connection Gate: Only mutual followers appear in the primary inbox
        // Non-mutual chats are accessible via the 'Requests' pill
        filtered = filtered.where((c) {
          if (c.category == 'group' ||
              c.category == 'channel' ||
              c.participants.length > 2) {
            return true;
          }
          return c.isMutual;
        }).toList();

        if (_activeFilter == 'unread') {
          filtered = filtered
              .where((c) => (c.unreadCounts[currentUserId!] ?? 0) > 0)
              .toList();
        } else if (_activeFilter == 'favorites') {
          filtered = filtered.where((c) => c.isStarred).toList();
        } else if (_activeFilter == 'groups') {
          filtered = filtered
              .where((c) => c.category == 'group' || c.participants.length > 2)
              .toList();
        } else if (_activeFilter == 'channels') {
          filtered = filtered.where((c) => c.category == 'channel').toList();
        } else if (_activeFilter == 'voicenotes') {
          filtered = filtered
              .where(
                (c) =>
                    c.hasVoiceMemo ||
                    c.lastMessage.toLowerCase().contains('voice note') ||
                    c.lastMessage.contains('🎙️'),
              )
              .toList();
        } else if (_activeFilter == 'files') {
          filtered = filtered
              .where(
                (c) =>
                    c.lastMessage.toLowerCase().contains('document') ||
                    c.lastMessage.contains('📄') ||
                    c.lastMessage.contains('photo') ||
                    c.lastMessage.contains('📷') ||
                    c.lastMessage.contains('video') ||
                    c.lastMessage.contains('🎥'),
              )
              .toList();
        }

        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((c) {
            final t = (c.title ?? '').toLowerCase();
            final msg = c.lastMessage.toLowerCase();
            final role = (c.roleBadge ?? '').toLowerCase();
            return t.contains(_searchQuery) ||
                msg.contains(_searchQuery) ||
                role.contains(_searchQuery);
          }).toList();

          return _buildAdvancedSearchCombinedView(filtered);
        }

        if (filtered.isEmpty) {
          if (_activeFilter != 'all') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 56,
                    color: context.border,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No conversations found',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _openNewChatSearch,
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text(
                      'Start New Conversation',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          return _buildEmptyChatsState();
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 4, bottom: 90),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final chat = filtered[index];
            return _buildChatItem(chat, index);
          },
        );
      },
      loading: () =>
          Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
      error: (err, _) => Center(
        child: Text(
          'Error: $err',
          style: TextStyle(color: AppColors.brandPink),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6B. ADVANCED COMBINED SEARCH VIEW (VERIFIED CREATORS + CHATS)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildAdvancedSearchCombinedView(List<ChatModel> filteredChats) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];
        final verifiedUsers = docs
            .map(
              (doc) =>
                  AppUser.fromMap(doc.data() as Map<String, dynamic>, doc.id),
            )
            .where((u) => u.id != currentUserId)
            .where((u) {
              final name = u.fullName.toLowerCase();
              final username = (u.username ?? '').toLowerCase();
              final bio = (u.bio ?? '').toLowerCase();
              final job = (u.jobTitle ?? '').toLowerCase();
              final role = u.role.toLowerCase();
              return name.contains(_searchQuery) ||
                  username.contains(_searchQuery) ||
                  bio.contains(_searchQuery) ||
                  job.contains(_searchQuery) ||
                  role.contains(_searchQuery);
            })
            .toList();

        final hasVerified = verifiedUsers.isNotEmpty;
        final hasChats = filteredChats.isNotEmpty;

        if (!hasVerified && !hasChats) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.search_off_rounded,
                      size: 32,
                      color: AppColors.brandPink,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No results for "$_searchQuery"',
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Try searching with a creator name, handle, role, or message content.',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _openNewChatSearch,
                    icon: const Icon(
                      Icons.person_search_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    label: const Text(
                      'Explore All Creators',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(top: 6, bottom: 90),
          children: [
            if (hasVerified) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.verified_rounded,
                      color: AppColors.brandBlue,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Verified Creators',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${verifiedUsers.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ...verifiedUsers.map(
                (user) => _buildVerifiedCreatorSearchCard(user),
              ),
              const SizedBox(height: 10),
            ],

            if (hasChats) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.brandPink,
                      size: 15,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Conversations',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '(${filteredChats.length})',
                      style: TextStyle(color: context.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              ...List.generate(
                filteredChats.length,
                (index) => _buildChatItem(filteredChats[index], index),
              ),
            ],
          ],
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6C. VERIFIED CREATORS VIEW (DEDICATED FILTER TAB)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildVerifiedCreatorsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isVerified', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.brandBlue),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final verifiedUsers = docs
            .map(
              (doc) =>
                  AppUser.fromMap(doc.data() as Map<String, dynamic>, doc.id),
            )
            .where((u) => u.id != currentUserId)
            .toList();

        final filtered = _searchQuery.isEmpty
            ? verifiedUsers
            : verifiedUsers.where((u) {
                final name = u.fullName.toLowerCase();
                final username = (u.username ?? '').toLowerCase();
                final bio = (u.bio ?? '').toLowerCase();
                final job = (u.jobTitle ?? '').toLowerCase();
                final role = u.role.toLowerCase();
                return name.contains(_searchQuery) ||
                    username.contains(_searchQuery) ||
                    bio.contains(_searchQuery) ||
                    job.contains(_searchQuery) ||
                    role.contains(_searchQuery);
              }).toList();

        if (filtered.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: AppColors.brandBlue,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _searchQuery.isEmpty
                      ? 'No Verified Creators Found'
                      : 'No verified creators matching "$_searchQuery"',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Verified creators have official authenticity checkmarks and badges.',
                  style: GoogleFonts.inter(
                    color: context.textMuted,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 90),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            return _buildVerifiedCreatorSearchCard(filtered[index]);
          },
        );
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 6D. ADVANCED SEARCH CARD WITH VERIFIED USERS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildVerifiedCreatorSearchCard(AppUser user) {
    final role =
        (user.jobTitle?.isNotEmpty == true
                ? user.jobTitle!
                : (user.role.isNotEmpty ? user.role : 'CREATOR'))
            .toUpperCase();
    final username = user.username?.isNotEmpty == true
        ? user.username!
        : 'creator';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar with VIP verified ring and presence dot
              Consumer(
                builder: (context, ref, _) {
                  final presenceAsync = ref.watch(
                    userPresenceDetailsProvider(user.id),
                  );
                  final presence = presenceAsync.value ?? const UserPresence();

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.brandBlue,
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child:
                              (user.profilePhotoUrl != null &&
                                  user.profilePhotoUrl!.isNotEmpty)
                              ? Image.network(
                                  user.profilePhotoUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _avatarInitialFallback(user.fullName),
                                )
                              : _avatarInitialFallback(user.fullName),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: LiveUserPresenceDot(
                          presence: presence,
                          size: 12,
                          borderColor: context.surface,
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(width: 12),

              // Info column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            user.fullName,
                            style: GoogleFonts.inter(
                              color: context.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.brandBlue.withValues(
                                alpha: 0.45,
                              ),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.verified_rounded,
                                color: AppColors.brandBlue,
                                size: 10.5,
                              ),
                              const SizedBox(width: 2.5),
                              Text(
                                'VERIFIED',
                                style: GoogleFonts.inter(
                                  color: AppColors.brandBlue,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '@$username',
                          style: GoogleFonts.inter(
                            color: context.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(
                            color: context.border,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            role,
                            style: GoogleFonts.inter(
                              color: AppColors.brandPink,
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          if (user.bio != null && user.bio!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              user.bio!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: context.textSecondary,
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],

          const SizedBox(height: 10),
          // Security / Status Strip
          Row(
            children: [
              const Icon(
                Icons.shield_rounded,
                color: AppColors.brandBlue,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                'Oneova Shield · 1:1 chats end-to-end encrypted',
                style: GoogleFonts.inter(
                  color: context.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              if (user.location != null && user.location!.isNotEmpty) ...[
                Icon(
                  Icons.location_on_outlined,
                  color: context.textMuted,
                  size: 11,
                ),
                const SizedBox(width: 2),
                Text(
                  user.location!,
                  style: GoogleFonts.inter(
                    color: context.textMuted,
                    fontSize: 10,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 12),
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ElevatedButton.icon(
                    onPressed: () => _openChatWithTarget(user.id),
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                    label: Text(
                      'Message',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: OutlinedButton.icon(
                    onPressed: () => _openChatWithTarget(user.id),
                    icon: const Icon(
                      Icons.graphic_eq_rounded,
                      size: 15,
                      color: AppColors.brandPink,
                    ),
                    label: Text(
                      'Voice Drop',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brandPink,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: AppColors.brandPink.withValues(alpha: 0.5),
                        width: 1.0,
                      ),
                      backgroundColor: AppColors.brandPink.withValues(
                        alpha: 0.12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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

  Widget _buildChatItem(ChatModel chat, int index) {
    final unreadCount = chat.unreadCounts[currentUserId!] ?? 0;
    final otherUserId = chat.participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => chat.participants.first,
    );

    // Formatted time or fallback
    final timeStr = chat.lastMessageTime != null
        ? timeago.format(chat.lastMessageTime!.toDate(), locale: 'en_short')
        : 'now';

    return InkWell(
          onTap: () {
            context.push('/hub/messages/${chat.id}');
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                // Avatar with overlay badge
                _buildAvatarWithBadge(chat, otherUserId),
                const SizedBox(width: 12),

                // Middle Text Column
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    chat.title ?? 'Creator Contact',
                                    style: GoogleFonts.inter(
                                      color: context.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (chat.isVerified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.check_circle_rounded,
                                    color: AppColors.brandBlue,
                                    size: 13,
                                  ),
                                ],
                                const SizedBox(width: 4),
                                CreatorLevelBadge(
                                  tier: CreatorTier.fromLevel(
                                    chat.creatorLevel,
                                  ),
                                  isCompact: true,
                                  onTap: () {
                                    CreatorLevelDetailModal.show(
                                      context,
                                      tier: CreatorTier.fromLevel(
                                        chat.creatorLevel,
                                      ),
                                      username: chat.title,
                                    );
                                  },
                                ),
                                if (chat.roleBadge != null &&
                                    chat.roleBadge!.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  _buildRoleBadge(chat.roleBadge!),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            timeStr,
                            style: GoogleFonts.inter(
                              color: unreadCount > 0
                                  ? AppColors.brandPink
                                  : context.textMuted,
                              fontSize: 10.5,
                              fontWeight: unreadCount > 0
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Message Snippet row
                      Row(
                        children: [
                          // Delivery checkmark ticks
                          if (chat.deliveryStatus == 'read') ...[
                            const Icon(
                              Icons.done_all_rounded,
                              size: 14,
                              color: AppColors.brandPink,
                            ),
                            const SizedBox(width: 4),
                          ] else if (chat.deliveryStatus == 'delivered') ...[
                            Icon(
                              Icons.done_all_rounded,
                              size: 14,
                              color: context.textMuted,
                            ),
                            const SizedBox(width: 4),
                          ] else if (chat.deliveryStatus == 'sent') ...[
                            Icon(
                              Icons.done_rounded,
                              size: 14,
                              color: context.textMuted,
                            ),
                            const SizedBox(width: 4),
                          ],

                          // Audio duration or waveform
                          if (chat.hasVoiceMemo) ...[
                            const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 14,
                              color: AppColors.brandBlue,
                            ),
                            const SizedBox(width: 4),
                            if (chat.voiceDuration != null) ...[
                              Text(
                                chat.voiceDuration!,
                                style: GoogleFonts.inter(
                                  color: context.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                          ] else if (chat.avatarOverlayIcon == 'whatsapp' ||
                              chat.category == 'whatsapp_sync') ...[
                            const Icon(
                              Icons.description_rounded,
                              size: 13,
                              color: AppColors.brandBlue,
                            ),
                            const SizedBox(width: 4),
                          ],

                          // Message snippet
                          Expanded(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                children: [
                                  if (chat.messagePrefix != null)
                                    TextSpan(
                                      text: chat.messagePrefix!,
                                      style: GoogleFonts.inter(
                                        color: context.textSecondary,
                                        fontSize: 12.0,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  TextSpan(
                                    text: chat.lastMessage.isNotEmpty
                                        ? chat.lastMessage
                                        : 'Tap to open conversation',
                                    style: GoogleFonts.inter(
                                      color: unreadCount > 0
                                          ? context.textPrimary
                                          : context.textSecondary,
                                      fontSize: 12.0,
                                      fontWeight: unreadCount > 0
                                          ? FontWeight.w500
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Unread count badge circle
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.brandPink.withOpacity(
                                      0.45,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                '$unreadCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
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
        )
        .animate()
        .fadeIn(delay: Duration(milliseconds: 25 * index))
        .slideX(begin: 0.05, end: 0);
  }

  Widget _buildAvatarWithBadge(ChatModel chat, String otherUserId) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: chat.isOnline
                  ? AppColors.brandPink
                  : (chat.roleBadge == 'PRO'
                        ? AppColors.brandBlue
                        : AppColors.brandBlue.withOpacity(0.4)),
              width: 1.5,
            ),
          ),
          child: ClipOval(
            child: chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty
                ? Image.network(
                    chat.avatarUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildFallbackAvatar(chat.title),
                  )
                : _buildFallbackAvatar(chat.title),
          ),
        ),

        // Bottom right badge overlay on avatar
        if (chat.isOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                shape: BoxShape.circle,
                border: Border.all(color: context.surface, width: 2),
              ),
            ),
          )
        else if (chat.avatarOverlayIcon == 'music')
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.border),
              ),
              child: const Icon(
                Icons.music_note_rounded,
                size: 10,
                color: AppColors.brandBlue,
              ),
            ),
          )
        else if (chat.avatarOverlayIcon == 'video')
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.border),
              ),
              child: const Icon(
                Icons.videocam_rounded,
                size: 10,
                color: AppColors.brandBlue,
              ),
            ),
          )
        else if (chat.avatarOverlayIcon == 'whatsapp' ||
            chat.category == 'whatsapp_sync')
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.border),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 10,
                color: AppColors.brandBlue,
              ),
            ),
          )
        else if (chat.avatarOverlayIcon == 'lightning')
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: context.border),
              ),
              child: const Icon(
                Icons.bolt_rounded,
                size: 11,
                color: AppColors.brandPink,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFallbackAvatar(String? title) {
    final letter = (title != null && title.isNotEmpty)
        ? title[0].toUpperCase()
        : 'O';
    return Container(
      color: context.surfaceMid,
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(
            color: AppColors.brandBlue,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildRoleBadge(String badge) {
    Color textColor = const Color(0xFF0C4FA8);
    Color bgColor = const Color(0xFF0C4FA8).withOpacity(0.15);
    Color borderColor = const Color(0xFF0C4FA8).withOpacity(0.4);

    final bUpper = badge.toUpperCase();
    if (bUpper == 'CHANNEL') {
      textColor = const Color(0xFF0C4FA8);
      bgColor = const Color(0xFF0C4FA8).withOpacity(0.15);
      borderColor = const Color(0xFF0C4FA8).withOpacity(0.4);
    } else if (bUpper == 'PRO') {
      textColor = AppColors.brandBlue;
      bgColor = AppColors.brandBlue.withOpacity(0.15);
      borderColor = AppColors.brandBlue.withOpacity(0.4);
    } else if (bUpper == 'DIR') {
      textColor = const Color(0xFFC084FC);
      bgColor = const Color(0xFF9333EA).withOpacity(0.2);
      borderColor = const Color(0xFF9333EA).withOpacity(0.4);
    } else if (bUpper == 'ARTIST') {
      textColor = context.textSecondary;
      bgColor = context.surfaceMid;
      borderColor = Colors.white.withOpacity(0.1);
    } else if (bUpper == 'WHATSAPP SYNC') {
      textColor = const Color(0xFF34D399);
      bgColor = const Color(0xFF10B981).withOpacity(0.15);
      borderColor = const Color(0xFF10B981).withOpacity(0.4);
    } else if (bUpper == 'PRODUCER') {
      textColor = const Color(0xFFFCD34D);
      bgColor = const Color(0xFFF59E0B).withOpacity(0.2);
      borderColor = const Color(0xFFF59E0B).withOpacity(0.4);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Text(
        badge,
        style: TextStyle(
          color: textColor,
          fontSize: 8.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 7. FLOATING ACTION BUTTONS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildAiStudioFab() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _openAiStudioCompanion,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.brandBlue, AppColors.brandPink],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.brandBlue.withOpacity(0.35),
              blurRadius: 14,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(2.5),
        child: Container(
          decoration: BoxDecoration(color: context.bg, shape: BoxShape.circle),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(
                Icons.circle_outlined,
                color: AppColors.brandBlue,
                size: 26,
              ),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.brandBlue, AppColors.brandPink],
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.brandPink,
                    shape: BoxShape.circle,
                    border: Border.all(color: context.bg, width: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Labelled primary action above the bottom nav ("New chat" / "New call").
  Widget _buildComposeFab({bool forCall = false}) {
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.1,
      child: Material(
        color: AppColors.brandBlue,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () {
            HapticFeedback.lightImpact();
            _openNewChatSearch();
          },
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: AppShadows.md,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  forCall ? Icons.add_call : Icons.add_comment_rounded,
                  color: AppColors.brandWhite,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  forCall ? 'New call' : 'New chat',
                  style: GoogleFonts.inter(
                    color: AppColors.brandWhite,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.2, end: 0);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 8. TOP SECTION TABS (Replaces bottom bar so chat panel has no menus under it)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildTopSectionTabs(AsyncValue<List<ChatModel>> chatsAsync) {
    final unread = chatsAsync.maybeWhen(
      data: (chats) {
        var count = 0;
        final myId = currentUserId ?? '';
        for (final c in chats) {
          count += c.unreadCounts[myId] ?? 0;
        }
        return count;
      },
      orElse: () => 0,
    );

    final tabs = <(int, String, IconData, IconData, String?)>[
      (0, 'Chats', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, unread > 0 ? (unread > 99 ? '99+' : '$unread') : null),
      (3, 'Calls', Icons.call_outlined, Icons.call_rounded, null),
      (1, 'Updates', Icons.play_circle_outline_rounded, Icons.play_circle_fill_rounded, null),
      (2, 'Communities', Icons.groups_outlined, Icons.groups_rounded, null),
    ];

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        children: tabs.map((t) {
          final index = t.$1;
          final label = t.$2;
          final icon = t.$3;
          final activeIcon = t.$4;
          final badge = t.$5;
          final isSelected = _activeBottomTab == index;

          return Expanded(
            child: InkWell(
              onTap: () {
                if (_activeBottomTab == index) return;
                HapticFeedback.selectionClick();
                setState(() => _activeBottomTab = index);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? AppColors.brandBlue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSelected ? activeIcon : icon,
                      size: 15,
                      color: isSelected ? AppColors.brandBlue : context.textSecondary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.brandBlue : context.textSecondary,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.0),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          badge,
                          style: GoogleFonts.inter(
                            color: AppColors.brandWhite,
                            fontSize: 9.0,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 9. UPDATES TAB VIEW (LIVE STORIES & STATUS MANAGEMENT)
  // ──────────────────────────────────────────────────────────────────────────
  void _showAddStatusOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add Status Update',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Share moments, behind-the-scenes, and announcements with collaborators.',
                style: TextStyle(color: context.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: AppColors.brandBlue,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Capture with Camera',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Take a photo or recorded clip',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/create/camera');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: AppColors.brandPink,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Pick from Gallery',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Select photo or video from your device',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickMediaForStatus();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: AppColors.brandBlue,
                    size: 22,
                  ),
                ),
                title: Text(
                  'Text Status',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Type a quick status announcement',
                  style: TextStyle(color: context.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreateTextStatusDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMediaForStatus() async {
    final uid = currentUserId;
    if (uid == null) return;

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.brandPink,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Uploading status to your story...'),
          ],
        ),
        backgroundColor: context.surface,
        duration: const Duration(seconds: 4),
      ),
    );

    try {
      final storage = ref.read(storageServiceProvider);
      final fileName = 'story_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final storagePath = 'stories/$uid/$fileName';
      final downloadUrl = await storage.uploadFile(
        File(pickedFile.path),
        storagePath,
      );

      if (downloadUrl == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload story media')),
          );
        }
        return;
      }

      final user = await ref.read(userProvider.notifier).getUser(uid);
      final authorName = (user != null && user.fullName.isNotEmpty)
          ? user.fullName
          : (user?.username ?? 'Oneova Creator');
      final authorAvatar = user?.profilePhotoUrl ?? '';

      final newStory = Story(
        id: FirebaseFirestore.instance.collection('stories').doc().id,
        authorId: uid,
        authorName: authorName,
        authorAvatarUrl: authorAvatar,
        mediaType: StoryMediaType.photo,
        mediaUrl: downloadUrl,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
        lifecycle: StoryLifecycle.active,
      );

      await ref.read(storyServiceProvider).createStory(newStory);

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Status update published!'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving status: $e')));
      }
    }
  }

  void _showCreateTextStatusDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: context.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.edit_note_rounded, color: AppColors.brandPink),
            const SizedBox(width: 10),
            Text(
              'Text Status',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(color: context.textPrimary),
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'What is on your mind as a creative?',
            hintStyle: TextStyle(color: context.textMuted),
            filled: true,
            fillColor: context.surfaceMid,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              final text = textController.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx);

              final uid = currentUserId;
              if (uid == null) return;

              final user = await ref.read(userProvider.notifier).getUser(uid);
              final authorName = (user != null && user.fullName.isNotEmpty)
                  ? user.fullName
                  : (user?.username ?? 'Oneova Creator');
              final authorAvatar = user?.profilePhotoUrl ?? '';

              final newStory = Story(
                id: FirebaseFirestore.instance.collection('stories').doc().id,
                authorId: uid,
                authorName: authorName,
                authorAvatarUrl: authorAvatar,
                mediaType: StoryMediaType.text,
                mediaUrl:
                    'https://placehold.co/1080x1920/0c4fa8/ffffff/png?text=${Uri.encodeComponent(text)}',
                createdAt: DateTime.now(),
                expiresAt: DateTime.now().add(const Duration(hours: 24)),
                lifecycle: StoryLifecycle.active,
              );

              await ref.read(storyServiceProvider).createStory(newStory);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Text status published!'),
                    backgroundColor: AppColors.brandPink,
                  ),
                );
              }
            },
            child: const Text(
              'Share Status',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesTab() {
    final storiesAsync = ref.watch(feedStoriesStreamProvider);
    final storyGroups = storiesAsync.value ?? const <UserStoryGroup>[];
    final currentUid = currentUserId ?? '';

    UserStoryGroup? myGroup;
    for (final g in storyGroups) {
      if (g.authorId == currentUid && g.stories.isNotEmpty) {
        myGroup = g;
        break;
      }
    }

    DateTime latestOf(UserStoryGroup g) => g.stories
        .map((s) => s.createdAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);
    int byLatest(UserStoryGroup a, UserStoryGroup b) =>
        latestOf(b).compareTo(latestOf(a));

    final others = storyGroups
        .where((g) => g.authorId != currentUid && g.stories.isNotEmpty)
        .toList();
    final recent = others.where((g) => g.hasUnviewed).toList()..sort(byLatest);
    final viewed = others.where((g) => !g.hasUnviewed).toList()..sort(byLatest);

    return ListView(
      padding: const EdgeInsets.only(bottom: 168),
      physics: const BouncingScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Status',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
        ),
        _buildMyStatusRow(myGroup, latestOf),
        if (storiesAsync.isLoading && storyGroups.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          )
        else if (others.isEmpty)
          _buildStatusEmptyState()
        else ...[
          if (recent.isNotEmpty) ...[
            _statusSectionLabel('Recent updates'),
            for (final g in recent) _buildStatusRow(g, latestOf(g)),
          ],
          if (viewed.isNotEmpty) ...[
            _statusSectionLabel('Viewed updates'),
            for (final g in viewed) _buildStatusRow(g, latestOf(g)),
          ],
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.schedule_rounded, size: 12, color: context.textMuted),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  'Status updates disappear after 24 hours',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: context.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// WhatsApp-style time label: "Today, 10:42", "Yesterday, 21:03", else relative.
  String _statusTime(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(d),
      alwaysUse24HourFormat: MediaQuery.of(context).alwaysUse24HourFormat,
    );
    if (now.difference(d).inMinutes < 1) return 'Just now';
    if (day == today) return 'Today, $time';
    if (day == today.subtract(const Duration(days: 1)))
      return 'Yesterday, $time';
    return timeago.format(d);
  }

  Widget _statusSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: context.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Avatar wrapped in a segmented ring: one arc per story, brand blue while
  /// unseen and muted once the current user has viewed it.
  Widget _statusAvatar({
    required String avatarUrl,
    required String name,
    required List<bool> seen,
  }) {
    const double size = 54;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: seen.isEmpty
            ? null
            : _StatusRingPainter(
                seen: seen,
                unseenColor: AppColors.brandBlue,
                seenColor: context.textMuted.withValues(alpha: 0.45),
              ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: CircleAvatar(
            backgroundColor: context.surfaceMid,
            backgroundImage: avatarUrl.isNotEmpty
                ? NetworkImage(avatarUrl)
                : null,
            child: avatarUrl.isEmpty
                ? Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: GoogleFonts.inter(
                      color: AppColors.brandBlue,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildMyStatusRow(
    UserStoryGroup? myGroup,
    DateTime Function(UserStoryGroup) latestOf,
  ) {
    final hasMyStatus = myGroup != null && myGroup.stories.isNotEmpty;

    return FutureBuilder<AppUser?>(
      future:
          _currentUserFuture ??
          (currentUserId != null ? _getUserCached(currentUserId!) : null),
      builder: (context, userSnap) {
        final me = userSnap.data;
        final avatarUrl = me?.profilePhotoUrl ?? '';
        final name = (me != null && me.fullName.isNotEmpty)
            ? me.fullName
            : (me?.username ?? '');

        return InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            final group = myGroup;
            if (group != null && group.stories.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewerScreen(
                    stories: group.stories,
                    authorName: 'My status',
                    authorAvatarUrl: avatarUrl,
                    authorId: currentUserId,
                    isMine: true,
                  ),
                ),
              );
            } else {
              _showAddStatusOptions();
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _statusAvatar(
                      avatarUrl: avatarUrl,
                      name: name,
                      // Own ring always reads as "active" in brand blue.
                      seen: hasMyStatus
                          ? List.filled(myGroup.stories.length, false)
                          : const [],
                    ),
                    if (!hasMyStatus)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.bg, width: 2),
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 14,
                            color: AppColors.brandWhite,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My status',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasMyStatus
                            ? _statusTime(latestOf(myGroup))
                            : 'Tap to add status update',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasMyStatus)
                  IconButton(
                    tooltip: 'Add to status',
                    onPressed: _showAddStatusOptions,
                    icon: Icon(
                      Icons.add_circle_outline_rounded,
                      color: AppColors.brandBlue,
                      size: 22,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(UserStoryGroup group, DateTime latest) {
    final uid = currentUserId ?? '';
    final seen = [for (final s in group.stories) s.viewers.contains(uid)];

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => StoryViewerScreen(
              stories: group.stories,
              authorName: group.authorName,
              authorAvatarUrl: group.authorAvatarUrl,
              authorId: group.authorId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            _statusAvatar(
              avatarUrl: group.authorAvatarUrl,
              name: group.authorName,
              // Viewed groups render fully muted, as on WhatsApp.
              seen: group.hasUnviewed
                  ? seen
                  : List.filled(group.stories.length, true),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.authorName.isNotEmpty
                        ? group.authorName
                        : 'Oneova member',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: context.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusTime(latest),
                    style: GoogleFonts.inter(
                      color: context.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusEmptyState() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 8),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.donut_large_rounded,
              color: AppColors.brandBlue,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No updates yet',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Status updates from people you follow will show up here.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  /// Stacked status actions: small pencil (text status) above the camera button.
  Widget _buildStatusFabs() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: 'Text status',
          child: Material(
            color: context.surfaceMid,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(color: context.border, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showCreateTextStatusDialog();
              },
              child: SizedBox(
                width: 42,
                height: 42,
                child: Icon(
                  Icons.edit_rounded,
                  color: context.textPrimary,
                  size: 19,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Tooltip(
          message: 'Photo or video status',
          child: Material(
            color: AppColors.brandBlue,
            elevation: 4,
            shadowColor: AppColors.brandBlue.withValues(alpha: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.lightImpact();
                _showAddStatusOptions();
              },
              child: const SizedBox(
                width: 56,
                height: 56,
                child: Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.brandWhite,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 10. CALLS TAB VIEW
  // ──────────────────────────────────────────────────────────────────────────
  // ──────────────────────────────────────────────────────────────────────────
  // 10. CALLS TAB VIEW (LIVE REAL-TIME CALL STREAM & HISTORY)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildCallsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 140),
      children: [
        StreamBuilder<QuerySnapshot>(
          // Per-user history written by the onCallFinished Cloud Function
          // (outcome and talk time from this user's point of view).
          stream: currentUserId != null
              ? FirebaseFirestore.instance
                    .collection('users')
                    .doc(currentUserId)
                    .collection('call_history')
                    .orderBy('startedAt', descending: true)
                    .limit(100)
                    .snapshots()
              : const Stream.empty(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brandBlue),
                ),
              );
            }

            final docs = List<DocumentSnapshot>.from(snapshot.data?.docs ?? []);
            docs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['startedAt'];
              final bTime = bData['startedAt'];
              final aDate = aTime is Timestamp
                  ? aTime.toDate()
                  : (aTime is String ? DateTime.tryParse(aTime) : null) ??
                        DateTime.fromMillisecondsSinceEpoch(0);
              final bDate = bTime is Timestamp
                  ? bTime.toDate()
                  : (bTime is String ? DateTime.tryParse(bTime) : null) ??
                        DateTime.fromMillisecondsSinceEpoch(0);
              return bDate.compareTo(aDate);
            });

            if (docs.isEmpty) {
              return _buildCallsEmptyState();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Recent Calls',
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${docs.length}',
                        style: const TextStyle(
                          color: AppColors.brandBlue,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...docs.map((doc) => _buildLiveCallItem(doc)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildCallsEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.brandBlue.withOpacity(0.3),
                width: 1.5,
              ),
            ),
            child: const Icon(
              Icons.phone_in_talk_rounded,
              color: AppColors.brandBlue,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No Recent Calls',
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Connect with collaborators, creators, and friends with encrypted high-fidelity audio & video calls.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 2,
            ),
            onPressed: _openNewChatSearch,
            icon: const Icon(Icons.add_call, size: 18),
            label: const Text(
              'Start a Call with Friends & Creators',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveCallItem(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final participants = List<String>.from(data['participantIds'] ?? const []);
    final others = participants.where((p) => p != currentUserId).toList();
    final hostId = (data['hostId'] ?? '') as String;
    final otherUserId = others.isNotEmpty ? others.first : hostId;
    final isGroup = data['isGroup'] == true || others.length > 1;
    final groupTitle = data['title'] as String?;

    final isVideo = data['isVideo'] == true;
    final outcome = data['outcome'] as String? ?? 'completed';
    final isOutgoing = data['direction'] == 'outgoing';
    final durationSec = (data['durationSec'] as num?)?.toInt() ?? 0;
    final startedAt = data['startedAt'];
    final date = startedAt is Timestamp ? startedAt.toDate() : DateTime.now();
    final timeStr = timeago.format(date);

    final isMissed = !isOutgoing && outcome != 'completed';
    final String outcomeLabel;
    if (outcome == 'completed') {
      final m = durationSec ~/ 60;
      final sec = (durationSec % 60).toString().padLeft(2, '0');
      outcomeLabel = durationSec > 0 ? '$m:$sec' : (isOutgoing ? 'Outgoing' : 'Incoming');
    } else if (isOutgoing) {
      outcomeLabel = outcome == 'busy'
          ? 'Busy'
          : outcome == 'declined'
              ? 'Declined'
              : 'No answer';
    } else {
      outcomeLabel = outcome == 'declined' ? 'Declined' : 'Missed';
    }

    final IconData directionIcon;
    final Color directionColor;
    if (isMissed) {
      directionIcon = Icons.call_missed_rounded;
      directionColor = AppColors.brandPink;
    } else if (isOutgoing) {
      directionIcon = Icons.call_made_rounded;
      directionColor = AppColors.brandBlue;
    } else {
      directionIcon = Icons.call_received_rounded;
      directionColor = AppColors.brandBlue;
    }

    return FutureBuilder<AppUser?>(
      future: otherUserId.isNotEmpty ? _getUserCached(otherUserId) : null,
      builder: (context, userSnap) {
        final user = userSnap.data;
        final String userName = (user != null && user.fullName.isNotEmpty)
            ? user.fullName
            : ((user != null &&
                      user.username != null &&
                      user.username!.isNotEmpty)
                  ? user.username!
                  : 'Oneova user');
        final String name = isGroup
            ? ((groupTitle != null && groupTitle.isNotEmpty)
                  ? groupTitle
                  : '$userName +${others.length - 1}')
            : userName;
        final String avatar = isGroup ? '' : (user?.photoUrl ?? '');

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.surfaceMid,
                backgroundImage: avatar.isNotEmpty
                    ? NetworkImage(avatar)
                    : null,
                child: avatar.isEmpty
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.brandBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: isMissed
                            ? AppColors.brandPink
                            : context.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(directionIcon, color: directionColor, size: 13),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            '${isGroup ? 'Group ' : ''}${isVideo ? 'video' : 'voice'} · $outcomeLabel · $timeStr',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  color: AppColors.brandPink,
                  size: 22,
                ),
                tooltip: isVideo ? 'Video Call Back' : 'Voice Call Back',
                onPressed: () => isGroup
                    ? startOneovaCall(
                        context,
                        ref,
                        targetUserIds: others,
                        isVideo: isVideo,
                        title: groupTitle,
                      )
                    : _initiateDirectCall(
                        otherUserId: otherUserId,
                        otherUserName: name,
                        otherUserAvatar: avatar,
                        isVideo: isVideo,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _initiateDirectCall({
    required String otherUserId,
    String? otherUserName,
    String? otherUserAvatar,
    required bool isVideo,
  }) async {
    if (currentUserId == null || otherUserId.isEmpty) return;
    await startOneovaCall(
      context,
      ref,
      targetUserIds: [otherUserId],
      isVideo: isVideo,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 11. PUBLIC CONNECTION ROOMS & VIP PRIVATE ROOMS
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildRoomsList() => const RoomsListView(vip: false);

  Widget _buildVipPrivateRoomsList() => const RoomsListView(vip: true);
}

/// Draws the WhatsApp-style segmented status ring (one arc per story).
class _StatusRingPainter extends CustomPainter {
  final List<bool> seen;
  final Color unseenColor;
  final Color seenColor;

  _StatusRingPainter({
    required this.seen,
    required this.unseenColor,
    required this.seenColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.4;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final n = seen.length;
    final gap = n > 1 ? 0.12 : 0.0;
    final sweep = (2 * math.pi - gap * n) / n;
    for (var i = 0; i < n; i++) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = seen[i] ? seenColor : unseenColor;
      canvas.drawArc(
        rect,
        -math.pi / 2 + i * (sweep + gap) + gap / 2,
        sweep,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StatusRingPainter old) =>
      old.unseenColor != unseenColor ||
      old.seenColor != seenColor ||
      old.seen.join() != seen.join();
}
