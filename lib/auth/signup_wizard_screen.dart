import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl_phone_field/country_picker_dialog.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import '../../backend/location_service.dart';
import '../../backend/user_service.dart';
import '../../backend/onboarding_persistence_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/social_preview_card.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'auth_repository.dart';
import 'services/secure_logout_service.dart';

class SignupWizardScreen extends ConsumerStatefulWidget {
  const SignupWizardScreen({super.key});

  @override
  ConsumerState<SignupWizardScreen> createState() => _SignupWizardScreenState();
}

class _SignupWizardScreenState extends ConsumerState<SignupWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isSaving = false;
  bool _isLoadingDraft = true;

  String? _initialCountryCode;
  String _fullPhoneNumber = '';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _igController = TextEditingController();
  final _ytController = TextEditingController();

  // Password UI state
  bool _passwordVisible = false;
  int _passwordStrength = 0; // 0-4
  String _passwordStrengthLabel = '';

  // Email availability
  bool? _emailAvailable; // null = unchecked, true = available, false = taken
  bool _isCheckingEmail = false;

  // Avatar upload
  File? _avatarFile;
  double? _avatarUploadProgress;
  bool _isUploadingAvatar = false;

  String _selectedRole = 'Client';
  final List<String> _roles = ['Client', 'Artist', 'Staff'];

  String? _selectedDepartment;
  final List<String> _departments = ['Video Production', 'Audio Production', 'Post-Production', 'Marketing'];

  String _avatarPath = '';
  bool _agreedToTerms = false;
  bool _optInEmails = true;
  String _preferredLanguage = 'en';
  String _themeMode = 'system';
  // ── Google pre-auth state ────────────────────────────────────────────────────
  // When user arrives from Google Sign-In (new account), we pre-fill their
  // identity and skip the email/password security step entirely.
  bool _isGoogleUser = false;
  String? _googleUid;
  bool _googleDataApplied = false; // Prevent re-applying on every rebuild


  @override
  void initState() {
    super.initState();
    _loadDraft();
    _detectLocation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Read GoRouter extra to detect Google Sign-In pre-fill
    // This runs after the route is fully resolved, so GoRouterState is available
    if (_googleDataApplied) return;
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra != null && extra['fromGoogle'] == true) {
      _googleDataApplied = true;
      _isGoogleUser = true;
      _googleUid = extra['uid'] as String?;
      final email = extra['email'] as String? ?? '';
      final name = extra['name'] as String? ?? '';
      _emailController.text = email;
      _nameController.text = name;
      // Jump to step 1 (Personal Identity) — skip step 0 (Role) isn't needed,
      // but we DO skip step 2 (Security) via _nextStep logic below.
    }
  }

  Future<void> _detectLocation() async {
    final code = await LocationService.getCountryCode();
    if (mounted && code != null && _initialCountryCode == null) {
      setState(() {
        _initialCountryCode = code;
      });
    }
  }

  Future<void> _loadDraft() async {
    final draft = await ref.read(onboardingPersistenceProvider).loadDraft();
    if (draft != null && mounted) {
      setState(() => _isLoadingDraft = false);
      final resume = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Resume Signup?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: Text('We found an incomplete signup draft. Would you like to resume where you left off?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(onboardingPersistenceProvider).clearDraft();
                Navigator.of(context).pop(false);
              },
              child: Text('Start Over', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (resume == true) {
        final data = draft['data'] as Map<String, dynamic>;
        setState(() {
          _currentStep = draft['stepIndex'] as int;
          _selectedRole = data['role'] ?? 'Client';
          _emailController.text = data['email'] ?? '';
          _passwordController.text = data['password'] ?? '';
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _fullPhoneNumber = data['fullPhone'] ?? '';
          if (data['countryCode'] != null) {
            _initialCountryCode = data['countryCode'];
          }
          _avatarPath = data['avatar'] ?? '';
          _selectedDepartment = data['department'];
          _igController.text = data['ig'] ?? '';
          _ytController.text = data['yt'] ?? '';
          _agreedToTerms = data['agreedToTerms'] ?? false;
          _optInEmails = data['optInEmails'] ?? true;
        });
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(_currentStep);
          }
        });
      }
    } else {
      if (mounted) setState(() => _isLoadingDraft = false);
    }
  }

  Future<void> _saveDraft() async {
    final data = {
      'role': _selectedRole,
      'email': _emailController.text,
      // ⚠️ SECURITY: password is NEVER persisted in drafts
      'name': _nameController.text,
      'phone': _phoneController.text,
      'fullPhone': _fullPhoneNumber,
      'countryCode': _initialCountryCode,
      'avatar': _avatarPath,
      'department': _selectedDepartment,
      'ig': _igController.text,
      'yt': _ytController.text,
      'agreedToTerms': _agreedToTerms,
      'emailOptIn': _optInEmails,
      'currentStep': _currentStep,
    };
    await ref.read(onboardingPersistenceProvider).saveDraft(_currentStep, data);
  }

  void _nextStep() {
    final totalSteps = 9;
    if (_currentStep < totalSteps) {
      int nextStep = _currentStep + 1;
      // For Google users, skip step index 2 (Account Security — email/password)
      // since Firebase Auth is already handled by Google Sign-In
      if (_isGoogleUser && nextStep == 2) nextStep = 3;
      _pageController.animateToPage(
        nextStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep = nextStep);
      _saveDraft();
    }
  }

  Future<void> _attemptExit() async {
    if (_currentStep > 0 || _emailController.text.isNotEmpty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text('Save & Exit?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          content: Text('Your progress will be saved. You can resume later.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8))),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.primary, foregroundColor: Colors.white),
              onPressed: () {
                _saveDraft();
                Navigator.of(context).pop(true);
              },
              child: const Text('Save & Exit'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    if (mounted) {
      await ref.read(secureLogoutServiceProvider).logout();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      int prevStep = _currentStep - 1;
      // For Google users, skip back over step 2 (Account Security)
      if (_isGoogleUser && prevStep == 2) prevStep = 1;
      _pageController.animateToPage(
        prevStep,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep = prevStep);
      _saveDraft();
    } else {
      _attemptExit();
    }
  }

  // ── Password strength calculator ─────────────────────────────────────────
  void _evaluatePasswordStrength(String password) {
    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]'))) score++;
    final labels = ['', 'Weak', 'Fair', 'Strong', 'Very Strong'];
    setState(() {
      _passwordStrength = score;
      _passwordStrengthLabel = score > 0 ? labels[score] : '';
    });
  }

  // ── Email availability check (debounced) ──────────────────────────────────
  Future<void> _checkEmailAvailability(String email) async {
    if (!email.contains('@') || !email.contains('.')) {
      setState(() => _emailAvailable = null);
      return;
    }
    setState(() {
      _isCheckingEmail = true;
      _emailAvailable = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email.toLowerCase().trim())
          .limit(1)
          .get();
      if (mounted) {
        setState(() {
          _emailAvailable = snap.docs.isEmpty;
          _isCheckingEmail = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingEmail = false);
    }
  }

  // ── Real avatar picker + Firebase Storage upload ──────────────────────────
  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('Choose Photo', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded),
                title: const Text('Choose from Gallery'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_rounded),
                title: const Text('Take a Photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    final picked = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) return;

    setState(() {
      _avatarFile = File(picked.path);
      _isUploadingAvatar = true;
      _avatarUploadProgress = 0;
    });

    try {
      // Upload to Firebase Storage (temp path; will be moved to uid path on signup)
      final tempRef = FirebaseStorage.instance
          .ref('avatars/temp/${DateTime.now().millisecondsSinceEpoch}.jpg');
      final task = tempRef.putFile(_avatarFile!);
      task.snapshotEvents.listen((snap) {
        if (mounted) {
          setState(() {
            _avatarUploadProgress =
                snap.bytesTransferred / snap.totalBytes;
          });
        }
      });
      await task;
      final downloadUrl = await tempRef.getDownloadURL();
      if (mounted) {
        setState(() {
          _avatarPath = downloadUrl;
          _isUploadingAvatar = false;
          _avatarUploadProgress = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploadingAvatar = false;
          _avatarUploadProgress = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to upload photo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _completeSignup() async {
    setState(() => _isSaving = true);

    // ── Pre-flight: check for duplicate phone (skip email dupe for Google users) ─
    try {
      if (!_isGoogleUser) {
        final emailSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: _emailController.text.toLowerCase().trim())
            .limit(1)
            .get();
        if (emailSnap.docs.isNotEmpty) {
          if (mounted) {
            setState(() => _isSaving = false);
            _showDuplicateSheet(isEmail: true, isPhone: false);
          }
          return;
        }
      }

      if (_fullPhoneNumber.isNotEmpty) {
        final phoneSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: _fullPhoneNumber)
            .limit(1)
            .get();
        if (phoneSnap.docs.isNotEmpty) {
          if (mounted) {
            setState(() => _isSaving = false);
            _showDuplicateSheet(isEmail: false, isPhone: true);
          }
          return;
        }
      }
    } catch (_) {
      // Non-fatal: proceed if Firestore check fails
    }

    try {
      String uid;

      if (_isGoogleUser && _googleUid != null) {
        // ✨ Google users are already Firebase-authenticated — just create Firestore profile
        uid = _googleUid!;
      } else {
        final userCredential = await ref.read(authRepositoryProvider).createUserWithEmailAndPassword(
          email: _emailController.text,
          password: _passwordController.text,
        );
        uid = userCredential.user?.uid ?? (throw Exception('Failed to get user ID after creation.'));
      }


      // Move temp avatar to permanent path if exists
      String photoUrl = _avatarPath;
      if (_avatarFile != null && _avatarPath.isNotEmpty) {
        try {
          final permRef = FirebaseStorage.instance.ref('avatars/$uid.jpg');
          await permRef.putFile(_avatarFile!);
          photoUrl = await permRef.getDownloadURL();
        } catch (_) {}
      }

      final newUser = AppUser(
        id: uid,
        fullName: _nameController.text,
        email: _emailController.text,
        role: _selectedRole,
        department: _selectedRole == 'Staff'
            ? (_selectedDepartment ?? 'Video Production')
            : '',
        status: 'pending',
        preferredLanguage: _preferredLanguage,
        themeMode: _themeMode,
        createdAt: DateTime.now(),
      );

      await ref.read(userProvider.notifier).createUser(newUser);

      // Save phone + photoUrl to the Firestore user doc directly
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        if (_fullPhoneNumber.isNotEmpty) 'phoneNumber': _fullPhoneNumber,
        if (photoUrl.isNotEmpty) 'photoUrl': photoUrl,
        'optInEmails': _optInEmails,
      });

      await ref.read(onboardingPersistenceProvider).clearDraft();

      if (mounted) {
        setState(() => _isSaving = false);
        context.go('/auth/main_login');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        String errorMessage = e.message ?? 'Authentication failed';
        if (e.code == 'email-already-in-use') {
          errorMessage = 'An account with this email already exists.';
        } else if (e.code == 'weak-password') {
          errorMessage = 'Password too weak. Add uppercase, numbers and symbols.';
        } else if (e.code == 'invalid-email') {
          errorMessage = 'Invalid email address.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            action: e.code == 'email-already-in-use'
                ? SnackBarAction(
                    label: 'Log In',
                    textColor: Colors.white,
                    onPressed: () => context.go('/auth/main_login'),
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('An unexpected error occurred. Please try again.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }

  void _showDuplicateSheet({required bool isEmail, required bool isPhone}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.mpepeMaroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    color: AppColors.mpepeMaroon, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                isEmail && isPhone
                    ? 'Email & Phone Already Registered'
                    : isEmail
                        ? 'Email Already Registered'
                        : 'Phone Number Already Registered',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                isEmail && isPhone
                    ? 'Both your email and phone are linked to an existing account. Please log in instead.'
                    : isEmail
                        ? 'This email is already linked to an existing MPEPE Studio account.'
                        : 'This phone number is already linked to an existing account.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await ref.read(secureLogoutServiceProvider).logout();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Log In Instead',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Go Back & Edit',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDraft) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.onSurface),
          onPressed: _prevStep,
        ),
        title: Text('Join MPEPE Studio', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: const [
          ThemeToggleButton(),
          SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStepContainer(1, 'Welcome & Intent', 'What brings you to MPEPE Studio?', _buildRoleSelection(), canAdvance: true),
                  _buildStepContainer(2, 'Personal Identity', 'What should we call you?', _buildIdentityFields(), canAdvance: _nameController.text.trim().isNotEmpty),
                  // Step 3 (index 2): Account Security — skipped for Google users via _nextStep logic
                  _buildStepContainer(3, 'Account Security', 'Secure your account', _buildSecurityFields(),
                      canAdvance: _isGoogleUser ||
                          (_emailController.text.contains('@') && _passwordController.text.length >= 6)),
                  _buildStepContainer(4, 'Contact Details', 'How can we reach you?', _buildContactFields(), canAdvance: _phoneController.text.trim().isNotEmpty),
                  _buildStepContainer(5, 'Avatar Setup', 'Add a profile picture', _buildAvatarSelection(), canAdvance: true),
                  _buildStepContainer(6, 'Focus Area', 'Select your main interest or department', _buildDepartmentSelection(), canAdvance: true),
                  _buildStepContainer(7, 'Social Links', 'Connect your audience', _buildSocialFields(), canAdvance: true),
                  _buildStepContainer(8, 'Preferences', 'Customize your experience', _buildPreferences(), canAdvance: true),
                  _buildStepContainer(9, 'Agreements', 'Just a few rules to follow', _buildAgreements(), canAdvance: _agreedToTerms),
                  _buildFinalStep(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContainer(int step, String title, String subtitle, Widget child, {required bool canAdvance}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Step $step of 10', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text(title, style: AppTheme.h1Style),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
          const SizedBox(height: 32),
          child,
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: MpepeButton(
              text: 'Continue',
              onPressed: canAdvance ? _nextStep : () {},
              isPrimary: canAdvance,
            ),
          ),
        ],
      ).animate().fadeIn().slideX(begin: 0.05),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(10, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  // --- Step 1: Role ---
  Widget _buildRoleSelection() {
    return Column(
      children: _roles.map((role) {
        final isSelected = _selectedRole == role;
        return GestureDetector(
          onTap: () => setState(() => _selectedRole = role),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1) : Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outline,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  role == 'Client' ? Icons.work_outline : (role == 'Artist' ? Icons.mic_external_on_outlined : Icons.admin_panel_settings_outlined),
                  color: isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(role, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                if (isSelected) Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- Step 2: Identity ---
  Widget _buildIdentityFields() {
    return Column(
      children: [
        _buildTextField('Full Legal Name', _nameController, icon: Icons.person_outline, onChanged: (_) => setState((){})),
        const SizedBox(height: 16),
        Text('We use this for billing and official communications.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
      ],
    );
  }

  // --- Step 3: Security ---
  Widget _buildSecurityFields() {
    final strengthColors = [
      Colors.transparent,
      Colors.redAccent,
      Colors.orangeAccent,
      Colors.lightGreen,
      Colors.green,
    ];
    final strengthColor = _passwordStrength > 0
        ? strengthColors[_passwordStrength]
        : Theme.of(context).colorScheme.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Email field with availability indicator
        TextField(
          controller: _emailController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          keyboardType: TextInputType.emailAddress,
          onChanged: (val) {
            setState(() {});
            _checkEmailAvailability(val);
          },
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            prefixIcon: Icon(Icons.email_outlined,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            suffixIcon: _isCheckingEmail
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _emailAvailable == null
                    ? null
                    : Icon(
                        _emailAvailable! ? Icons.check_circle : Icons.cancel,
                        color: _emailAvailable! ? Colors.green : Colors.redAccent,
                      ),
            helperText: _emailAvailable == null
                ? null
                : _emailAvailable!
                    ? '✓ Email is available'
                    : '✗ This email is already registered',
            helperStyle: TextStyle(
              color: _emailAvailable == true ? Colors.green : Colors.redAccent,
              fontSize: 12,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: _emailAvailable == false
                    ? Colors.redAccent
                    : _emailAvailable == true
                        ? Colors.green
                        : Theme.of(context).colorScheme.outline,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Password field with show/hide + strength meter
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          onChanged: (val) {
            setState(() {});
            _evaluatePasswordStrength(val);
          },
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            prefixIcon: Icon(Icons.lock_outline,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible ? Icons.visibility_off : Icons.visibility,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 2),
            ),
          ),
        ),
        if (_passwordController.text.isNotEmpty) ...[
          const SizedBox(height: 12),
          // Strength bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _passwordStrength / 4,
              backgroundColor:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _passwordStrengthLabel,
                style: TextStyle(
                    color: strengthColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              Text(
                '${_passwordController.text.length} chars',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.4),
                    fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Rule checklist
          _buildPasswordRule(
              '≥ 8 characters', _passwordController.text.length >= 8),
          _buildPasswordRule('Uppercase letter',
              _passwordController.text.contains(RegExp(r'[A-Z]'))),
          _buildPasswordRule(
              'Number', _passwordController.text.contains(RegExp(r'[0-9]'))),
          _buildPasswordRule(
              'Symbol (!@#...)',
              _passwordController.text
                  .contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]'))),
        ],
      ],
    );
  }

  Widget _buildPasswordRule(String label, bool met) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            met ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: met
                ? Colors.green
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: met
                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)
                  : Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 4: Contact ---
  Widget _buildContactFields() {
    return Column(
      children: [
        IntlPhoneField(
          controller: _phoneController,
          initialCountryCode: _initialCountryCode ?? 'KE', // Default to Kenya
          decoration: InputDecoration(
            labelText: 'Phone Number',
            hintText: 'e.g. 07... / 70000...',
            labelStyle: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            ),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          dropdownTextStyle:
              TextStyle(color: Theme.of(context).colorScheme.onSurface),
          pickerDialogStyle: PickerDialogStyle(
            backgroundColor: const Color(0xFF161616),
            listTileDivider: const SizedBox.shrink(),
            countryCodeStyle: const TextStyle(
                color: Colors.white70, fontWeight: FontWeight.w500),
            countryNameStyle: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
            searchFieldInputDecoration: InputDecoration(
              hintText: 'Search country...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white70),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white10,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          onChanged: (phone) {
            _fullPhoneNumber = phone.completeNumber;
            _initialCountryCode = phone.countryISOCode;
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Icon(Icons.info_outline,
                size: 14,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Enter any format — 07, 7, 01, 1, +254... we handle it automatically.',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // --- Step 5: Avatar ---
  Widget _buildAvatarSelection() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircleAvatar(
                  radius: 64,
                  backgroundColor:
                      Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  backgroundImage:
                      _avatarFile != null ? FileImage(_avatarFile!) : null,
                  child: _avatarFile == null
                      ? Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 44,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.35),
                        )
                      : null,
                ),
                if (_isUploadingAvatar)
                  SizedBox(
                    width: 128,
                    height: 128,
                    child: CircularProgressIndicator(
                      value: _avatarUploadProgress,
                      strokeWidth: 3,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (_avatarPath.isNotEmpty && !_isUploadingAvatar)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).colorScheme.surface,
                            width: 2),
                      ),
                      child: const Icon(Icons.check,
                          color: Colors.white, size: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (_isUploadingAvatar)
            Text(
              'Uploading... ${((_avatarUploadProgress ?? 0) * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600),
            )
          else
            Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _pickAndUploadAvatar,
                  icon: const Icon(Icons.photo_camera_rounded, size: 18),
                  label: Text(
                      _avatarPath.isEmpty ? 'Upload Photo' : 'Change Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _avatarPath.isEmpty
                      ? 'Optional — you can add this later'
                      : '✓ Photo uploaded successfully',
                  style: TextStyle(
                    color: _avatarPath.isEmpty
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.4)
                        : Colors.green,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // --- Step 6: Department ---
  Widget _buildDepartmentSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedRole == 'Staff') ...[
          Text('Select your primary department:', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
          const SizedBox(height: 16),
          _buildDropdown(_selectedDepartment ?? _departments[0], _departments, (val) => setState(() => _selectedDepartment = val)),
        ] else ...[
          Text('Which area of production interests you most?', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 14)),
          const SizedBox(height: 16),
          _buildDropdown(_selectedDepartment ?? 'Video Production', ['Video Production', 'Audio Production', 'Both'], (val) => setState(() => _selectedDepartment = val)),
        ],
      ],
    );
  }

  // --- Step 7: Social ---
  Widget _buildSocialFields() {
    return Column(
      children: [
        _buildSocialTextField('Instagram Handle / Link (Optional)', _igController, icon: Icons.camera_alt_outlined, prefixUrl: 'https://instagram.com/'),
        const SizedBox(height: 16),
        _buildSocialTextField('YouTube Channel URL (Optional)', _ytController, icon: Icons.play_arrow_outlined, prefixUrl: 'https://youtube.com/'),
        const SizedBox(height: 16),
        Text('Paste your profile links above to generate a preview card.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12)),
      ],
    );
  }

  Widget _buildSocialTextField(String label, TextEditingController controller, {required IconData icon, required String prefixUrl}) {
    String currentText = controller.text.trim();
    bool hasValue = currentText.isNotEmpty;
    // Format full URL to pass to preview card
    String fullUrl = '';
    if (hasValue) {
      if (currentText.startsWith('http')) {
        fullUrl = currentText;
      } else {
        fullUrl = prefixUrl + currentText;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
            prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
            suffixIcon: hasValue ? IconButton(
              icon: Icon(Icons.open_in_new, color: Theme.of(context).colorScheme.primary),
              tooltip: 'Verify Link',
              onPressed: () => _verifySocialLink(currentText, prefixUrl),
            ) : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
            ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
          ),
        ),
        if (hasValue) ...[
          const SizedBox(height: 12),
          SocialPreviewCard(url: fullUrl),
        ],
      ],
    );
  }

  Future<void> _verifySocialLink(String input, String prefixUrl) async {
    final String urlString;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      urlString = input;
    } else {
      urlString = '$prefixUrl${input.replaceAll('@', '')}';
    }
    final uri = Uri.parse(urlString);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open link')),
        );
      }
    }
  }

  // --- Step 8: Preferences ---
  Widget _buildPreferences() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Preferred Language', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _preferredLanguage,
                dropdownColor: Theme.of(context).colorScheme.surface,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'en', child: Text('English')),
                  DropdownMenuItem(value: 'es', child: Text('Spanish (Español)')),
                  DropdownMenuItem(value: 'fr', child: Text('French (Français)')),
                ],
                onChanged: (val) => setState(() => _preferredLanguage = val ?? 'en'),
              ),
              const SizedBox(height: 24),
              Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _themeMode,
                dropdownColor: Theme.of(context).colorScheme.surface,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('System Default')),
                  DropdownMenuItem(value: 'light', child: Text('Light Mode')),
                  DropdownMenuItem(value: 'dark', child: Text('Dark Mode')),
                ],
                onChanged: (val) => setState(() => _themeMode = val ?? 'system'),
              ),
              const SizedBox(height: 24),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Email Notifications'),
                subtitle: const Text('Receive updates on sessions and productions.'),
                value: _optInEmails,
                activeThumbColor: Theme.of(context).colorScheme.primary,
                onChanged: (val) => setState(() => _optInEmails = val),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --- Step 9: Agreements ---
  Widget _buildAgreements() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Row(
        children: [
          Checkbox(
            value: _agreedToTerms,
            activeColor: Theme.of(context).colorScheme.primary,
            onChanged: (val) => setState(() => _agreedToTerms = val ?? false),
          ),
          Expanded(
            child: Text(
              'I agree to the MPEPE Studio Terms of Service and Privacy Policy.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // --- Step 10: Final ---
  Widget _buildFinalStep() {
    return Stack(
      children: [
        if (_isSaving) _buildAnimatedBackground(),
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IDBadgeCard(
                name: _nameController.text,
                role: _selectedRole,
                department: _selectedDepartment,
                isLoading: _isSaving,
              ).animate().fadeIn().scale(delay: 100.ms, duration: 400.ms, curve: Curves.easeOutBack),
              const SizedBox(height: 48),
              if (!_isSaving)
                SizedBox(
                  width: double.infinity,
                  child: MpepeButton(text: 'Complete & Enter', onPressed: _completeSignup),
                ).animate().slideY(begin: 1, delay: 300.ms).fadeIn(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnimatedBackground() {
    return Positioned.fill(
      child: Stack(
        children: [
          // Gentle pulsing background tint
          Container(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
          ).animate(onPlay: (controller) => controller.repeat(reverse: true)).fade(duration: 1.5.seconds, begin: 0.5, end: 1.0),
          
          // Floating Production Icons
          Positioned(
            top: 50, left: 30,
            child: Icon(Icons.videocam_rounded, size: 120, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08))
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .moveY(begin: 0, end: -30, duration: 3.seconds, curve: Curves.easeInOutSine)
              .rotate(begin: -0.05, end: 0.05, duration: 4.seconds),
          ),
          Positioned(
            bottom: 80, right: 20,
            child: Icon(Icons.mic_external_on_rounded, size: 140, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.06))
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .moveY(begin: 0, end: 40, duration: 3.5.seconds, curve: Curves.easeInOutSine)
              .rotate(begin: 0.05, end: -0.05, duration: 5.seconds),
          ),
          Positioned(
            top: 150, right: -20,
            child: Icon(Icons.movie_creation_rounded, size: 90, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.07))
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .moveX(begin: 0, end: -25, duration: 4.seconds, curve: Curves.easeInOutSine)
              .scale(begin: const Offset(0.9, 0.9), end: const Offset(1.1, 1.1), duration: 3.seconds),
          ),
          Positioned(
            bottom: 200, left: -10,
            child: Icon(Icons.graphic_eq_rounded, size: 100, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05))
              .animate(onPlay: (controller) => controller.repeat(reverse: true))
              .moveX(begin: 0, end: 20, duration: 3.2.seconds, curve: Curves.easeInOutSine),
          ),
        ],
      ),
    );
  }

  // --- Helpers ---
  Widget _buildTextField(String label, TextEditingController controller, {required IconData icon, bool isPassword = false, void Function(String)? onChanged}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      onChanged: onChanged,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
        prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildDropdown(String value, List<String> items, ValueChanged<String?> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surface,
          items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: TextStyle(color: Theme.of(context).colorScheme.onSurface)))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}


class IDBadgeCard extends StatefulWidget {
  final String name;
  final String role;
  final String? department;
  final bool isLoading;

  const IDBadgeCard({
    super.key,
    required this.name,
    required this.role,
    this.department,
    this.isLoading = false,
  });

  @override
  State<IDBadgeCard> createState() => _IDBadgeCardState();
}

class _IDBadgeCardState extends State<IDBadgeCard> {
  double _x = 0;
  double _y = 0;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final size = box.size;
        final position = box.globalToLocal(event.position);
        setState(() {
          _x = (position.dy - size.height / 2) / (size.height / 2);
          _y = (position.dx - size.width / 2) / (size.width / 2);
        });
      },
      onExit: (_) => setState(() {
        _x = 0;
        _y = 0;
      }),
      child: GestureDetector(
        onPanUpdate: (details) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final size = box.size;
          setState(() {
            _x += details.delta.dy / size.height;
            _y -= details.delta.dx / size.width;
            _x = _x.clamp(-1.0, 1.0);
            _y = _y.clamp(-1.0, 1.0);
          });
        },
        onPanEnd: (_) => setState(() {
          _x = 0;
          _y = 0;
        }),
        child: TweenAnimationBuilder(
          tween: Tween<Offset>(begin: Offset.zero, end: Offset(_x, _y)),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          builder: (context, Offset offset, child) {
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(-offset.dx * 0.5)
                ..rotateY(offset.dy * 0.5),
              alignment: Alignment.center,
              child: child,
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                  blurRadius: 30,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: widget.isLoading
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 32),
                    Icon(Icons.sync_rounded, size: 60, color: Theme.of(context).colorScheme.primary)
                      .animate(onPlay: (controller) => controller.repeat())
                      .rotate(duration: 2.seconds, curve: Curves.linear),
                    const SizedBox(height: 24),
                    Text('Provisioning Studio Access...', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16))
                      .animate(onPlay: (controller) => controller.repeat(reverse: true))
                      .fade(begin: 0.5, end: 1.0, duration: 1.seconds),
                    const SizedBox(height: 12),
                    Text('Setting up your specialized workspace', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                    const SizedBox(height: 32),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      ),
                      child: Icon(Icons.workspace_premium, size: 60, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 24),
                    Text('MPEPE STUDIO ACCESS', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      widget.name.isEmpty ? 'New User' : widget.name,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text('${widget.role}${widget.department != null ? ' • ${widget.department}' : ''}', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                  ],
                ),
          ),
        ),
      ),
    );
  }
}
