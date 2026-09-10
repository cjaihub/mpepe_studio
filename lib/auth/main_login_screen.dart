import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mpepe_studio/auth/auth_repository.dart';
import 'package:mpepe_studio/auth/services/pin_auth_service.dart';
import 'package:mpepe_studio/auth/screens/mpepe_pin_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:local_auth/local_auth.dart';
import 'package:pinput/pinput.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../shared/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class MainLoginScreen extends ConsumerStatefulWidget {
  const MainLoginScreen({super.key});

  @override
  ConsumerState<MainLoginScreen> createState() => _MainLoginScreenState();
}

class _MainLoginScreenState extends ConsumerState<MainLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  // Country code state — defaults to Kenya (+254)
  String _selectedDialCode = '+254';
  
  bool _isLoading = false;
  bool _isOtpSent = false;
  String _verificationId = '';
  String? _errorMessage;
  // Lazily built from controller + country code on every interaction
  String get _completePhoneNumber {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return '';
    return _normalizePhone(raw, _selectedDialCode);
  }

  // Tracks whether the normalized phone belongs to an existing account
  bool? _isExistingUserAccount;
  
  // Resend Timer State
  int _resendTimeout = 60;
  Timer? _resendTimer;
  bool get _canResend => _resendTimeout == 0;
  
  // Biometric State
  bool _isCheckingBiometrics = false;

  // ── Kenyan Phone Normalizer ───────────────────────────────────────────────
  // Accepts any format: 07xxxxxxx, 7xxxxxxx, 01xxxxxxx, 1xxxxxxx, +2547...
  // Strips leading zeros and country-code duplicates, forces E.164 for KE.
  String _normalizePhone(String raw, String dialCode) {
    // Already in E.164
    if (raw.startsWith('+')) return raw;
    
    String digits = raw.replaceAll(RegExp(r'\D'), '');

    // Kenyan numbers: Safaricom/Airtel start with 07, 01, 011, 010
    // Strip one leading zero if present (0712345678 → 712345678)
    if (dialCode == '+254') {
      if (digits.startsWith('0')) digits = digits.substring(1);
      // If user already typed 254 prefix, strip it
      if (digits.startsWith('254')) digits = digits.substring(3);
      return '+254$digits';
    }

    // Generic: strip a single leading zero
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '$dialCode$digits';
  }

  // ── Firestore lookup: does this phone number have an account? ─────────────
  Future<bool> _isExistingUser(String normalizedPhone) async {
    try {
      // Check our Firestore users collection by phoneNumber field
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(1)
          .get();
      return snap.docs.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Precache assets...
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      precacheImage(const AssetImage('assets/logos/app_logo.png'), context);
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final pinAuthService = ref.read(pinAuthServiceProvider);
        if (await pinAuthService.isSessionExpired()) {
          if (mounted) context.go('/auth/locked');
          return;
        }
        if (mounted) _checkStatusAndRedirect();
      }
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

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

  /// Checks the Firestore user document status and routes accordingly.
  /// PIN is only shown if the user has explicitly set one up previously.
  /// PIN setup is voluntary and lives in Settings → Privacy & Security.
  Future<void> _checkStatusAndRedirect() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    // ── Check if user has a Firestore profile ──────────────────────────────
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!doc.exists) {
        // Firebase account exists but no Firestore profile yet
        // (edge case: account created externally or Firestore write failed)
        if (mounted) context.go('/auth/signup_wizard');
        return;
      }

      final status = doc.data()?['status'] as String? ?? 'active';
      if (status == 'pending') {
        if (mounted) context.go('/auth/pending');
        return;
      }
    } catch (_) {
      // Network error — allow through; home screen will handle it
    }

    // ── PIN gate (only if user has set one up) ─────────────────────────────
    final pinAuthService = ref.read(pinAuthServiceProvider);
    final hasPin = await pinAuthService.hasPinSet();
    if (hasPin && mounted) {
      final success = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const MpepePinScreen(mode: PinScreenMode.verify),
        ),
      );
      if (success != true || !mounted) return;
    }

    if (mounted) context.go('/hub/home');
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userCred = await ref.read(authRepositoryProvider).signInWithGoogle();
      if (userCred == null || !mounted) {
        setState(() => _isLoading = false);
        return;
      }

      final uid = userCred.user?.uid;
      if (uid == null) {
        setState(() => _isLoading = false);
        return;
      }

      // ── Detect new vs returning Google user ────────────────────────────────
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!mounted) return;

      if (!doc.exists) {
        // ✨ New user — send them to signup wizard with Google creds pre-filled
        // The wizard will skip the email/password step since Google auth is used
        final googleEmail = userCred.user?.email ?? '';
        final googleName = userCred.user?.displayName ?? '';
        final googlePhoto = userCred.user?.photoURL ?? '';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Welcome, ${googleName.isNotEmpty ? googleName.split(" ").first : "there"}! '
                    'Complete your MPEPE Studio profile to get started.',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.blue.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 4),
          ),
        );

        context.go('/auth/signup_wizard', extra: {
          'fromGoogle': true,
          'email': googleEmail,
          'name': googleName,
          'photoUrl': googlePhoto,
          'uid': uid,
        });
        return;
      }

      // Returning user — normal flow
      setState(() => _isLoading = false);
      _checkStatusAndRedirect();
    } catch (e) {
      if (kDebugMode) {
        try {
          // Fallback to anonymous auth for local testing if Google Sign In fails
          // (common on iOS simulators due to keychain sharing limitations)
          await FirebaseAuth.instance.signInAnonymously();
          if (mounted) _checkStatusAndRedirect();
          return;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _sendCode() async {
    final phone = _completePhoneNumber;
    // E.164 numbers are at minimum +1XXXXXXXXXX (10 digits + country code)
    final digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.isEmpty || digitsOnly.length < 7) {
      setState(() => _errorMessage = 'Please enter a valid phone number (e.g. 0712 345 678)');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isExistingUserAccount = null;
    });

    // ── Step 1: Check if this number is known in Firestore ─────────────────
    final exists = await _isExistingUser(phone);
    if (!mounted) return;
    setState(() => _isExistingUserAccount = exists);

    // ── Step 2: Show contextual banner before sending OTP ─────────────────
    if (!exists) {
      // New user — inform them they'll be creating an account
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mpepeGold.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Colors.black87, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'New here! We\'ll create your account after verifying.',
                  style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.mpepeMaroon.withValues(alpha: 0.95),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Welcome back! Sending a verification code to your number.',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }

    // ── Step 3: Send OTP via Firebase SMS ─────────────────────────────────
    try {
      await ref.read(authRepositoryProvider).verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) _checkStatusAndRedirect();
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          String msg = e.message ?? 'Verification failed';
          final msgLower = msg.toLowerCase();
          if (msgLower.contains('play_integrity') || msgLower.contains('billing')) {
            msg = 'SMS verification is currently unavailable. Please try again on a real device.';
          } else if (msgLower.contains('quota-exceeded') || msgLower.contains('quota_exceeded')) {
            msg = 'SMS quota exceeded. Please wait a few minutes and try again.';
          } else if (msgLower.contains('invalid-phone-number') || msgLower.contains('invalid_phone_number')) {
            msg = 'Invalid phone number. Please enter a valid number (e.g. 0712 345 678).';
          } else if (msgLower.contains('too-many-requests') || msgLower.contains('too_many_requests')) {
            msg = 'Too many attempts. Please wait a few minutes before trying again.';
          }
          setState(() {
            _isLoading = false;
            _errorMessage = msg;
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _isOtpSent = true;
            _verificationId = verificationId;
          });
          _startResendTimer();
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _verifyCode(String code) async {
    if (code.isEmpty || code.length < 6) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithOTP(
        verificationId: _verificationId,
        smsCode: code,
      );
      if (mounted) _checkStatusAndRedirect();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Incorrect verification code. Please check and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser != null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final defaultPinTheme = PinTheme(
      width: 56,
      height: 56,
      textStyle: TextStyle(
        fontSize: 20,
        color: Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.3),
      ),
    );

    final focusedPinTheme = defaultPinTheme.copyDecorationWith(
      border: Border.all(color: Theme.of(context).colorScheme.primary),
      borderRadius: BorderRadius.circular(12),
    );

    final submittedPinTheme = defaultPinTheme.copyWith(
      decoration: defaultPinTheme.decoration?.copyWith(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Logo
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/logos/app_logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  ).animate().fade().scale(delay: 100.ms, duration: 400.ms, curve: Curves.easeOutBack),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'MPEPE', 
                        style: Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        )
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.mpepeMaroon,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'STUDIO',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ).animate().fade(delay: 200.ms).slideY(begin: 0.2, end: 0, duration: 300.ms),
                  const SizedBox(height: 8),
                  Text(
                    'The ultimate enterprise creator suite',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ).animate().fade(delay: 300.ms),
                  const SizedBox(height: 40),

                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ).animate().fade().slideY(begin: -0.1, end: 0, duration: 200.ms),
                    const SizedBox(height: 24),
                  ],

                  // Form Container (Red Background)
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.mpepeMaroon,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.mpepeMaroon),
                    ),
                    child: !_isOtpSent ? _buildPhoneEntry() : _buildOtpEntry(defaultPinTheme, focusedPinTheme, submittedPinTheme),
                  ).animate().fade(delay: 400.ms).slideY(begin: 0.1, end: 0, duration: 300.ms),
                  
                  const SizedBox(height: 32),
                  
                  // Social Proof (Live Users)
                  _buildSocialProof().animate().fade(delay: 500.ms),
                  
                  const SizedBox(height: 32),
                  
                  // Trusted Brands
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildBrandLogo(FontAwesomeIcons.youtube, 'YouTube'),
                      const SizedBox(width: 24),
                      _buildBrandLogo(FontAwesomeIcons.instagram, 'Instagram'),
                      const SizedBox(width: 24),
                      _buildBrandLogo(FontAwesomeIcons.tiktok, 'TikTok'),
                    ],
                  ).animate().fade(delay: 600.ms),


                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneEntry() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome Back',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: Colors.white),
        ),
        const SizedBox(height: 6),
        Text(
          'Access your enterprise creator suite to manage content, track analytics, and grow your brand.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.9),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),

        // ── Smart Phone Field ──────────────────────────────────────────────
        IntlPhoneField(
          controller: _phoneController,
          // Auto-set Kenya; user can change flag to any country
          initialCountryCode: 'KE',
          keyboardType: TextInputType.phone,
          inputFormatters: [
            // Allow digits, spaces, hyphens — user can type 0712 or 712
            FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-]')),
          ],
          decoration: InputDecoration(
            hintText: 'e.g. 0712 345 678 or 712 345 678',
            hintStyle: TextStyle(
              color: Colors.black.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(
                color: Colors.black,
                width: 2.0,
              ),
            ),
            counterText: '',
          ),
          dropdownIcon: const Icon(
            Icons.arrow_drop_down_rounded,
            color: Colors.black,
          ),
          style: const TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
          onChanged: (phone) {
            // Keep the selected dial code in sync so the getter works correctly
            setState(() => _selectedDialCode = phone.countryCode);
          },
          onSubmitted: (_) => _sendCode(),
          invalidNumberMessage: 'Please enter a valid phone number',
        ),

        // ── Kenyan format helper hint ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            'e.g. 0700... / 700...',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── Continue Button ──────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _sendCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.phone_android_rounded, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'Continue with Phone',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
            Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.3))),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton.icon(
            onPressed: _isLoading ? null : _signInWithGoogle,
            icon: SvgPicture.asset('assets/google_logo.svg', width: 22, height: 22),
            label: const Text(
              'Continue with Google',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.black),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpEntry(PinTheme defaultPinTheme, PinTheme focusedPinTheme, PinTheme submittedPinTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.message_rounded, color: Theme.of(context).colorScheme.primary, size: 32),
        ),
        const SizedBox(height: 20),
        Text(
          'Verify your number',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'We sent a 6-digit code to',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
        ),
        Text(
          _phoneController.text,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 15, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        
        // Premium Pinput for OTP
        Pinput(
          controller: _otpController,
          length: 6,
          defaultPinTheme: defaultPinTheme,
          focusedPinTheme: focusedPinTheme,
          submittedPinTheme: submittedPinTheme,
          pinputAutovalidateMode: PinputAutovalidateMode.onSubmit,
          showCursor: true,
          autofocus: true,
          onCompleted: (pin) => _verifyCode(pin),
        ),
        
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () => _verifyCode(_otpController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Verify Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text("Didn't receive the code? ", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
            TextButton(
              onPressed: _canResend && !_isLoading ? _sendCode : null,
              child: Text(
                _canResend ? 'Resend' : 'Resend in ${_resendTimeout}s',
                style: TextStyle(
                  color: _canResend ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _isOtpSent = false;
              _otpController.clear();
              _errorMessage = null;
              _resendTimer?.cancel();
            });
          },
          child: Text('Change phone number', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
        ),
      ],
    );
  }

  Widget _buildBrandLogo(dynamic icon, String name) {
    return Column(
      children: [
        FaIcon(icon, size: 20, color: Colors.white.withValues(alpha: 0.4)),
      ],
    );
  }
  }

  Widget _buildSocialProof() {
    return FutureBuilder<List<dynamic>>(
      // Fetch 3 users with photos, and the total count of all users
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').limit(3).get(),
        FirebaseFirestore.instance.collection('users').count().get()
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(height: 40); // Placeholder while loading
        }

        final usersSnapshot = snapshot.data![0] as QuerySnapshot;
        final countSnapshot = snapshot.data![1] as AggregateQuerySnapshot;
        
        final docs = usersSnapshot.docs;
        final totalCount = countSnapshot.count ?? 0;
        
        // Formatter for numbers (e.g. 1,200)
        final String formattedCount = totalCount > 1000 
            ? '${(totalCount / 1000).toStringAsFixed(1)}k' 
            : totalCount.toString();

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 40,
              width: docs.isEmpty ? 40 : 50.0 + (docs.length > 1 ? 25 : 0),
              child: Stack(
                children: [
                  if (docs.isEmpty)
                    Positioned(
                      left: 0,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        child: const Icon(Icons.person, size: 20, color: Colors.white),
                      ),
                    ),
                  if (docs.isNotEmpty)
                    Positioned(
                      left: 0,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                        backgroundImage: (docs[0].data() as Map).containsKey('photoUrl') && (docs[0].data() as Map)['photoUrl'] != null 
                            ? NetworkImage((docs[0].data() as Map)['photoUrl']) 
                            : null,
                        child: (!(docs[0].data() as Map).containsKey('photoUrl') || (docs[0].data() as Map)['photoUrl'] == null) 
                            ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                    ),
                  if (docs.length > 1)
                    Positioned(
                      left: 25,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                        backgroundImage: (docs[1].data() as Map).containsKey('photoUrl') && (docs[1].data() as Map)['photoUrl'] != null 
                            ? NetworkImage((docs[1].data() as Map)['photoUrl']) 
                            : null,
                        child: (!(docs[1].data() as Map).containsKey('photoUrl') || (docs[1].data() as Map)['photoUrl'] == null) 
                            ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                    ),
                  if (docs.length > 2)
                    Positioned(
                      left: 50,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        backgroundImage: (docs[2].data() as Map).containsKey('photoUrl') && (docs[2].data() as Map)['photoUrl'] != null 
                            ? NetworkImage((docs[2].data() as Map)['photoUrl']) 
                            : null,
                        child: (!(docs[2].data() as Map).containsKey('photoUrl') || (docs[2].data() as Map)['photoUrl'] == null) 
                            ? const Icon(Icons.person, color: Colors.white) : null,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$formattedCount ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextSpan(
                    text: 'creators already joined',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 13,
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
