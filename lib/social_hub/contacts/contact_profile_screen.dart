import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../backend/contacts/models/contact_profile.dart';
import '../../shared/theme/app_theme.dart';

class ContactProfileScreen extends ConsumerStatefulWidget {
  final ContactProfile profile;

  const ContactProfileScreen({
    super.key,
    required this.profile,
  });

  @override
  ConsumerState<ContactProfileScreen> createState() => _ContactProfileScreenState();
}

class _ContactProfileScreenState extends ConsumerState<ContactProfileScreen> {
  // Assume we start with a dummy state for demonstration
  bool isMuted = false;
  
  void _executeAction(String actionName) {
    // Scaffold message to represent action dispatch
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Executing action: $actionName for ${widget.profile.displayName}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: context.textPrimary),
            onPressed: _showMoreActionsBottomSheet,
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _buildHeader(p),
            const SizedBox(height: 24),
            _buildPrimaryActions(),
            const SizedBox(height: 32),
            _buildDetailsSection(p),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ContactProfile p) {
    return Container(
      width: double.infinity,
      color: context.surface,
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          Hero(
            tag: 'avatar_${p.id}',
            child: CircleAvatar(
              radius: 64,
              backgroundColor: context.surfaceMid,
              backgroundImage: NetworkImage(p.profileImage),
              onBackgroundImageError: (_, _) {},
            ),
          ),
          const SizedBox(height: 16),
          Text(
            p.displayName,
            style: GoogleFonts.inter(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '@${p.username}',
            style: GoogleFonts.inter(
              fontSize: 16,
              color: context.textSecondary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildRelationshipChip(p.relationshipStatus),
        ],
      ),
    );
  }

  Widget _buildRelationshipChip(ContactRelationship status) {
    if (status == ContactRelationship.none) return const SizedBox.shrink();
    
    Color chipColor;
    String label;
    
    switch (status) {
      case ContactRelationship.mutual:
        chipColor = AppColors.brandBlue;
        label = "MUTUAL";
        break;
      case ContactRelationship.following:
        chipColor = Colors.blueAccent;
        label = "FOLLOWING";
        break;
      case ContactRelationship.follower:
        chipColor = Colors.greenAccent;
        label = "FOLLOWER";
        break;
      case ContactRelationship.blocked:
        chipColor = Colors.red;
        label = "BLOCKED";
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.2),
        border: Border.all(color: chipColor.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          color: chipColor,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildPrimaryActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.message,
            label: "Message",
            onTap: () => _executeAction("Message"),
          ),
          _ActionButton(
            icon: Icons.call,
            label: "Call",
            onTap: () => _executeAction("Call"),
          ),
          _ActionButton(
            icon: Icons.videocam,
            label: "Video",
            onTap: () => _executeAction("Video Call"),
          ),
          _ActionButton(
            icon: widget.profile.relationshipStatus == ContactRelationship.following ||
                  widget.profile.relationshipStatus == ContactRelationship.mutual 
                  ? Icons.person_remove 
                  : Icons.person_add,
            label: widget.profile.relationshipStatus == ContactRelationship.following ||
                   widget.profile.relationshipStatus == ContactRelationship.mutual
                   ? "Unfollow" : "Follow",
            onTap: () => _executeAction(
              widget.profile.relationshipStatus == ContactRelationship.following ||
              widget.profile.relationshipStatus == ContactRelationship.mutual 
              ? "Unfollow" : "Follow"
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection(ContactProfile p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Render contact info only if permissions allowed it (not null)
          if (p.phone != null || p.email != null) ...[
            _SectionTitle("CONTACT INFO"),
            if (p.phone != null) _InfoRow(Icons.phone, p.phone!),
            if (p.email != null) _InfoRow(Icons.email, p.email!),
            const SizedBox(height: 24),
          ],
          
          if (p.lastInteraction != null) ...[
            _SectionTitle("LAST INTERACTION"),
            _InfoRow(Icons.history, DateFormat.yMMMd().add_jm().format(p.lastInteraction!)),
            const SizedBox(height: 24),
          ],
          
          if (p.tags.isNotEmpty) ...[
            _SectionTitle("TAGS"),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: p.tags.map((tag) => Chip(
                label: Text(tag, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: context.textPrimary)),
                backgroundColor: context.surfaceMid,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              )).toList(),
            ),
            const SizedBox(height: 24),
          ],
          
          if (p.sharedConversations.isNotEmpty) ...[
            _SectionTitle("SHARED CONVERSATIONS (${p.sharedConversations.length})"),
            _ListPreview(items: p.sharedConversations, icon: Icons.forum),
            const SizedBox(height: 24),
          ],
          
          if (p.sharedChannels.isNotEmpty) ...[
            _SectionTitle("SHARED CHANNELS (${p.sharedChannels.length})"),
            _ListPreview(items: p.sharedChannels, icon: Icons.tag),
            const SizedBox(height: 24),
          ],
          
          if (p.recentFiles.isNotEmpty) ...[
            _SectionTitle("RECENT FILES"),
            _ListPreview(items: p.recentFiles, icon: Icons.insert_drive_file),
            const SizedBox(height: 24),
          ],
          
          if (p.mediaUris.isNotEmpty) ...[
            _SectionTitle("MEDIA"),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: p.mediaUris.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 12),
                    decoration: BoxDecoration(
                      color: context.surfaceMid,
                      borderRadius: BorderRadius.circular(12),
                      image: DecorationImage(
                        image: NetworkImage(p.mediaUris[index]),
                        fit: BoxFit.cover,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
          
          if (p.notes.isNotEmpty) ...[
            _SectionTitle("NOTES"),
            ...p.notes.map((n) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(n, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 14)),
              ),
            )),
          ],
        ],
      ),
    );
  }

  void _showMoreActionsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(isMuted ? Icons.volume_up : Icons.volume_off, color: context.textPrimary),
                title: Text(isMuted ? 'Unmute' : 'Mute', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
                onTap: () {
                  setState(() => isMuted = !isMuted);
                  context.pop();
                  _executeAction(isMuted ? "Mute" : "Unmute");
                },
              ),
              ListTile(
                leading: Icon(Icons.note_add, color: context.textPrimary),
                title: Text('Add note', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Add note");
                },
              ),
              ListTile(
                leading: Icon(Icons.assignment_ind, color: context.textPrimary),
                title: Text('Assign', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Assign");
                },
              ),
              ListTile(
                leading: Icon(Icons.task, color: context.textPrimary),
                title: Text('Create task', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Create task");
                },
              ),
              ListTile(
                leading: Icon(Icons.schedule, color: context.textPrimary),
                title: Text('Schedule follow-up', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Schedule follow-up");
                },
              ),
              Divider(color: context.border),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.redAccent),
                title: Text('Block', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Block");
                },
              ),
              ListTile(
                leading: const Icon(Icons.flag, color: Colors.redAccent),
                title: Text('Report', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                onTap: () {
                  context.pop();
                  _executeAction("Report");
                },
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.brandBlue, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: context.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: context.textSecondary,
          letterSpacing: 2.0,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: context.textSecondary, size: 20),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListPreview extends StatelessWidget {
  final List<String> items;
  final IconData icon;

  const _ListPreview({required this.items, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items.take(3).map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, color: AppColors.brandBlue, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item,
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}
