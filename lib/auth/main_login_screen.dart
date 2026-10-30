import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_repository.dart';
import 'services/pin_auth_service.dart';
import 'services/oneova_biometrics_service.dart';
import 'services/oneova_username_service.dart';
import 'services/oneova_smart_phone_engine.dart';
import 'services/otp_autofill.dart';
import 'services/account_link_service.dart';
import 'screens/oneova_pin_screen.dart';
import 'widgets/onboarding_identity_fields.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pinput/pinput.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../shared/theme/app_theme.dart';
import '../backend/social/services/recommendation_service.dart';
import '../ova_assistant/services/ova_auth_coach.dart';
import '../ova_assistant/widgets/ova_inline_hint.dart';
import 'security/login_history.dart';
import 'security/login_security.dart';
import '../security/ova_guard_service.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

enum AuthScreenStep {
  phoneInput,
  existingUserAuth,
  existingUserOtp,
  forgotPasswordOtp,
  resetPassword,
  newUserOtp,
  newUserProfile,
  /// Signed in with one check; LoginSecurity wants another one.
  secondFactor,
  verificationSuccess,
}

/// Interactive touch wrapper providing premium scale bounce and haptic impact
class _TactileScaleTap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _TactileScaleTap({
    required this.child,
    required this.onTap,
  });

  @override
  State<_TactileScaleTap> createState() => _TactileScaleTapState();
}

class _TactileScaleTapState extends State<_TactileScaleTap> {
  static const double _pressedScale = 0.96;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _isPressed = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            },
      child: AnimatedScale(
        scale: _isPressed ? _pressedScale : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}

class MainLoginScreen extends ConsumerStatefulWidget {
  const MainLoginScreen({super.key});

  @override
  ConsumerState<MainLoginScreen> createState() => _MainLoginScreenState();
}

class _MainLoginScreenState extends ConsumerState<MainLoginScreen> {
  // Navigation & Step State
  AuthScreenStep _currentStep = AuthScreenStep.phoneInput;

  // Controllers
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  // Fills the SMS code via Google's consent prompt (no SMS permission).
  final OtpAutofill _otpAutofill = OtpAutofill();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _secondPasswordController = TextEditingController();
  final TextEditingController _createPasswordController = TextEditingController();
  final TextEditingController _createConfirmController = TextEditingController();
  final TextEditingController _resetPasswordController = TextEditingController();
  final TextEditingController _resetConfirmPasswordController = TextEditingController();

  // New User Registration Controllers
  final TextEditingController _regNameController = TextEditingController();
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regRecoveryEmailController = TextEditingController();

  // Visibility toggles
  bool _passwordVisible = false;
  bool _resetPasswordVisible = false;
  bool _resetConfirmPasswordVisible = false;
  bool _regPasswordVisible = false;
  bool _regEnableBiometrics = false;
  int _newUserSubStep = 0;

  // Method selector for existing users: 0: Password, 1: SMS OTP
  int _selectedExistingAuthMethod = 0;

  // ── Two-factor sign-in (LoginSecurity) ─────────────────────────────────────
  final Set<AuthFactor> _factors = {};
  AuthFactor? _requiredFactor;
  DeviceScan? _deviceScan;
  bool _scanningDevice = false;
  bool _accountHasPassword = false;
  bool _biometricReadyForUser = false;
  bool _pinReadyForUser = false;
  bool _otpIsSecondFactor = false;
  bool _enrollBiometricAfterSignIn = false;
  Map<String, dynamic>? _legacyProfile;
  String? _legacyProfileUid;
  String? _pendingLegacyPassword;

  // ── Ova live feedback state ───────────────────────────────────────────────
  String? _otpErrorCode;
  int _otpWrongAttempts = 0;
  bool _otpSending = false;
  bool _otpVerifying = false;
  bool _otpAutoVerified = false;
  int _passwordFailures = 0;
  DateTime? _passwordCooldownUntil;
  OvaHint? _bioHint;
  Timer? _cooldownTicker;

