import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:qr/qr.dart';

import '../../auth/security/login_security.dart';
import '../../auth/services/oneova_smart_phone_engine.dart';
import '../../backend/secure_pairing/crypto_utils.dart';
import '../../backend/secure_pairing/secure_pairing_service.dart';
import '../../desktop_agent/desktop_firebase_rest_client.dart';
import '../../shared/theme/app_theme.dart';
import '../ova_agent_sync_controller.dart';

enum _AuthMethodTab {
  phone,
  email,
  google,
  qrSession,
}

/// Modal dialog providing comprehensive Oneova Account Authentication,
/// Profile Inspection, Cross-Device QR Session pairing, and Mobile-Sync Switching.
class OneovaWorkstationAuthDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSignedOut;
  final VoidCallback? onSignedIn;

  const OneovaWorkstationAuthDialog({
    super.key,
    this.onSignedOut,
    this.onSignedIn,
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onSignedOut,
    VoidCallback? onSignedIn,
  }) {
    HapticFeedback.lightImpact();
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => OneovaWorkstationAuthDialog(
        onSignedOut: onSignedOut,
        onSignedIn: onSignedIn,
      ),
    );
  }

  @override
  ConsumerState<OneovaWorkstationAuthDialog> createState() =>
      _OneovaWorkstationAuthDialogState();
}

