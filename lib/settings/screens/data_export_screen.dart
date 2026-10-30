import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';

/// Screen allowing Oneova users to request a complete GDPR-compliant archive of their data.
class DataExportScreen extends StatefulWidget {
  const DataExportScreen({super.key});

  @override
  State<DataExportScreen> createState() => _DataExportScreenState();
}

class _DataExportScreenState extends State<DataExportScreen> {
  bool _isSubmitting = false;
  String _selectedFormat = 'JSON';
  final Set<String> _selectedCategories = {'profile', 'posts', 'messages', 'settings'};

  Future<void> _submitExportRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('data_exports')
          .add({
        'userId': user.uid,
        'userEmail': user.email ?? 'creator@oneova.app',
        'format': _selectedFormat,
        'categories': _selectedCategories.toList(),
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: context.border, width: 1.0),
          ),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.brandBlue, size: 22),
              const SizedBox(width: 8),
              Text(
                'Archive Requested',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            'We are compiling your Oneova data archive. A secure download link will be delivered to ${user.email ?? 'your email'} once your package is prepared.',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              color: context.textSecondary,
              height: 1.4,
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request export: $e', style: const TextStyle(color: Colors.white)),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Download Your Data',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: context.topBarFg,
            letterSpacing: -0.3,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.25), width: 1.2),
                  ),
                  child: const Icon(Icons.cloud_download_rounded, color: AppColors.brandBlue, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Get a copy of what you\'ve shared on Oneova',
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'We\'ll email a download link to ${user?.email ?? 'your account email'}. Files can take up to 24 hours to generate.',
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: context.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Categories section
          Text(
            'SELECT INFORMATION TO INCLUDE',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _buildCategoryTile('profile', 'Profile Information', 'Bio, avatars, contact details, account history', Icons.person_outline),
                Divider(height: 1, thickness: 1, color: context.border, indent: 56),
                _buildCategoryTile('posts', 'Posts & Studio Creations', 'Videos, reels, audio clips, looks, captions', Icons.video_library_outlined),
                Divider(height: 1, thickness: 1, color: context.border, indent: 56),
                _buildCategoryTile('messages', 'Messages & Transcripts', 'Chat messages, media attachments, Ova AI interactions', Icons.chat_bubble_outline),
                Divider(height: 1, thickness: 1, color: context.border, indent: 56),
                _buildCategoryTile('settings', 'Settings & Preferences', 'Security choices, blocklist, push notifications', Icons.tune_outlined),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Format selection
          Text(
            'DATA FORMAT',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: context.border, width: 1.0),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                _buildFormatOption('JSON', 'Raw JSON (For backup)'),
                const SizedBox(width: 8),
                _buildFormatOption('HTML', 'Visual HTML (Read in browser)'),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // Request button
          SizedBox(
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                elevation: 0,
              ),
              onPressed: _isSubmitting || _selectedCategories.isEmpty ? null : _submitExportRequest,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Request Archive',
                      style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 24),

          // Previous requests stream
          if (user != null) ...[
            Text(
              'RECENT EXPORT REQUESTS',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('data_exports')
                  .orderBy('requestedAt', descending: true)
                  .limit(5)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surface,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: context.border, width: 1.0),
                    ),
                    child: Center(
                      child: Text(
                        'No previous data exports requested.',
                        style: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                      ),
                    ),
                  );
                }

                return Container(
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    separatorBuilder: (context, index) => Divider(height: 1, color: context.border),
                    itemBuilder: (context, index) {
                      final data = docs[index].data() as Map<String, dynamic>;
                      final status = data['status'] as String? ?? 'pending';
                      final format = data['format'] as String? ?? 'JSON';
                      final ts = (data['requestedAt'] as Timestamp?)?.toDate();
                      final dateStr = ts != null ? '${ts.day}/${ts.month}/${ts.year}' : 'Recent';

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          status == 'ready' ? Icons.check_circle_outline : Icons.hourglass_top_rounded,
                          color: status == 'ready' ? const Color(0xFF10B981) : AppColors.brandBlue,
                          size: 20,
                        ),
                        title: Text(
                          'Oneova Archive ($format)',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
                        ),
                        subtitle: Text(
                          'Requested $dateStr • Status: ${status.toUpperCase()}',
                          style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryTile(String key, String title, String subtitle, IconData icon) {
    final isSelected = _selectedCategories.contains(key);

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          if (isSelected) {
            _selectedCategories.remove(key);
          } else {
            _selectedCategories.add(key);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isSelected ? AppColors.brandBlue : context.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11.0, color: context.textMuted),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: isSelected,
              activeColor: AppColors.brandBlue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedCategories.add(key);
                  } else {
                    _selectedCategories.remove(key);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatOption(String format, String desc) {
    final isSelected = _selectedFormat == format;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedFormat = format);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: isSelected ? AppColors.brandBlue : context.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      format,
                      style: GoogleFonts.inter(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? AppColors.brandBlue : context.textPrimary,
                      ),
                    ),
                    Text(
                      desc,
                      style: GoogleFonts.inter(fontSize: 10.0, color: context.textMuted),
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
}