  int get _cooldownSeconds {
    final until = _passwordCooldownUntil;
    if (until == null) return 0;
    final s = until.difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  // ── Live limits: texts sent, code tries, password tries ─────────────────
  static const int _maxTexts = 5; // per 15 minutes, kept across restarts
  static const Duration _textWindow = Duration(minutes: 15);
  static const int _maxCodeTries = 5;
  static const int _maxPasswordTries = 5;
  static const _limitStore = FlutterSecureStorage();
  List<DateTime> _textSends = [];
  Timer? _limitTicker;

  List<DateTime> get _recentTextSends {
    final cutoff = DateTime.now().subtract(_textWindow);
    return _textSends.where((t) => t.isAfter(cutoff)).toList();
  }

  int get _textsLeft => (_maxTexts - _recentTextSends.length).clamp(0, _maxTexts);

  int get _textCooldownSeconds {
    if (_textsLeft > 0) return 0;
    final oldest = _recentTextSends.reduce((a, b) => a.isBefore(b) ? a : b);
    final s = oldest.add(_textWindow).difference(DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  int get _codeTriesLeft => (_maxCodeTries - _otpWrongAttempts).clamp(0, _maxCodeTries);
  int get _passwordTriesLeft => (_maxPasswordTries - _passwordFailures).clamp(0, _maxPasswordTries);

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _loadTextSends() async {
    try {
      final raw = await _limitStore.read(key: 'oneova_sms_sends');
      if (raw == null || raw.isEmpty) return;
      _textSends = raw
          .split(',')
          .map((v) => DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0))
          .toList();
      _textSends = _recentTextSends;
      if (_textCooldownSeconds > 0) _ensureLimitTicker();
    } catch (_) {}
  }

  Future<void> _recordTextSend() async {
    _textSends = [..._recentTextSends, DateTime.now()];
    try {
      await _limitStore.write(
        key: 'oneova_sms_sends',
        value: _textSends.map((t) => t.millisecondsSinceEpoch).join(','),
      );
    } catch (_) {}
    if (_textsLeft == 0) _ensureLimitTicker();
  }

  /// One shared 1-second tick while any countdown is running.
  void _ensureLimitTicker() {
    if (_limitTicker?.isActive == true) return;
    _limitTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_textCooldownSeconds == 0 && _cooldownSeconds == 0) t.cancel();
      setState(() {});
    });
  }

  Widget _limitChip(IconData icon, String text, {bool warn = false, bool ok = false}) {
    final color = warn ? AppColors.brandPink : (ok ? AppColors.brandBlue : context.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  /// Live counters under the code boxes.
  Widget _buildCodeCounters() {
    final cooldown = _textCooldownSeconds;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        _limitChip(Icons.sms_rounded, 'Texts left $_textsLeft/$_maxTexts', warn: _textsLeft <= 1),
        _limitChip(Icons.pin_rounded, 'Tries left $_codeTriesLeft/$_maxCodeTries', warn: _codeTriesLeft <= 2),
        if (cooldown > 0)
          _limitChip(Icons.timer_rounded, 'More texts in ${_clock(cooldown)}', warn: true)
        else if (_resendTimeout > 0)
          _limitChip(Icons.timer_rounded, 'New code in ${_clock(_resendTimeout)}')
        else
          _limitChip(Icons.refresh_rounded, 'New code ready', ok: true),
      ],
    );
  }

  /// Live counters under a password field.
  Widget _buildPasswordCounters() {
    final wait = _cooldownSeconds;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (wait > 0)
            _limitChip(Icons.timer_rounded, 'Try again in ${_clock(wait)}', warn: true)
          else
            _limitChip(Icons.key_rounded, 'Tries left $_passwordTriesLeft/$_maxPasswordTries',
                warn: _passwordTriesLeft <= 2),
        ],
      ),
    );
  }

  bool get _hardwareCapsLock =>
      HardwareKeyboard.instance.lockModesEnabled.contains(KeyboardLockMode.capsLock);

  // ── Smart Worldwide Phone Engine ──────────────────────────────────────────
  final OneovaSmartPhoneEngine _phoneEngine = OneovaSmartPhoneEngine();
  CountryPhoneMeta _selectedCountryMeta = OneovaSmartPhoneEngine.defaultCountry;
  String _selectedCountryIso = 'KE';
  String get _selectedDialCode => _selectedCountryMeta.dialCode;
  String _formatHint = 'e.g. 0712 345 678';
  LastUsedAccountInfo? _rememberedAccount;

  // Loading & Error States
  bool _isLoading = false;
  String? _errorMessage;
  String _verificationId = '';
  // From Firebase's first codeSent; "Resend" for the same number passes it
  // back so the session is reused instead of re-checking the app (reCAPTCHA).
  int? _resendToken;
  String _resendTokenPhone = '';

  // Phone Lookup Debounce & Identification State
  Timer? _lookupDebounceTimer;
  bool _isCheckingUser = false;
  bool _userChecked = false;
  Map<String, dynamic>? _identifiedUser;
  String? _identifiedUserId;

  // Username Availability Debounce State
  Timer? _usernameDebounceTimer;
  bool _isCheckingUsername = false;
  UsernameCheckResult? _usernameCheckResult;

  // Biometrics Hardware Check
  bool _isBiometricsAvailable = false;
  String _biometricTypeLabel = 'Fingerprint / Touch ID';
  // Account this device can sign back in to with a fingerprint.
  String? _bioQuickAccount;

  // Resend Timer State
  int _resendTimeout = 60;
  Timer? _resendTimer;
  bool get _canResend => _resendTimeout == 0;

  // Phone Verification Success Feedback State
  String _successHeadline = 'You\'re in!';
  String _successMessage = 'Welcome to Oneova!';
  bool _isSuccessRedirecting = false;
  Future<void> Function()? _onSuccessContinue;
  Timer? _successRedirectTimer;

  // Lazily parsed and normalized via Worldwide Smart Phone Engine
  String get _completePhoneNumber {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return '';
    final parsed = _phoneEngine.parseAndNormalize(
      input: raw,
      fallbackCountry: _selectedCountryMeta,
    );
    return parsed.e164;
  }

  @override
  void initState() {
    super.initState();

    _phoneController.addListener(_onPhoneTextChanged);
    _regUsernameController.addListener(_onUsernameTextChanged);

    _loadTextSends();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      precacheImage(const AssetImage('assets/images/oneova_logo.jpg'), context);
      await _checkBiometricsAvailability();

      // A session only opens the app after it passed the two-check policy on
      // this device. A session that has not (old app version, new device,
      // signup wizard) is asked for what is still missing.
      await LoginSecurity.instance.restore();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null && !user.isAnonymous) {
        if (LoginSecurity.instance.isVerified(user)) {
          final pinAuthService = ref.read(pinAuthServiceProvider);
          if (await pinAuthService.isSessionExpired()) {
            if (mounted) context.go('/auth/locked');
            return;
          }
          if (mounted) context.go('/hub/home');
          return;
        }
        _factors
          ..clear()
          ..addAll(LoginSecurity.instance.pendingFactorsFor(user.uid));
        await _detectCountryAndLoadRememberedAccount();
        // Reopened app: wait for a tap before texting a code.
        _verificationId = '';
        await _continueAfterPrimary(autoSendCode: false);
        return;
      }

      // Silent worldwide country detection & last used account memory
      await _detectCountryAndLoadRememberedAccount();
      // Sent here by the signup wizard to sign in to an existing account.
      _applyPendingLinkHint();
    });
  }

  /// Silently detects country and loads device memory without blocking UI
  Future<void> _detectCountryAndLoadRememberedAccount() async {
    try {
      final detected = await _phoneEngine.detectCountrySilently();
      final remembered = await _phoneEngine.getLastUsedAccount();

      if (!mounted) return;
      setState(() {
        _selectedCountryMeta = detected;
        _selectedCountryIso = detected.isoCode;
        _formatHint = detected.formatHint;
        _rememberedAccount = remembered;
      });
    } catch (_) {}
  }

  /// 1-Tap Quick Login from remembered account on this device
  void _applyRememberedAccount(LastUsedAccountInfo account) {
    HapticFeedback.lightImpact();
    final meta = _phoneEngine.findByIso(account.countryIso);
    String dialDigits = meta.dialCode.replaceAll('+', '');
    String localDigits = account.phoneE164.replaceAll(RegExp(r'\D'), '');
    if (localDigits.startsWith(dialDigits)) {
      localDigits = localDigits.substring(dialDigits.length);
    }
    setState(() {
      _selectedCountryIso = account.countryIso;
      _selectedCountryMeta = meta;
      _formatHint = meta.formatHint;
      _phoneController.text = localDigits;
    });
    _performPhoneLookup();
  }

  @override
  void dispose() {
    _successRedirectTimer?.cancel();
    _lookupDebounceTimer?.cancel();
    _usernameDebounceTimer?.cancel();
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpAutofill.cancel();
    _otpController.dispose();
    _passwordController.dispose();
    _secondPasswordController.dispose();
    _createPasswordController.dispose();
    _createConfirmController.dispose();
    _cooldownTicker?.cancel();
    _limitTicker?.cancel();
    _resetPasswordController.dispose();
    _resetConfirmPasswordController.dispose();
    _regNameController.dispose();
    _regUsernameController.dispose();
    _regPasswordController.dispose();
    _regRecoveryEmailController.dispose();
    super.dispose();
  }

  // ── Biometrics Availability ────────────────────────────────────────────────
  Future<void> _checkBiometricsAvailability() async {
    try {
      final bioService = ref.read(oneovaBiometricsServiceProvider);
      final isAvail = await bioService.isBiometricsAvailable();
      final label = await bioService.getBiometricTypeLabel();
      final quick = isAvail && await bioService.hasSignInKey()
          ? await bioService.getEnrolledUserEmail()
          : null;
      if (mounted) {
        setState(() {
          _isBiometricsAvailable = isAvail;
          _biometricTypeLabel = label;
          _bioQuickAccount = quick;
        });
      }
    } catch (_) {}
  }

  // ── Resend Countdown Timer ─────────────────────────────────────────────────
  void _startResendTimer() {
    _resendTimeout = 60;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendTimeout == 0) {
        timer.cancel();
        if (mounted) setState(() {});
      } else {
        if (mounted) {
          setState(() {
            _resendTimeout--;
          });
        }
      }
    });
  }

  // ── Phone Auto-Identification (Debounced 350ms) ────────────────────────────
  void _onPhoneTextChanged() {
    _lookupDebounceTimer?.cancel();
    final raw = _phoneController.text;

    if (raw.isNotEmpty) {
      final parsed = _phoneEngine.parseAndNormalize(
        input: raw,
        fallbackCountry: _selectedCountryMeta,
      );

      // Auto-switch country if user pasted or typed full international number
      if (parsed.wasCountryAutoSwitched && parsed.country.isoCode != _selectedCountryIso) {
        setState(() {
          _selectedCountryMeta = parsed.country;
          _selectedCountryIso = parsed.country.isoCode;
          _formatHint = parsed.country.formatHint;
        });
      }
    }

    final digits = raw.replaceAll(RegExp(r'\D'), '');

    if (digits.length < 8) {
      if (_identifiedUser != null || _userChecked || _isCheckingUser) {
        setState(() {
          _identifiedUser = null;
          _identifiedUserId = null;
          _userChecked = false;
          _isCheckingUser = false;
        });
      }
      return;
    }

    setState(() {
      _isCheckingUser = true;
    });

    _lookupDebounceTimer = Timer(const Duration(milliseconds: 350), _performPhoneLookup);
  }

  Future<void> _performPhoneLookup() async {
    final normalized = _completePhoneNumber;
    if (normalized.isEmpty) {
      if (mounted) setState(() => _isCheckingUser = false);
      return;
    }

    try {
      // 1. Primary check on phoneNumber
      var query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: normalized)
          .limit(1)
          .get();

      // 2. Fallback check on phone
      if (query.docs.isEmpty) {
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', isEqualTo: normalized)
            .limit(1)
            .get();
      }

      // 3. Alternate format check (e.g., 07xx or no plus)
      if (query.docs.isEmpty && normalized.startsWith('+254')) {
        final localFormat = '0${normalized.substring(4)}';
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: localFormat)
            .limit(1)
            .get();
        if (query.docs.isEmpty) {
          query = await FirebaseFirestore.instance
              .collection('users')
              .where('phone', isEqualTo: localFormat)
              .limit(1)
              .get();
        }
      }

      if (query.docs.isEmpty && normalized.startsWith('+')) {
        final noPlus = normalized.substring(1);
        query = await FirebaseFirestore.instance
            .collection('users')
            .where('phoneNumber', isEqualTo: noPlus)
            .limit(1)
            .get();
      }

      if (mounted) {
        if (query.docs.isNotEmpty) {
          final doc = query.docs.first;
          setState(() {
            _identifiedUser = doc.data();
            _identifiedUserId = doc.id;
            _userChecked = true;
            _isCheckingUser = false;
          });
        } else {
          setState(() {
            _identifiedUser = null;
            _identifiedUserId = null;
            _userChecked = true;
            _isCheckingUser = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCheckingUser = false;
          _userChecked = true;
        });
      }
    }
  }

  // ── Username Availability (Debounced 300ms) ────────────────────────────────
  void _onUsernameTextChanged() {
    _usernameDebounceTimer?.cancel();
    final clean = _regUsernameController.text.trim().toLowerCase();
    if (clean.length < 3) {
      setState(() {
        _usernameCheckResult = null;
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);

    _usernameDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final res = await ref.read(oneovaUsernameServiceProvider).validateAndCheckAvailability(clean);
        if (mounted) {
          setState(() {
            _usernameCheckResult = res;
            _isCheckingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isCheckingUsername = false);
      }
    });
  }

  // ── Password Strength Calculator ───────────────────────────────────────────
  int _calculatePasswordStrength(String password) => OvaAuthCoach.passwordScore(password);

  String _getPasswordStrengthLabel(int score) {
    switch (score) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Strong';
      case 4:
        return 'Excellent';
      default:
        return 'Weak';
    }
  }

  Color _getPasswordStrengthColor(int score) {
    switch (score) {
      case 0:
      case 1:
      case 2:
        return AppColors.brandPink;
      default:
        return AppColors.brandBlue;
    }
  }

  // ── Navigation & Status Redirect ───────────────────────────────────────────
  Future<void> _checkStatusAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    // Never open the app for a session that did not pass the two-check gate.
    if (!LoginSecurity.instance.isVerified(user)) {
      await _continueAfterPrimary();
      return;
    }

    await _linkPendingSignIn(user);

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      final phone = (data['phoneNumber'] ?? data['phone'] ?? user.phoneNumber ?? _completePhoneNumber) as String?;
      final displayName = data['displayName'] as String? ?? user.displayName;
      final username = data['username'] as String?;

      if (phone != null && phone.isNotEmpty) {
        await _phoneEngine.saveLastUsedAccount(
          phoneE164: phone,
          countryIso: _selectedCountryIso,
          displayName: displayName,
          username: username,
        );
      }

      final status = data['status'] as String? ?? 'active';
      if (status == 'pending') {
        if (mounted) context.go('/auth/pending');
        return;
      }
    } catch (e) {
      debugPrint('[MainLoginScreen] error checking status: $e');
    }

    // Pre-warm the For You recommendation feed in background so auto-play reel has zero latency
    try {
      ref.read(recommendationServiceProvider).getFeed(user.uid, FeedMode.forYou);
    } catch (_) {}

    final pinAuthService = ref.read(pinAuthServiceProvider);
    final hasPin = await pinAuthService.hasPinSet();
    if (hasPin && !_factors.contains(AuthFactor.pin) && mounted) {
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const OneovaPinScreen(mode: PinScreenMode.verify),
        ),
      );
      if (success != true || !mounted) return;
    }

    await _offerBiometricSignIn(user);
    if (mounted) context.go('/hub/home');
  }

  /// After a verified sign-in: quietly refresh the device key for enrolled
  /// users, or offer fingerprint sign-in once to users who haven't turned it on.
  Future<void> _offerBiometricSignIn(User user) async {
    if (user.isAnonymous || !mounted) return;
    final bio = ref.read(oneovaBiometricsServiceProvider);
    try {
      await bio.ensureSignInKey();
      final askedAtSignup = _enrollBiometricAfterSignIn;
      _enrollBiometricAfterSignIn = false;
      if (!askedAtSignup) {
        if (!await bio.shouldOfferEnrollment(user.uid) || !mounted) return;
        await bio.markEnrollmentOffered(user.uid);
        if (!mounted) return;
        final yes = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: ctx.surface,
            icon: const Icon(Icons.fingerprint_rounded, color: AppColors.brandBlue, size: 36),
            title: Text('Sign in with your fingerprint?',
                style: TextStyle(color: ctx.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text(
              'Next time, unlock Oneova on this phone with one touch. It works only on this trusted '
              'device and only for this account; your password is never stored.',
              style: TextStyle(color: ctx.textSecondary, fontSize: 12.5, height: 1.35),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Turn on'),
              ),
            ],
          ),
        );
        if (yes != true || !mounted) return;
      }
      final result = await bio.enrollUserBiometrics(
        userId: user.uid,
        userEmail: user.phoneNumber ?? user.email ?? user.displayName ?? 'your account',
        displayName: user.displayName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        content: Text(result.isSuccess
            ? 'Fingerprint sign-in is on for this phone'
            : (result.errorMessage ?? 'Could not turn on fingerprint sign-in')),
      ));
    } catch (e) {
      debugPrint('[MainLoginScreen] biometric offer skipped: $e');
    }
  }

  // ── Verification Success Trigger & Transition ──────────────────────────────
  void _triggerVerificationSuccess({
    required Future<void> Function() onContinue,
    String headline = 'You\'re in!',
    String message = 'Welcome back to Oneova.',
    bool isNewUser = false,
  }) {
    HapticFeedback.heavyImpact();
    _successRedirectTimer?.cancel();
    setState(() {
      _currentStep = AuthScreenStep.verificationSuccess;
      _successHeadline = headline;
      _successMessage = message;
      _isSuccessRedirecting = false;
      _onSuccessContinue = onContinue;
    });

    _successRedirectTimer = Timer(const Duration(milliseconds: 1400), () async {
      if (mounted && _currentStep == AuthScreenStep.verificationSuccess && !_isSuccessRedirecting) {
        _isSuccessRedirecting = true;
        await _onSuccessContinue?.call();
      }
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Two-check sign-in engine
  // ───────────────────────────────────────────────────────────────────────────

  bool _hasProvider(User user, String id) => user.providerData.any((p) => p.providerId == id);

  /// Phone number the second-factor SMS goes to: the number on the Firebase
  /// account first (authoritative), then the profile, then what was typed.
  String? get _secondFactorPhone {
    final user = FirebaseAuth.instance.currentUser;
    final authPhone = user?.phoneNumber;
    if (authPhone != null && authPhone.isNotEmpty) return authPhone;
    final docPhone = (_legacyProfile?['phoneNumber'] ?? _legacyProfile?['phone']) as String?;
    if (docPhone != null && docPhone.startsWith('+')) return docPhone;
    final typed = _completePhoneNumber;
    return typed.isNotEmpty ? typed : null;
  }

  /// Loads the profile behind this session. Accounts made by older app
  /// versions may keep their profile (and an old password hash) under the
  /// uid found by phone lookup instead of the signed-in uid.
  Future<void> _loadAccountProfile(User user) async {
    try {
      final own = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get()
          .timeout(const Duration(seconds: 3));
      if (own.exists) {
        _legacyProfile = own.data();
        _legacyProfileUid = null;
        return;
      }
      final otherId = _identifiedUserId;
      if (otherId != null && otherId != user.uid) {
        final other = await FirebaseFirestore.instance
            .collection('users')
            .doc(otherId)
            .get()
            .timeout(const Duration(seconds: 3));
        if (other.exists) {
          _legacyProfile = other.data();
          _legacyProfileUid = otherId;
        }
      }
    } catch (e) {
      debugPrint('[MainLoginScreen] profile load: $e');
    }
  }

  bool get _legacyPasswordStored => _hasLegacyPassword(_legacyProfile);

  /// Accounts from older app versions had a password hash in their profile.
  /// Ova Guard moves those hashes server-side and leaves this flag.
  static bool _hasLegacyPassword(Map<String, dynamic>? doc) {
    final hash = doc?['passwordHash'] as String?;
    final plain = doc?['password'] as String?;
    return (hash != null && hash.isNotEmpty) ||
        (plain != null && plain.isNotEmpty) ||
        doc?['legacyPasswordPending'] == true;
  }

  /// The server compares [pw] with the old hash (checkLegacyPassword), so
  /// clients never read password hashes. Failures are counted server-side.
  Future<bool> _legacyPasswordMatches(String pw, {required String phone}) async {
    try {
      return await ref.read(ovaGuardServiceProvider).checkLegacyPassword(password: pw, phone: phone);
    } catch (e) {
      debugPrint('[MainLoginScreen] legacy password check: $e');
      return false;
    }
  }

  /// Old accounts kept a password hash in the public profile. Once the
  /// password is registered with Firebase Auth, remove it, and copy an
  /// orphaned profile onto the real account.
  Future<void> _scrubLegacyPassword(User user) async {
    final users = FirebaseFirestore.instance.collection('users');
    try {
      if (_legacyProfileUid != null && _legacyProfile != null) {
        final copy = Map<String, dynamic>.from(_legacyProfile!)
          ..remove('passwordHash')
          ..remove('password')
          ..remove('legacyPasswordPending')
          ..remove('followers')
          ..remove('following');
        await users.doc(user.uid).set({
          ...copy,
          'migratedFromUid': _legacyProfileUid,
          'phoneNumber': user.phoneNumber ?? copy['phoneNumber'],
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _legacyProfileUid = null;
      }
      await users.doc(user.uid).set({
        'passwordHash': FieldValue.delete(),
        'password': FieldValue.delete(),
        'legacyPasswordPending': FieldValue.delete(),
        'authPasswordLinked': true,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _legacyProfile?.remove('passwordHash');
      _legacyProfile?.remove('password');
    } catch (e) {
      debugPrint('[MainLoginScreen] legacy password scrub: $e');
    }
  }

  /// Decides what the signed-in user still has to prove and shows that step,
  /// or accepts the session when the policy is met.
  Future<void> _continueAfterPrimary({bool autoSendCode = true}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (user == null || user.isAnonymous) {
      setState(() {
        _isLoading = false;
        _currentStep = AuthScreenStep.phoneInput;
      });
      return;
    }

    if (_deviceScan == null) {
      setState(() {
        _scanningDevice = true;
        _isLoading = true;
      });
      try {
        _deviceScan = await LoginSecurity.instance.scanDevice(user.uid).timeout(const Duration(seconds: 4));
        await _loadAccountProfile(user);
      } catch (e) {
        debugPrint('[MainLoginScreen] scanDevice error or timeout: $e');
      }
      _deviceScan ??= DeviceScan(
        deviceId: 'unknown',
        label: 'This device',
        trusted: false,
        isPhysicalDevice: true,
      );
      if (!mounted) return;
      _scanningDevice = false;
    }

    final bio = ref.read(oneovaBiometricsServiceProvider);
    _accountHasPassword = _hasProvider(user, 'password') || _legacyPasswordStored;
    _biometricReadyForUser = _isBiometricsAvailable &&
        await bio.isUserEnrolled(user.uid) &&
        await bio.getEnrolledUserId() == user.uid;
    _pinReadyForUser = await ref.read(pinAuthServiceProvider).isPinOwnedBy(user.uid);
    if (!mounted) return;

    final trusted = _deviceScan!.trusted && _deviceScan!.isPhysicalDevice;
    final missing = LoginSecurity.missingFactor(
      _factors,
      deviceTrusted: trusted,
      hasPassword: _accountHasPassword,
      biometricReady: _biometricReadyForUser,
      pinReady: _pinReadyForUser,
    );

    if (missing == null) {
      await _finishVerified(trusted);
      return;
    }

    setState(() {
      _isLoading = false;
      _errorMessage = null;
      _requiredFactor = missing;
      _currentStep = AuthScreenStep.secondFactor;
      _otpIsSecondFactor = missing == AuthFactor.smsOtp;
      _bioHint = null;
    });

    if (missing == AuthFactor.smsOtp && _secondFactorPhone != null && autoSendCode) {
      _otpController.clear();
      _otpErrorCode = null;
      await _sendOtp(onSuccess: () {}, phoneOverride: _secondFactorPhone);
    } else if (missing == AuthFactor.password && _pendingLegacyPassword != null && _accountHasPassword) {
      final pw = _pendingLegacyPassword!;
      _pendingLegacyPassword = null;
      await _verifySecondFactorPassword(pw);
    } else if (missing == AuthFactor.biometric) {
      await _runBiometricFactor();
    } else if (missing == AuthFactor.pin) {
      await _runPinFactor();
    }
  }

  String _factorSummary() {
    const names = {
      AuthFactor.password: 'password',
      AuthFactor.smsOtp: 'text code',
      AuthFactor.federated: 'Google/Facebook',
      AuthFactor.biometric: 'fingerprint',
      AuthFactor.pin: 'PIN',
      AuthFactor.deviceKey: 'this phone\'s saved sign-in',
      AuthFactor.trustedDevice: 'your known phone',
    };
    return AuthFactor.values.where(_factors.contains).map((f) => names[f]).join(' + ');
  }

  Future<void> _finishVerified(bool deviceWasTrusted) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    if (deviceWasTrusted) _factors.add(AuthFactor.trustedDevice);
    try {
      await LoginSecurity.instance.markVerified(user, _factors, deviceTrusted: deviceWasTrusted);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'We need one more step to keep your account safe.';
      });
      return;
    }
    if (!mounted) return;
    final isNew = _currentStep == AuthScreenStep.newUserProfile;
    setState(() => _isLoading = false);
    _triggerVerificationSuccess(
      onContinue: _checkStatusAndRedirect,
      headline: isNew ? 'Welcome to Oneova!' : 'You\'re in!',
      message: deviceWasTrusted
          ? 'Checked with ${_factorSummary()}.'
          : 'Checked with ${_factorSummary()}. We\'ll remember this phone.',
      isNewUser: isNew,
    );
  }

  /// Leave a half-finished sign-in and start over.
  Future<void> _abandonSignIn() async {
    _resendTimer?.cancel();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !LoginSecurity.instance.isVerified(user)) {
      await FirebaseAuth.instance.signOut();
    }
    if (!mounted) return;
    setState(() {
      _factors.clear();
      _deviceScan = null;
      _requiredFactor = null;
      _legacyProfile = null;
      _legacyProfileUid = null;
      _pendingLegacyPassword = null;
      _otpIsSecondFactor = false;
      _otpErrorCode = null;
      _bioHint = null;
      _isLoading = false;
      _errorMessage = null;
      _secondPasswordController.clear();
      _currentStep = AuthScreenStep.phoneInput;
    });
  }

  void _registerPasswordFailure() {
    _passwordFailures++;
    if (_passwordFailures >= 5) {
      _passwordCooldownUntil = DateTime.now().add(const Duration(seconds: 60));
      _passwordFailures = 0;
      _ensureLimitTicker();
    }
  }

  /// Second factor: the password of the signed-in account.
  Future<void> _verifySecondFactorPassword(String pw) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _abandonSignIn();
    if (_cooldownSeconds > 0) return;
    if (pw.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_hasProvider(user, 'password') && user.email != null) {
        await user.reauthenticateWithCredential(EmailAuthProvider.credential(email: user.email!, password: pw));
      } else {
        if (!await _legacyPasswordMatches(pw, phone: user.phoneNumber ?? _completePhoneNumber)) {
          throw FirebaseAuthException(code: 'legacy-wrong-password');
        }
        // Register the old password with Firebase Auth, then drop the hash.
        final phone = user.phoneNumber ?? _completePhoneNumber;
        await user.linkWithCredential(
          EmailAuthProvider.credential(email: LoginSecurity.authEmailForPhone(phone), password: pw),
        );
        await _scrubLegacyPassword(user);
      }
      _passwordFailures = 0;
      _flashCheck('Password correct');
      _factors.add(AuthFactor.password);
      _secondPasswordController.clear();
      await _continueAfterPrimary();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        switch (e.code) {
          case 'wrong-password':
          case 'invalid-credential':
          case 'invalid-login-credentials':
          case 'user-mismatch':
          case 'legacy-wrong-password':
            _registerPasswordFailure();
            _errorMessage = null;
            // Legacy checks are already counted by the server.
            if (e.code != 'legacy-wrong-password') {
              ref.read(ovaGuardServiceProvider).reportAuthFailure(user.phoneNumber ?? _completePhoneNumber, otp: false);
            }
            LoginHistory.instance.recordFailure(method: 'password', code: e.code);
          case 'weak-password':
            _requiredFactor = AuthFactor.password;
            _accountHasPassword = false;
            _errorMessage = 'Your old password is too short for the new security rules. Please create a new one.';
          case 'too-many-requests':
            _passwordCooldownUntil = DateTime.now().add(const Duration(seconds: 60));
            _errorMessage = null;
          case 'operation-not-allowed':
            _errorMessage = 'Password sign-in is not enabled for Oneova yet. Use your fingerprint or try later.';
          case 'email-already-in-use':
          case 'credential-already-in-use':
          case 'provider-already-linked':
            _errorMessage = 'This password is linked to a different account. Contact support.';
          default:
            _errorMessage = e.message ?? 'Could not check your password. Try again.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Could not check your password: $e';
        });
      }
    }
  }

  /// For accounts that never had a password: create one now (this becomes
  /// their second check from the next sign-in on).
  Future<void> _createPasswordFactor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _abandonSignIn();
    final pw = _createPasswordController.text;
    final confirm = _createConfirmController.text;
    final hint = OvaAuthCoach.newPassword(pw, phone: user.phoneNumber);
    if (pw.length < 8 || OvaAuthCoach.isCommonPassword(pw)) {
      setState(() => _errorMessage = hint?.text ?? 'Use at least 8 characters.');
      return;
    }
    if (pw != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      if (_hasProvider(user, 'password')) {
        await user.updatePassword(pw);
      } else {
        final phone = user.phoneNumber ?? _completePhoneNumber;
        await user.linkWithCredential(
          EmailAuthProvider.credential(email: user.email ?? LoginSecurity.authEmailForPhone(phone), password: pw),
        );
      }
      await _scrubLegacyPassword(user);
      _factors.add(AuthFactor.password);
      _createPasswordController.clear();
      _createConfirmController.clear();
      await _continueAfterPrimary();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = switch (e.code) {
            'weak-password' => 'That password is too weak. Try a longer one.',
            'operation-not-allowed' => 'Password sign-in is not enabled for Oneova yet.',
            'requires-recent-login' => 'For safety, enter a text code first.',
            _ => e.message ?? 'Could not save your password.',
          };
        });
      }
    }
  }

  /// Fingerprint as a check for the account that is already signed in.
  Future<void> _runBiometricFactor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _abandonSignIn();
    final bio = ref.read(oneovaBiometricsServiceProvider);
    if (await bio.getEnrolledUserId() != user.uid) {
      setState(() => _bioHint = const OvaHint(
          'Fingerprint isn\'t set up for this account on this phone. Use your password or a text code.',
          OvaHintTone.warning));
      return;
    }
    setState(() => _bioHint = OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, scanning: true));
    final result = await bio.authenticateWithDetails(
      reason: 'Confirm it\'s you to open Oneova',
      biometricOnly: true,
    );
    if (!mounted) return;
    if (result.isSuccess) {
      HapticFeedback.heavyImpact();
      setState(() => _bioHint = OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, success: true));
      _flashCheck('Fingerprint matched');
      _factors.add(AuthFactor.biometric);
      await _continueAfterPrimary();
    } else {
      setState(() => _bioHint = OvaAuthCoach.biometric(
            available: true,
            enrolledOnDevice: !result.isNotEnrolled,
            success: false,
            canceled: result.isCanceled,
            lockedOut: result.isLockedOut,
            error: result.errorMessage,
          ));
    }
  }

  // ── Social & Guest Logins ──────────────────────────────────────────────────

  /// Social sign-in counts as one check; existing accounts continue to the
  /// second check. A uid without a profile is either a new person (signup
  /// wizard) or someone whose Oneova account was made with another method:
  /// then the empty uid is released and the credential is linked to the real
  /// account once they sign in to it.
  Future<void> _afterFederatedSignIn(
    User user,
    Map<String, Object?> wizardExtra, {
    AuthCredential? credential,
  }) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    LoginSecurity.instance.recordFactor(user.uid, AuthFactor.federated);
    if (!doc.exists) {
      final link = ref.read(accountLinkServiceProvider);
      final label = AccountLinkService.labelFor(credential?.providerId ?? 'google.com');
      final match = await link.findProfileFor(email: user.email, exceptUid: user.uid);
      if (!mounted) return;
      final hasAccount = await _askHasExistingAccount(label, match);
      if (!mounted) return;
      if (hasAccount == null) {
        await link.releaseEmptyUser(user);
        link.clearPending();
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      if (credential != null) link.holdForLinking(credential);
      if (hasAccount) {
        link.setPhoneHint(match?.phone);
        await link.releaseEmptyUser(user);
        if (!mounted) return;
        _factors.clear();
        setState(() {
          _isLoading = false;
          _currentStep = AuthScreenStep.phoneInput;
        });
        _applyPendingLinkHint();
        return;
      }
      setState(() => _isLoading = false);
      context.go('/auth/signup_wizard', extra: {...wizardExtra, 'uid': user.uid});
      return;
    }
    _factors
      ..clear()
      ..add(AuthFactor.federated);
    _deviceScan = null;
    await _continueAfterPrimary();
  }

  /// `account-exists-with-different-credential`: the email already has an
  /// Oneova sign-in with another method ("One account per email address").
  /// Keep the new credential and link it after the person signs in.
  Future<bool> _holdCredentialOfExistingEmail(FirebaseAuthException e) async {
    if (e.code != 'account-exists-with-different-credential' || e.credential == null) return false;
    final link = ref.read(accountLinkServiceProvider);
    link.holdForLinking(e.credential!);
    if (e.email != null) {
      final match = await link.findProfileFor(email: e.email, exceptUid: '');
      link.setPhoneHint(match?.phone);
    }
    if (!mounted) return true;
    setState(() {
      _isLoading = false;
      _currentStep = AuthScreenStep.phoneInput;
    });
    _applyPendingLinkHint();
    return true;
  }

  /// "Do you already have an Oneova account?" after a social sign-in that has
  /// no profile. Returns true (existing), false (new) or null (cancel).
  Future<bool?> _askHasExistingAccount(String label, ExistingAccountMatch? match) {
    final known = match?.username != null ? '@${match!.username}' : null;
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                known != null ? 'Is $known your account?' : 'Already on Oneova?',
                style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: ctx.textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                known != null
                    ? 'This $label matches $known. Sign in to it once with your phone number and we\'ll link $label, so both open the same account.'
                    : 'If you already made an Oneova account with your phone number, sign in to it once and we\'ll link $label. You won\'t need to register again.',
                style: GoogleFonts.inter(fontSize: 12.5, height: 1.35, color: ctx.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text('I have an account – link $label',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ctx.textPrimary,
                    side: BorderSide(color: ctx.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('I\'m new to Oneova', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Prefills the phone of the account a held credential will be linked to.
  void _applyPendingLinkHint() {
    final link = ref.read(accountLinkServiceProvider);
    if (link.pendingCredential == null || !mounted) return;
    final phone = link.pendingPhoneHint;
    if (phone != null && phone.startsWith('+')) {
      _phoneController.text = phone;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.brandBlue,
      content: Text('Sign in to your Oneova account to link ${link.pendingLabel ?? 'it'}.'),
    ));
  }

  /// After a verified sign-in: link a held credential and keep the profile's
  /// list of sign-in methods current.
  Future<void> _linkPendingSignIn(User user) async {
    final link = ref.read(accountLinkServiceProvider);
    final message = await link.linkPending(user);
    await link.recordProviders(FirebaseAuth.instance.currentUser ?? user);
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        content: Text(message),
      ));
    }
  }

  Future<void> _signInWithGoogle() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userCred = await ref.read(authRepositoryProvider).signInWithGoogle();
      final user = userCred?.user;
      if (user == null || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      await _afterFederatedSignIn(user, {
        'fromGoogle': true,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
      }, credential: ref.read(authRepositoryProvider).lastGoogleCredential ?? userCred?.credential);
    } catch (e) {
      if (e is FirebaseAuthException && await _holdCredentialOfExistingEmail(e)) return;
      debugPrint('[MainLoginScreen] Google sign-in error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          final errStr = e.toString();
          if (errStr.contains('cancelled') ||
              errStr.contains('canceled') ||
              errStr.contains('SIGN_IN_CANCELLED') ||
              errStr.contains('12501')) {
            _errorMessage = null;
          } else if (errStr.contains('network') ||
              errStr.contains('offline') ||
              errStr.contains('NETWORK_ERROR')) {
            _errorMessage = 'Network connection issue. Please check your internet and try again.';
          } else {
            _errorMessage = 'Could not sign in with Google. Please try again or use phone number.';
          }
        });
      }
    }
  }

  Future<void> _signInWithTikTok() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final provider = OAuthProvider('oidc.tiktok');
      final userCred = await FirebaseAuth.instance.signInWithProvider(provider);
      final user = userCred.user;
      if (user == null || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      await _afterFederatedSignIn(user, {
        'fromTikTok': true,
        'name': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
      }, credential: userCred.credential);
    } catch (e) {
      if (e is FirebaseAuthException && await _holdCredentialOfExistingEmail(e)) return;
      debugPrint('[MainLoginScreen] TikTok sign-in error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          final errStr = e.toString();
          if (errStr.contains('cancelled') || errStr.contains('canceled')) {
            _errorMessage = null;
          } else {
            _errorMessage = 'TikTok sign-in failed. Please try another method.';
          }
        });
      }
    }
  }

  Future<void> _signInWithFacebook() async {
    HapticFeedback.lightImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final facebookProvider = FacebookAuthProvider();
      facebookProvider.addScope('email');
      facebookProvider.addScope('public_profile');
      final userCred = await FirebaseAuth.instance.signInWithProvider(facebookProvider);
      final user = userCred.user;
      if (user == null || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      await _afterFederatedSignIn(user, {
        'fromFacebook': true,
        'email': user.email ?? '',
        'name': user.displayName ?? '',
        'photoUrl': user.photoURL ?? '',
      }, credential: userCred.credential);
    } catch (e) {
      if (e is FirebaseAuthException && await _holdCredentialOfExistingEmail(e)) return;
      debugPrint('[MainLoginScreen] Facebook sign-in error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          final errStr = e.toString();
          if (errStr.contains('cancelled') || errStr.contains('canceled')) {
            _errorMessage = null;
          } else {
            _errorMessage = 'Facebook sign-in failed. Please try another method.';
          }
        });
      }
    }
  }

  /// Guests browse public screens only (router: LoginSecurity.isGuestRoute).
  /// No profile is created for a guest.
  Future<void> _exploreAsGuest() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.signInAnonymously();
      if (!mounted) return;
      setState(() => _isLoading = false);
      _triggerVerificationSuccess(
        onContinue: () async {
          if (mounted) context.go('/hub/home');
        },
        headline: 'Welcome, guest',
        message: 'Look around. Sign in to post, chat or follow.',
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Guest entry: $e';
        });
      }
    }
  }

  // ── Biometric Unlock ───────────────────────────────────────────────────────
  /// A fingerprint never opens an account on its own: it unlocks the session
  /// that is already on this phone, or exchanges this device's server key for
  /// the enrolled (existing) account. Either way the device must also be
  /// trusted for that account, otherwise an SMS code is required.
  Future<void> _unlockWithBiometrics() async {
    final bio = ref.read(oneovaBiometricsServiceProvider);
    final cap = await bio.getCapabilityDetails();
    if (!mounted) return;
    if (!cap.isHardwareAvailable || !cap.hasEnrolledBiometrics) {
      setState(() => _bioHint = OvaAuthCoach.biometric(
            available: cap.isHardwareAvailable,
            enrolledOnDevice: cap.hasEnrolledBiometrics,
          ));
      return;
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && !currentUser.isAnonymous) {
      await _runBiometricFactor();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _bioHint = OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, scanning: true);
    });
    try {
      final fastLogin = await bio.authenticateForFastSignIn();
      if (!mounted) return;
      if (fastLogin.isSuccess) {
        final user = FirebaseAuth.instance.currentUser;
        // The key must belong to an existing Oneova profile.
        final profile = user == null
            ? null
            : await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (user == null || profile == null || !profile.exists) {
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _bioHint = const OvaHint('No Oneova account is linked to this fingerprint key.', OvaHintTone.error);
          });
          return;
        }
        HapticFeedback.heavyImpact();
        _identifiedUserId = user.uid;
        _factors
          ..clear()
          ..addAll({AuthFactor.deviceKey, AuthFactor.biometric});
        _deviceScan = null;
        setState(() => _bioHint = OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, success: true));
        await _continueAfterPrimary();
      } else {
        setState(() {
          _isLoading = false;
          final msg = fastLogin.errorMessage ?? '';
          _bioHint = fastLogin.noEnrolledUser
              ? const OvaHint('Fingerprint isn\'t set up on this phone yet. Sign in with your password or a text code first.',
                  OvaHintTone.warning)
              : msg.toLowerCase().contains('cancel')
                  ? OvaAuthCoach.biometric(available: true, enrolledOnDevice: true, canceled: true)
                  : OvaHint(msg.isEmpty ? 'Fingerprint didn\'t match. Try again.' : msg, OvaHintTone.error);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _bioHint = OvaHint('Fingerprint sign-in failed: $e', OvaHintTone.error);
        });
      }
    }
  }

  // ── SMS OTP Send Logic ─────────────────────────────────────────────────────
  Future<void> _sendOtp({required VoidCallback onSuccess, String? phoneOverride}) async {
    final phone = phoneOverride ?? _completePhoneNumber;
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty || digitsOnly.length < 7) {
      setState(() => _errorMessage = 'Please enter a valid phone number (e.g. 0712 345 678)');
      return;
    }
    if (_textsLeft == 0) {
      _ensureLimitTicker();
      setState(() => _errorMessage =
          'You asked for $_maxTexts codes. You can ask again in ${_clock(_textCooldownSeconds)}, or use your password.');
      return;
    }

    // A second tap while a request is in flight would start a new session
    // (and a new app check). Ignore it.
    if (_otpSending) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _otpErrorCode = null;
      _otpSending = true;
      _otpAutoVerified = false;
    });

    final resendToken = phone == _resendTokenPhone ? _resendToken : null;
    try {
      await ref.read(authRepositoryProvider).verifyPhoneNumber(
        phoneNumber: phone,
        forceResendingToken: resendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Android read the SMS itself (or verified the number instantly).
          // Skip if the typed/autofilled code is already being checked.
          if (!mounted || _otpVerifying) return;
          _otpAutofill.cancel();
          setState(() {
            _otpAutoVerified = true;
            _otpVerifying = true;
            _isLoading = true;
            _otpSending = false;
            if (credential.smsCode != null) _otpController.text = credential.smsCode!;
          });
          try {
            await _applyOtpCredential(credential);
          } on FirebaseAuthException catch (e) {
            debugPrint('[MainLoginScreen] auto-verify failed: ${e.code}');
            if (mounted) {
              setState(() {
                _otpAutoVerified = false;
                _otpErrorCode = e.code;
              });
            }
          } catch (e) {
            debugPrint('[MainLoginScreen] auto-verify failed: $e');
            if (mounted) setState(() => _otpAutoVerified = false);
          } finally {
            if (mounted) {
              setState(() {
                _otpVerifying = false;
                _isLoading = false;
              });
            }
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          String msg = e.message ?? 'Verification failed';
          var switchToPassword = false;
          final msgLower = msg.toLowerCase();
          final code = e.code.toLowerCase();
          debugPrint('[MainLoginScreen] phone verification failed: ${e.code} ${e.message}');
          if (code == 'app-not-authorized' ||
              code == 'invalid-app-credential' ||
              code == 'missing-client-identifier' ||
              msgLower.contains('cert') ||
              msgLower.contains('not authorized') ||
              msgLower.contains('17093')) {
            // Google couldn't verify this phone/app (Play Integrity and the
            // reCAPTCHA fallback both failed). Not something an update fixes,
            // so steer straight to the password step.
            msg = 'We couldn\'t send a text code to this phone right now. Sign in with your password instead.';
            switchToPassword = true;
          } else if (code.startsWith('web-') ||
              code == 'captcha-check-failed' ||
              msgLower.contains('play integrity') ||
              msgLower.contains('recaptcha')) {
            switchToPassword = true;
            msg = 'We couldn\'t verify this phone for a text code. Sign in with your password instead.';
          } else if (msgLower.contains('billing')) {
            msg = 'Text codes are paused right now. Please use your password.';
          } else if (code == 'quota-exceeded' || msgLower.contains('quota')) {
            msg = 'Too many texts sent today. Try again later or sign in with Google.';
          } else if (code == 'invalid-phone-number' || msgLower.contains('invalid-phone-number')) {
            msg = 'Invalid phone number. Please enter a valid number (e.g. 0712 345 678).';
          } else if (code == 'too-many-requests' || msgLower.contains('too-many-requests')) {
            msg = 'Too many attempts. Please wait a few minutes before trying again.';
          } else if (code == 'network-request-failed' || msgLower.contains('network')) {
            msg = 'Network connection error. Please check your internet connection.';
          }
          setState(() {
            _isLoading = false;
            _otpSending = false;
            _otpErrorCode = e.code;
            _errorMessage = msg;
            if (switchToPassword) _selectedExistingAuthMethod = 0;
          });
        },
        codeSent: (String verificationId, int? newResendToken) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _otpSending = false;
            _verificationId = verificationId;
            _resendToken = newResendToken ?? _resendToken;
            _resendTokenPhone = phone;
            _otpWrongAttempts = 0; // fresh code, fresh tries
          });
          // Fills the code from the SMS and submits it (manual entry still works).
          _otpAutofill.restart(_otpController, onCode: _verifyOtpCode);
          _recordTextSend();
          _startResendTimer();
          onSuccess();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _otpSending = false;
        _errorMessage = e.toString();
      });
    }
  }

  /// Uses a verified SMS credential: as the first check (signs in to the
  /// phone's account) or as the second check for the signed-in account.
  Future<void> _applyOtpCredential(PhoneAuthCredential credential) async {
    if (_otpIsSecondFactor) {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return _abandonSignIn();
      if (_hasProvider(user, 'phone')) {
        await user.reauthenticateWithCredential(credential);
      } else {
        try {
          await user.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          // The code was right, but this number is still its own Firebase
          // user (a duplicate made before linking existed). The code proves
          // the number, so it counts as the check; merging the two users
          // needs an admin step (see account_link_service.dart).
          if (e.code != 'credential-already-in-use') rethrow;
          debugPrint('[MainLoginScreen] phone belongs to another uid; flagged for merge');
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'duplicatePhoneAccount': _secondFactorPhone,
          }).catchError((_) {});
        }
      }
      _factors.add(AuthFactor.smsOtp);
      _otpIsSecondFactor = false;
      _flashCheck('Code correct');
      await _continueAfterPrimary();
      return;
    }

    await FirebaseAuth.instance.signInWithCredential(credential);
    _flashCheck('Code correct');
    _factors
      ..clear()
      ..add(AuthFactor.smsOtp);
    _deviceScan = null;
    switch (_currentStep) {
      case AuthScreenStep.forgotPasswordOtp:
        if (mounted) setState(() => _currentStep = AuthScreenStep.resetPassword);
      case AuthScreenStep.newUserOtp:
        await _afterNewUserOtp();
      default:
        await _continueAfterPrimary();
    }
  }

  /// After the registration SMS: a number that already has a profile is an
  /// existing account (never a second one); otherwise build the profile.
  Future<void> _afterNewUserOtp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!mounted) return;
    if (doc.exists) {
      await _continueAfterPrimary();
    } else {
      setState(() => _currentStep = AuthScreenStep.newUserProfile);
    }
  }

  // ── SMS OTP Verify Logic ───────────────────────────────────────────────────
  Future<void> _verifyOtpCode(String code) async {
    if (code.length < 6 || _otpVerifying) return;
    if (_verificationId.isEmpty) {
      setState(() => _errorMessage = 'Request a code first.');
      return;
    }
    if (_codeTriesLeft == 0) {
      setState(() => _errorMessage = 'Too many wrong codes. Tap Resend to get a new one.');
      return;
    }

    setState(() {
      _isLoading = true;
      _otpVerifying = true;
      _errorMessage = null;
      _otpErrorCode = null;
    });

    try {
      final credential = PhoneAuthProvider.credential(verificationId: _verificationId, smsCode: code);
      await _applyOtpCredential(credential);
      _otpWrongAttempts = 0;
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _otpErrorCode = e.code;
          if (e.code == 'invalid-verification-code') _otpWrongAttempts++;
          _errorMessage = null;
        });
      }
      if (e.code == 'invalid-verification-code') {
        ref.read(ovaGuardServiceProvider).reportAuthFailure(_completePhoneNumber, otp: true);
      }
      LoginHistory.instance.recordFailure(
        method: 'smsOtp',
        code: e.code,
        phone: _otpIsSecondFactor ? null : _completePhoneNumber,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'We couldn\'t check that code. Try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _otpVerifying = false);
    }
  }

  // ── Existing User Authentication Actions ───────────────────────────────────
  /// Password as the first check. The password is verified by Firebase Auth
  /// (never by comparing hashes on the phone).
  Future<void> _signInWithPassword() async {
    final password = _passwordController.text;
    if (_cooldownSeconds > 0) return;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: LoginSecurity.authEmailForPhone(_completePhoneNumber),
        password: password,
      );
      _passwordFailures = 0;
      _flashCheck('Password correct');
      _factors
        ..clear()
        ..add(AuthFactor.password);
      _deviceScan = null;
      _passwordController.clear();
      await _continueAfterPrimary();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      const badCredential = {'user-not-found', 'invalid-credential', 'wrong-password', 'invalid-login-credentials', 'invalid-email'};
      if (badCredential.contains(e.code)) {
        // Accounts from older app versions only have a hash in their profile.
        // If it matches, prove the phone once and the password is upgraded.
        final legacy = _identifiedUser != null &&
            _identifiedUser!['authPasswordLinked'] != true &&
            _hasLegacyPassword(_identifiedUser);
        if (legacy && await _legacyPasswordMatches(password, phone: _completePhoneNumber)) {
          _pendingLegacyPassword = password;
          _passwordController.clear();
          _otpController.clear();
          setState(() => _isLoading = false);
          await _sendOtp(onSuccess: () => setState(() => _currentStep = AuthScreenStep.existingUserOtp));
          return;
        }
        if (!legacy) {
          ref.read(ovaGuardServiceProvider).reportAuthFailure(_completePhoneNumber, otp: false);
        }
        LoginHistory.instance.recordFailure(method: 'password', code: e.code, phone: _completePhoneNumber);
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _registerPasswordFailure();
        });
      } else if (e.code == 'too-many-requests') {
        setState(() {
          _isLoading = false;
          _passwordCooldownUntil = DateTime.now().add(const Duration(seconds: 60));
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = e.code == 'network-request-failed'
              ? 'Network connection error. Please check your internet connection.'
              : (e.message ?? 'Sign in failed.');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign in error: $e';
        });
      }
    }
  }

  // ── Forgot Password Actions ────────────────────────────────────────────────
  void _startForgotPasswordFlow() {
    _otpController.clear();
    _otpIsSecondFactor = false;
    _sendOtp(
      onSuccess: () {
        setState(() {
          _currentStep = AuthScreenStep.forgotPasswordOtp;
        });
      },
    );
  }

  /// Runs after the SMS code signed the user in: sets the new password in
  /// Firebase Auth, then continues the normal two-check flow.
  Future<void> _resetPassword() async {
    final newPass = _resetPasswordController.text;
    final confirmPass = _resetConfirmPasswordController.text;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous || !_factors.contains(AuthFactor.smsOtp)) {
      setState(() => _errorMessage = 'Enter the code we texted you first.');
      return;
    }
    if (newPass.length < 8 || OvaAuthCoach.isCommonPassword(newPass)) {
      setState(() => _errorMessage = OvaAuthCoach.newPassword(newPass)?.text ?? 'Use at least 8 characters.');
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _loadAccountProfile(user);
      if (_hasProvider(user, 'password')) {
        await user.updatePassword(newPass);
      } else {
        await user.linkWithCredential(EmailAuthProvider.credential(
          email: LoginSecurity.authEmailForPhone(user.phoneNumber ?? _completePhoneNumber),
          password: newPass,
        ));
      }
      await _scrubLegacyPassword(user);
      _factors.add(AuthFactor.password);
      _resetPasswordController.clear();
      _resetConfirmPasswordController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Password updated.'),
            backgroundColor: AppColors.brandBlue,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
      await _continueAfterPrimary();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = switch (e.code) {
            'weak-password' => 'That password is too weak. Try a longer one.',
            'operation-not-allowed' => 'Password sign-in is not enabled for Oneova yet.',
            'requires-recent-login' => 'Ask for a new text code and try again.',
            _ => e.message ?? 'Failed to reset password.',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to reset password: $e';
        });
      }
    }
  }

  // ── New User Registration Actions ──────────────────────────────────────────
  void _startNewUserRegistrationFlow() {
    _otpController.clear();
    _otpIsSecondFactor = false;
    _sendOtp(
      onSuccess: () {
        setState(() {
          _currentStep = AuthScreenStep.newUserOtp;
        });
      },
    );
  }

  /// Creates the profile for the number verified by SMS. The password is
  /// registered with Firebase Auth (no hash is stored in Firestore), so the
  /// new account starts with two checks: SMS code + password.
  Future<void> _completeRegistration() async {
    final name = _regNameController.text.trim();
    final username = _regUsernameController.text.trim().toLowerCase();
    final password = _regPasswordController.text;
    final recoveryEmail = _regRecoveryEmailController.text.trim();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || user.isAnonymous || !_factors.contains(AuthFactor.smsOtp)) {
      setState(() => _errorMessage = 'Enter the code we texted you first.');
      return;
    }
    if (name.length < 2) {
      setState(() => _errorMessage = 'Please enter your full name or creator name.');
      return;
    }
    if (_usernameCheckResult == null || !_usernameCheckResult!.isValidAndAvailable) {
      setState(() => _errorMessage = _usernameCheckResult?.message ?? 'Please choose a valid and available username.');
      return;
    }
    if (password.length < 8 || OvaAuthCoach.isCommonPassword(password)) {
      setState(() => _errorMessage =
          OvaAuthCoach.newPassword(password, name: name, username: username)?.text ?? 'Use at least 8 characters.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final uid = user.uid;
      final phone = user.phoneNumber ?? _completePhoneNumber;

      // 1. Password -> Firebase Auth
      if (!_hasProvider(user, 'password')) {
        await user.linkWithCredential(
          EmailAuthProvider.credential(email: LoginSecurity.authEmailForPhone(phone), password: password),
        );
      }

      // 2. Claim username
      try {
        await ref.read(oneovaUsernameServiceProvider).claimUsername(uid, username);
      } catch (_) {}

      // 3. Profile in Firestore (no password material)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'displayName': name,
        'username': username,
        'phoneNumber': phone,
        'phone': phone,
        'recoveryEmail': recoveryEmail,
        'role': 'creator',
        'accountType': 'Creator / Influencer',
        'status': 'active',
        'isVerified': false,
        'verifiedBadge': 'none',
        'authPasswordLinked': true,
        'followers': 0,
        'following': 0,
        'bio': 'All you need in your Pocket as a creative',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _factors.add(AuthFactor.password);
      _enrollBiometricAfterSignIn = _regEnableBiometrics;
      _deviceScan = null;
      await _continueAfterPrimary();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = switch (e.code) {
            'weak-password' => 'That password is too weak. Try a longer one.',
            'operation-not-allowed' => 'Password sign-in is not enabled for Oneova yet.',
            'email-already-in-use' || 'credential-already-in-use' =>
              'This number already has a password. Sign in instead.',
            _ => 'Registration failed: ${e.message ?? e.code}',
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Registration failed: $e';
        });
      }
    }
  }

  // ── Handle CTA Tap on Step 1 (Phone Input) ──────────────────────────────────
  void _handlePhoneCtaTap() {
    final phone = _completePhoneNumber;
    final digits = phone.replaceAll(RegExp(r'\D'), '');

    if (phone.isEmpty || digits.length < 7) {
      setState(() => _errorMessage = 'Please enter a valid phone number (e.g. 0712 345 678)');
      return;
    }

    if (_identifiedUser != null) {
      // Existing User Flow
      setState(() {
        _errorMessage = null;
        _currentStep = AuthScreenStep.existingUserAuth;
      });
    } else {
      // New User Flow
      _startNewUserRegistrationFlow();
    }
  }

  // ── Main Build Method ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser != null &&
        !FirebaseAuth.instance.currentUser!.isAnonymous &&
        _currentStep == AuthScreenStep.phoneInput &&
        _isSuccessRedirecting) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
      );
    }

    final isDark = context.isDark;
    final bgColor = context.bg;

    final defaultPinTheme = PinTheme(
      width: 44,
      height: 46,
      textStyle: TextStyle(
        fontSize: 18,
        color: context.textPrimary,
        fontWeight: FontWeight.w800,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: context.border, width: 1.0),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        color: context.surfaceMid,
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: AppColors.brandBlue, width: 1.5),
      borderRadius: BorderRadius.circular(AppRadius.sm),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: context.surfaceMid,
        border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.0),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep == AuthScreenStep.verificationSuccess) {
          return;
        }
        if (_currentStep != AuthScreenStep.phoneInput) {
          setState(() {
            _currentStep = AuthScreenStep.phoneInput;
            _errorMessage = null;
          });
        } else {
          if (Navigator.of(context).canPop()) {
            context.pop();
          } else {
            context.go('/hub/home');
          }
        }
      },
      child: Scaffold(
        backgroundColor: bgColor,
        body: SafeArea(
          child: Column(
            children: [
              _buildTopNavBar(),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Logo until an account is found, then that person's photo
                          _buildHero().animate().fade(duration: 300.ms),
                          const SizedBox(height: 14),

                          // Error Banner
                          if (_errorMessage != null) ...[
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 360),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                  border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.error,
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => setState(() => _errorMessage = null),
                                      child: Padding(
                                        padding: const EdgeInsets.only(left: 6),
                                        child: Icon(Icons.close_rounded, color: Theme.of(context).colorScheme.error, size: 15),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ).animate().fade().slideY(begin: -0.1, end: 0, duration: 200.ms),
                            const SizedBox(height: 10),
                          ],

                          // Core Form Container — Executive Dual-Mode Surface
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Container(
                              decoration: BoxDecoration(
                                color: context.surface,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                border: Border.all(color: context.border, width: 1.0),
                                boxShadow: isDark
                                    ? [
                                        BoxShadow(
                                          color: AppColors.brandBlue.withValues(alpha: 0.16),
                                          blurRadius: 18,
                                          spreadRadius: 0,
                                          offset: const Offset(0, 4),
                                        ),
                                      ]
                                    : AppShadows.sm,
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Deep Sapphire & Pink accent hairline bar
                                    Container(
                                      height: 2.5,
                                      width: double.infinity,
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [AppColors.brandBlue, AppColors.brandPink],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 260),
                                        switchInCurve: Curves.easeOutCubic,
                                        switchOutCurve: Curves.easeInCubic,
                                        transitionBuilder: (child, animation) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position: Tween<Offset>(
                                                begin: const Offset(0.04, 0),
                                                end: Offset.zero,
                                              ).animate(animation),
                                              child: child,
                                            ),
                                          );
                                        },
                                        child: KeyedSubtree(
                                          key: ValueKey(_currentStep),
                                          child: _buildCurrentStepView(defaultPinTheme, focusedPinTheme, submittedPinTheme),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ).animate().fade(delay: 350.ms).slideY(begin: 0.08, end: 0, duration: 300.ms),

                          const SizedBox(height: 14),

                          if (_currentStep == AuthScreenStep.phoneInput) ...[
                          // Social Proof (Live Creators)
                          _buildSocialProof().animate().fade(delay: 450.ms),

                          const SizedBox(height: 12),

                          // Brand Logos
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildBrandLogo(FontAwesomeIcons.youtube),
                              const SizedBox(width: 20),
                              _buildBrandLogo(FontAwesomeIcons.instagram),
                              const SizedBox(width: 20),
                              _buildBrandLogo(FontAwesomeIcons.tiktok),
                            ],
                          ).animate().fade(delay: 550.ms),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopNavBar() {
    if (_currentStep == AuthScreenStep.verificationSuccess) {
      return const SizedBox(height: 12);
    }
    final canGoBackInSteps = _currentStep != AuthScreenStep.phoneInput;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TactileScaleTap(
            onTap: () {
              HapticFeedback.lightImpact();
              if (_currentStep != AuthScreenStep.phoneInput) {
                setState(() {
                  _currentStep = AuthScreenStep.phoneInput;
                  _errorMessage = null;
                });
              } else {
                if (Navigator.of(context).canPop()) {
                  context.pop();
                } else {
                  context.go('/hub/home');
                }
              }
            },
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 13,
                    color: context.textPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    canGoBackInSteps ? 'Back' : 'Feed',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.brandBlue),
                const SizedBox(width: 5),
                Text(
                  '256-Bit SSL Secured',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Dynamic Step View Switcher ─────────────────────────────────────────────
  Widget _buildCurrentStepView(
    PinTheme defaultPinTheme,
    PinTheme focusedPinTheme,
    PinTheme submittedPinTheme,
  ) {
    switch (_currentStep) {
      case AuthScreenStep.phoneInput:
        return _buildPhoneEntry();
      case AuthScreenStep.existingUserAuth:
        return _buildExistingUserAuth(defaultPinTheme, focusedPinTheme, submittedPinTheme);
      case AuthScreenStep.existingUserOtp:
        return _buildOtpEntry(
          title: 'Enter the code',
          subtitle: 'We texted a 6-digit code to',
          targetPhone: _completePhoneNumber,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          onVerify: _verifyOtpCode,
          onBack: () => setState(() => _currentStep = AuthScreenStep.existingUserAuth),
        );
      case AuthScreenStep.forgotPasswordOtp:
        return _buildOtpEntry(
          title: 'Reset your password',
          subtitle: 'We texted a 6-digit code to',
          targetPhone: _completePhoneNumber,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          onVerify: _verifyOtpCode,
          onBack: () => setState(() => _currentStep = AuthScreenStep.existingUserAuth),
        );
      case AuthScreenStep.resetPassword:
        return _buildResetPasswordView();
      case AuthScreenStep.newUserOtp:
        return _buildOtpEntry(
          title: 'Enter the code',
          subtitle: 'We texted a 6-digit code to',
          targetPhone: _completePhoneNumber,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          onVerify: _verifyOtpCode,
          onBack: () => setState(() => _currentStep = AuthScreenStep.phoneInput),
        );
      case AuthScreenStep.newUserProfile:
        return _buildNewUserProfileView();
      case AuthScreenStep.secondFactor:
        return _buildSecondFactorView(defaultPinTheme, focusedPinTheme, submittedPinTheme);
      case AuthScreenStep.verificationSuccess:
        return _buildVerificationSuccessView();
    }
  }

  // ── Verification Success Visual Screen ─────────────────────────────────────
  Widget _buildVerificationSuccessView() {
    final phone = _completePhoneNumber.isNotEmpty
        ? _completePhoneNumber
        : (_identifiedUser?['phoneNumber'] ?? _identifiedUser?['phone'] ?? 'Authenticated');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Glowing Animated Checkmark Badge ──────────────────────────────
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [AppColors.brandBlue, AppColors.brandPink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandBlue.withValues(alpha: 0.45),
                    blurRadius: 28,
                    spreadRadius: 4,
                  ),
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Center(
                child: Icon(
                  Icons.verified_rounded,
                  size: 46,
                  color: Colors.white,
                ),
              ),
            )
                .animate()
                .scale(duration: const Duration(milliseconds: 450), curve: Curves.elasticOut)
                .shimmer(duration: const Duration(milliseconds: 1000)),
            const SizedBox(height: 20),

            // ── Headline & Message ────────────────────────────────────────────
            Text(
              _successHeadline,
              style: GoogleFonts.inter(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: context.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            Text(
              _successMessage,
              style: GoogleFonts.inter(
                fontSize: 13.0,
                fontWeight: FontWeight.w500,
                color: context.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // ── Phone / Account Status Pill ───────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981), // Emerald verified green
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    phone.isNotEmpty ? 'Phone checked • $phone' : 'All checks done',
                    style: GoogleFonts.inter(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),

            // ── Animated Loading Progress Indicator ───────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Directing to For You Feed',
                        style: GoogleFonts.inter(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimary,
                        ),
                      ),
                      Text(
                        'Auto-play ready',
                        style: GoogleFonts.inter(
                          fontSize: 11.0,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandBlue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    child: const LinearProgressIndicator(
                      minHeight: 4,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandBlue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Immediate Continue CTA ─────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 40,
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _successRedirectTimer?.cancel();
                  _onSuccessContinue?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Continue to Feed',
                      style: GoogleFonts.inter(
                        fontSize: 13.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded, size: 15),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 1. STEP: Phone Input & Real-Time Auto-Identification
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildPhoneEntry() {
    final displayName = _identifiedUser?['displayName'] as String? ?? 'Creator';
    final firstName = displayName.trim().split(' ').first;

    String ctaButtonText;
    if (_identifiedUser != null) {
      ctaButtonText = 'Continue as $firstName →';
    } else if (_userChecked && _completePhoneNumber.length >= 8) {
      ctaButtonText = 'Create Free Account →';
    } else {
      ctaButtonText = 'Continue →';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bioQuickAccount != null) ...[
          _buildBiometricQuickCard(_bioQuickAccount!),
          OvaInlineHint(_bioHint),
          const SizedBox(height: 14),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Sign In or Join',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15.5,
                color: context.textPrimary,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
              decoration: BoxDecoration(
                color: AppColors.brandPink,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.35),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Text(
                'STUDIO',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Enter your mobile number to identify your account or register.',
          style: TextStyle(
            color: context.textSecondary,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),

        // ── 1-Tap Quick Account Recognition (Device Memory) ─────────────────
        if (_rememberedAccount != null && _identifiedUser == null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1.0),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      (_rememberedAccount!.displayName?.isNotEmpty == true
                              ? _rememberedAccount!.displayName![0]
                              : 'O')
                          .toUpperCase(),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _rememberedAccount!.displayName ?? 'Welcome Back',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.verified_rounded, size: 13, color: AppColors.brandBlue),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '@${_rememberedAccount!.username ?? 'creator'} • ${_rememberedAccount!.phoneE164}',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _applyRememberedAccount(_rememberedAccount!),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '1-Tap',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(width: 3),
                        Icon(Icons.bolt_rounded, size: 14, color: AppColors.brandPink),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Smart Phone Field ────────────────────────────────────────────────
        IntlPhoneField(
          key: ValueKey('phone_field_$_selectedCountryIso'),
          controller: _phoneController,
          initialCountryCode: _selectedCountryIso,
          disableLengthCheck: true,
          keyboardType: TextInputType.phone,
          cursorColor: AppColors.brandBlue,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-\+\(\)]')),
          ],
          decoration: InputDecoration(
            hintText: _formatHint,
            hintStyle: TextStyle(
              color: context.textMuted,
              fontSize: 12.0,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: context.surfaceMid,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
              borderSide: const BorderSide(
                color: AppColors.brandBlue,
                width: 1.5,
              ),
            ),
            counterText: '',
          ),
          dropdownIcon: Icon(
            Icons.arrow_drop_down_rounded,
            color: context.textSecondary,
          ),
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
          onChanged: (phone) {
            if (phone.countryCode != _selectedDialCode) {
              final meta = _phoneEngine.findByDialCode(phone.countryCode);
              if (meta != null && meta != _selectedCountryMeta) {
                setState(() {
                  _selectedCountryMeta = meta;
                  _selectedCountryIso = meta.isoCode;
                  _formatHint = meta.formatHint;
                });
              }
            }
          },
          onCountryChanged: (country) {
            final meta = _phoneEngine.findByIso(country.code);
            setState(() {
              _selectedCountryIso = country.code;
              _selectedCountryMeta = meta;
              _formatHint = meta.formatHint;
            });
            _onPhoneTextChanged();
          },
          onSubmitted: (_) => _handlePhoneCtaTap(),
        ),

        // Format helper hint
        Padding(
          padding: const EdgeInsets.only(top: 3, left: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_selectedCountryMeta.flagEmoji} ${_selectedCountryMeta.formatHint}',
                style: TextStyle(
                  color: context.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_isCheckingUser)
                Row(
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.brandBlue),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Looking…',
                      style: TextStyle(color: context.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
            ],
          ),
        ),

        // ── Real-Time Account Preview Card ───────────────────────────────────
        if (_identifiedUser != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.brandBlue),
              const SizedBox(width: 5),
              Text('Account found', style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ] else if (_userChecked && _completePhoneNumber.length >= 8) ...[
          const SizedBox(height: 8),
          _buildNewUserHint(),
        ],

        const SizedBox(height: 12),

        // ── Dynamic Continue CTA Button (Deep Executive Sapphire) ─────────────
        _TactileScaleTap(
          onTap: _isLoading ? null : _handlePhoneCtaTap,
          child: Container(
            width: double.infinity,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.brandBlue,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brandBlue.withValues(alpha: 0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _isLoading
                ? const Center(
                    child: SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _identifiedUser != null ? Icons.verified_user_rounded : Icons.arrow_forward_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ctaButtonText,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: Divider(color: context.border, thickness: 1)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'OR',
                style: TextStyle(
                  color: context.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Expanded(child: Divider(color: context.border, thickness: 1)),
          ],
        ),
        const SizedBox(height: 10),

        // Social Buttons
        Row(
          children: [
            _buildSocialLoginButton(
              icon: SvgPicture.asset('assets/google_logo.svg', width: 16, height: 16),
              label: 'Google',
              onTap: _signInWithGoogle,
            ),
            const SizedBox(width: 8),
            _buildSocialLoginButton(
              icon: const FaIcon(FontAwesomeIcons.tiktok, size: 15, color: Colors.white),
              label: 'TikTok',
              onTap: _signInWithTikTok,
            ),
            const SizedBox(width: 8),
            _buildSocialLoginButton(
              icon: SvgPicture.asset('assets/logos/facebook.svg', width: 16, height: 16),
              label: 'Facebook',
              onTap: _signInWithFacebook,
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Guest Explorer Option
        _TactileScaleTap(
          onTap: _isLoading ? null : _exploreAsGuest,
          child: Container(
            width: double.infinity,
            height: 36,
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.explore_rounded, color: context.textSecondary, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Explore Oneova as Guest',
                  style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Identified User Preview Card ───────────────────────────────────────────
  /// One-tap fingerprint re-login for the account enrolled on this device.
  Widget _buildBiometricQuickCard(String account) {
    return Material(
      color: AppColors.brandBlue.withValues(alpha: context.isDark ? 0.16 : 0.07),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: _isLoading ? null : _unlockWithBiometrics,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.35), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(color: AppColors.brandBlue, shape: BoxShape.circle),
                child: const Icon(Icons.fingerprint_rounded, color: AppColors.brandWhite, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Continue with fingerprint',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                    const SizedBox(height: 2),
                    Text(account,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: context.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.brandBlue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInitialsAvatar(String name) {
    final initials = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : 'O';
    return Container(
      color: AppColors.brandBlue,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 26,
        ),
      ),
    );
  }

  // ── New User Subtle Registration Hint ──────────────────────────────────────
  Widget _buildNewUserHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_alt_1_rounded, size: 14, color: AppColors.brandPink),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'New Account: Tap Next to register in seconds',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ).animate().fade(duration: 250.ms);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 2. STEP: Multi-Option Authentication for Existing Users
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildExistingUserAuth(
    PinTheme defaultPinTheme,
    PinTheme focusedPinTheme,
    PinTheme submittedPinTheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back to phone input row
        Row(
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _errorMessage = null;
                  _currentStep = AuthScreenStep.phoneInput;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Not you? Change number',
              style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Prominent Biometric Shortcut if supported
        if (_isBiometricsAvailable) ...[
          SizedBox(
            width: double.infinity,
            height: 38,
            child: OutlinedButton.icon(
              onPressed: _isLoading ? null : _unlockWithBiometrics,
              icon: const Icon(Icons.fingerprint_rounded, color: AppColors.brandPink, size: 18),
              label: Text(
                'Use ${_biometricTypeLabel.split(' /').first.toLowerCase()}',
                style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: context.surfaceMid,
                side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.5), width: 1.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
          ),
          OvaInlineHint(_bioHint),
          const SizedBox(height: 10),
        ],

        // Method Selector Tabs
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              _buildAuthTab(0, 'Password', Icons.lock_outline_rounded),
              _buildAuthTab(1, 'Text code', Icons.sms_outlined),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Content according to selected auth method
        if (_selectedExistingAuthMethod == 0) ...[
          // Option A: Password (then SMS on a new device)
          _buildPasswordInputSection(),
        ] else ...[
          // Option B: SMS code (then password or fingerprint)
          _buildSmsOtpRequestSection(),
        ],
        const SizedBox(height: 10),
        _buildTwoCheckNotice(),
      ],
    );
  }

  Widget _buildAuthTab(int index, String label, IconData icon) {
    final isSelected = _selectedExistingAuthMethod == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _errorMessage = null;
          _selectedExistingAuthMethod = index;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xs),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isSelected ? Colors.white : context.textSecondary, size: 13),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textSecondary,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-view: Password Entry ───────────────────────────────────────────────
  Widget _buildPasswordInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          cursorColor: AppColors.brandBlue,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: context.textMuted, fontSize: 12.0),
            filled: true,
            fillColor: context.surfaceMid,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
            prefixIcon: Icon(Icons.key_rounded, color: context.textSecondary, size: 16),
            suffixIcon: IconButton(
              icon: Icon(
                _passwordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: context.textSecondary,
                size: 18,
              ),
              onPressed: () => setState(() => _passwordVisible = !_passwordVisible),
            ),
          ),
          onSubmitted: (_) => _signInWithPassword(),
        ),
        OvaInlineHint(OvaAuthCoach.signInPassword(
          _passwordController.text,
          hardwareCapsLock: _hardwareCapsLock,
          failedAttempts: _passwordFailures,
          cooldownSeconds: _cooldownSeconds,
        )),
        _buildPasswordCounters(),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _isLoading ? null : _startForgotPasswordFlow,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(40, 22),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Forgot password?',
              style: TextStyle(
                color: AppColors.brandPink,
                fontWeight: FontWeight.w700,
                fontSize: 11.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _isLoading || _cooldownSeconds > 0 ? null : _signInWithPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: _isLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Continue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ── Sub-view: SMS OTP Request ──────────────────────────────────────────────
  Widget _buildSmsOtpRequestSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              const Icon(Icons.sms_rounded, color: AppColors.brandPink, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'We\'ll text a 6-digit code to $_completePhoneNumber',
                  style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () {
                    _otpController.clear();
                    _sendOtp(
                      onSuccess: () => setState(() => _currentStep = AuthScreenStep.existingUserOtp),
                    );
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: _isLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Text me a code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Header: Oneova logo until an account is found, then that person's photo,
  // name and the one thing to do next.
  // ───────────────────────────────────────────────────────────────────────────
  ({String name, String? photo, String? handle})? get _foundAccount {
    final p = _legacyProfile ?? _identifiedUser;
    if (p != null) {
      final name = (p['displayName'] ?? p['name'] ?? 'Oneova member').toString();
      final photo = (p['photoUrl'] ?? p['avatarUrl'])?.toString();
      return (name: name, photo: (photo == null || photo.isEmpty) ? null : photo, handle: p['username']?.toString());
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous && _currentStep != AuthScreenStep.phoneInput) {
      return (name: user.displayName ?? 'Your account', photo: user.photoURL, handle: null);
    }
    return null;
  }

  int get _checksDone => _factors.where((f) => f != AuthFactor.trustedDevice).length;

  String _heroCaption() {
    switch (_currentStep) {
      case AuthScreenStep.phoneInput:
        return _identifiedUser != null ? 'Good to see you again' : 'All you need in your Pocket as a creative';
      case AuthScreenStep.existingUserAuth:
        return 'How do you want to sign in?';
      case AuthScreenStep.existingUserOtp:
      case AuthScreenStep.forgotPasswordOtp:
      case AuthScreenStep.newUserOtp:
        return 'Check your messages';
      case AuthScreenStep.resetPassword:
        return 'Make a new password';
      case AuthScreenStep.newUserProfile:
        return 'Set up your profile';
      case AuthScreenStep.secondFactor:
        if (_scanningDevice) return 'Checking this phone…';
        return switch (_requiredFactor) {
          AuthFactor.smsOtp => 'One more step: the code we texted you',
          AuthFactor.password => _accountHasPassword ? 'One more step: your password' : 'One more step: create a password',
          AuthFactor.biometric => 'One more step: your fingerprint',
          AuthFactor.pin => 'One more step: your PIN',
          _ => 'One more step',
        };
      case AuthScreenStep.verificationSuccess:
        return 'You\'re in';
    }
  }

  Widget _buildHero() {
    final account = _foundAccount;
    final success = _currentStep == AuthScreenStep.verificationSuccess;
    final showSteps = !success &&
        (_currentStep == AuthScreenStep.secondFactor || _currentStep == AuthScreenStep.existingUserAuth || _checksDone > 0);

    final Widget top;
    if (account == null) {
      top = Column(
        key: const ValueKey('logo'),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/images/oneova_logo.jpg', width: 44, height: 44, fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
            'ONEOVA',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2.0, color: context.textPrimary),
          ),
        ],
      );
    } else {
      final firstName = account.name.trim().split(RegExp(r'\s+')).first;
      top = Column(
        key: ValueKey('acct-${account.name}'),
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.brandBlue, AppColors.brandPink],
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: context.bg, shape: BoxShape.circle),
                    child: ClipOval(
                      child: account.photo != null
                          ? Image.network(
                              account.photo!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => _buildInitialsAvatar(account.name),
                            )
                          : _buildInitialsAvatar(account.name),
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(success),
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: success ? AppColors.brandBlue : context.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: success ? AppColors.brandBlue : context.border, width: 1.5),
                      ),
                      child: Icon(
                        success ? Icons.check_rounded : Icons.lock_rounded,
                        size: 13,
                        color: success ? Colors.white : AppColors.brandBlue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            success ? 'Welcome, $firstName' : 'Hi, $firstName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: context.textPrimary),
          ),
          if (account.handle != null && account.handle!.isNotEmpty)
            Text('@${account.handle}',
                style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ],
      );
    }

    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: child),
          ),
          child: top,
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: Text(
            _heroCaption(),
            key: ValueKey(_heroCaption()),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        if (showSteps) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 2; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i < _checksDone ? 22 : 8,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i < _checksDone ? AppColors.brandBlue : context.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 6),
              Text(
                'Step ${(_checksDone + 1).clamp(1, 2)} of 2',
                style: TextStyle(color: context.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// Small pop-up confirming each finished step.
  void _flashCheck(String text) {
    if (!mounted) return;
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 1300),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
        margin: const EdgeInsets.fromLTRB(48, 0, 48, 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ));
  }

  /// PIN as a check: only the PIN set on this phone by this same account.
  Future<void> _runPinFactor() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _abandonSignIn();
    if (!await ref.read(pinAuthServiceProvider).isPinOwnedBy(user.uid)) {
      setState(() => _bioHint = const OvaHint('No PIN is set for this account on this phone.', OvaHintTone.warning));
      return;
    }
    if (!mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const OneovaPinScreen(mode: PinScreenMode.verify)),
    );
    if (!mounted) return;
    if (ok == true) {
      _flashCheck('PIN correct');
      _factors.add(AuthFactor.pin);
      await _continueAfterPrimary();
    } else {
      setState(() => _bioHint = const OvaHint('PIN not confirmed. Try again or pick another way.', OvaHintTone.warning));
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Second check ("One more check") — what LoginSecurity still needs
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildTwoCheckNotice() {
    return Row(
      children: [
        const Icon(Icons.shield_rounded, size: 13, color: AppColors.brandBlue),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            'For your safety we always ask for 2 steps. A new phone also gets a text code.',
            style: TextStyle(color: context.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _factorChip(String label, IconData icon, bool done) {
    final color = done ? AppColors.brandBlue : context.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: done ? AppColors.brandBlue.withValues(alpha: 0.10) : context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: done ? AppColors.brandBlue.withValues(alpha: 0.4) : context.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(done ? Icons.check_circle_rounded : icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildSecondFactorView(
    PinTheme defaultPinTheme,
    PinTheme focusedPinTheme,
    PinTheme submittedPinTheme,
  ) {
    final required = _requiredFactor;
    final scan = _deviceScan;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (_factors.contains(AuthFactor.password) || required == AuthFactor.password)
              _factorChip('Password', Icons.key_rounded, _factors.contains(AuthFactor.password)),
            if (_factors.contains(AuthFactor.smsOtp) || required == AuthFactor.smsOtp)
              _factorChip('Text code', Icons.sms_rounded, _factors.contains(AuthFactor.smsOtp)),
            if (_factors.contains(AuthFactor.federated))
              _factorChip('Google/Facebook', Icons.public_rounded, true),
            if (_factors.contains(AuthFactor.deviceKey))
              _factorChip('Saved on this phone', Icons.vpn_key_rounded, true),
            if (_factors.contains(AuthFactor.biometric) || required == AuthFactor.biometric)
              _factorChip('Fingerprint', Icons.fingerprint_rounded, _factors.contains(AuthFactor.biometric)),
            if (_factors.contains(AuthFactor.pin) || required == AuthFactor.pin)
              _factorChip('PIN', Icons.pin_rounded, _factors.contains(AuthFactor.pin)),
            _factorChip('Known phone', Icons.phonelink_lock_rounded, scan?.trusted == true && scan!.isPhysicalDevice),
          ],
        ),
        OvaInlineHint(OvaAuthCoach.device(
          scanning: _scanningDevice || scan == null,
          trusted: scan?.trusted,
          label: scan?.label,
          isPhysical: scan?.isPhysicalDevice ?? true,
        )),
        const SizedBox(height: 12),
      ],
    );

    Widget body;
    switch (required) {
      case AuthFactor.smsOtp:
        final phone = _secondFactorPhone;
        if (phone != null && _verificationId.isEmpty && !_otpSending) {
          body = Column(
            children: [
              _primaryButton(
                'Text me a code',
                Icons.sms_rounded,
                () => _sendOtp(onSuccess: () => setState(() {}), phoneOverride: phone),
              ),
              OvaInlineHint(OvaHint('We\'ll text a 6-digit code to ${OvaAuthCoach.maskPhone(phone)}.')),
            ],
          );
        } else if (phone == null) {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add your phone number so we can text you a code.',
                  style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                cursorColor: AppColors.brandBlue,
                style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: '$_selectedDialCode $_formatHint',
                  hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: context.surfaceMid,
                  isDense: true,
                  prefixIcon: Icon(Icons.phone_rounded, color: context.textSecondary, size: 16),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () => _sendOtp(onSuccess: () => setState(() {}), phoneOverride: _completePhoneNumber),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: const Text('Text me a code', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          );
        } else {
          body = _buildOtpEntry(
            title: 'Enter the code',
            subtitle: scan?.trusted == true ? 'We texted a 6-digit code to' : 'New phone — we texted a 6-digit code to',
            targetPhone: phone,
            defaultPinTheme: defaultPinTheme,
            focusedPinTheme: focusedPinTheme,
            submittedPinTheme: submittedPinTheme,
            onVerify: _verifyOtpCode,
            onBack: _abandonSignIn,
          );
        }
      case AuthFactor.password:
        body = _accountHasPassword ? _buildSecondPasswordSection() : _buildCreatePasswordSection();
      case AuthFactor.pin:
        body = Column(
          children: [
            _primaryButton('Enter your PIN', Icons.pin_rounded, _runPinFactor),
            OvaInlineHint(_bioHint ?? const OvaHint('Use the PIN you set for this account on this phone.')),
            if (_biometricReadyForUser)
              TextButton(
                onPressed: _isLoading ? null : () => setState(() => _requiredFactor = AuthFactor.biometric),
                child: const Text('Use fingerprint instead',
                    style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
            if (_accountHasPassword && !_factors.contains(AuthFactor.password))
              TextButton(
                onPressed: _isLoading ? null : () => setState(() => _requiredFactor = AuthFactor.password),
                child: const Text('Use password instead',
                    style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
              ),
          ],
        );
      case AuthFactor.biometric:
        body = Column(
          children: [
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _runBiometricFactor,
                icon: const Icon(Icons.fingerprint_rounded, size: 20, color: Colors.white),
                label: const Text('Touch to use fingerprint',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
              ),
            ),
            OvaInlineHint(_bioHint ??
                OvaAuthCoach.biometric(available: _isBiometricsAvailable, enrolledOnDevice: _biometricReadyForUser)),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [
                if (_accountHasPassword && !_factors.contains(AuthFactor.password))
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => setState(() {
                              _requiredFactor = AuthFactor.password;
                              _errorMessage = null;
                            }),
                    child: const Text('Use password instead',
                        style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                if (_pinReadyForUser && !_factors.contains(AuthFactor.pin))
                  TextButton(
                    onPressed: _isLoading ? null : _runPinFactor,
                    child: const Text('Use PIN instead',
                        style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                if (!_factors.contains(AuthFactor.smsOtp) && _secondFactorPhone != null)
                  TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _requiredFactor = AuthFactor.smsOtp;
                              _otpIsSecondFactor = true;
                              _otpController.clear();
                            });
                            _sendOtp(onSuccess: () {}, phoneOverride: _secondFactorPhone);
                          },
                    child: const Text('Text me a code instead',
                        style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ],
        );
      default:
        body = const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        header,
        body,
        const SizedBox(height: 6),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _abandonSignIn,
            child: Text('Not you? Use another account',
                style: TextStyle(color: context.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String hint,
    required bool visible,
    required VoidCallback onToggle,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: !visible,
      cursorColor: AppColors.brandBlue,
      onChanged: (_) => setState(() {}),
      onSubmitted: onSubmitted,
      style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: context.textMuted, fontSize: 12.0),
        filled: true,
        fillColor: context.surfaceMid,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
        prefixIcon: Icon(Icons.key_rounded, color: context.textSecondary, size: 16),
        suffixIcon: IconButton(
          icon: Icon(visible ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: context.textSecondary, size: 18),
          onPressed: onToggle,
        ),
      ),
    );
  }

  Widget _primaryButton(String label, IconData icon, VoidCallback? onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 40,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brandBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        ),
        child: _isLoading
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
      ),
    );
  }

  Widget _buildSecondPasswordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Type your Oneova password.',
            style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _passwordField(
          controller: _secondPasswordController,
          hint: 'Password',
          visible: _passwordVisible,
          onToggle: () => setState(() => _passwordVisible = !_passwordVisible),
          onSubmitted: (v) => _verifySecondFactorPassword(v),
        ),
        OvaInlineHint(OvaAuthCoach.signInPassword(
          _secondPasswordController.text,
          hardwareCapsLock: _hardwareCapsLock,
          failedAttempts: _passwordFailures,
          cooldownSeconds: _cooldownSeconds,
        )),
        _buildPasswordCounters(),
        if (_factors.contains(AuthFactor.smsOtp))
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _errorMessage = null;
                        _currentStep = AuthScreenStep.resetPassword;
                      }),
              child: const Text('Forgot password?',
                  style: TextStyle(color: AppColors.brandPink, fontWeight: FontWeight.w700, fontSize: 11.5)),
            ),
          )
        else
          const SizedBox(height: 10),
        _primaryButton(
          'Continue',
          Icons.lock_open_rounded,
          _cooldownSeconds > 0 ? null : () => _verifySecondFactorPassword(_secondPasswordController.text),
        ),
        if (_biometricReadyForUser && _deviceScan?.trusted == true && !_factors.contains(AuthFactor.biometric))
          Center(
            child: TextButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => setState(() {
                        _requiredFactor = AuthFactor.biometric;
                        _errorMessage = null;
                      }),
              icon: const Icon(Icons.fingerprint_rounded, size: 16, color: AppColors.brandPink),
              label: const Text('Use fingerprint instead',
                  style: TextStyle(color: AppColors.brandPink, fontSize: 11.5, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
    );
  }

  Widget _buildCreatePasswordSection() {
    final user = FirebaseAuth.instance.currentUser;
    final strength = _calculatePasswordStrength(_createPasswordController.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Make a password. Next time you\'ll use it with your text code.',
            style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _passwordField(
          controller: _createPasswordController,
          hint: 'New password (8+ characters)',
          visible: _resetPasswordVisible,
          onToggle: () => setState(() => _resetPasswordVisible = !_resetPasswordVisible),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: strength == 0 ? 0.05 : strength / 4.0,
            backgroundColor: context.border,
            valueColor: AlwaysStoppedAnimation<Color>(_getPasswordStrengthColor(strength)),
            minHeight: 3,
          ),
        ),
        OvaInlineHint(OvaAuthCoach.newPassword(
          _createPasswordController.text,
          name: _legacyProfile?['displayName'] as String?,
          username: _legacyProfile?['username'] as String?,
          phone: user?.phoneNumber,
          hardwareCapsLock: _hardwareCapsLock,
        )),
        const SizedBox(height: 8),
        _passwordField(
          controller: _createConfirmController,
          hint: 'Confirm password',
          visible: _resetConfirmPasswordVisible,
          onToggle: () => setState(() => _resetConfirmPasswordVisible = !_resetConfirmPasswordVisible),
          onSubmitted: (_) => _createPasswordFactor(),
        ),
        if (_createConfirmController.text.isNotEmpty)
          OvaInlineHint(_createConfirmController.text == _createPasswordController.text
              ? const OvaHint('Passwords match.', OvaHintTone.success)
              : const OvaHint('Passwords don\'t match yet.', OvaHintTone.warning)),
        const SizedBox(height: 12),
        _primaryButton('Save password & continue', Icons.lock_rounded, _createPasswordFactor),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Shared OTP Entry Component (Used for Login, Forgot Password, and New User)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildOtpEntry({
    required String title,
    required String subtitle,
    required String targetPhone,
    required PinTheme defaultPinTheme,
    required PinTheme focusedPinTheme,
    required PinTheme submittedPinTheme,
    required Function(String) onVerify,
    required VoidCallback onBack,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.brandBlue.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.brandBlue.withValues(alpha: 0.15),
                blurRadius: 8,
              ),
            ],
          ),
          child: const Icon(Icons.message_rounded, color: AppColors.brandBlue, size: 22),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          targetPhone,
          style: const TextStyle(color: AppColors.brandBlue, fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),

        // Pinput 6-digit entry
        Pinput(
          controller: _otpController,
          length: 6,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
          showCursor: true,
          autofocus: true,
          forceErrorState: _otpErrorCode == 'invalid-verification-code',
          onChanged: (_) => setState(() {
            if (_otpErrorCode == 'invalid-verification-code') _otpErrorCode = null;
          }),
          onCompleted: (pin) => onVerify(pin),
        ),
        OvaInlineHint(
          OvaAuthCoach.otp(
            phone: targetPhone,
            code: _otpController.text,
            resendSeconds: _resendTimeout,
            sending: _otpSending,
            verifying: _otpVerifying,
            autoVerified: _otpAutoVerified,
            errorCode: _otpErrorCode,
            wrongAttempts: _otpWrongAttempts,
          ),
          padding: const EdgeInsets.only(top: 8),
        ),
        const SizedBox(height: 8),
        _buildCodeCounters(),

        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () => onVerify(_otpController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: _isLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Continue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Didn't receive code? ", style: TextStyle(color: context.textSecondary, fontSize: 11.5)),
            TextButton(
              onPressed: _canResend && !_isLoading && _textsLeft > 0
                  ? () {
                      _otpController.clear();
                      _sendOtp(onSuccess: () {}, phoneOverride: targetPhone);
                    }
                  : null,
              child: Text(
                _canResend ? 'Resend' : 'Resend in ${_clock(_resendTimeout)}',
                style: TextStyle(
                  color: _canResend ? AppColors.brandPink : context.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Reset Password View
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildResetPasswordView() {
    final strength = _calculatePasswordStrength(_resetPasswordController.text);
    final strengthLabel = _getPasswordStrengthLabel(strength);
    final strengthColor = _getPasswordStrengthColor(strength);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _currentStep = AuthScreenStep.existingUserAuth),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 16),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'New password',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Pick a new password you haven\'t used before.',
          style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 12),

        // New Password field
        TextField(
          controller: _resetPasswordController,
          obscureText: !_resetPasswordVisible,
          cursorColor: AppColors.brandBlue,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'New password (8+ characters)',
            hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
            filled: true,
            fillColor: context.surfaceMid,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
            suffixIcon: IconButton(
              icon: Icon(
                _resetPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: context.textSecondary,
                size: 18,
              ),
              onPressed: () => setState(() => _resetPasswordVisible = !_resetPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // Strength Bar
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: strength == 0 ? 0.05 : strength / 4.0,
                  backgroundColor: context.border,
                  valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                  minHeight: 3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(color: strengthColor, fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        OvaInlineHint(OvaAuthCoach.newPassword(
          _resetPasswordController.text,
          phone: _completePhoneNumber,
          hardwareCapsLock: _hardwareCapsLock,
        )),
        const SizedBox(height: 8),

        // Confirm Password field
        TextField(
          controller: _resetConfirmPasswordController,
          obscureText: !_resetConfirmPasswordVisible,
          cursorColor: AppColors.brandBlue,
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Confirm New Password',
            hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
            filled: true,
            fillColor: context.surfaceMid,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
            suffixIcon: IconButton(
              icon: Icon(
                _resetConfirmPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: context.textSecondary,
                size: 18,
              ),
              onPressed: () => setState(() => _resetConfirmPasswordVisible = !_resetConfirmPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _resetPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            child: _isLoading
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_reset_rounded, size: 15, color: Colors.white),
                      SizedBox(width: 6),
                      Text('Save & continue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // ───────────────────────────────────────────────────────────────────────────
  // 3. STEP: Fast Mobile Registration Profile Setup (Max 2 inputs per micro-view)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildNewUserProfileView() {
    final strength = _calculatePasswordStrength(_regPasswordController.text);
    final strengthLabel = _getPasswordStrengthLabel(strength);
    final strengthColor = _getPasswordStrengthColor(strength);

    if (_newUserSubStep == 0) {
      // ── Micro-Step 1 of 2: Creator Identity (2 inputs: Name & Handle) ─────
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Create Oneova Profile',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35), width: 1.0),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flash_on_rounded, size: 10, color: AppColors.brandPink),
                    SizedBox(width: 3),
                    Text(
                      'STEP 1 OF 2',
                      style: TextStyle(color: AppColors.brandPink, fontSize: 9.5, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Number $_completePhoneNumber checked. Now pick your name.',
            style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 10),

          // "Why This Matters" Callout Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.22), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.alternate_email_rounded, size: 14, color: AppColors.brandBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Your @username is how people find you.',
                    style: TextStyle(color: context.textSecondary, fontSize: 10.5, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          OnboardingIdentityFields(
            nameController: _regNameController,
            usernameController: _regUsernameController,
            checking: _isCheckingUsername,
            result: _usernameCheckResult,
          ),
          const SizedBox(height: 14),

          // Next Button (Step 1 of 2 -> Step 2)
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              onPressed: () {
                final name = _regNameController.text.trim();
                final username = _regUsernameController.text.trim();
                if (name.length < 2) {
                  setState(() => _errorMessage = 'Please enter your full name or creator name.');
                  return;
                }
                if (username.isEmpty) {
                  setState(() => _errorMessage = 'Please enter a unique @username.');
                  return;
                }
                if (_usernameCheckResult != null && !_usernameCheckResult!.isValidAndAvailable) {
                  setState(() => _errorMessage = 'Please choose an available username.');
                  return;
                }
                setState(() {
                  _errorMessage = null;
                  _newUserSubStep = 1;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Continue to Security (1 step left) →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // ── Micro-Step 2 of 2: Security & Passkeys (2 inputs: Password & Passkey)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Keep it safe',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: context.textPrimary),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.full),
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_rounded, size: 10, color: AppColors.brandPink),
                  SizedBox(width: 3),
                  Text(
                    'ALMOST THERE • 2 OF 2',
                    style: TextStyle(color: AppColors.brandPink, fontSize: 9.5, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          'Almost done! Protect your new account with a strong master password.',
          style: TextStyle(color: context.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),

        // "Why This Matters" Callout Box
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.22), width: 1.0),
          ),
          child: Row(
            children: [
              const Icon(Icons.fingerprint_rounded, size: 15, color: AppColors.brandPink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Your fingerprint only works on this phone and only for your account.',
                  style: TextStyle(color: context.textSecondary, fontSize: 10.5, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // INPUT 1: Master Password Field
        TextField(
          controller: _regPasswordController,
          obscureText: !_regPasswordVisible,
          cursorColor: AppColors.brandBlue,
          onChanged: (_) => setState(() {}),
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Password (8+ characters)',
            hintStyle: TextStyle(color: context.textMuted, fontSize: 12),
            filled: true,
            fillColor: context.surfaceMid,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border, width: 1.0)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5)),
            prefixIcon: Icon(Icons.lock_outline_rounded, color: context.textSecondary, size: 16),
            suffixIcon: IconButton(
              icon: Icon(
                _regPasswordVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: context.textSecondary,
                size: 18,
              ),
              onPressed: () => setState(() => _regPasswordVisible = !_regPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 5),

        // Password Strength Bar
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: strength == 0 ? 0.05 : strength / 4.0,
                  backgroundColor: context.border,
                  valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
                  minHeight: 3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              strengthLabel,
              style: TextStyle(color: strengthColor, fontSize: 10.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        OvaInlineHint(OvaAuthCoach.newPassword(
          _regPasswordController.text,
          name: _regNameController.text,
          username: _regUsernameController.text,
          phone: _completePhoneNumber,
          hardwareCapsLock: _hardwareCapsLock,
        )),
        const SizedBox(height: 10),

        // INPUT 2: Biometric Passkey Switch
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              const Icon(Icons.fingerprint_rounded, color: AppColors.brandBlue, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Use fingerprint next time',
                      style: TextStyle(color: context.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'Open Oneova with one touch on this phone',
                      style: TextStyle(color: context.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _regEnableBiometrics,
                activeThumbColor: AppColors.brandBlue,
                activeTrackColor: AppColors.brandBlue.withValues(alpha: 0.4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (val) => setState(() => _regEnableBiometrics = val),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Action Buttons Row: Back + Complete
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_rounded, color: context.textSecondary, size: 20),
              tooltip: 'Back to Identity',
              onPressed: () => setState(() => _newUserSubStep = 0),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _completeRegistration,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.rocket_launch_rounded, size: 15, color: Colors.white),
                            SizedBox(width: 6),
                            Text('Launch Oneova Studio →', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Helper Widgets ─────────────────────────────────────────────────────────
  Widget _buildSocialLoginButton({
    required Widget icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: _TactileScaleTap(
        onTap: _isLoading ? null : onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrandLogo(dynamic icon) {
    return FaIcon(icon, size: 15, color: context.textMuted);
  }

  Widget _buildSocialProof() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').limit(3).get(),
        FirebaseFirestore.instance.collection('users').count().get(),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 30);
        }

        final usersSnapshot = snapshot.data![0] as QuerySnapshot;
        final countSnapshot = snapshot.data![1] as AggregateQuerySnapshot;

        final docs = usersSnapshot.docs;
        final totalCount = countSnapshot.count ?? 0;

        final String formattedCount = totalCount > 1000
            ? '${(totalCount / 1000).toStringAsFixed(1)}k'
            : totalCount.toString();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 28,
              width: docs.isEmpty ? 28 : 38.0 + (docs.length > 1 ? 16 : 0),
              child: Stack(
                children: [
                  if (docs.isEmpty)
                    Positioned(
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.brandBlue, width: 1.0),
                        ),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                          child: const Icon(Icons.person_rounded, size: 13, color: AppColors.brandBlue),
                        ),
                      ),
                    ),
                  if (docs.isNotEmpty)
                    Positioned(
                      left: 0,
                      child: Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.brandBlue, width: 1.0),
                        ),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.brandBlue.withValues(alpha: 0.2),
                          backgroundImage: (docs[0].data() as Map).containsKey('photoUrl') && (docs[0].data() as Map)['photoUrl'] != null
                              ? NetworkImage((docs[0].data() as Map)['photoUrl'])
                              : null,
                          child: (!(docs[0].data() as Map).containsKey('photoUrl') || (docs[0].data() as Map)['photoUrl'] == null)
                              ? const Icon(Icons.person_rounded, color: AppColors.brandBlue, size: 13)
                              : null,
                        ),
                      ),
                    ),
                  if (docs.length > 1)
                    Positioned(
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.brandPink, width: 1.0),
                        ),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.brandPink.withValues(alpha: 0.2),
                          backgroundImage: (docs[1].data() as Map).containsKey('photoUrl') && (docs[1].data() as Map)['photoUrl'] != null
                              ? NetworkImage((docs[1].data() as Map)['photoUrl'])
                              : null,
                          child: (!(docs[1].data() as Map).containsKey('photoUrl') || (docs[1].data() as Map)['photoUrl'] == null)
                              ? const Icon(Icons.person_rounded, color: AppColors.brandPink, size: 13)
                              : null,
                        ),
                      ),
                    ),
                  if (docs.length > 2)
                    Positioned(
                      left: 32,
                      child: Container(
                        padding: const EdgeInsets.all(1.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: context.border, width: 1.0),
                        ),
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: context.surfaceMid,
                          backgroundImage: (docs[2].data() as Map).containsKey('photoUrl') && (docs[2].data() as Map)['photoUrl'] != null
                              ? NetworkImage((docs[2].data() as Map)['photoUrl'])
                              : null,
                          child: (!(docs[2].data() as Map).containsKey('photoUrl') || (docs[2].data() as Map)['photoUrl'] == null)
                              ? Icon(Icons.person_rounded, color: context.textSecondary, size: 13)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$formattedCount ',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: 'creators already joined',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
