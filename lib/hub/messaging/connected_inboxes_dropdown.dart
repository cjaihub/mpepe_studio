import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/social_connection_service.dart';
import '../../shared/theme/app_theme.dart';

class ConnectedInboxesDropdown extends ConsumerWidget {
  final String selectedPlatform;
  final ValueChanged<String> onSelectPlatform;
  final VoidCallback onClose;
  final int totalUnreadCount;

  const ConnectedInboxesDropdown({
    super.key,
    required this.selectedPlatform,
    required this.onSelectPlatform,
    required this.onClose,
    this.totalUnreadCount = 48,
  });

  static void show(
    BuildContext context, {
    required String selectedPlatform,
    required ValueChanged<String> onSelectPlatform,
    int totalUnreadCount = 48,
  }) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
        alignment: Alignment.topCenter,
        child: ConnectedInboxesDropdown(
          selectedPlatform: selectedPlatform,
          onSelectPlatform: (platform) {
            Navigator.of(ctx).pop();
            onSelectPlatform(platform);
          },
          onClose: () => Navigator.of(ctx).pop(),
          totalUnreadCount: totalUnreadCount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionsAsync = ref.watch(userSocialConnectionsStreamProvider);
    final connections = connectionsAsync.value ?? [];

    final int computedAllCount = connections.fold<int>(
      totalUnreadCount,
      (sum, item) => sum + (item.unreadCount > 0 ? item.unreadCount : 0),
    );

    return Container(
      width: 290,
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.12),
            blurRadius: 18,
            spreadRadius: -2,
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ─── Header: CONNECTED INBOXES & SYNCED pill ─────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CONNECTED INBOXES',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: AppColors.brandPink,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'SYNCED',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ─── Empty state or Platforms list ──────────────────────────────
          if (connections.isEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.hub_outlined,
                    color: Colors.white.withValues(alpha: 0.4),
                    size: 24,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No Connected Platforms',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connect WhatsApp Biz, TikTok, Instagram or YouTube to aggregate messages, comments, and uploads in Oneova.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ] else ...[
            // 1. All Inboxes card
            _buildInboxTile(
              isSelected: selectedPlatform == 'all',
              iconWidget: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.45)),
                ),
                child: const Icon(Icons.language_rounded, color: Colors.white, size: 18),
              ),
              title: Row(
                children: [
                  Text(
                    'All Inboxes',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: const BoxDecoration(
                      color: AppColors.brandPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              subtitle: 'Active aggregator',
              badgeCount: computedAllCount,
              badgeColor: AppColors.brandPink,
              onTap: () => onSelectPlatform('all'),
            ),
            const SizedBox(height: 7),

            // 2. Connected Platform items
            ...connections.map((conn) {
              final isSelected = selectedPlatform.toLowerCase() == conn.platform.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildInboxTile(
                  isSelected: isSelected,
                  iconWidget: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Color(conn.badgeColorHex).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Color(conn.badgeColorHex).withValues(alpha: 0.45)),
                    ),
                    child: Center(
                      child: Text(
                        conn.badgeCode,
                        style: GoogleFonts.inter(
                          color: Color(conn.badgeColorHex),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        conn.displayName,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  subtitle: conn.accountName.isNotEmpty ? conn.accountName : 'Active',
                  badgeCount: conn.unreadCount > 0 ? conn.unreadCount : null,
                  badgeColor: const Color(0xFF1E293B),
                  onTap: () => onSelectPlatform(conn.platform),
                  onInfoTap: () => _showPlatformCapabilities(context, ref, conn),
                ),
              );
            }),
          ],

          // ─── Bottom CTA: + Connect New Platform ─────────────────────────
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: AppColors.brandPink.withValues(alpha: 0.6),
                width: 1.2,
              ),
              backgroundColor: AppColors.brandPink.withValues(alpha: 0.08),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 11),
            ),
            onPressed: () {
              Navigator.of(context).pop();
              ConnectPlatformSheet.show(context);
            },
            icon: const Icon(Icons.add, color: AppColors.brandPink, size: 16),
            label: Text(
              'Connect New Platform',
              style: GoogleFonts.inter(
                color: AppColors.brandPink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInboxTile({
    required bool isSelected,
    required Widget iconWidget,
    required Widget title,
    required String subtitle,
    int? badgeCount,
    Color badgeColor = const Color(0xFF1E293B),
    required VoidCallback onTap,
    VoidCallback? onInfoTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF18181C)
              : const Color(0xFF121215),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.brandBlue.withValues(alpha: 0.8)
                : Colors.white.withValues(alpha: 0.06),
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          children: [
            iconWidget,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  title,
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (badgeCount != null && badgeCount > 0) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  '$badgeCount',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            if (onInfoTap != null)
              GestureDetector(
                onTap: onInfoTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPlatformCapabilities(BuildContext context, WidgetRef ref, SocialConnection conn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F0F12),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Color(conn.badgeColorHex).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        conn.badgeCode,
                        style: GoogleFonts.inter(
                          color: Color(conn.badgeColorHex),
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          conn.displayName,
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          conn.accountName,
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: const Text('ACTIVE', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'ACTIVE API CAPABILITIES',
                style: GoogleFonts.inter(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: conn.capabilities.map((cap) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E24),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PlatformCapability.getIcon(cap), size: 14, color: AppColors.brandPink),
                        const SizedBox(width: 6),
                        Text(
                          PlatformCapability.getLabel(cap),
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent, width: 1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await ref.read(socialConnectionProvider.notifier).disconnectPlatform(conn.platform);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${conn.displayName} disconnected.'),
                              backgroundColor: Colors.black87,
                            ),
                          );
                        }
                      },
                      child: const Text('Disconnect Platform', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ConnectPlatformSheet extends ConsumerStatefulWidget {
  const ConnectPlatformSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const ConnectPlatformSheet(),
    );
  }

  @override
  ConsumerState<ConnectPlatformSheet> createState() => _ConnectPlatformSheetState();
}

class _ConnectPlatformSheetState extends ConsumerState<ConnectPlatformSheet> {
  final Map<String, TextEditingController> _handleControllers = {};

  @override
  void initState() {
    super.initState();
    for (final p in kSupportedPlatforms) {
      _handleControllers[p.id] = TextEditingController(text: p.handleHint);
    }
  }

  @override
  void dispose() {
    for (final controller in _handleControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionsAsync = ref.watch(userSocialConnectionsStreamProvider);
    final connections = connectionsAsync.value ?? [];
    final connectedPlatformIds = connections.map((c) => c.platform.toLowerCase()).toSet();

    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D11),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.85),
            blurRadius: 30,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.15),
            blurRadius: 36,
            spreadRadius: 1,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Connect New Platform',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Omnichannel inboxes, comments & uploads',
                        style: GoogleFonts.inter(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  itemCount: kSupportedPlatforms.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final platform = kSupportedPlatforms[index];
                    final isConnected = connectedPlatformIds.contains(platform.id.toLowerCase());

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141416),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isConnected
                              ? AppColors.brandBlue.withValues(alpha: 0.6)
                              : Colors.white.withValues(alpha: 0.08),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.7),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: isConnected
                                ? AppColors.brandBlue.withValues(alpha: 0.22)
                                : AppColors.brandBlue.withValues(alpha: 0.06),
                            blurRadius: 20,
                            spreadRadius: -2,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Color(platform.badgeColorHex).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Color(platform.badgeColorHex).withValues(alpha: 0.5),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(platform.badgeColorHex).withValues(alpha: 0.25),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              child: Center(
                                child: Text(
                                  platform.badgeCode,
                                  style: GoogleFonts.inter(
                                    color: Color(platform.badgeColorHex),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        platform.displayName,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (platform.isRecommended) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.brandPink.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'HOT',
                                            style: TextStyle(
                                              color: AppColors.brandPink,
                                              fontSize: 8.5,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    platform.description,
                                    style: GoogleFonts.inter(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isConnected)
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E293B),
                                  foregroundColor: Colors.white70,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onPressed: () async {
                                  await ref.read(socialConnectionProvider.notifier).disconnectPlatform(platform.id);
                                },
                                child: const Text('Linked', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              )
                            else
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: AppColors.brandBlue.withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                onPressed: () async {
                                  final handle = _handleControllers[platform.id]?.text.trim() ?? platform.handleHint;
                                  await ref.read(socialConnectionProvider.notifier).addConnection(
                                    platform.id,
                                    handle,
                                    displayName: platform.displayName,
                                    badgeCode: platform.badgeCode,
                                    badgeColorHex: platform.badgeColorHex,
                                    capabilities: platform.capabilities,
                                    unreadCount: platform.id == 'whatsapp' ? 24 : (platform.id == 'tiktok' ? 14 : (platform.id == 'instagram' ? 10 : 0)),
                                  );
                                  HapticFeedback.lightImpact();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Connected ${platform.displayName}!'),
                                        backgroundColor: AppColors.brandBlue,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                },
                                child: const Text('Connect', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Capabilities row
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: platform.capabilities.map((cap) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(PlatformCapability.getIcon(cap), size: 10, color: Colors.white60),
                                  const SizedBox(width: 4),
                                  Text(
                                    PlatformCapability.getLabel(cap),
                                    style: const TextStyle(color: Colors.white70, fontSize: 9.5, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
  }
}
