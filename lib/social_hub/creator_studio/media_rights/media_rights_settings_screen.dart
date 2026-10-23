import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../../backend/media_rights/models/media_rights_models.dart';
import '../../../../backend/media_rights/services/media_rights_service.dart';
import '../../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class MediaRightsSettingsScreen extends ConsumerStatefulWidget {
  final String mediaId;

  const MediaRightsSettingsScreen({
    super.key,
    required this.mediaId,
  });

  @override
  ConsumerState<MediaRightsSettingsScreen> createState() => _MediaRightsSettingsScreenState();
}

class _MediaRightsSettingsScreenState extends ConsumerState<MediaRightsSettingsScreen> {
  // ignore: unused_field
  final _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    final rightsAsync = ref.watch(mediaRightsServiceProvider).streamMediaRights(widget.mediaId);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        title: Text('Media Rights & Reuse', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: StreamBuilder<MediaRightsProfile?>(
        stream: rightsAsync,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: context.textPrimary)));
          }
          
          final profile = snapshot.data;
          if (profile == null) {
            return Center(child: Text('Rights profile not found.', style: TextStyle(color: context.textMuted)));
          }

          if (profile.isRevoked) {
            return const Center(child: Text('These rights have been permanently revoked.', style: TextStyle(color: AppColors.brandBlue, fontSize: 18, fontWeight: FontWeight.bold)));
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildSectionTitle('Visibility & License'),
              _buildCard([
                ListTile(
                  title: Text('Visibility', style: TextStyle(color: context.textPrimary)),
                  subtitle: Text(_formatEnum(profile.visibility.name), style: TextStyle(color: context.textSecondary)),
                  trailing: Icon(Icons.public, color: context.textMuted),
                ),
                ListTile(
                  title: Text('License', style: TextStyle(color: context.textPrimary)),
                  subtitle: Text(_formatEnum(profile.license.name), style: TextStyle(color: context.textSecondary)),
                  trailing: Icon(Icons.gavel, color: context.textMuted),
                ),
              ]),

              const SizedBox(height: 24),
              _buildSectionTitle('Reuse Permissions'),
              _buildCard([
                _buildSwitch('Allow Download', profile.permissions.allowDownload, (v) => _updatePermission(profile, allowDownload: v)),
                _buildSwitch('Allow Remix', profile.permissions.allowRemix, (v) => _updatePermission(profile, allowRemix: v)),
                _buildSwitch('Allow Duet', profile.permissions.allowDuet, (v) => _updatePermission(profile, allowDuet: v)),
                _buildSwitch('Allow Stitch', profile.permissions.allowStitch, (v) => _updatePermission(profile, allowStitch: v)),
                _buildSwitch('Allow Repost', profile.permissions.allowRepost, (v) => _updatePermission(profile, allowRepost: v)),
                _buildSwitch('Allow Embed', profile.permissions.allowEmbed, (v) => _updatePermission(profile, allowEmbed: v)),
              ]),

              const SizedBox(height: 24),
              _buildSectionTitle('Advanced Rights'),
              _buildCard([
                _buildSwitch('Opt-in to AI Processing', profile.permissions.allowAIProcessing, (v) => _updatePermission(profile, allowAIProcessing: v)),
                _buildSwitch('Allow Commercial Use', profile.permissions.allowCommercialUse, (v) => _updatePermission(profile, allowCommercialUse: v)),
              ]),
              
              const SizedBox(height: 32),
              OutlinedButton.icon(
                icon: Icon(Icons.block, color: AppColors.brandBlue),
                label: Text('Revoke All Reuse Rights', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.brandBlue),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _revokeRights(context),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(color: context.textMuted, fontSize: 14, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      color: context.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(children: children),
    );
  }

  Widget _buildSwitch(String title, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(title, style: TextStyle(color: context.textPrimary)),
      value: value,
      activeThumbColor: AppColors.brandBlue,
      onChanged: onChanged,
    );
  }

  Future<void> _updatePermission(MediaRightsProfile profile, {
    bool? allowDownload,
    bool? allowRemix,
    bool? allowDuet,
    bool? allowStitch,
    bool? allowRepost,
    bool? allowEmbed,
    bool? allowAIProcessing,
    bool? allowCommercialUse,
  }) async {
    final updatedPermissions = ReusePermissions(
      allowDownload: allowDownload ?? profile.permissions.allowDownload,
      allowRemix: allowRemix ?? profile.permissions.allowRemix,
      allowDuet: allowDuet ?? profile.permissions.allowDuet,
      allowStitch: allowStitch ?? profile.permissions.allowStitch,
      allowRepost: allowRepost ?? profile.permissions.allowRepost,
      allowEmbed: allowEmbed ?? profile.permissions.allowEmbed,
      allowAIProcessing: allowAIProcessing ?? profile.permissions.allowAIProcessing,
      allowCommercialUse: allowCommercialUse ?? profile.permissions.allowCommercialUse,
    );

    final updatedProfile = MediaRightsProfile(
      mediaId: profile.mediaId,
      ownerId: profile.ownerId,
      creatorId: profile.creatorId,
      sourceUrl: profile.sourceUrl,
      attributionRequirement: profile.attributionRequirement,
      license: profile.license,
      visibility: profile.visibility,
      isRevoked: profile.isRevoked,
      permissions: updatedPermissions,
    );

    await ref.read(mediaRightsServiceProvider).updateMediaRights(widget.mediaId, updatedProfile);
  }

  Future<void> _revokeRights(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        title: Text('Revoke Rights?', style: TextStyle(color: context.textPrimary)),
        content: Text('This will permanently disable downloads, remixes, duets, and stitches for this media, and may trigger backend deletion of downstream derivative works.', style: TextStyle(color: context.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: context.textMuted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold))),
        ],
      )
    );
    
    if (confirm == true) {
      await ref.read(mediaRightsServiceProvider).revokeReuse(widget.mediaId);
    }
  }

  String _formatEnum(String str) {
    return str[0].toUpperCase() + str.substring(1).replaceAllMapped(RegExp(r'[A-Z]'), (match) => ' ${match.group(0)}');
  }
}
