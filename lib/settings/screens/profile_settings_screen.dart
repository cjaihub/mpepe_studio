import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/services/oneova_biometrics_service.dart';
import '../../backend/storage_service.dart';
import '../../backend/user_service.dart';
import '../../providers/settings_provider.dart';
import '../../shared/services/draft_store.dart';
import '../../shared/services/oneova_feature_tour_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/undo/undo_manager.dart';
import '../commands/update_setting_command.dart';
import '../widgets/oneova_about_account_sheet.dart';
import '../widgets/oneova_profile_qr_sheet.dart';
import '../widgets/oneova_verification_request_sheet.dart';
import '../widgets/settings_kit.dart';

/// Oneova Profile 2.0 Settings Screen
///
/// Features:
/// - Avatar & Cover Photo uploads (direct to Firebase Storage)
/// - Real-time Username availability check with cooldown protection
/// - Pronouns & Creator Niche / Category picker
/// - Account Type switcher: Personal / Creator / Business
/// - Business-specific fields (Email, Phone, Hours, Shop catalog)
/// - Multiple external Links in Bio manager
/// - Location metadata
/// - My Profile QR Code modal (instant offline/online sharing)
/// - Verification request flow and "About this account" transparency
/// - Instant debounced auto-save across local DraftStore and Cloud Firestore
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _locationController = TextEditingController();
  final _bizEmailController = TextEditingController();
  final _bizPhoneController = TextEditingController();
  final _bizHoursController = TextEditingController();
  final _bizShopUrlController = TextEditingController();

  bool _initialized = false;
  Timer? _debounce;
  Timer? _usernameDebounce;
  late Map<String, dynamic> _lastSavedProfile;

  // Username validation state
  bool _isCheckingUsername = false;
  bool? _isUsernameValid;
  String _usernameStatusMessage = '';

  // Uploading state
  bool _isUploadingAvatar = false;
  bool _isUploadingCover = false;

  final List<String> _commonPronouns = ['he/him', 'she/her', 'they/them', 'he/they', 'she/they'];

  final List<String> _creatorCategories = [
    'Afrobeats & Dance',
    'Music & Audio',
    'Film & Video',
    'Fashion & Beauty',
    'Comedy & Skits',
    'Tech & Gaming',
    'Business & Biz Pro',
    'Fitness & Health',
    'Visual Arts',
    'Education',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _usernameDebounce?.cancel();
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _bizEmailController.dispose();
    _bizPhoneController.dispose();
    _bizHoursController.dispose();
    _bizShopUrlController.dispose();
    super.dispose();
  }

  void _onFieldChanged(Map<String, dynamic> currentProfile) {
    // Write in-flight draft to DraftStore
    DraftStore.instance.setDraft(DraftStore.profileDisplayNameKey, _displayNameController.text);
    DraftStore.instance.setDraft(DraftStore.profileBioKey, _bioController.text);

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () {
      _autoSave(currentProfile);
    });
  }

  void _onUsernameChanged(String newUsername, String currentUid, Map<String, dynamic> currentProfile) {
    _usernameDebounce?.cancel();
    final clean = newUsername.trim().toLowerCase().replaceAll('@', '');

    if (clean.length < 3) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameValid = false;
        _usernameStatusMessage = 'Username must be at least 3 characters';
      });
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameStatusMessage = 'Checking availability…';
    });

    _usernameDebounce = Timer(const Duration(milliseconds: 500), () async {
      final available = await ref.read(userProvider.notifier).isUsernameAvailable(clean, currentUid);
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameValid = available;
        _usernameStatusMessage = available ? 'Username is available!' : 'Username is already taken';
      });

      if (available) {
        _autoSave(currentProfile);
      }
    });
  }

  void _autoSave(Map<String, dynamic> currentProfile) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final newProfile = {
      ...currentProfile,
      'displayName': _displayNameController.text.trim(),
      'username': _usernameController.text.trim().toLowerCase().replaceAll('@', ''),
      'bio': _bioController.text.trim(),
      'location': _locationController.text.trim(),
      'businessDetails': {
        'email': _bizEmailController.text.trim(),
        'phone': _bizPhoneController.text.trim(),
        'hours': _bizHoursController.text.trim(),
        'shopUrl': _bizShopUrlController.text.trim(),
      },
    };

    final command = UpdateSettingCommand(
      ref: ref,
      category: 'profile',
      undoData: _lastSavedProfile,
      data: newProfile,
      name: 'Update Profile',
    );

    ref.read(undoManagerProvider.notifier).executeAndRegister(command);
    _lastSavedProfile = newProfile;

    // Simultaneously sync to users/{uid} collection for public profile parity
    ref.read(userProvider.notifier).updateUserProfile(uid, {
      'fullName': _displayNameController.text.trim(),
      'displayName': _displayNameController.text.trim(),
      if (_usernameController.text.trim().isNotEmpty)
        'username': _usernameController.text.trim().toLowerCase().replaceAll('@', ''),
      'bio': _bioController.text.trim(),
      'location': _locationController.text.trim(),
      'businessDetails': newProfile['businessDetails'],
      'accountType': newProfile['accountType'] ?? 'personal',
      'category': newProfile['category'] ?? '',
      'pronouns': newProfile['pronouns'] ?? '',
      'links': newProfile['links'] ?? [],
    });
  }

  Future<void> _pickAndUploadImage({required bool isCover}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: isCover ? 85 : 90,
      maxWidth: isCover ? 1920 : 800,
    );

    if (picked == null) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      if (isCover) {
        _isUploadingCover = true;
      } else {
        _isUploadingAvatar = true;
      }
    });

    try {
      final storage = ref.read(storageServiceProvider);
      final file = File(picked.path);
      final ext = picked.path.split('.').last;
      final path = 'users/$uid/${isCover ? "cover" : "avatar"}_${DateTime.now().millisecondsSinceEpoch}.$ext';

      final url = await storage.uploadFile(file, path);
      if (url != null && mounted) {
        final fieldKey = isCover ? 'coverPhotoUrl' : 'profilePhotoUrl';
        await ref.read(userProvider.notifier).updateUserProfile(uid, {fieldKey: url});
        ref.read(settingsProvider.notifier).updateSetting('profile', fieldKey, url);

        HapticFeedback.mediumImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${isCover ? "Cover" : "Avatar"} updated successfully!'),
              backgroundColor: AppColors.brandBlue,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload image: $e'),
            backgroundColor: AppColors.brandPink,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          if (isCover) {
            _isUploadingCover = false;
          } else {
            _isUploadingAvatar = false;
          }
        });
      }
    }
  }

  void _showAddLinkModal(Map<String, dynamic> profile) {
    final titleController = TextEditingController();
    final urlController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Add External Link',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: ctx.textPrimary,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: ctx.textSecondary, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'LINK TITLE',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: titleController,
              style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
              decoration: InputDecoration(
                hintText: 'e.g. YouTube Channel, Merch, Spotify',
                hintStyle: GoogleFonts.inter(fontSize: 12.5, color: ctx.textMuted),
                filled: true,
                fillColor: ctx.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: ctx.border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'URL DESTINATION',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AppColors.brandBlue,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: urlController,
              keyboardType: TextInputType.url,
              style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary),
              decoration: InputDecoration(
                hintText: 'https://...',
                hintStyle: GoogleFonts.inter(fontSize: 12.5, color: ctx.textMuted),
                filled: true,
                fillColor: ctx.surfaceMid,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  borderSide: BorderSide(color: ctx.border),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final title = titleController.text.trim();
                  var url = urlController.text.trim();
                  if (title.isEmpty || url.isEmpty) return;
                  if (!url.startsWith('http://') && !url.startsWith('https://')) {
                    url = 'https://$url';
                  }

                  final currentLinks = List<dynamic>.from(profile['links'] ?? []);
                  currentLinks.add({'title': title, 'url': url});

                  settingsWrite(
                    ref,
                    category: 'profile',
                    current: profile,
                    key: 'links',
                    value: currentLinks,
                    label: 'Links',
                  );

                  final uid = FirebaseAuth.instance.currentUser?.uid;
                  if (uid != null) {
                    ref.read(userProvider.notifier).updateUserProfile(uid, {'links': currentLinks});
                  }

                  Navigator.pop(ctx);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  elevation: 0,
                ),
                child: Text(
                  'Add Link',
                  style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final userAsync = ref.watch(currentUserProfileProvider);
    final appUser = userAsync.value;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text(
              'Edit Profile',
              style: GoogleFonts.inter(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.topBarFg,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(width: 8),
            const SettingsSaveIndicator(),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.brandBlue),
        ),
        error: (e, s) => Center(
          child: Text('Error: $e', style: const TextStyle(color: AppColors.brandPink)),
        ),
        data: (settings) {
          final profile = settings['profile'] as Map<String, dynamic>? ?? {};

          if (!_initialized) {
            _displayNameController.text = profile['displayName'] ?? appUser?.fullName ?? '';
            _usernameController.text = profile['username'] ?? appUser?.username ?? '';
            _bioController.text = profile['bio'] ?? appUser?.bio ?? '';
            _locationController.text = profile['location'] ?? appUser?.location ?? '';

            final biz = profile['businessDetails'] as Map<String, dynamic>? ?? appUser?.businessDetails ?? {};
            _bizEmailController.text = biz['email'] ?? '';
            _bizPhoneController.text = biz['phone'] ?? '';
            _bizHoursController.text = biz['hours'] ?? '';
            _bizShopUrlController.text = biz['shopUrl'] ?? '';

            _lastSavedProfile = profile;
            _initialized = true;
          }

          final selectedAccountType = profile['accountType'] as String? ?? appUser?.accountType ?? 'personal';
          final selectedCategory = profile['category'] as String? ?? appUser?.category ?? '';
          final selectedPronoun = profile['pronouns'] as String? ?? appUser?.pronouns ?? '';
          final links = List<dynamic>.from(profile['links'] ?? appUser?.links ?? []);
          final coverUrl = profile['coverPhotoUrl'] ?? appUser?.coverPhotoUrl;
          final avatarUrl = profile['profilePhotoUrl'] ?? appUser?.profilePhotoUrl;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            children: [
              // 1. Cover & Avatar Visual Branding Block
              _buildCoverAndAvatarHeader(context, coverUrl: coverUrl, avatarUrl: avatarUrl),
              const SizedBox(height: 20),

              // 2. Core Identity Group
              _buildGroupContainer(
                context,
                title: 'CORE IDENTITY',
                children: [
                  _buildInputLabel('DISPLAY NAME'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _displayNameController,
                    onChanged: (_) => _onFieldChanged(profile),
                    style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w600, color: context.textPrimary),
                    decoration: _inputDecoration(context, hint: 'Official Creator Name'),
                  ),
                  const SizedBox(height: 16),

                  _buildInputLabel('HANDLE / USERNAME'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _usernameController,
                    onChanged: (val) => _onUsernameChanged(val, appUser?.id ?? '', profile),
                    style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w600, color: AppColors.brandPink),
                    decoration: _inputDecoration(
                      context,
                      hint: 'username',
                      prefixText: '@',
                      suffixIcon: _isCheckingUsername
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                              ),
                            )
                          : _isUsernameValid == true
                              ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18)
                              : _isUsernameValid == false
                                  ? const Icon(Icons.error_outline_rounded, color: AppColors.brandPink, size: 18)
                                  : null,
                    ),
                  ),
                  if (_usernameStatusMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _usernameStatusMessage,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _isUsernameValid == true ? const Color(0xFF10B981) : AppColors.brandPink,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  _buildInputLabel('PRONOUNS'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _commonPronouns.map((p) {
                      final isSelected = selectedPronoun == p;
                      return ChoiceChip(
                        label: Text(p),
                        selected: isSelected,
                        onSelected: (selected) {
                          final next = selected ? p : '';
                          settingsWrite(ref, category: 'profile', current: profile, key: 'pronouns', value: next, label: 'Pronouns');
                        },
                        selectedColor: AppColors.brandBlue,
                        backgroundColor: context.surfaceMid,
                        labelStyle: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : context.textSecondary,
                        ),
                        side: BorderSide(color: isSelected ? AppColors.brandBlue : context.border, width: 1.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  _buildInputLabel('CREATOR BIO'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _bioController,
                    onChanged: (_) => _onFieldChanged(profile),
                    maxLines: 3,
                    maxLength: 150,
                    style: GoogleFonts.inter(fontSize: 13.0, color: context.textPrimary, height: 1.4),
                    decoration: _inputDecoration(context, hint: 'Tell your audience about your style and studio vision...'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Category & Creator Niche
              _buildGroupContainer(
                context,
                title: 'CATEGORY & NICHE',
                children: [
                  Text(
                    'Select the primary industry category for your profile recommendation algorithm:',
                    style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _creatorCategories.map((cat) {
                      final isSelected = selectedCategory == cat;
                      return ChoiceChip(
                        label: Text(cat),
                        selected: isSelected,
                        onSelected: (selected) {
                          final next = selected ? cat : '';
                          settingsWrite(ref, category: 'profile', current: profile, key: 'category', value: next, label: 'Category');
                        },
                        selectedColor: AppColors.brandBlue,
                        backgroundColor: context.surfaceMid,
                        labelStyle: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? Colors.white : context.textPrimary,
                        ),
                        side: BorderSide(color: isSelected ? AppColors.brandBlue : context.border, width: 1.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      );
                    }).toList(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4. Account Type (Personal / Creator / Business)
              _buildGroupContainer(
                context,
                title: 'ACCOUNT TYPE',
                children: [
                  Row(
                    children: [
                      _buildAccountTypeOption(
                        context,
                        type: 'personal',
                        label: 'Personal',
                        icon: Icons.person_rounded,
                        isSelected: selectedAccountType == 'personal',
                        onTap: () => settingsWrite(ref, category: 'profile', current: profile, key: 'accountType', value: 'personal', label: 'Account Type'),
                      ),
                      const SizedBox(width: 8),
                      _buildAccountTypeOption(
                        context,
                        type: 'creator',
                        label: 'Creator Pro',
                        icon: Icons.auto_awesome_rounded,
                        isSelected: selectedAccountType == 'creator',
                        onTap: () => settingsWrite(ref, category: 'profile', current: profile, key: 'accountType', value: 'creator', label: 'Account Type'),
                      ),
                      const SizedBox(width: 8),
                      _buildAccountTypeOption(
                        context,
                        type: 'business',
                        label: 'Business',
                        icon: Icons.storefront_rounded,
                        isSelected: selectedAccountType == 'business',
                        onTap: () => settingsWrite(ref, category: 'profile', current: profile, key: 'accountType', value: 'business', label: 'Account Type'),
                      ),
                    ],
                  ),
                  if (selectedAccountType == 'business') ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),
                    _buildInputLabel('BUSINESS EMAIL'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bizEmailController,
                      onChanged: (_) => _onFieldChanged(profile),
                      keyboardType: TextInputType.emailAddress,
                      style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                      decoration: _inputDecoration(context, hint: 'contact@business.com'),
                    ),
                    const SizedBox(height: 14),
                    _buildInputLabel('BUSINESS PHONE / WHATSAPP'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bizPhoneController,
                      onChanged: (_) => _onFieldChanged(profile),
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                      decoration: _inputDecoration(context, hint: '+1 (555) 000-0000'),
                    ),
                    const SizedBox(height: 14),
                    _buildInputLabel('BUSINESS HOURS'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bizHoursController,
                      onChanged: (_) => _onFieldChanged(profile),
                      style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                      decoration: _inputDecoration(context, hint: 'Mon - Fri: 9:00 AM - 6:00 PM'),
                    ),
                    const SizedBox(height: 14),
                    _buildInputLabel('CATALOG / SHOP URL'),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _bizShopUrlController,
                      onChanged: (_) => _onFieldChanged(profile),
                      style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                      decoration: _inputDecoration(context, hint: 'https://shop.oneova.app/...'),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),

              // 5. Links in Bio
              _buildGroupContainer(
                context,
                title: 'LINKS IN BIO',
                action: TextButton.icon(
                  onPressed: () => _showAddLinkModal(profile),
                  icon: const Icon(Icons.add_rounded, size: 16, color: AppColors.brandBlue),
                  label: Text('Add Link', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
                children: [
                  if (links.isEmpty)
                    Text(
                      'No links added yet. Add external channels to direct followers to your portfolio or storefront.',
                      style: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                    )
                  else
                    ...links.asMap().entries.map((entry) {
                      final index = entry.key;
                      final link = entry.value as Map<String, dynamic>;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.link_rounded, size: 16, color: AppColors.brandBlue),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    link['title']?.toString() ?? 'Link',
                                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: context.textPrimary),
                                  ),
                                  Text(
                                    link['url']?.toString() ?? '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppColors.brandPink),
                              onPressed: () {
                                final updated = List<dynamic>.from(links)..removeAt(index);
                                settingsWrite(ref, category: 'profile', current: profile, key: 'links', value: updated, label: 'Delete Link');
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
              const SizedBox(height: 16),

              // 6. Location (Optional)
              _buildGroupContainer(
                context,
                title: 'LOCATION',
                children: [
                  TextField(
                    controller: _locationController,
                    onChanged: (_) => _onFieldChanged(profile),
                    style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
                    decoration: _inputDecoration(
                      context,
                      hint: 'City, Country (e.g. Lagos, Nigeria / London, UK)',
                      prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: AppColors.brandBlue),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 7. Creator Tools & Transparency (QR, Verification, About)
              _buildGroupContainer(
                context,
                title: 'CREATOR TRANSPARENCY & TOOLS',
                children: [
                  _buildActionTile(
                    context,
                    icon: Icons.qr_code_2_rounded,
                    title: 'My Profile QR Code',
                    subtitle: 'Show high-contrast card for instant offline scanning',
                    accentColor: AppColors.brandBlue,
                    onTap: () {
                      if (appUser != null) OneovaProfileQrSheet.show(context, appUser);
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildActionTile(
                    context,
                    icon: Icons.verified_user_outlined,
                    title: appUser?.isVerified == true ? 'Verification Badge Active' : 'Request Verification Badge',
                    subtitle: appUser?.isVerified == true
                        ? 'Official studio trust badge confirmed on profile'
                        : 'Submit legal identity to get official blue check badge',
                    accentColor: appUser?.isVerified == true ? const Color(0xFF10B981) : AppColors.brandBlue,
                    trailing: appUser?.isVerified == true ? const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18) : null,
                    onTap: () {
                      if (appUser != null && !appUser.isVerified) {
                        OneovaVerificationRequestSheet.show(context, appUser);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildActionTile(
                    context,
                    icon: Icons.info_outline_rounded,
                    title: 'About This Account',
                    subtitle: 'Account join date, location, and username history',
                    accentColor: AppColors.brandPink,
                    onTap: () {
                      if (appUser != null) OneovaAboutAccountSheet.show(context, appUser);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 8. Hardware Biometrics & Tour
              _buildBiometricsAndTour(context),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCoverAndAvatarHeader(
    BuildContext context, {
    String? coverUrl,
    String? avatarUrl,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.border, width: 1.0),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Cover Banner
          Stack(
            children: [
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.brandBlue.withValues(alpha: 0.8),
                      AppColors.brandPink.withValues(alpha: 0.6),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  image: coverUrl != null && coverUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(coverUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _isUploadingCover
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : null,
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: InkWell(
                  onTap: () => _pickAndUploadImage(isCover: true),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.0),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'Edit Cover',
                          style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Avatar block overlapping
          Transform.translate(
            offset: const Offset(0, -32),
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.border, width: 2.0),
                      ),
                      child: CircleAvatar(
                        radius: 40,
                        backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                        backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                        child: _isUploadingAvatar
                            ? const CircularProgressIndicator(color: AppColors.brandBlue)
                            : (avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(Icons.person, size: 40, color: AppColors.brandBlue)
                                : null),
                      ),
                    ),
                    InkWell(
                      onTap: () => _pickAndUploadImage(isCover: false),
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(Icons.photo_camera_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Tap to change official photo',
                  style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupContainer(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: AppColors.brandBlue,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildInputLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: context.textSecondary,
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    String? prefixText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
      prefixText: prefixText,
      prefixStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.brandPink),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: context.surfaceMid,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: context.border, width: 1.0),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: context.border, width: 1.0),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
      ),
    );
  }

  Widget _buildAccountTypeOption(
    BuildContext context, {
    required String type,
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.12) : context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: isSelected ? AppColors.brandBlue : context.border,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: isSelected ? AppColors.brandBlue : context.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? AppColors.brandBlue : context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: context.border, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 13.0, fontWeight: FontWeight.w700, color: context.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(fontSize: 11.0, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.brandBlue),
          ],
        ),
      ),
    );
  }

  Widget _buildBiometricsAndTour(BuildContext context) {
    return Column(
      children: [
        // Biometrics
        FutureBuilder<BiometricCapability>(
          future: ref.read(oneovaBiometricsServiceProvider).getCapabilityDetails(),
          builder: (context, snapshot) {
            final cap = snapshot.data;
            final isReady = cap?.hasEnrolledBiometrics ?? false;

            return Container(
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.fingerprint_rounded, color: AppColors.brandBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hardware Passkey & Biometrics',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: context.textPrimary),
                        ),
                        Text(
                          isReady ? 'Hardware Keystore active' : 'Bind fingerprint for studio actions',
                          style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/settings/privacy'),
                    child: Text('Configure', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),

        // Interactive Tour
        InkWell(
          onTap: () async {
            await ref.read(featureTourServiceProvider).resetTour();
            if (context.mounted) {
              ref.read(featureTourCurrentStepProvider.notifier).setStep(0);
              ref.read(featureTourVisibilityProvider.notifier).show();
              context.go('/hub/home');
            }
          },
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, size: 18, color: AppColors.brandPink),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Replay Interactive Feature Tour',
                    style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                  ),
                ),
                const Icon(Icons.play_circle_fill_rounded, size: 18, color: AppColors.brandPink),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
