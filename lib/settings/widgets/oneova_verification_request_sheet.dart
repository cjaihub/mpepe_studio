import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/user_service.dart';
import '../../shared/theme/app_theme.dart';

class OneovaVerificationRequestSheet extends ConsumerStatefulWidget {
  final AppUser user;

  const OneovaVerificationRequestSheet({super.key, required this.user});

  static Future<void> show(BuildContext context, AppUser user) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OneovaVerificationRequestSheet(user: user),
    );
  }

  @override
  ConsumerState<OneovaVerificationRequestSheet> createState() => _OneovaVerificationRequestSheetState();
}

class _OneovaVerificationRequestSheetState extends ConsumerState<OneovaVerificationRequestSheet> {
  final _legalNameController = TextEditingController();
  final _stageNameController = TextEditingController();
  final _proofLinkController = TextEditingController();
  String _selectedCategory = 'Creator & Art';
  bool _isSubmitting = false;

  final List<String> _categories = [
    'Creator & Art',
    'Music & Audio',
    'Film & Entertainment',
    'Fashion & Modeling',
    'Tech & Gaming',
    'Business & Brand',
    'Journalism & News',
    'Government & Public',
  ];

  @override
  void initState() {
    super.initState();
    _legalNameController.text = widget.user.fullName;
    _stageNameController.text = widget.user.username ?? '';
  }

  @override
  void dispose() {
    _legalNameController.dispose();
    _stageNameController.dispose();
    _proofLinkController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final legalName = _legalNameController.text.trim();
    if (legalName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your official legal name.'),
          backgroundColor: AppColors.brandPink,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      await ref.read(userProvider.notifier).requestVerification(widget.user.id, {
        'legalName': legalName,
        'stageName': _stageNameController.text.trim(),
        'category': _selectedCategory,
        'proofLink': _proofLinkController.text.trim(),
        'submittedAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Verification request submitted! Our studio trust team will review your account.',
                  style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.brandBlue,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit: $e'),
          backgroundColor: AppColors.brandPink,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.textMuted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.verified_rounded, color: AppColors.brandBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request Verification Badge',
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        'Verified badges confirm creator authenticity on Oneova',
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.textSecondary, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              'LEGAL FULL NAME',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _legalNameController,
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'As it appears on official government ID',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'KNOWN AS / STAGE NAME',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _stageNameController,
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'Public creator or brand name',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'CREATOR CATEGORY',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  dropdownColor: context.surface,
                  items: _categories.map((c) {
                    return DropdownMenuItem(
                      value: c,
                      child: Text(
                        c,
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategory = val);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'OFFICIAL WEBSITE OR PROOF LINK',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _proofLinkController,
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
              decoration: InputDecoration(
                hintText: 'https://yourwebsite.com or article link',
                hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                filled: true,
                fillColor: context.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: context.border),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  elevation: 0,
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Submit Verification Request',
                        style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
