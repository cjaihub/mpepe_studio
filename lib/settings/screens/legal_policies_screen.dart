import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/platform_docs_cms_service.dart';

/// Real-time Cloud-Synced + Offline-First Rules, Regulations & Advanced Feature
/// Documentation Center for Oneova.
///
/// Consumes `publishedPlatformDocsProvider` (`platform_cms_docs` in Firestore)
/// so any edit made by an Admin in the Oneova App or on the live React Website
/// (`oneova.app`) updates both surfaces immediately in real time, while
/// guaranteeing 100% instant offline readability via `OneovaPlatformDocsCatalog`.
class LegalPoliciesScreen extends ConsumerStatefulWidget {
  final String? initialTab;

  const LegalPoliciesScreen({super.key, this.initialTab});

  @override
  ConsumerState<LegalPoliciesScreen> createState() => _LegalPoliciesScreenState();
}

class _LegalPoliciesScreenState extends ConsumerState<LegalPoliciesScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _activeTrack; // 'rules' | 'features'
  late String _selectedRuleTab;
  String _selectedFeatureCategory = 'all';
  String _query = '';
  final Set<String> _expandedIds = <String>{
    'policy-community-guidelines',
    'policy-terms-of-service',
    'policy-privacy',
    'policy-child-safety',
    'regulation-african-global-compliance',
    'live-studio',
  };

  static const List<_FilterChipSpec> _ruleTabs = [
    _FilterChipSpec(id: 'all', label: 'All Rules', icon: Icons.verified_user_outlined),
    _FilterChipSpec(id: 'guidelines', label: 'Community', icon: Icons.people_alt_rounded),
    _FilterChipSpec(id: 'terms', label: 'Terms', icon: Icons.description_rounded),
    _FilterChipSpec(id: 'privacy', label: 'Privacy', icon: Icons.shield_outlined),
    _FilterChipSpec(id: 'safety', label: 'Teen Safety', icon: Icons.health_and_safety_rounded),
    _FilterChipSpec(id: 'biz', label: 'Biz & Wallet', icon: Icons.account_balance_wallet_rounded),
    _FilterChipSpec(id: 'deletion', label: 'Deletion', icon: Icons.delete_sweep_rounded),
    _FilterChipSpec(id: 'law_enforcement', label: 'Law Enforcement', icon: Icons.gavel_rounded),
    _FilterChipSpec(id: 'africa', label: 'Africa & Law', icon: Icons.public_rounded),
  ];

  static const List<String> _sevenPromises = [
    'Your content is 100% yours — we only license it to run Oneova.',
    'We never sell your personal data, phone number, or chats.',
    'Fraud, hate, violence & child exploitation are removed fast.',
    'Every moderation action states the rule and includes human appeal.',
    'Wallet & Coins run on licensed mobile-money, card & bank rails.',
    'Built Africa-first: low-data friendly, local currencies & laws.',
    'Download or permanently delete your data anytime in Settings.',
  ];

  @override
  void initState() {
    super.initState();
    final incoming = widget.initialTab?.trim().toLowerCase() ?? '';
    if (incoming == 'features' || incoming == 'docs') {
      _activeTrack = 'features';
      _selectedRuleTab = 'all';
    } else {
      _activeTrack = 'rules';
      final matchesRule = _ruleTabs.any((t) => t.id == incoming);
      _selectedRuleTab = matchesRule ? incoming : 'all';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  IconData _iconForDoc(PlatformCmsDoc doc) {
    if (doc.docType == 'feature') {
      switch (doc.id) {
        case 'live-studio':
          return Icons.live_tv_rounded;
        case 'creator-rooms':
          return Icons.spatial_audio_off_rounded;
        case 'looks-color-engine':
          return Icons.palette_rounded;
        case 'mobile-editor':
          return Icons.movie_edit;
        case 'reels-feed':
          return Icons.smart_display_rounded;
        case 'ova-ai-lab':
          return Icons.auto_awesome_rounded;
        case 'device-thermal-advisor':
          return Icons.memory_rounded;
        case 'wallet-biz-commerce':
          return Icons.account_balance_wallet_rounded;
        case 'universal-sharing':
          return Icons.share_rounded;
        case 'security-desktop-ecosystem':
          return Icons.security_rounded;
        default:
          return Icons.stars_rounded;
      }
    }
    switch (doc.policyTab) {
      case 'guidelines':
        return Icons.people_alt_rounded;
      case 'terms':
        return Icons.description_rounded;
      case 'privacy':
        return Icons.lock_person_rounded;
      case 'safety':
        return Icons.shield_rounded;
      case 'biz':
        return Icons.storefront_rounded;
      case 'deletion':
        return Icons.manage_accounts_rounded;
      case 'law_enforcement':
        return Icons.gavel_rounded;
      case 'africa':
        return Icons.public_rounded;
      default:
        return doc.docType == 'regulation' ? Icons.policy_rounded : Icons.verified_user_rounded;
    }
  }

  bool _matchesQuery(PlatformCmsDoc doc, String q) {
    if (doc.title.toLowerCase().contains(q) ||
        doc.inShort.toLowerCase().contains(q) ||
        doc.badge.toLowerCase().contains(q) ||
        doc.category.toLowerCase().contains(q)) {
      return true;
    }
    for (final sec in doc.sections) {
      if (sec.heading.toLowerCase().contains(q) ||
          sec.summary.toLowerCase().contains(q) ||
          sec.callout.toLowerCase().contains(q)) {
        return true;
      }
      if (sec.bullets.any((b) => b.toLowerCase().contains(q))) {
        return true;
      }
    }
    return false;
  }

  List<PlatformCmsDoc> _filterDocs(List<PlatformCmsDoc> allDocs) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      return allDocs.where((d) => _matchesQuery(d, q)).toList();
    }

    if (_activeTrack == 'features') {
      final features = allDocs.where((d) => d.docType == 'feature').toList();
      if (_selectedFeatureCategory == 'all') return features;
      return features.where((d) => d.category == _selectedFeatureCategory).toList();
    }

    final rules = allDocs.where((d) => d.docType != 'feature').toList();
    if (_selectedRuleTab == 'all') return rules;
    return rules.where((d) {
      if (d.policyTab == _selectedRuleTab) return true;
      if (_selectedRuleTab == 'africa' && d.docType == 'regulation') return true;
      return false;
    }).toList();
  }

  void _toggleCard(String id) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(publishedPlatformDocsProvider);
    final isAdmin = ref.watch(isPlatformDocsAdminProvider).value ?? false;
    final allDocs = docsAsync.value ?? OneovaPlatformDocsCatalog.defaults;
    final visibleDocs = _filterDocs(allDocs);
    final liveCloudCount = allDocs.where((d) => d.isLiveFromCloud).length;
    bool isSignedIn = false;
    try {
      isSignedIn = FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      isSignedIn = false;
    }

    final featureCategories = <String>{
      for (final d in allDocs)
        if (d.docType == 'feature' && d.category.isNotEmpty) d.category,
    }.toList();

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.textPrimary),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(isSignedIn ? '/hub/home' : '/auth/main_login');
            }
          },
        ),
        title: Text(
          'Rules, Docs & Legal',
          style: GoogleFonts.inter(
            fontSize: 17.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        actions: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(
                child: SizedBox(
                  height: 32,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      context.push('/settings/admin-cms');
                    },
                    icon: const Icon(Icons.edit_note_rounded, size: 15),
                    label: Text(
                      'Live CMS',
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandPink,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
        children: [
          _buildHeroPromisesCard(context, liveCloudCount),
          const SizedBox(height: 12),
          _buildSearchField(context),
          const SizedBox(height: 10),
          if (_query.trim().isEmpty) ...[
            _buildTrackSwitcher(
              context,
              rulesCount: allDocs.where((d) => d.docType != 'feature').length,
              featuresCount: allDocs.where((d) => d.docType == 'feature').length,
            ),
            const SizedBox(height: 10),
            if (_activeTrack == 'rules')
              _buildRulesCategoryStrip(context)
            else
              _buildFeatureCategoryStrip(context, featureCategories),
          ] else ...[
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                'MATCHING DOCS & RULES (${visibleDocs.length})',
                style: GoogleFonts.inter(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          if (visibleDocs.isEmpty)
            _buildEmptySearch(context)
          else
            for (final doc in visibleDocs) ...[
              _buildCmsDocCard(context, doc, isAdmin: isAdmin),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 8),
          _buildQuickActionsCard(context, isSignedIn: isSignedIn, isAdmin: isAdmin),
        ],
      ),
    );
  }

  Widget _buildHeroPromisesCard(BuildContext context, int liveCloudCount) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  'OUR 7 PROMISES',
                  style: GoogleFonts.inter(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  'OFFLINE READY',
                  style: GoogleFonts.inter(
                    fontSize: 9.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: AppColors.brandPink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.30),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.brandBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      liveCloudCount > 0
                          ? 'LIVE SYNCED ($liveCloudCount)'
                          : 'APP + WEB SYNC',
                      style: GoogleFonts.inter(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Plain-language rules, African & global regulations, and advanced feature docs — synced live across Oneova App and Web.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < _sevenPromises.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandBlue,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _sevenPromises[i],
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: context.textSecondary,
                        height: 1.32,
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

  Widget _buildSearchField(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 17, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Search rules, 4K Live, M-Pesa, Looks, teens, POPIA...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12.0,
                  color: context.textMuted,
                ),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                setState(() => _query = '');
              },
              child: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildTrackSwitcher(
    BuildContext context, {
    required int rulesCount,
    required int featuresCount,
  }) {
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTrackButton(
              context,
              id: 'rules',
              label: 'Rules & Regulations ($rulesCount)',
              icon: Icons.gavel_rounded,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildTrackButton(
              context,
              id: 'features',
              label: 'Platform Features ($featuresCount)',
              icon: Icons.auto_awesome_mosaic_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackButton(
    BuildContext context, {
    required String id,
    required String label,
    required IconData icon,
  }) {
    final selected = _activeTrack == id;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _activeTrack = id);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: selected ? Colors.white : context.textSecondary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : context.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesCategoryStrip(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final tab in _ruleTabs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedRuleTab = tab.id);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: _selectedRuleTab == tab.id ? AppColors.brandBlue : context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: _selectedRuleTab == tab.id ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tab.icon,
                        size: 14,
                        color: _selectedRuleTab == tab.id ? Colors.white : context.textSecondary,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        tab.label,
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w700,
                          color: _selectedRuleTab == tab.id ? Colors.white : context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureCategoryStrip(BuildContext context, List<String> categories) {
    final allItems = ['all', ...categories];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final cat in allItems)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() => _selectedFeatureCategory = cat);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: _selectedFeatureCategory == cat ? AppColors.brandBlue : context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: _selectedFeatureCategory == cat ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      cat == 'all' ? 'All Features' : cat,
                      style: GoogleFonts.inter(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w700,
                        color: _selectedFeatureCategory == cat ? Colors.white : context.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCmsDocCard(
    BuildContext context,
    PlatformCmsDoc doc, {
    required bool isAdmin,
  }) {
    final expanded = _expandedIds.contains(doc.id) || _query.trim().isNotEmpty;
    final badgeColor = doc.isAccentBadge ? AppColors.brandPink : AppColors.brandBlue;
    final iconData = _iconForDoc(doc);

    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _toggleCard(doc.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: badgeColor.withValues(alpha: 0.3), width: 1.0),
                    ),
                    child: Icon(iconData, size: 16, color: badgeColor),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: badgeColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                doc.badge,
                                style: GoogleFonts.inter(
                                  fontSize: 9.0,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.6,
                                  color: badgeColor,
                                ),
                              ),
                            ),
                            Text(
                              '${doc.version} · ${doc.readTime}',
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: context.textMuted,
                              ),
                            ),
                            if (doc.isLiveFromCloud)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.brandBlue.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                ),
                                child: Text(
                                  'LIVE',
                                  style: GoogleFonts.inter(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: AppColors.brandBlue,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          doc.title,
                          style: GoogleFonts.inter(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: context.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      padding: EdgeInsets.zero,
                      tooltip: 'Edit Live (Syncs App + Website)',
                      icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.brandPink),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        context.push('/settings/admin-cms?doc=${Uri.encodeComponent(doc.id)}');
                      },
                    ),
                  Icon(
                    expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 19,
                    color: context.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 12.0,
                      height: 1.35,
                      color: context.textPrimary,
                    ),
                    children: [
                      TextSpan(
                        text: 'In short: ',
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandBlue,
                        ),
                      ),
                      TextSpan(
                        text: doc.inShort,
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w500,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) ...[
                const SizedBox(height: 10),
                for (int sIdx = 0; sIdx < doc.sections.length; sIdx++) ...[
                  _buildSectionBlock(context, doc.sections[sIdx]),
                  if (sIdx < doc.sections.length - 1) const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                Divider(height: 1, thickness: 1, color: context.border),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 12, color: context.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Effective ${doc.effectiveDate} · ${doc.category}',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: context.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBlock(BuildContext context, PlatformDocSection sec) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sec.heading.isNotEmpty) ...[
          Text(
            sec.heading,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
        ],
        if (sec.summary.isNotEmpty) ...[
          Text(
            sec.summary,
            style: GoogleFonts.inter(
              fontSize: 12.0,
              fontWeight: FontWeight.w400,
              height: 1.38,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (sec.callout.isNotEmpty) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: AppColors.brandPink.withValues(alpha: 0.30),
                width: 1.0,
              ),
            ),
            child: Text(
              sec.callout,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
        for (final bullet in sec.bullets)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.brandBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    bullet,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w400,
                      height: 1.38,
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmptySearch(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 30, color: context.textMuted),
          const SizedBox(height: 8),
          Text(
            'No rule or feature matches "$_query"',
            style: GoogleFonts.inter(
              fontSize: 13.0,
              fontWeight: FontWeight.w700,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Try searching: M-Pesa, copyright, 4K Live, Looks, 116, delete, or POPIA',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: context.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(
    BuildContext context, {
    required bool isSignedIn,
    required bool isAdmin,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRIVACY & SAFETY CONTACTS',
            style: GoogleFonts.inter(
              fontSize: 10.0,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Privacy & DPO: dpo@oneova.app · Appeals: appeals@oneova.app · Child Safety (24/7): childsafety@oneova.app · Copyright: copyright@oneova.app · Law Enforcement: lawenforcement@oneova.app · Legal: legal@oneova.app',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              height: 1.38,
              color: context.textSecondary,
            ),
          ),
          if (isSignedIn) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push('/settings/privacy');
                },
                icon: const Icon(Icons.lock_outline_rounded, size: 16),
                label: Text(
                  'Manage My Privacy, 2FA & Data Controls',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
          ],
          if (isAdmin) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push('/settings/admin-cms');
                },
                icon: const Icon(Icons.cloud_sync_rounded, size: 16, color: AppColors.brandPink),
                label: Text(
                  'Open Real-Time Docs & Rules Admin CMS',
                  style: GoogleFonts.inter(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.border, width: 1.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChipSpec {
  final String id;
  final String label;
  final IconData icon;

  const _FilterChipSpec({
    required this.id,
    required this.label,
    required this.icon,
  });
}