class _OneovaWorkstationAuthDialogState
    extends ConsumerState<OneovaWorkstationAuthDialog> {
  final DesktopFirebaseRestClient _cloud = DesktopFirebaseRestClient.instance;
  final OneovaSmartPhoneEngine _phoneEngine = OneovaSmartPhoneEngine();

  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  _AuthMethodTab _activeTab = _AuthMethodTab.phone;
  bool _passwordVisible = false;
  bool _signingIn = false;
  bool _isCheckingAccount = false;
  Map<String, dynamic>? _identifiedUser;
  String? _errorMessage;
  String? _infoMessage;

  CountryPhoneMeta _selectedCountryMeta = OneovaSmartPhoneEngine.defaultCountry;
  Timer? _lookupDebounce;

  StreamSubscription<List<DesktopRestDoc>>? _pairingSub;
  String? _activeQrPin;
  bool _publishingQr = false;

  String get _computerName => Platform.localHostname;

  String get _completePhoneE164 {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return '';
    return _phoneEngine
        .parseAndNormalize(input: raw, fallbackCountry: _selectedCountryMeta)
        .e164;
  }

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onInputChanged);
    _emailController.addListener(_onInputChanged);
    _initPhoneCountry();
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pairingSub?.cancel();
    super.dispose();
  }

  Future<void> _initPhoneCountry() async {
    try {
      final detected = await _phoneEngine.detectCountrySilently();
      if (mounted) {
        setState(() => _selectedCountryMeta = detected);
      }
    } catch (_) {}
  }

  void _onInputChanged() {
    _lookupDebounce?.cancel();
    _lookupDebounce = Timer(const Duration(milliseconds: 380), _runLookup);
  }

  Future<void> _runLookup() async {
    if (_activeTab == _AuthMethodTab.phone) {
      final e164 = _completePhoneE164;
      if (e164.replaceAll(RegExp(r'\D'), '').length < 8) {
        if (mounted && _identifiedUser != null) {
          setState(() => _identifiedUser = null);
        }
        return;
      }
      if (mounted) setState(() => _isCheckingAccount = true);
      final found = await _cloud.lookupAccount(phone: e164);
      if (mounted) {
        setState(() {
          _isCheckingAccount = false;
          _identifiedUser = found;
        });
      }
    } else if (_activeTab == _AuthMethodTab.email) {
      final email = _emailController.text.trim();
      if (!email.contains('@') || !email.contains('.')) {
        if (mounted && _identifiedUser != null) {
          setState(() => _identifiedUser = null);
        }
        return;
      }
      if (mounted) setState(() => _isCheckingAccount = true);
      final found = await _cloud.lookupAccount(email: email);
      if (mounted) {
        setState(() {
          _isCheckingAccount = false;
          _identifiedUser = found;
        });
      }
    }
  }

  Future<void> _startQrPairing() async {
    await _pairingSub?.cancel();
    _pairingSub = null;

    setState(() {
      _publishingQr = true;
      _errorMessage = null;
    });

    try {
      await _cloud.ensureAuthenticated();
      final pairingService = ref.read(securePairingProvider.notifier);
      final pin = pairingService.generatePairingPin();
      final salt = ref.read(securePairingProvider).salt;
      final agentUid = _cloud.currentUid;

      await _cloud.setDocument('desktop_pairing/$pin', {
        'computer_name': _computerName,
        'salt': salt,
        'agent_uid': agentUid,
        'os': Platform.operatingSystem,
        'status': 'waiting',
        'created_at': DateTime.now().toUtc(),
      });

      setState(() {
        _activeQrPin = pin;
        _publishingQr = false;
      });

      _pairingSub = _cloud
          .watchCollection(
            'desktop_pairing/$pin/responses',
            interval: const Duration(milliseconds: 1000),
          )
          .listen((docs) async {
        for (final doc in docs) {
          final data = doc.data;
          final encryptedUid = (data['encrypted_uid'] ?? '').toString();
          if (encryptedUid.isEmpty) continue;

          final key = CryptoUtils.deriveKeyFromPin(pin, salt);
          final decryptedUid = CryptoUtils.decryptPayload(encryptedUid, key);
          if (decryptedUid != null && decryptedUid.isNotEmpty) {
            await _pairingSub?.cancel();
            _pairingSub = null;
            unawaited(_cloud.deleteDocument('desktop_pairing/$pin').catchError((_) {}));

            await _handleAuthSuccess(
              uid: decryptedUid,
              label: (data['mobile_name'] ?? 'Mobile Phone').toString(),
            );
            break;
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _publishingQr = false;
          _errorMessage = 'Failed to generate QR session: $e';
        });
      }
    }
  }

  Future<void> _signInWithPhoneOrEmail() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _errorMessage = 'Enter your password to sign in.');
      return;
    }

    String targetEmail;
    String rememberLabel;

    if (_activeTab == _AuthMethodTab.phone) {
      final e164 = _completePhoneE164;
      if (e164.replaceAll(RegExp(r'\D'), '').length < 7) {
        setState(() => _errorMessage = 'Enter your mobile phone number.');
        return;
      }
      targetEmail = LoginSecurity.authEmailForPhone(e164);
      final handle = _identifiedUser?['username'] as String?;
      rememberLabel = handle != null && handle.isNotEmpty ? '@$handle • $e164' : e164;
    } else {
      final email = _emailController.text.trim();
      if (email.isEmpty || !email.contains('@')) {
        setState(() => _errorMessage = 'Enter a valid email address.');
        return;
      }
      targetEmail = email;
      final handle = _identifiedUser?['username'] as String?;
      rememberLabel = handle != null && handle.isNotEmpty ? '@$handle • $email' : email;
    }

    setState(() {
      _signingIn = true;
      _errorMessage = null;
      _infoMessage = null;
    });

    try {
      final uid = await _cloud.signInWithEmailAndPassword(
        email: targetEmail,
        password: password,
      );
      await _cloud.setRememberedAccountLabel(rememberLabel);
      _passwordController.clear();
      await _handleAuthSuccess(uid: uid, label: rememberLabel);
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _signingIn = true;
      _errorMessage = null;
    });
    try {
      final uid = await _cloud.signInWithGoogle();
      await _handleAuthSuccess(uid: uid, label: 'Google Account');
    } on DesktopCloudException catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _signingIn = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _handleAuthSuccess({
    required String uid,
    required String label,
  }) async {
    final cleanHost = _computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    final deviceId = 'desktop_${uid}_$cleanHost';

    ref.read(ovaAgentSyncProvider.notifier).bindDesktopWorkstation(
          deviceId: deviceId,
          computerName: _computerName,
          ownerUid: uid,
        );

    // Fetch and populate rich profile
    try {
      final userDoc = await _cloud.getDocument('users/$uid');
      if (userDoc != null) {
        ref.read(ovaAgentSyncProvider.notifier).setAuthUser(
              uid: uid,
              displayName: (userDoc['displayName'] ?? userDoc['fullName'] ?? 'Oneova Creator').toString(),
              username: (userDoc['username'] ?? '').toString(),
              email: (userDoc['email'] ?? userDoc['recoveryEmail'] ?? '').toString(),
              phone: (userDoc['phone'] ?? userDoc['phoneNumber'] ?? '').toString(),
              photoUrl: (userDoc['photoUrl'] ?? userDoc['profilePhotoUrl'] ?? userDoc['photoURL'] ?? '').toString(),
              isAccountUser: true,
            );
      }
    } catch (_) {}

    widget.onSignedIn?.call();
    if (mounted) {
      setState(() => _signingIn = false);
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signed in as $label • Account synced with mobile!'),
          backgroundColor: AppColors.brandBlue,
        ),
      );
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          'Sign Out of Workstation?',
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          'Signing out stops live cloud sync for this computer. You can log back in anytime with your mobile number, email, Google, or QR session.',
          style: GoogleFonts.inter(
            fontSize: 12.5,
            color: ctx.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                color: ctx.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Sign Out',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    ref.read(ovaAgentSyncProvider.notifier).clearAuthUser();
    ref.read(ovaAgentSyncProvider.notifier).unbindDesktopWorkstation();
    await _cloud.signOutAccount();
    widget.onSignedOut?.call();

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Signed out of workstation.'),
          backgroundColor: AppColors.brandBlue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ovaAgentSyncProvider);
    final isAuthenticated = state.authUid != null;

    return Dialog(
      backgroundColor: context.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: context.border, width: 1.0),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 680),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.brandBlue, AppColors.brandPink],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.hub_rounded,
                      size: 17,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Oneova Workstation Account',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          'Same account, chats & memories across Mobile & Mac',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    splashRadius: 18,
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: context.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Divider(color: context.border, height: 1),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Active Account Profile Card
                    if (isAuthenticated) ...[
                      _buildActiveAccountCard(context, state),
                      const SizedBox(height: 18),
                      Text(
                        'SWITCH OR LINK ANOTHER ACCOUNT',
                        style: GoogleFonts.inter(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: context.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],

                    // Tab Selector: Phone | Email | Google | QR Session
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: context.border, width: 1.0),
                      ),
                      child: Row(
                        children: [
                          _buildTabItem(
                            label: 'Phone',
                            tab: _AuthMethodTab.phone,
                            icon: Icons.smartphone_rounded,
                          ),
                          _buildTabItem(
                            label: 'Email',
                            tab: _AuthMethodTab.email,
                            icon: Icons.mail_outline_rounded,
                          ),
                          _buildTabItem(
                            label: 'Google',
                            tab: _AuthMethodTab.google,
                            icon: Icons.g_mobiledata_rounded,
                          ),
                          _buildTabItem(
                            label: 'QR Code',
                            tab: _AuthMethodTab.qrSession,
                            icon: Icons.qr_code_2_rounded,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (_errorMessage != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: AppColors.brandPink.withValues(alpha: 0.4),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.brandPink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    if (_infoMessage != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(
                            color: AppColors.brandBlue.withValues(alpha: 0.4),
                            width: 1.0,
                          ),
                        ),
                        child: Text(
                          _infoMessage!,
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],

                    // Tab Views
                    switch (_activeTab) {
                      _AuthMethodTab.phone => _buildPhoneTab(context),
                      _AuthMethodTab.email => _buildEmailTab(context),
                      _AuthMethodTab.google => _buildGoogleTab(context),
                      _AuthMethodTab.qrSession => _buildQrTab(context),
                    },
                  ],
                ),
              ),
            ),

            if (isAuthenticated) ...[
              Divider(color: context.border, height: 1),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Spacer(),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brandPink,
                        side: BorderSide(
                          color: AppColors.brandPink.withValues(alpha: 0.4),
                          width: 1.0,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                      ),
                      onPressed: _confirmSignOut,
                      icon: const Icon(Icons.logout_rounded, size: 15),
                      label: Text(
                        'Sign Out',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAccountCard(
    BuildContext context,
    OvaAgentWorkspaceState state,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.brandBlue, AppColors.brandPink],
                  ),
                  border: Border.all(color: Colors.white, width: 1.5),
                  image: state.authPhotoUrl != null &&
                          state.authPhotoUrl!.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(state.authPhotoUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: state.authPhotoUrl == null || state.authPhotoUrl!.isEmpty
                    ? Text(
                        state.accountAvatarInitial,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            state.displayAccountName,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified_rounded,
                          size: 14,
                          color: AppColors.brandBlue,
                        ),
                      ],
                    ),
                    if (state.authUsername != null &&
                        state.authUsername!.isNotEmpty) ...[
                      Text(
                        '@${state.authUsername}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                    Text(
                      state.authPhone?.isNotEmpty == true
                          ? state.authPhone!
                          : (state.authEmail ?? 'Verified Account'),
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        color: context.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'SYNCED',
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: context.border, width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.computer_rounded,
                    size: 14, color: AppColors.brandBlue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Workstation: ${state.workstationName ?? _computerName} • Mode: ${state.fullComputerAccess ? "Full Access" : "Supervised"}',
                    style: GoogleFonts.inter(
                      fontSize: 10.5,
                      color: context.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required String label,
    required _AuthMethodTab tab,
    required IconData icon,
  }) {
    final active = _activeTab == tab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm - 2),
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _activeTab = tab;
            _errorMessage = null;
            _infoMessage = null;
          });
          if (tab == _AuthMethodTab.qrSession && _pairingSub == null) {
            _startQrPairing();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 32,
          decoration: BoxDecoration(
            color: active ? AppColors.brandBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm - 2),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: active ? Colors.white : context.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: active ? Colors.white : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Mobile Phone Number',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        IntlPhoneField(
          controller: _phoneController,
          initialCountryCode: _selectedCountryMeta.isoCode,
          disableLengthCheck: true,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.surfaceMid,
            hintText: _selectedCountryMeta.formatHint,
            hintStyle:
                GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            suffixIcon: _isCheckingAccount
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  )
                : null,
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
              borderSide:
                  const BorderSide(color: AppColors.brandBlue, width: 1.0),
            ),
          ),
          onCountryChanged: (c) {
            final m = _phoneEngine.findByIso(c.code);
            setState(() => _selectedCountryMeta = m);
          },
        ),

        if (_identifiedUser != null) ...[
          const SizedBox(height: 8),
          _buildIdentifiedPreview(context),
        ],

        const SizedBox(height: 10),
        Text(
          'Oneova Password',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
          onSubmitted: (_) => _signInWithPhoneOrEmail(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.surfaceMid,
            hintText: 'Enter password',
            hintStyle:
                GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            prefixIcon: Icon(Icons.lock_outline_rounded,
                size: 16, color: context.textSecondary),
            suffixIcon: IconButton(
              splashRadius: 16,
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 16,
                color: context.textSecondary,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderSide:
                  const BorderSide(color: AppColors.brandBlue, width: 1.0),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: _signingIn ? null : _signInWithPhoneOrEmail,
            child: _signingIn
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _identifiedUser != null
                        ? 'Continue as ${(_identifiedUser!["displayName"] ?? "Creator").toString().split(" ").first} →'
                        : 'Sign In & Link Mobile Account',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Email Address',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.surfaceMid,
            hintText: 'creator@oneova.app',
            hintStyle:
                GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            prefixIcon: Icon(Icons.mail_outline_rounded,
                size: 16, color: context.textSecondary),
            suffixIcon: _isCheckingAccount
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: AppColors.brandBlue,
                      ),
                    ),
                  )
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderSide:
                  const BorderSide(color: AppColors.brandBlue, width: 1.0),
            ),
          ),
        ),

        if (_identifiedUser != null) ...[
          const SizedBox(height: 8),
          _buildIdentifiedPreview(context),
        ],

        const SizedBox(height: 10),
        Text(
          'Oneova Password',
          style: GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _passwordController,
          obscureText: !_passwordVisible,
          style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
          onSubmitted: (_) => _signInWithPhoneOrEmail(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.surfaceMid,
            hintText: 'Enter password',
            hintStyle:
                GoogleFonts.inter(fontSize: 12, color: context.textMuted),
            prefixIcon: Icon(Icons.lock_outline_rounded,
                size: 16, color: context.textSecondary),
            suffixIcon: IconButton(
              splashRadius: 16,
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                size: 16,
                color: context.textSecondary,
              ),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              borderSide:
                  const BorderSide(color: AppColors.brandBlue, width: 1.0),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: _signingIn ? null : _signInWithPhoneOrEmail,
            child: _signingIn
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    _identifiedUser != null
                        ? 'Continue as ${(_identifiedUser!["displayName"] ?? "Creator").toString().split(" ").first} →'
                        : 'Sign In & Link Mobile Account',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleTab(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Single Sign-On with Google',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Sign in with the same Google Account associated with your Oneova mobile app profile.',
          style: GoogleFonts.inter(
            fontSize: 11.5,
            color: context.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 40,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: context.surfaceMid,
              side: BorderSide(color: context.border, width: 1.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: _signingIn ? null : _signInWithGoogle,
            child: _signingIn
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.brandBlue,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SvgPicture.asset(
                        'assets/google_logo.svg',
                        width: 16,
                        height: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Continue with Google',
                        style: GoogleFonts.inter(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildQrTab(BuildContext context) {
    final pin = _activeQrPin;
    final qrPayload = pin != null
        ? 'ONEOVA-PAIR:${jsonEncode({"pin": pin, "host": _computerName})}'
        : null;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: AppColors.brandBlue.withValues(alpha: 0.35),
              width: 1.0,
            ),
          ),
          child: qrPayload == null || _publishingQr
              ? const SizedBox(
                  width: 160,
                  height: 160,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.brandBlue,
                    ),
                  ),
                )
              : SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(160, 160),
                        painter: _AuthDialogQrPainter(
                          data: qrPayload,
                          fgColor: const Color(0xFF0F172A),
                          accentColor: AppColors.brandBlue,
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          border: Border.all(
                            color: AppColors.brandBlue,
                            width: 1.5,
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.hub_rounded,
                            size: 18,
                            color: AppColors.brandBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        if (pin != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.full),
              border: Border.all(
                color: AppColors.brandBlue.withValues(alpha: 0.3),
                width: 1.0,
              ),
            ),
            child: Text(
              'SESSION CODE: $pin',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.brandBlue,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          'Scan with Oneova Mobile App',
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: context.textPrimary,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Open Oneova on your phone → Settings / Connect → Scan QR Code to log in here instantly.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 11,
            color: context.textSecondary,
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildIdentifiedPreview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.brandBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.brandBlue, AppColors.brandPink],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              ((_identifiedUser!['displayName'] ?? _identifiedUser!['username'] ?? 'O')
                      .toString()
                      .trim()
                      .characters
                      .firstOrNull ??
                  'O')
                  .toUpperCase(),
              style: GoogleFonts.inter(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_identifiedUser!["displayName"] ?? "Oneova Creator"}${_identifiedUser!["username"] != null ? " (@${_identifiedUser!["username"]})" : ""}',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Found',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.brandBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthDialogQrPainter extends CustomPainter {
  final String data;
  final Color fgColor;
  final Color accentColor;

  const _AuthDialogQrPainter({
    required this.data,
    required this.fgColor,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final qr = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.H,
    );
    final qrImage = QrImage(qr);
    final count = qrImage.moduleCount;
    final moduleSize = size.width / count;

    final paintFg = Paint()
      ..color = fgColor
      ..style = PaintingStyle.fill;

    final paintAccent = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    for (int x = 0; x < count; x++) {
      for (int y = 0; y < count; y++) {
        if (qrImage.isDark(y, x)) {
          final isCorner = (x < 7 && y < 7) ||
              (x < 7 && y >= count - 7) ||
              (x >= count - 7 && y < 7);
          final rect = Rect.fromLTWH(
            x * moduleSize,
            y * moduleSize,
            moduleSize * 0.92,
            moduleSize * 0.92,
          );
          final rrect = RRect.fromRectAndRadius(
            rect,
            Radius.circular(moduleSize * 0.24),
          );
          canvas.drawRRect(rrect, isCorner ? paintAccent : paintFg);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AuthDialogQrPainter oldDelegate) {
    return oldDelegate.data != data ||
        oldDelegate.fgColor != fgColor ||
        oldDelegate.accentColor != accentColor;
  }
}
