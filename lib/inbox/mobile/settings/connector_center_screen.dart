import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/connectors/models/connector_models.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectorCenterScreen extends ConsumerStatefulWidget {
  const ConnectorCenterScreen({super.key});

  @override
  ConsumerState<ConnectorCenterScreen> createState() => _ConnectorCenterScreenState();
}

class _ConnectorCenterScreenState extends ConsumerState<ConnectorCenterScreen> {
  // In a real implementation, this would come from a Riverpod provider
  final List<ConnectedAccount> _mockAccounts = [
    ConnectedAccount(
      externalAccountId: 'yt_123',
      platformId: 'YouTube',
      connectorId: 'youtube_core',
      displayName: 'Oneova Official',
      status: 'VERIFIED',
      capabilities: [
        PlatformCapability.contentPublish,
        PlatformCapability.analytics,
        PlatformCapability.mediaUpload,
      ],
      scopes: const ['youtube.readonly', 'youtube.upload'],
      connectedAt: DateTime.now().subtract(const Duration(days: 3)),
      reauthRequired: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        title: Text(
          'Connector Center',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: context.textPrimary,
          ),
        ),
        iconTheme: IconThemeData(color: context.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildHeader(),
          const SizedBox(height: 24),
          _buildSectionTitle('Active Connections'),
          const SizedBox(height: 12),
          ..._mockAccounts.map((a) => _buildAccountCard(a)),
          const SizedBox(height: 24),
          _buildAddConnectorButton(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: AppColors.brandBlue, size: 28),
              const SizedBox(width: 12),
              Text(
                'Platform Control',
                style: GoogleFonts.inter(
                  color: context.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Manage your live connections to external platforms. Health checks are continuously executed.',
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.inter(
        color: context.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildAccountCard(ConnectedAccount account) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: account.reauthRequired ? Colors.red : context.border, 
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_getPlatformIcon(account.platformId), color: context.textPrimary, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      account.platformId,
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _buildHealthBadge(account),
            ],
          ),
          const SizedBox(height: 16),
          _buildCapabilityMatrix(account.capabilities),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  // View Webhook Lifecycle & detailed health
                },
                child: Text(
                  'Diagnostics',
                  style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.surfaceMid,
                  foregroundColor: context.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  // Trigger Reauth
                },
                child: Text('Re-Auth', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHealthBadge(ConnectedAccount account) {
    final color = account.reauthRequired ? Colors.red : Colors.green;
    final text = account.reauthRequired ? 'ACTION REQUIRED' : 'HEALTHY';
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCapabilityMatrix(List<PlatformCapability> caps) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: caps.map((c) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.bg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.border),
          ),
          child: Text(
            c.name,
            style: GoogleFonts.inter(
              color: context.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildAddConnectorButton() {
    return InkWell(
      onTap: () {
        // Show OAuth modal selector
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brandBlue, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.add, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            Text(
              'Link New Provider',
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platformId) {
    switch (platformId.toLowerCase()) {
      case 'youtube': return Icons.play_circle_fill;
      case 'instagram': return Icons.camera_alt;
      case 'facebook': return Icons.facebook;
      case 'whatsapp': return Icons.chat;
      case 'tiktok': return Icons.music_note;
      default: return Icons.api;
    }
  }
}
