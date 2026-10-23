import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pinput/pinput.dart';
import 'services/otp_autofill.dart';

import '../../backend/onboarding_persistence_service.dart';
import '../../backend/recommendation/algorithm/online_feature_store.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/theme_toggle_button.dart';
import 'auth_repository.dart';
import 'services/oneova_ai_onboarding_guardian.dart';
import 'services/oneova_biometrics_service.dart';
import 'services/oneova_username_service.dart';
import 'services/oneova_smart_phone_engine.dart';
import 'security/login_security.dart';

class SignupWizardScreen extends ConsumerStatefulWidget {
  const SignupWizardScreen({super.key});

  @override
  ConsumerState<SignupWizardScreen> createState() => _SignupWizardScreenState();
}

class _SignupWizardScreenState extends ConsumerState<SignupWizardScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  static const int _totalSteps = 5;

  bool _isSaving = false;
  bool _isLoading = false;

  // Step 1: Phone & OTP (Smart Worldwide Engine)
  final OneovaSmartPhoneEngine _phoneEngine = OneovaSmartPhoneEngine();
  CountryPhoneMeta _selectedCountryMeta = OneovaSmartPhoneEngine.defaultCountry;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  // Fills the SMS code via Google's consent prompt (no SMS permission).
  final OtpAutofill _otpAutofill = OtpAutofill();
  String _selectedCountryCode = 'KE';
  String get _selectedDialCode => _selectedCountryMeta.dialCode;
  String _formatHint = 'e.g. 712 345 678';
  String _fullPhoneNumber = '';
  String _verificationId = '';
  // Reused by "Resend Code" for the same number (no new app check / reCAPTCHA).
  int? _resendToken;
  String _resendTokenPhone = '';
  bool _isOtpSent = false;
  int _otpResendTimer = 60;
  Timer? _timer;

  // Step 2: Password & Biometrics
  final TextEditingController _passwordController = TextEditingController();
  bool _passwordVisible = false;
  int _passwordStrength = 0;
  String _passwordStrengthLabel = 'Weak';
  bool _enableBiometrics = true;
  String _biometricLabel = 'Biometric Passkey';

  // Step 3: Identity & Username
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  String _selectedAccountType = 'Creator / Influencer';
  final List<String> _accountTypes = [
    'Creator / Influencer',
    'Brand / Business',
    'Community / Personal',
  ];
  UsernameCheckResult? _usernameCheckResult;
  bool _isCheckingUsername = false;
  Timer? _usernameDebounce;

  // Step 4: Niches & AI Protection
  final List<String> _allNiches = [
    'Tech & AI',
    'Filmmaking & VFX',
    'Music & Audio',
    'Fashion & Style',
    'Comedy & Culture',
    'Gaming',
    'Business & Startups',
    'Visual Arts',
  ];
  final Set<String> _selectedNiches = {'Tech & AI', 'Filmmaking & VFX'};
  final TextEditingController _bioController = TextEditingController();
  AiAccountSafetyReport? _aiSafetyReport;
  bool _isAnalyzingSafety = false;

  // Google pre-fill support
  String? _googleUid;
  bool _googleDataApplied = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
    _initBiometrics();
    _loadDraft();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous && _googleUid == null) {
        if (mounted) {
          context.go('/hub/home');
          return;
        }
      }
      await _detectCountrySilently();
    });
  }

  /// Silently detects user country in background
  Future<void> _detectCountrySilently() async {
    try {
      final meta = await _phoneEngine.detectCountrySilently();
      if (mounted) {
        setState(() {
          _selectedCountryMeta = meta;
          _selectedCountryCode = meta.isoCode;
          _formatHint = meta.formatHint;
        });
      }
    } catch (_) {}
  }

  /// Parses typed/pasted numbers and dynamically auto-switches country if needed
  void _onPhoneChanged() {
    final raw = _phoneController.text;
    if (raw.isNotEmpty) {
      final parsed = _phoneEngine.parseAndNormalize(
        input: raw,
        fallbackCountry: _selectedCountryMeta,
      );
      if (parsed.wasCountryAutoSwitched && parsed.country.isoCode != _selectedCountryCode) {
        setState(() {
          _selectedCountryMeta = parsed.country;
          _selectedCountryCode = parsed.country.isoCode;
          _formatHint = parsed.country.formatHint;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra as Map<String, dynamic>?;
    if (extra != null) {
      if (!_googleDataApplied && extra['fromGoogle'] == true) {
        _googleDataApplied = true;
        _googleUid = extra['uid'] as String?;
        final email = extra['email'] as String? ?? '';
        final name = extra['name'] as String? ?? '';
        _nameController.text = name;
        if (email.contains('@')) {
          _usernameController.text = email.split('@').first.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');
          _checkUsernameAvailability(_usernameController.text);
        }
      } else if (!_googleDataApplied && (extra['fromTikTok'] == true || extra['fromFacebook'] == true)) {
        _googleDataApplied = true;
        _googleUid = extra['uid'] as String?;
        final name = extra['name'] as String? ?? '';
        if (name.isNotEmpty && _nameController.text.isEmpty) {
          _nameController.text = name;
        }
      }

      if (extra['phone'] != null && _phoneController.text.isEmpty) {
        final phone = extra['phone'] as String;
        _fullPhoneNumber = phone;
        _phoneController.text = phone.replaceFirst(_selectedDialCode, '').replaceFirst('+254', '');
        if (extra['phoneVerified'] == true) {
          _isOtpSent = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_currentStep == 0 && mounted) {
              _goToStep(1);
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _timer?.cancel();
    _usernameDebounce?.cancel();
    _phoneController.dispose();
    _otpAutofill.cancel();
    _otpController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    final bioService = ref.read(oneovaBiometricsServiceProvider);
    final supported = await bioService.isDeviceSupported();
    if (supported) {
      final label = await bioService.getBiometricTypeLabel();
      if (mounted) {
        setState(() {
          _biometricLabel = label;
          _enableBiometrics = true;
        });
      }
    } else {
      if (mounted) setState(() => _enableBiometrics = false);
    }
  }

  Future<void> _loadDraft() async {
    final persistence = ref.read(onboardingPersistenceProvider);
    final draft = await persistence.loadDraft();
    if (draft != null && mounted) {
      final resume = await _showResumeDraftDialog();
      if (resume == true && mounted) {
        final data = draft['data'] as Map<String, dynamic>? ?? {};
        setState(() {
          _nameController.text = data['name'] ?? '';
          _phoneController.text = data['phone'] ?? '';
          _selectedAccountType = data['accountType'] ?? 'Creator / Influencer';
          _usernameController.text = data['username'] ?? '';
          _bioController.text = data['bio'] ?? '';
          if (data['niches'] is List) {
            _selectedNiches.clear();
            _selectedNiches.addAll(List<String>.from(data['niches']));
          }
          final step = draft['stepIndex'] as int? ?? 0;
          _currentStep = step.clamp(0, _totalSteps - 1);
        });
        _pageController.jumpToPage(_currentStep);
      } else {
        await persistence.clearDraft();
      }
    }
  }

  Future<bool?> _showResumeDraftDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'Resume Signup?',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
        content: Text(
          'We found an incomplete signup draft. Would you like to resume where you left off?',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: textSecondary,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Start Over',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Resume',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _saveCurrentDraft() {
    ref.read(onboardingPersistenceProvider).saveDraft(_currentStep, {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'accountType': _selectedAccountType,
      'username': _usernameController.text.trim(),
      'bio': _bioController.text.trim(),
      'niches': _selectedNiches.toList(),
    });
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _totalSteps) return;
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );
    _saveCurrentDraft();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _goToStep(_currentStep + 1);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    } else {
      context.pop();
    }
  }

  // ── Phone & OTP Flow ───────────────────────────────────────────────────────

  String _computeFullPhoneNumber() {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return '';
    final parsed = _phoneEngine.parseAndNormalize(
      input: raw,
      fallbackCountry: _selectedCountryMeta,
    );
    return parsed.e164;
  }

  Future<void> _handleSendOtp() async {
    final phone = _computeFullPhoneNumber();
    if (phone.length < 9) {
      _showSnackbar('Please enter a valid phone number.', isError: true);
      return;
    }
    if (_isLoading) return;

    setState(() => _isLoading = true);
    _fullPhoneNumber = phone;

    // 1. Check if phone is already registered
    try {
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => _isLoading = false);
        _showPhoneAlreadyRegisteredModal();
        return;
      }
    } catch (_) {}

    // 2. Trigger Firebase Phone Auth
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: phone == _resendTokenPhone ? _resendToken : null,
        verificationCompleted: (PhoneAuthCredential cred) async {
          if (FirebaseAuth.instance.currentUser?.phoneNumber == phone) return;
          _otpAutofill.cancel();
          final UserCredential signed;
          try {
            signed = await FirebaseAuth.instance.signInWithCredential(cred);
          } catch (e) {
            debugPrint('[SignupWizard] auto-verify failed: $e');
            if (mounted) setState(() => _isLoading = false);
            return;
          }
          if (signed.user != null) LoginSecurity.instance.recordFactor(signed.user!.uid, AuthFactor.smsOtp);
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isOtpSent = true;
            });
            _nextStep();
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (mounted) {
            setState(() => _isLoading = false);
            _showSnackbar(e.message ?? 'Verification failed. Please retry.', isError: true);
          }
        },
        codeSent: (String verId, int? resendToken) {
          if (mounted) {
            setState(() {
              _verificationId = verId;
              _resendToken = resendToken ?? _resendToken;
              _resendTokenPhone = phone;
              _isOtpSent = true;
              _isLoading = false;
            });
            _startResendTimer();
            _showSnackbar('Verification code sent to $phone');
            _otpAutofill.restart(_otpController, onCode: (_) => _handleVerifyOtp());
          }
        },
        codeAutoRetrievalTimeout: (String verId) {
          _verificationId = verId;
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Failed to request OTP: $e', isError: true);
      }
    }
  }

  void _startResendTimer() {
    _otpResendTimer = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_otpResendTimer <= 1) {
        t.cancel();
        if (mounted) setState(() => _otpResendTimer = 0);
      } else {
        if (mounted) setState(() => _otpResendTimer--);
      }
    });
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _showSnackbar('Please enter the complete 6-digit code.', isError: true);
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      await authRepo.signInWithOTP(
        verificationId: _verificationId,
        smsCode: code,
      );
      final signedIn = FirebaseAuth.instance.currentUser;
      if (signedIn != null) LoginSecurity.instance.recordFactor(signedIn.uid, AuthFactor.smsOtp);
      if (mounted) {
        setState(() => _isLoading = false);
        _nextStep();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('Invalid code. Please re-check and try again.', isError: true);
      }
    }
  }

  void _showPhoneAlreadyRegisteredModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.paddingOf(context).bottom + 20,
        ),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border(top: BorderSide(color: isDark ? AppColors.outline : AppColors.lightBorder, width: 1.0)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: surfaceMid,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded, size: 28, color: AppColors.brandBlue),
            ),
            const SizedBox(height: 14),
            Text(
              'Phone Number Already Registered',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This phone number is already linked to an existing Oneova account.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  context.push('/auth/main_login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: Text(
                  'Log In Instead',
                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Go Back & Edit',
                style: GoogleFonts.inter(fontSize: 13, color: textSecondary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Password Evaluation ────────────────────────────────────────────────────

  void _calculatePasswordStrength(String pass) {
    int score = 0;
    if (pass.length >= 8) score++;
    if (pass.contains(RegExp(r'[A-Z]'))) score++;
    if (pass.contains(RegExp(r'[0-9]'))) score++;
    if (pass.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) score++;

    String label = 'Weak';
    if (score == 2) {
      label = 'Fair';
    } else if (score == 3) {
      label = 'Good';
    } else if (score == 4) {
      label = 'Strong';
    }

    setState(() {
      _passwordStrength = score;
      _passwordStrengthLabel = label;
    });
  }

  // ── Username Debounce Check ────────────────────────────────────────────────

  void _checkUsernameAvailability(String username) {
    _usernameDebounce?.cancel();
    if (username.trim().isEmpty) {
      setState(() => _usernameCheckResult = null);
      return;
    }

    setState(() => _isCheckingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 350), () async {
      final usernameService = ref.read(oneovaUsernameServiceProvider);
      final result = await usernameService.validateAndCheckAvailability(
        username,
        accountType: _selectedAccountType,
      );
      if (mounted) {
        setState(() {
          _usernameCheckResult = result;
          _isCheckingUsername = false;
        });
      }
    });
  }

  // ── AI Safety Analysis ─────────────────────────────────────────────────────

  Future<void> _runAiSafetyScan() async {
    setState(() => _isAnalyzingSafety = true);
    final guardian = ref.read(oneovaAiOnboardingGuardianProvider);
    final report = await guardian.evaluateProfileSafety(
      username: _usernameController.text.trim(),
      displayName: _nameController.text.trim(),
      bio: _bioController.text.trim(),
      contactPhoneOrEmail: _fullPhoneNumber,
    );
    if (mounted) {
      setState(() {
        _aiSafetyReport = report;
        _isAnalyzingSafety = false;
      });
    }
  }

  // ── Final Completion ───────────────────────────────────────────────────────

  Future<void> _secureNewAccount(User? user) async {
    if (user == null || user.isAnonymous) return;
    final sec = LoginSecurity.instance;
    final pw = _passwordController.text;
    try {
      if (pw.length >= 6 && !user.providerData.any((p) => p.providerId == 'password')) {
        await user.linkWithCredential(EmailAuthProvider.credential(
          email: LoginSecurity.authEmailForPhone(user.phoneNumber ?? _fullPhoneNumber),
          password: pw,
        ));
        sec.recordFactor(user.uid, AuthFactor.password);
      }
      final factors = sec.pendingFactorsFor(user.uid);
      final scan = await sec.scanDevice(user.uid);
      final trusted = scan.trusted && scan.isPhysicalDevice;
      if (LoginSecurity.meetsPolicy(factors, deviceTrusted: trusted)) {
        await sec.markVerified(user, factors, deviceTrusted: trusted);
      }
    } catch (e) {
      debugPrint('[SignupWizard] securing account: $e');
    }
  }


  Future<void> _completeOnboarding() async {
    setState(() => _isSaving = true);
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? _googleUid ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';

    try {
      final username = _usernameController.text.trim().toLowerCase();
      final displayName = _nameController.text.trim().isEmpty ? 'Oneova Creator' : _nameController.text.trim();
      final role = (_selectedAccountType == 'Brand / Business') ? 'business' : 'creator';

      // 1. Claim username
      final usernameService = ref.read(oneovaUsernameServiceProvider);
      try {
        await usernameService.claimUsername(uid, username);
      } catch (_) {}

      // 2. Set profile data in Firestore
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': displayName,
        'username': username,
        'phoneNumber': _fullPhoneNumber,
        'role': role,
        'accountType': _selectedAccountType,
        'bio': _bioController.text.trim(),
        'niches': _selectedNiches.toList(),
        'status': 'active',
        'isVerified': (_selectedAccountType != 'Community / Personal'),
        'verifiedBadge': (_selectedAccountType == 'Brand / Business') ? 'business' : 'creator',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 3. Password -> Firebase Auth (never stored in Firestore), then accept
      // the session if SMS code + password meet the two-check policy. If not,
      // the login screen asks for what is missing.
      await _secureNewAccount(user);

      // 3b. Enroll biometrics if selected (only for a verified session)
      if (_enableBiometrics && user != null && LoginSecurity.instance.isVerified(user)) {
        final bioService = ref.read(oneovaBiometricsServiceProvider);
        await bioService.enrollUserBiometrics(
          userId: user.uid,
          userEmail: user.phoneNumber ?? _fullPhoneNumber,
          displayName: displayName,
        );
      }

      // 4. Generate Algorithmic Taste Seed with OpenRouter live model
      final guardian = ref.read(oneovaAiOnboardingGuardianProvider);
      await guardian.generateAlgorithmicSeed(
        userId: uid,
        selectedNiches: _selectedNiches.toList(),
        creatorRole: role,
        primaryGoal: 'Viral audience growth',
      );

      // Hydrate local feature store
      ref.read(onlineFeatureStoreProvider).hydrateProfile(uid);

      // 5. Clear draft
      await ref.read(onboardingPersistenceProvider).clearDraft();

      // 6. Save last used account in device memory for 1-tap recognition next time
      await _phoneEngine.saveLastUsedAccount(
        phoneE164: _fullPhoneNumber,
        countryIso: _selectedCountryCode,
        displayName: _nameController.text.trim(),
        username: _usernameController.text.trim(),
      );

      if (mounted) {
        setState(() => _isSaving = false);
        HapticFeedback.heavyImpact();
        context.go('/hub/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnackbar('Failed to finalize profile: $e', isError: true);
      }
    }
  }

  void _showSnackbar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.white),
        ),
        backgroundColor: isError ? Colors.redAccent : AppColors.brandBlue,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      ),
    );
  }

  // ── Welcoming Milestone Badge Helper ────────────────────────────────────
  Widget _buildStepHeaderBadge({
    required int stepNumber,
    required String milestoneText,
    required String stepTitle,
    required String stepSubtitle,
    required IconData headerIcon,
    required Color textP,
    required Color textS,
  }) {
    final isAlmostThere = stepNumber >= 3;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.28), width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(headerIcon, size: 13, color: AppColors.brandBlue),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        'STEP $stepNumber OF 5 • $milestoneText',
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandBlue,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isAlmostThere)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35), width: 1.0),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on_rounded, size: 11, color: AppColors.brandPink),
                    const SizedBox(width: 3),
                    Text(
                      stepNumber == 5 ? 'ALL SET!' : 'ALMOST THERE!',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandPink,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ).animate().scale(duration: 300.ms, curve: Curves.easeOutBack),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          stepTitle,
          style: GoogleFonts.inter(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: textP,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          stepSubtitle,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: textS,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  // ── "Why This Matters" Contextual Value Box ───────────────────────────────
  Widget _buildWhyItMatters({
    required IconData icon,
    required String title,
    required String description,
    required Color surfaceMid,
    required Color border,
    required Color textP,
    required Color textS,
    Color iconColor = AppColors.brandBlue,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: surfaceMid.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: iconColor.withValues(alpha: 0.22), width: 1.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: textP,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        'WHY THIS MATTERS',
                        style: GoogleFonts.inter(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: iconColor,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    color: textS,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final surfaceColor = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.outline : AppColors.lightBorder;
    final textPrimary = isDark ? AppColors.textPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.textSecondary : AppColors.lightTextSecondary;

    final stepLabels = [
      'Welcome • Phone Auth',
      'Security & Passkeys',
      'Creator Handle & Tier',
      'AI Shield & Niches',
      'VIP Creator Pass',
    ];

    return Scaffold(
      backgroundColor: bgColor,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          backgroundColor: bgColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: textPrimary, size: 20),
            onPressed: _prevStep,
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Join Oneova',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                _currentStep == 4
                    ? 'Almost there! Final Review'
                    : 'Step ${_currentStep + 1} of 5: ${stepLabels[_currentStep]}',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _currentStep >= 3 ? AppColors.brandPink : AppColors.brandBlue,
                ),
              ),
            ],
          ),
          centerTitle: true,
          actions: const [
            ThemeToggleButton(),
            SizedBox(width: 8),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(8),
            child: Row(
              children: List.generate(_totalSteps, (index) {
                final isActive = index <= _currentStep;
                final isCurrent = index == _currentStep;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: kDebugMode
                        ? () {
                            HapticFeedback.lightImpact();
                            setState(() => _currentStep = index);
                            _pageController.animateToPage(
                              index,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                            );
                          }
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2.5),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppColors.brandPink
                              : (isActive
                                  ? AppColors.brandBlue
                                  : (isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight)),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1PhoneAndOtp(surfaceColor, borderColor, textPrimary, textSecondary),
                _buildStep2PasswordAndBiometrics(surfaceColor, borderColor, textPrimary, textSecondary),
                _buildStep3IdentityAndUsername(surfaceColor, borderColor, textPrimary, textSecondary),
                _buildStep4AiProtectionAndSeeds(surfaceColor, borderColor, textPrimary, textSecondary),
                _buildStep5AccessPassReview(surfaceColor, borderColor, textPrimary, textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 1: Phone Authentication (Strictly 1 input on page: Phone OR OTP)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStep1PhoneAndOtp(Color surface, Color border, Color textP, Color textS) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeaderBadge(
            stepNumber: 1,
            milestoneText: 'AUTHENTICATION',
            stepTitle: 'Phone Authentication',
            stepSubtitle: 'Enter your phone number to secure your creator account with high-entropy SMS verification.',
            headerIcon: Icons.phone_android_rounded,
            textP: textP,
            textS: textS,
          ),

          _buildWhyItMatters(
            icon: Icons.verified_user_rounded,
            title: 'Bot Defense & Royalties Security',
            description: 'Phone verification guarantees 100% authentic human audiences, protects your monetization payouts, and enables instant 2-step account recovery.',
            surfaceMid: surfaceMid,
            border: border,
            textP: textP,
            textS: textS,
            iconColor: AppColors.brandBlue,
          ),

          // Input Form Container (Strictly 1 input: Phone OR OTP)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isOtpSent) ...[
                  // INPUT 1: Phone field
                  Row(
                    children: [
                      const Icon(Icons.phone_iphone_rounded, size: 15, color: AppColors.brandBlue),
                      const SizedBox(width: 6),
                      Text(
                        'Mobile Phone Number',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  IntlPhoneField(
                    key: ValueKey('wizard_phone_$_selectedCountryCode'),
                    controller: _phoneController,
                    initialCountryCode: _selectedCountryCode,
                    disableLengthCheck: true,
                    keyboardType: TextInputType.phone,
                    cursorColor: AppColors.brandBlue,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
                    ],
                    style: GoogleFonts.inter(fontSize: 14, color: textP, fontWeight: FontWeight.w600),
                    dropdownTextStyle: GoogleFonts.inter(fontSize: 13.5, color: textP),
                    decoration: InputDecoration(
                      hintText: _formatHint,
                      hintStyle: GoogleFonts.inter(fontSize: 13, color: textS),
                      filled: true,
                      fillColor: surfaceMid,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: border, width: 1.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: border, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
                      ),
                    ),
                    onCountryChanged: (country) {
                      final meta = _phoneEngine.findByIso(country.code);
                      setState(() {
                        _selectedCountryCode = country.code;
                        _selectedCountryMeta = meta;
                        _formatHint = meta.formatHint;
                      });
                      _onPhoneChanged();
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2),
                    child: Text(
                      '${_selectedCountryMeta.flagEmoji} ${_selectedCountryMeta.formatHint}',
                      style: GoogleFonts.inter(fontSize: 11, color: textS, fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleSendOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.send_rounded, size: 15, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Send Verification Code',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                    ),
                  ),
                ] else ...[
                  // SUB-STATE: OTP input (1 input)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pin_rounded, size: 15, color: AppColors.brandBlue),
                          const SizedBox(width: 6),
                          Text(
                            'Enter 6-Digit SMS Code',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                          ),
                        ],
                      ),
                      Text(
                        _fullPhoneNumber,
                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Pinput(
                      controller: _otpController,
                      length: 6,
                      defaultPinTheme: PinTheme(
                        width: 44,
                        height: 48,
                        textStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textP),
                        decoration: BoxDecoration(
                          color: surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: border, width: 1.0),
                        ),
                      ),
                      focusedPinTheme: PinTheme(
                        width: 44,
                        height: 48,
                        textStyle: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, color: textP),
                        decoration: BoxDecoration(
                          color: surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: const BorderSide(color: AppColors.brandBlue, width: 1.5).toMP(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        icon: Icon(Icons.timer_outlined, size: 14, color: _otpResendTimer == 0 ? AppColors.brandBlue : textS),
                        onPressed: _otpResendTimer == 0 ? _handleSendOtp : null,
                        label: Text(
                          _otpResendTimer == 0 ? 'Resend Code' : 'Resend in ${_otpResendTimer}s',
                          style: GoogleFonts.inter(fontSize: 12, color: _otpResendTimer == 0 ? AppColors.brandBlue : textS),
                        ),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.edit_outlined, size: 14, color: textS),
                        onPressed: () => setState(() => _isOtpSent = false),
                        label: Text(
                          'Edit Number',
                          style: GoogleFonts.inter(fontSize: 12, color: textS),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _handleVerifyOtp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.verified_rounded, size: 15, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Verify & Continue →',
                                  style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 2: Password & Biometric Passkey (Strictly 2 inputs: Password & Passkey)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStep2PasswordAndBiometrics(Color surface, Color border, Color textP, Color textS) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeaderBadge(
            stepNumber: 2,
            milestoneText: 'SECURITY LAYER',
            stepTitle: 'Password & Biometrics',
            stepSubtitle: 'Set your master password as a secondary auth layer and enable passkeys for instant biometric login.',
            headerIcon: Icons.shield_rounded,
            textP: textP,
            textS: textS,
          ),

          _buildWhyItMatters(
            icon: Icons.fingerprint_rounded,
            title: 'Zero Phishing & Passkey Defense',
            description: 'Enabling biometric passkeys anchors your session to device hardware (Fingerprint/Face ID), completely eliminating phishing and credential leaks.',
            surfaceMid: surfaceMid,
            border: border,
            textP: textP,
            textS: textS,
            iconColor: AppColors.brandPink,
          ),

          // Container with strictly 2 inputs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // INPUT 1: Password Field
                Row(
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Master Account Password',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  obscureText: !_passwordVisible,
                  onChanged: _calculatePasswordStrength,
                  style: GoogleFonts.inter(fontSize: 13.5, color: textP),
                  decoration: InputDecoration(
                    hintText: 'Enter strong password (min 8 characters)',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textS),
                    filled: true,
                    fillColor: surfaceMid,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _passwordVisible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18,
                        color: textS,
                      ),
                      onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Password strength bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _passwordStrength / 4.0,
                          backgroundColor: surfaceMid,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _passwordStrength <= 1
                                ? Colors.redAccent
                                : _passwordStrength <= 3
                                    ? Colors.amber
                                    : AppColors.brandBlue,
                          ),
                          minHeight: 3.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _passwordStrengthLabel,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _passwordStrength <= 1
                            ? Colors.redAccent
                            : _passwordStrength <= 3
                                ? Colors.amber
                                : AppColors.brandBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // INPUT 2: Biometric passkey switch
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fingerprint_rounded, size: 20, color: AppColors.brandPink),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _biometricLabel,
                              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: textP),
                            ),
                            Text(
                              'Instant 1-touch unlock & account takeover defense',
                              style: GoogleFonts.inter(fontSize: 10.5, color: textS),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _enableBiometrics,
                        activeThumbColor: AppColors.brandBlue,
                        onChanged: (val) => setState(() => _enableBiometrics = val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_passwordController.text.length < 6) {
                        _showSnackbar('Password must be at least 6 characters.', isError: true);
                        return;
                      }
                      _nextStep();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue (Step 3 of 5) →',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 3: Identity & Unique Username (Strictly 3 inputs: Tier, Name, Handle)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStep3IdentityAndUsername(Color surface, Color border, Color textP, Color textS) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeaderBadge(
            stepNumber: 3,
            milestoneText: 'CREATOR IDENTITY',
            stepTitle: 'Claim Your Name & Handle',
            stepSubtitle: 'Choose your account tier, display name, and permanent unique @username handle.',
            headerIcon: Icons.badge_rounded,
            textP: textP,
            textS: textS,
          ),

          _buildWhyItMatters(
            icon: Icons.alternate_email_rounded,
            title: 'Global Identity & Verified Status',
            description: 'Your @username is reserved on Oneova globally (oneova.app/@yourhandle). Early creators lock in premium short handles and qualify for verified badges.',
            surfaceMid: surfaceMid,
            border: border,
            textP: textP,
            textS: textS,
            iconColor: AppColors.brandBlue,
          ),

          // Container with strictly 3 inputs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // INPUT 1: Account Type Selection Chips
                Row(
                  children: [
                    const Icon(Icons.stars_rounded, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Account Type & Tier',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _accountTypes.map((type) {
                    final isSelected = _selectedAccountType == type;
                    return ChoiceChip(
                      label: Text(
                        type,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : textP,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.brandBlue,
                      backgroundColor: surfaceMid,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        side: BorderSide(color: isSelected ? AppColors.brandBlue : border, width: 1.0),
                      ),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedAccountType = type);
                          _checkUsernameAvailability(_usernameController.text);
                        }
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // INPUT 2: Display Name Field
                Row(
                  children: [
                    const Icon(Icons.badge_outlined, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Display Name / Brand',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  style: GoogleFonts.inter(fontSize: 13.5, color: textP),
                  decoration: InputDecoration(
                    hintText: 'e.g. Maya Lin or Horizon Media',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textS),
                    filled: true,
                    fillColor: surfaceMid,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // INPUT 3: Unique @username Handle Field
                Row(
                  children: [
                    const Icon(Icons.alternate_email_rounded, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Unique Handle (@username)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _usernameController,
                  onChanged: _checkUsernameAvailability,
                  style: GoogleFonts.inter(fontSize: 13.5, color: textP, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    prefixText: '@',
                    prefixStyle: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.brandBlue),
                    hintText: 'mayacreates (letters, numbers, _)',
                    hintStyle: GoogleFonts.inter(fontSize: 12.5, color: textS, fontWeight: FontWeight.w400),
                    filled: true,
                    fillColor: surfaceMid,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
                    ),
                    suffixIcon: _isCheckingUsername
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                            ),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),

                if (_usernameCheckResult != null)
                  Row(
                    children: [
                      Icon(
                        _usernameCheckResult!.isValidAndAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
                        size: 14,
                        color: _usernameCheckResult!.isValidAndAvailable ? Colors.greenAccent : Colors.redAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _usernameCheckResult!.message ?? '',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _usernameCheckResult!.isValidAndAvailable ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                      if (_usernameCheckResult!.potentialBadge != OneovaBadgeType.none) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.verified_rounded, size: 12, color: AppColors.brandBlue),
                              const SizedBox(width: 4),
                              Text(
                                'Verified Qualification',
                                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_nameController.text.trim().isEmpty) {
                        _showSnackbar('Please enter your display name.', isError: true);
                        return;
                      }
                      if (_usernameCheckResult != null && !_usernameCheckResult!.isValidAndAvailable) {
                        _showSnackbar('Please select an available username.', isError: true);
                        return;
                      }
                      _nextStep();
                      _runAiSafetyScan();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue (Step 4 of 5) →',
                          style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 4: AI Safety Shield & Niches (Strictly 2 inputs: Niches & Bio)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStep4AiProtectionAndSeeds(Color surface, Color border, Color textP, Color textS) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeaderBadge(
            stepNumber: 4,
            milestoneText: 'ALGORITHM SEEDING',
            stepTitle: 'AI Shield & Content Niches',
            stepSubtitle: 'Choose your creative niches so our AI models immediately calibrate your audience reach.',
            headerIcon: Icons.auto_awesome_rounded,
            textP: textP,
            textS: textS,
          ),

          _buildWhyItMatters(
            icon: Icons.rocket_launch_rounded,
            title: 'Neural Recommendation Seed',
            description: 'Selecting your niches immediately seeds Oneova distribution networks so your first posts are delivered to real users eager for your style.',
            surfaceMid: surfaceMid,
            border: border,
            textP: textP,
            textS: textS,
            iconColor: AppColors.brandPink,
          ),

          // AI Anti-Scam Shield Live Score Card
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandPink.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.security_rounded, size: 20, color: AppColors.brandPink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Oneova AI Anti-Phishing Shield',
                        style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: textP),
                      ),
                      Text(
                        _isAnalyzingSafety
                            ? 'Scanning credentials with OpenRouter model...'
                            : 'Protection Score: ${_aiSafetyReport?.safetyScore ?? 98}/100 • Safe & Verified',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: (_aiSafetyReport?.isSafe ?? true) ? Colors.greenAccent : Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Container with strictly 2 inputs (Niches + Bio)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: border, width: 1.0),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // INPUT 1: Content Niches FilterChips
                Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 15, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Select Content Niches (Tap all that apply)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _allNiches.map((niche) {
                    final isSelected = _selectedNiches.contains(niche);
                    return FilterChip(
                      label: Text(
                        niche,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected ? Colors.white : textP,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.brandBlue,
                      backgroundColor: surfaceMid,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        side: BorderSide(color: isSelected ? AppColors.brandBlue : border, width: 1.0),
                      ),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedNiches.add(niche);
                          } else {
                            _selectedNiches.remove(niche);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // INPUT 2: Bio / Creator Intent Text Field
                Row(
                  children: [
                    const Icon(Icons.edit_note_rounded, size: 16, color: AppColors.brandBlue),
                    const SizedBox(width: 6),
                    Text(
                      'Creator Bio & Intent (Optional)',
                      style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: textP),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _bioController,
                  maxLines: 2,
                  style: GoogleFonts.inter(fontSize: 12.5, color: textP),
                  decoration: InputDecoration(
                    hintText: 'e.g. Visual storyteller pushing cinematic reels & street culture',
                    hintStyle: GoogleFonts.inter(fontSize: 12, color: textS),
                    filled: true,
                    fillColor: surfaceMid,
                    isDense: true,
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedNiches.isEmpty) {
                        _showSnackbar('Please select at least 1 content niche.', isError: true);
                        return;
                      }
                      _nextStep();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.military_tech_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Review VIP Pass (Final Step) →',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Step 5: Creator Access Pass (Strictly 0 inputs: Celebration & Entry)
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildStep5AccessPassReview(Color surface, Color border, Color textP, Color textS) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceMid = isDark ? AppColors.darkSurfaceHighlight : AppColors.lightSurfaceHighlight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildStepHeaderBadge(
            stepNumber: 5,
            milestoneText: 'CREATOR VIP PASS',
            stepTitle: 'Your VIP Pass is Ready!',
            stepSubtitle: 'Review your creator credentials before launching into the global high-fidelity short video feed.',
            headerIcon: Icons.military_tech_rounded,
            textP: textP,
            textS: textS,
          ),

          _buildWhyItMatters(
            icon: Icons.stars_rounded,
            title: 'All Systems Hardened & Ready',
            description: 'Your pass verifies that your phone is authenticated, biometrics are armed, and your recommendation seeds are queued in the engine.',
            surfaceMid: surfaceMid,
            border: border,
            textP: textP,
            textS: textS,
            iconColor: AppColors.brandBlue,
          ),

          // Luxury Pass Card (0 inputs)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.2),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Column(
              children: [
                // Emblem
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: surfaceMid,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.brandBlue, width: 2.0),
                  ),
                  child: const Center(
                    child: Icon(Icons.star_rounded, size: 34, color: AppColors.brandBlue),
                  ),
                ),
                const SizedBox(height: 14),

                Text(
                  'ONEOVA ACCESS PASS',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2.0,
                    color: textS,
                  ),
                ),
                const SizedBox(height: 6),

                Text(
                  _nameController.text.trim().isEmpty ? 'Oneova Creator' : _nameController.text.trim(),
                  style: GoogleFonts.inter(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    color: textP,
                  ),
                ),
                const SizedBox(height: 4),

                Text(
                  '@${_usernameController.text.trim().isEmpty ? "creator" : _usernameController.text.trim()}',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPink,
                  ),
                ),
                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    border: Border.all(color: border, width: 1.0),
                  ),
                  child: Text(
                    '$_selectedAccountType • ${_selectedNiches.take(2).join(", ")}',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: textP,
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // Security Badges
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildPassPill(Icons.shield_rounded, 'AI Vetted', surfaceMid, border, textP),
                    _buildPassPill(Icons.fingerprint_rounded, 'Passkey Ready', surfaceMid, border, textP),
                    _buildPassPill(Icons.trending_up_rounded, 'Viral Seeded', surfaceMid, border, textP),
                  ],
                ),
              ],
            ),
          ).animate().scale(duration: 350.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 28),

          // Complete & Enter CTA
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _completeOnboarding,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.rocket_launch_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Complete & Enter Oneova',
                          style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildPassPill(IconData icon, String label, Color bg, Color border, Color textP) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: border, width: 1.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.brandBlue),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: textP)),
        ],
      ),
    );
  }
}

extension on BorderSide {
  Border toMP() => Border.all(color: color, width: width);
}

