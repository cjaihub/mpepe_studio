import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import 'auth_repository.dart';

class MainLoginScreen extends ConsumerStatefulWidget {
  const MainLoginScreen({super.key});

  @override
  ConsumerState<MainLoginScreen> createState() => _MainLoginScreenState();
}

class _MainLoginScreenState extends ConsumerState<MainLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  
  bool _isLoading = false;
  bool _isOtpSent = false;
  String _verificationId = '';
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _sendCode() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolve (Android only)
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (mounted) context.go('/hub/home');
        },
        verificationFailed: (FirebaseAuthException e) {
          setState(() {
            _isLoading = false;
            _errorMessage = e.message ?? 'Verification failed';
          });
        },
        codeSent: (String verificationId, int? resendToken) {
          setState(() {
            _isLoading = false;
            _isOtpSent = true;
            _verificationId = verificationId;
          });
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _verifyCode() async {
    final code = _otpController.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authRepositoryProvider).signInWithOTP(
        verificationId: _verificationId,
        smsCode: code,
      );
      if (mounted) context.go('/hub/home');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Invalid OTP code';
      });
    }
  }

  void _devBypass() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authRepositoryProvider).devBypassLogin();
      if (mounted) context.go('/hub/home');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFff8a00), Color(0xFFff3d00)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFff8a00).withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'M',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('MPEPE', style: AppTheme.h1Style.copyWith(fontSize: 30)),
                  const SizedBox(width: 8),
                  const Text(
                    'STUDIO',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2.0,
                      color: AppColors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
              ],

              if (!_isOtpSent) ...[
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '+1 234 567 8900',
                    hintStyle: const TextStyle(color: AppColors.dust),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.phone, color: AppColors.dust),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: MpepeButton(
                    label: _isLoading ? 'Sending...' : 'Continue with Phone',
                    variant: MpepeButtonVariant.white,
                    onPressed: _isLoading ? () {} : _sendCode,
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, letterSpacing: 4),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: '000000',
                    hintStyle: const TextStyle(color: AppColors.dust),
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: MpepeButton(
                    label: _isLoading ? 'Verifying...' : 'Verify Code',
                    variant: MpepeButtonVariant.white,
                    onPressed: _isLoading ? () {} : _verifyCode,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isOtpSent = false;
                      _otpController.clear();
                      _errorMessage = null;
                    });
                  },
                  child: const Text('Use a different number', style: TextStyle(color: AppColors.dust)),
                ),
              ],
              
              if (!kIsWeb && Platform.isWindows) ...[
                const SizedBox(height: 24),
                const Text('Running on Windows Desktop?', style: TextStyle(color: AppColors.ash, fontSize: 12)),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: MpepeButton(
                    label: 'Dev Bypass (Email Login)',
                    variant: MpepeButtonVariant.ghost,
                    onPressed: _isLoading ? () {} : _devBypass,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
