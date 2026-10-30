import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../services/platform_docs_cms_service.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isPlatformDocsAdminProvider).value == true;
    final docsAsync = ref.watch(publishedPlatformDocsProvider);
    final totalDocs = docsAsync.value?.length ?? OneovaPlatformDocsCatalog.defaults.length;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: Text(
          'About Oneova',
          style: GoogleFonts.inter(
            fontSize: 17.5,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OneovaCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: AppColors.brandBlue.withValues(alpha: 0.3),
                      width: 1.0,
                    ),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    size: 26,
                    color: AppColors.brandBlue,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Oneova',
                  style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Version 1.0.0 · Built Africa-first for creators, communities & businesses worldwide.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                      color: AppColors.brandPink.withValues(alpha: 0.30),
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    '$totalDocs LIVE DOCS & RULES · REAL-TIME WEB SYNC',
                    style: GoogleFonts.inter(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.brandPink,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            context.push('/legal');
                          },
                          icon: const Icon(Icons.gavel_rounded, size: 15),
                          label: Text(
                            'Rules & Legal',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 40,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            context.push('/legal?tab=features');
                          },
                          icon: Icon(
                            Icons.auto_stories_rounded,
                            size: 15,
                            color: context.textPrimary,
                          ),
                          label: Text(
                            'Feature Docs',
                            style: GoogleFonts.inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimary,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: context.surfaceMid,
                            side: BorderSide(color: context.border, width: 1.0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.brandPink.withValues(alpha: 0.45),
                  width: 1.0,
                ),
              ),
              child: _buildDocRow(
                context,
                Icons.edit_note_rounded,
                'Live Docs & Rules Admin CMS',
                'Edit features & policies live across App & Website',
                '/settings/admin-cms',
                false,
                accentColor: AppColors.brandPink,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              'PLATFORM DOCUMENTATION & GOVERNANCE',
              style: GoogleFonts.inter(
                fontSize: 10.0,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: context.textMuted,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Column(
              children: [
                _buildDocRow(
                  context,
                  Icons.stars_rounded,
                  'Platform Features & Studio Guides',
                  '4K Live, Looks Engine, AI Lab, Wallet & Creator Rooms',
                  '/legal?tab=features',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.people_alt_rounded,
                  'Community Guidelines',
                  'Scam protection, dignity rules, 3-strike ladder & appeals',
                  '/legal?tab=guidelines',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.description_rounded,
                  'Terms of Service',
                  '100% creator content ownership, SIM-recycle & consumer rights',
                  '/legal?tab=terms',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.shield_outlined,
                  'Privacy Policy',
                  'Zero personal-data sales, zero PIN storage & AI firewall',
                  '/legal?tab=privacy',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.health_and_safety_rounded,
                  'Child & Teen Safety',
                  'CSAM zero tolerance, teen privacy defaults & 116 helplines',
                  '/legal?tab=safety',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.storefront_rounded,
                  'Biz & Creator Monetization',
                  'Coins, Live Gifts, licensed M-Pesa/MoMo payouts & Biz rules',
                  '/legal?tab=biz',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.delete_sweep_rounded,
                  'Self-Service Data Deletion',
                  '2-tap account erasure, data export & OAuth revocation',
                  '/legal?tab=deletion',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.gavel_rounded,
                  'Law Enforcement Guidelines',
                  'Court-order due process, human-rights review & user notice',
                  '/legal?tab=law_enforcement',
                  true,
                ),
                _buildDocRow(
                  context,
                  Icons.public_rounded,
                  'African & Global Law',
                  'AU Malabo, Kenya ODPC, Nigeria NDPA, POPIA, GDPR & DSA',
                  '/legal?tab=africa',
                  false,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocRow(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    String route,
    bool showDivider, {
    Color? accentColor,
  }) {
    final resolvedAccent = accentColor ?? AppColors.brandBlue;
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: () {
            HapticFeedback.lightImpact();
            context.push(route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: resolvedAccent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          color: context.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: context.border, indent: 44, endIndent: 14),
      ],
    );
  }
}
