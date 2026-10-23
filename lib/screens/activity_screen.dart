import 'package:oneova/shared/widgets/smooth_load.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/notification_model.dart';
import '../shared/theme/app_theme.dart';
import '../auth/widgets/profile_completion_reminder_card.dart';
import '../backend/user_profile_completion_service.dart';
import '../widgets/oneova_assistant_overlay.dart';

final notificationsStreamProvider =
    StreamProvider.autoDispose<List<OneOvaNotification>>((ref) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return Stream.value([]);

      return FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => OneOvaNotification.fromMap(doc.data(), doc.id))
                .toList(),
          );
    });

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  int _selectedTabIndex = 0; // 0: Activity, 1: New followers
  String _selectedFilter = 'All activity';

  bool _showFollowersTab = true;
  bool _showAdvisoryCard = true;
  bool _showSafetyBanner = true;
  bool _showProfileCompletionCard = true;

  final List<String> _filters = [
    'All activity',
    'Likes',
    'Comments',
    'Mentions',
  ];

  @override
  Widget build(BuildContext context) {
    final notificationsAsync = ref.watch(notificationsStreamProvider);
    final topBarBg = context.topBarBg;
    final topBarFg = context.topBarFg;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: topBarBg,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: topBarFg, size: 22),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Activity Tab with Dropdown
            GestureDetector(
              onTap: () {
                setState(() => _selectedTabIndex = 0);
                _showFilterMenu(context);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _selectedFilter == 'All activity' ? 'Activity' : _selectedFilter,
                        style: AppTheme.h2Style.copyWith(
                          fontSize: 17,
                          color: _selectedTabIndex == 0 ? topBarFg : topBarFg.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.arrow_drop_down,
                        color: _selectedTabIndex == 0 ? AppColors.brandPink : topBarFg.withValues(alpha: 0.7),
                        size: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 2.5,
                    width: _selectedTabIndex == 0 ? 34 : 0,
                    decoration: BoxDecoration(
                      color: AppColors.brandPink,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandPink.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_showFollowersTab) ...[
              const SizedBox(width: 14),
              // New Followers Tab
              GestureDetector(
                onTap: () {
                  setState(() => _selectedTabIndex = 1);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New followers',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _selectedTabIndex == 1 ? topBarFg : topBarFg.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 2.5,
                      width: _selectedTabIndex == 1 ? 38 : 0,
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.brandPink.withValues(alpha: 0.5),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.tune_rounded, color: topBarFg, size: 21),
            tooltip: 'Customize Tabs & Panels',
            onPressed: () => _showTabCustomizationSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined, color: AppColors.brandPink, size: 22),
            tooltip: 'Community Guidelines & Policies',
            onPressed: () => _showPlatformPoliciesModal(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _selectedTabIndex == 1
          ? _buildFollowersView()
          : _buildActivityView(notificationsAsync),
    );
  }

  void _showFilterMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.filter_list_rounded, color: AppColors.brandPink, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Filter Activity',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ..._filters.map((filter) {
                  final isSelected = _selectedFilter == filter;
                  return ListTile(
                    leading: Icon(
                      _getFilterIcon(filter),
                      color: isSelected ? AppColors.brandPink : context.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      filter,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected ? AppColors.brandPink : context.textPrimary,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle_rounded, color: AppColors.brandPink)
                        : null,
                    onTap: () {
                      setState(() {
                        _selectedFilter = filter;
                      });
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTabCustomizationSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(
                  color: AppColors.brandBlue.withValues(alpha: 0.3),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor.withValues(alpha: 0.2),
                    blurRadius: 24,
                    offset: const Offset(0, -6),
                  ),
                ],
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: AppColors.brandBlue, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Customize Activity Tabs & Panels',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Toggle sections and tabs on or off to tailor your workflow.',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Show "New followers" Tab',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                      subtitle: Text(
                        'Displays new followers sub-tab on the header',
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                      activeThumbColor: AppColors.brandPink,
                      value: _showFollowersTab,
                      onChanged: (val) {
                        setState(() {
                          _showFollowersTab = val;
                          if (!val && _selectedTabIndex == 1) {
                            _selectedTabIndex = 0;
                          }
                        });
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Show Ova Algorithm Advisor Panel',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                      subtitle: Text(
                        'Real-time AI recommendations on your content reach',
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                      activeThumbColor: AppColors.brandBlue,
                      value: _showAdvisoryCard,
                      onChanged: (val) {
                        setState(() => _showAdvisoryCard = val);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Show Platform Safety & Rules Banner',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                      subtitle: Text(
                        'Zero-tolerance community guidelines badge',
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                      activeThumbColor: AppColors.brandPink,
                      value: _showSafetyBanner,
                      onChanged: (val) {
                        setState(() => _showSafetyBanner = val);
                        setModalState(() {});
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Show Profile Completion Card',
                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                      subtitle: Text(
                        'Reminders to complete creator bio & identity verification',
                        style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                      ),
                      activeThumbColor: AppColors.brandBlue,
                      value: _showProfileCompletionCard,
                      onChanged: (val) {
                        setState(() => _showProfileCompletionCard = val);
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case 'Likes':
        return Icons.favorite_rounded;
      case 'Comments':
        return Icons.chat_bubble_rounded;
      case 'Mentions':
        return Icons.alternate_email_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Widget _buildOvaAlgorithmAdvisoryCard(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final profileState = ref.watch(userProfileCompletionStateProvider);
        return profileState.maybeWhen(
          data: (state) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Ova Algorithm Advisor',
                              style: GoogleFonts.inter(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.brandPink.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ACTIVE',
                                style: GoogleFonts.inter(
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandPink,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          state.algorithmicAdvice,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: context.textSecondary,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () {
                            OneOvaAssistantOverlay.show(
                              context,
                              initialPrompt: 'Ova, advise me on how to optimize my reels and increase my algorithmic distribution score.',
                            );
                          },
                          child: Text(
                            'Chat with Ova AI Advisor →',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
          orElse: () => const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildSystemHealthAndRepairCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Colors.green.withValues(alpha: 0.35), width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(AppRadius.xs),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: const Icon(Icons.health_and_safety_rounded, color: Colors.green, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Ova System Health',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '100% HEALTHY',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.green,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Autonomous Gemini self-repair engine is actively monitoring schemas and media pipelines.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: context.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () {
                    context.push('/settings/ai');
                  },
                  child: Text(
                    'View Diagnostics & Key Vault →',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowersView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSafetyGuidelinesBanner(context),
          const ProfileCompletionReminderCard(),
          _buildOvaAlgorithmAdvisoryCard(context),
          _buildSystemHealthAndRepairCard(context),
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: context.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPink, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.35),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.person_add_alt_1_rounded,
              size: 48,
              color: AppColors.brandPink,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No New Followers',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'When people follow your profile, you will see them here with quick options to follow back.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: context.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 80),
          _buildPolicyFooter(context),
        ],
      ),
    );
  }

  Widget _buildActivityView(AsyncValue<List<OneOvaNotification>> notificationsAsync) {
    return notificationsAsync.smoothWhen(
      data: (notifications) {
        final filteredList = notifications.where((n) {
          if (_selectedFilter == 'Likes') return n.type == NotificationType.like;
          if (_selectedFilter == 'Comments') return n.type == NotificationType.reply;
          if (_selectedFilter == 'Mentions') return n.type == NotificationType.mention;
          return true;
        }).toList();

        if (filteredList.isEmpty) {
          return SingleChildScrollView(
            child: Column(
              children: [
                if (_showSafetyBanner) _buildSafetyGuidelinesBanner(context),
                if (_showProfileCompletionCard) const ProfileCompletionReminderCard(),
                if (_showAdvisoryCard) _buildOvaAlgorithmAdvisoryCard(context),
                _buildSystemHealthAndRepairCard(context),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: context.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandPink, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brandPink.withValues(alpha: 0.35),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    size: 48,
                    color: AppColors.brandPink,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'No Notifications Yet',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'When people follow you, like your content, or leave comments, they will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 80),
                _buildPolicyFooter(context),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          itemCount: filteredList.length + 6,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _showSafetyBanner ? _buildSafetyGuidelinesBanner(context) : const SizedBox.shrink();
            }
            if (index == 1) {
              return _showProfileCompletionCard ? const ProfileCompletionReminderCard() : const SizedBox.shrink();
            }
            if (index == 2) {
              return _showAdvisoryCard ? _buildOvaAlgorithmAdvisoryCard(context) : const SizedBox.shrink();
            }
            if (index == 3) {
              return _buildSystemHealthAndRepairCard(context);
            }
            if (index == 4) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 8.0,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 14,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'Priority Activity',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }
            if (index == filteredList.length + 5) {
              return _buildPolicyFooter(context);
            }
            final notification = filteredList[index - 5];
            return _NotificationTile(notification: notification);
          },
        );
      },
      loading: () => const OneovaSkeleton(),
      error: (err, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brandPink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: const Icon(
                Icons.notifications_off_outlined,
                size: 48,
                color: AppColors.brandPink,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No Activity Available',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'We could not load your activity at this time. Pull down or tap below to refresh.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: context.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => ref.refresh(notificationsStreamProvider),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh Activity'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandPink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyGuidelinesBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.border),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPink, width: 1.5),
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: AppColors.brandPink,
              size: 20,
            ),
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
                        'Community & Safety Rules',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'STANDARD',
                        style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Oneova enforces TikTok-standard community guidelines, copyright protection & creator terms.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => _showPlatformPoliciesModal(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Read Guidelines & Terms',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandPink,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_ios, size: 10, color: AppColors.brandPink),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        children: [
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              GestureDetector(
                onTap: () => _showPolicyDetailsDialog(
                  context,
                  title: 'Privacy Policy',
                  icon: Icons.privacy_tip_outlined,
                  content: _privacyPolicyDetails,
                ),
                child: Text(
                  'Privacy Policy',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.brandPink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text('•', style: TextStyle(color: AppColors.textMuted)),
              GestureDetector(
                onTap: () => _showPolicyDetailsDialog(
                  context,
                  title: 'Terms of Service',
                  icon: Icons.description_outlined,
                  content: _termsOfServiceDetails,
                ),
                child: Text(
                  'Terms of Service',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.brandPink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Text('•', style: TextStyle(color: AppColors.textMuted)),
              GestureDetector(
                onTap: () => _showPlatformPoliciesModal(context),
                child: Text(
                  'Community Rules',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.brandPink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Oneova Safety & Compliance Center • TikTok Verified Standards',
            style: GoogleFonts.inter(fontSize: 11, color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showPlatformPoliciesModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.verified_user_rounded, color: AppColors.brandPink, size: 26),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Oneova Community Guidelines',
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: context.textPrimary,
                              ),
                            ),
                            Text(
                              'Standardized Rules for Safety, IP & Monetization',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.brandPink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildPolicyCard(
                    icon: Icons.gavel_rounded,
                    title: '1. Safety, Civility & Harassment (Zero Tolerance)',
                    body:
                        'Oneova maintains a zero-tolerance policy against hate speech, harassment, bullying, sexual content involving minors, doxxing, violent extremism, self-harm, or dangerous stunts. Violations trigger immediate content takedown and potential account termination.',
                  ),
                  _buildPolicyCard(
                    icon: Icons.monetization_on_rounded,
                    title: '2. Commercial Content & TikTok Creator Standards',
                    body:
                        'All branded, sponsored, or affiliate videos must be clearly disclosed using the #ad or #sponsored tag. Creators participating in the Oneova Creator Marketplace must follow FTC disclosure guidelines and provide accurate product descriptions.',
                  ),
                  _buildPolicyCard(
                    icon: Icons.music_note_rounded,
                    title: '3. Intellectual Property & Copyright (DMCA)',
                    body:
                        'Only post audio and video you own or hold licenses to use. Audio attribution discs must remain intact. Counterfeiting, unlicensed music synchronization, and pirated media will be removed in accordance with DMCA regulations.',
                  ),
                  _buildPolicyCard(
                    icon: Icons.smart_toy_rounded,
                    title: '4. AI & Synthetic Media Transparency',
                    body:
                        'Media generated or substantially edited using Gemini Live or Mask Engine must carry an AI-generated disclosure label. Deceptive deepfakes or non-consensual synthetic likenesses are strictly prohibited.',
                  ),
                  _buildPolicyCard(
                    icon: Icons.lock_person_rounded,
                    title: '5. Account Security, Age Verification & Minors',
                    body:
                        'Oneova requires users to be at least 13 years old. Direct messaging between unverified adults and minor accounts is restricted. Account sharing, credential phishing, and engagement manipulation (fake likes/followers) violate platform rules.',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showPolicyDetailsDialog(
                              context,
                              title: 'Privacy Policy',
                              icon: Icons.privacy_tip_outlined,
                              content: _privacyPolicyDetails,
                            );
                          },
                          icon: const Icon(Icons.privacy_tip_outlined, size: 16),
                          label: const Text('Privacy Policy'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.surfaceMid,
                            foregroundColor: context.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(color: context.border),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showPolicyDetailsDialog(
                              context,
                              title: 'Terms of Service',
                              icon: Icons.description_outlined,
                              content: _termsOfServiceDetails,
                            );
                          },
                          icon: const Icon(Icons.description_outlined, size: 16),
                          label: const Text('Terms of Service'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandPink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPolicyCard({required IconData icon, required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: context.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _showPolicyDetailsDialog(BuildContext context, {required String title, required IconData icon, required String content}) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(20),
            constraints: const BoxConstraints(maxHeight: 520, maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: AppColors.brandPink, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: context.textSecondary),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                Divider(color: context.border),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      content,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: context.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPink,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('I Understand & Agree'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static const String _privacyPolicyDetails = '''
ONEOVA PRIVACY POLICY
Last Updated: October 11, 2026

1. DATA COLLECTION & CONSENT
Oneova collects information you provide directly, including account credentials, handle, profile assets, creator videos, audio stems, and direct messaging metadata. Telemetry data regarding media playback, frame rates, and crash diagnostics is collected to ensure native 60fps performance.

2. THIRD-PARTY PLATFORM INTEGRATIONS (TIKTOK & META)
When connecting external accounts (TikTok, YouTube, Meta/Instagram), Oneova accesses public profile metrics and publishing tokens strictly via OAuth 2.0. We never store plain-text passwords. You can revoke access at any time.

3. AI & CONVERSATIONAL VOICE DATA
Sessions conducted via Gemini Live and Mask Engine are encrypted in transit. Audio waveforms are processed solely to fulfill your creative prompts and are not used for public model training without explicit consent.

4. USER RIGHTS & DATA DELETION
Under global data protection standards (GDPR/CCPA), you retain full rights to request complete data deletion, export your creator archive, or opt out of personalized recommendations at any time via /deletion.html or in-app Settings.
''';

  static const String _termsOfServiceDetails = '''
ONEOVA TERMS OF SERVICE
Last Updated: October 11, 2026

1. AGREEMENT TO TERMS
By creating an account or accessing the Oneova platform, you agree to comply with these Terms of Service and our Community Guidelines. If you do not agree, you must discontinue use immediately.

2. CREATOR ELIGIBILITY & CONDUCT
You must be at least 13 years old. You agree not to upload content that violates intellectual property, incites violence, or engages in fraudulent commercial practices.

3. COMMERCIAL & SPONSORED CONTENT
Creators must clearly label branded integrations using platform tags (#ad, #sponsored) in compliance with FTC and TikTok Creator Marketplace standards.

4. CONTENT LICENSING & ATTRIBUTION
You retain ownership of your original video and audio content. By posting, you grant Oneova a worldwide, non-exclusive license to host, stream, and distribute the media across the feed. Audio attribution discs must be respected.

5. TERMINATION & ENFORCEMENT
Oneova reserves the right to suspend or terminate accounts that repeatedly violate Community Guidelines or engage in fraudulent activities.
''';
}

class _NotificationTile extends StatelessWidget {
  final OneOvaNotification notification;

  const _NotificationTile({required this.notification});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: notification.isRead ? context.border : AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (!notification.isRead)
            BoxShadow(
              color: AppColors.brandPink.withValues(alpha: 0.08),
              blurRadius: 16,
              spreadRadius: 1,
            ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        leading: _buildAvatar(context),
        title: _buildContent(context),
        trailing: _buildTrailing(context),
        onTap: () {
          // Handle navigation on tap
        },
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    IconData badgeIcon;
    switch (notification.type) {
      case NotificationType.like:
        badgeIcon = Icons.favorite;
        break;
      case NotificationType.reply:
        badgeIcon = Icons.chat_bubble;
        break;
      case NotificationType.follow:
        badgeIcon = Icons.person_add;
        break;
      case NotificationType.mention:
        badgeIcon = Icons.alternate_email;
        break;
    }

    final avatar = CircleAvatar(
      radius: 26,
      backgroundColor: context.surfaceMid,
      backgroundImage: notification.actorAvatarUrl.isNotEmpty
          ? NetworkImage(notification.actorAvatarUrl)
          : null,
      child: notification.actorAvatarUrl.isEmpty
          ? Text(
              notification.actorUsername.isNotEmpty
                  ? notification.actorUsername.substring(0, 1).toUpperCase()
                  : '?',
              style: TextStyle(
                color: context.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            )
          : null,
    );

    final avatarWithRing = notification.isRead
        ? avatar
        : Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.brandPink, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ],
            ),
            child: avatar,
          );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWithRing,
        Positioned(
          bottom: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.brandPink,
              shape: BoxShape.circle,
              border: Border.all(color: context.bg, width: 2),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandPink.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Icon(
              badgeIcon,
              size: 11,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: GoogleFonts.inter(
              color: context.textPrimary,
              fontSize: 14.5,
              height: 1.3,
            ),
            children: [
              TextSpan(
                text: '${notification.actorUsername} ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: _getNotificationActionText(notification.type)),
              if (notification.content.isNotEmpty)
                TextSpan(text: ' ${notification.content}'),
              TextSpan(
                text: '  ${notification.formattedTime}',
                style: TextStyle(color: context.textSecondary),
              ),
            ],
          ),
        ),
        if (notification.type == NotificationType.reply)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                _buildActionButton(context, Icons.favorite, 'Like', isPink: true),
                const SizedBox(width: 8),
                _buildActionButton(context, Icons.chat_bubble_outline, 'Reply'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, IconData icon, String label, {bool isPink = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isPink ? AppColors.brandPink.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isPink ? AppColors.brandPink : context.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isPink ? AppColors.brandPink : context.textPrimary),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isPink ? AppColors.brandPink : context.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  String _getNotificationActionText(NotificationType type) {
    switch (type) {
      case NotificationType.like:
        return 'liked your video.';
      case NotificationType.reply:
        return 'replied to your comment:';
      case NotificationType.follow:
        return 'started following you.';
      case NotificationType.mention:
        return 'mentioned you.';
    }
  }

  Widget? _buildTrailing(BuildContext context) {
    if (notification.type == NotificationType.follow) {
      return ElevatedButton(
        onPressed: () {},
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandPink,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: AppColors.brandPink.withValues(alpha: 0.5),
          minimumSize: const Size(86, 34),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(17),
          ),
        ),
        child: const Text(
          'Follow',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      );
    }
    if (notification.targetMediaUrl != null &&
        notification.targetMediaUrl!.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notification.type == NotificationType.like)
            const Padding(
              padding: EdgeInsets.only(right: 12.0),
              child: Icon(Icons.favorite, color: AppColors.brandPink, size: 18),
            ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
              image: DecorationImage(
                image: NetworkImage(notification.targetMediaUrl!),
                fit: BoxFit.cover,
              ),
            ),
          ),
        ],
      );
    }
    return null;
  }
}
