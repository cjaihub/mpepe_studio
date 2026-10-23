import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../backend/remote_connect_service.dart';
import '../backend/secure_pairing/crypto_utils.dart';
import '../auth/services/oneova_biometrics_service.dart';
import '../widgets/oneova_assistant_overlay.dart';
import '../shared/theme/app_theme.dart';

/// OneOva Workstation Connect Screen.
///
/// Provides a high-density, executive-scale interface for connecting, waking,
/// unlocking, and controlling remote workstations with zero visual distortion.
class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _passkeyController = TextEditingController();
  bool _isProcessing = false;
  bool _isUnlocking = false;

  @override
  void dispose() {
    _pinController.dispose();
    _passkeyController.dispose();
    super.dispose();
  }

  // Auto-connect to dev bypass desktop if running in bypass mode
  Future<void> _bypassConnect() async {
    setState(() => _isProcessing = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('registered_computers')
          .where('desktop_connected', isEqualTo: true)
          .get();

      final bypassDoc = snapshot.docs.firstWhere(
        (d) => d.id.startsWith('desktop_dev_bypass_'),
        orElse: () => throw Exception('No bypass desktop found. Ensure Desktop Agent is running.'),
      );

      await ref.read(remoteConnectProvider.notifier).linkComputer(bypassDoc.id);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connected to Dev Workstation!'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
        context.push('/remote_control');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _linkViaAccount() async {
    setState(() => _isProcessing = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('You must be signed in to sync via Oneova account.');

      final snapshot = await FirebaseFirestore.instance
          .collection('registered_computers')
          .where('owner_uid', isEqualTo: user.uid)
          .where('desktop_connected', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception('No active workstation found for your Oneova account.');
      }

      final deviceId = snapshot.docs.first.id;
      await ref.read(remoteConnectProvider.notifier).linkComputer(deviceId);

      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Linked via Oneova Account!'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
        context.push('/remote_control');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _connectSession() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid 6-digit PIN.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final doc = await FirebaseFirestore.instance.collection('desktop_pairing').doc(pin).get();
      if (!doc.exists) {
        throw Exception('Invalid or expired PIN.');
      }

      final data = doc.data()!;
      final salt = data['salt'] as String;
      final computerName = data['computer_name'] as String;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not signed in.');

      final key = CryptoUtils.deriveKeyFromPin(pin, salt);
      final encryptedUid = CryptoUtils.encryptPayload(user.uid, key);

      await FirebaseFirestore.instance
          .collection('desktop_pairing')
          .doc(pin)
          .collection('responses')
          .doc(user.uid)
          .set({
        'encrypted_uid': encryptedUid,
        'mobile_name': 'Oneova Mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });

      final deviceId = 'desktop_${user.uid}_${computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      await ref.read(remoteConnectProvider.notifier).linkComputer(deviceId, aesKey: key);

      if (mounted) {
        HapticFeedback.mediumImpact();
        context.push('/remote_control');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pairing failed: ${e.toString()}'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleWakeAndUnlock(LinkedComputer computer) async {
    final biometrics = ref.read(oneovaBiometricsServiceProvider);
    final authenticated = await biometrics.authenticate(reason: 'Wake & unlock workstation');
    if (authenticated) {
      setState(() => _isUnlocking = true);
      await ref.read(remoteConnectProvider.notifier).unlockWorkstation(passkey: '');
      if (mounted) {
        setState(() => _isUnlocking = false);
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Workstation wake & unlock signal dispatched!'),
            backgroundColor: AppColors.brandBlue,
          ),
        );
      }
    } else {
      _showPasskeyEntrySheet(computer);
    }
  }

  void _showPasskeyEntrySheet(LinkedComputer computer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.vpn_key_rounded, color: AppColors.brandPink, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unlock ${computer.name}',
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                          ),
                        ),
                        Text(
                          'Resume workstation session from sleep',
                          style: GoogleFonts.inter(
                            fontSize: 11.5,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _passkeyController,
                obscureText: true,
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter computer password or PIN',
                  hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 12),
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
                    borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: () async {
                    final pass = _passkeyController.text.trim();
                    Navigator.pop(sheetCtx);
                    setState(() => _isUnlocking = true);
                    await ref.read(remoteConnectProvider.notifier).unlockWorkstation(passkey: pass);
                    if (mounted) {
                      setState(() => _isUnlocking = false);
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Unlock command sent!'),
                          backgroundColor: AppColors.brandBlue,
                        ),
                      );
                    }
                  },
                  child: Text('Unlock & Resume', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteState = ref.watch(remoteConnectProvider);
    final linkedComputers = remoteState.linkedComputers;
    final activeComputerId = remoteState.activeComputerId;
    final activeComputer = linkedComputers.firstWhere(
      (c) => c.id == activeComputerId,
      orElse: () => linkedComputers.isNotEmpty
          ? linkedComputers.first
          : LinkedComputer(id: 'none', name: '', isOnline: false),
    );
    final hasLinked = linkedComputers.isNotEmpty && activeComputer.name.isNotEmpty;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary, size: 20),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: Text(
          'Workstation Display & Control',
          style: GoogleFonts.inter(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 20),
            tooltip: 'Ova AI Agent',
            onPressed: () => OneOvaAssistantOverlay.show(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ─────────────────────────────────────────────────────────────
            // 1. ACTIVE WORKSTATION DISPLAY HERO CARD (If paired)
            // ─────────────────────────────────────────────────────────────
            if (hasLinked) ...[
              _buildActiveWorkstationHeroCard(activeComputer),
              const SizedBox(height: 20),
            ],

            // ─────────────────────────────────────────────────────────────
            // 2. CONNECT / LINK OPTIONS SECTION
            // ─────────────────────────────────────────────────────────────
            Text(
              hasLinked ? 'LINK ANOTHER WORKSTATION' : 'CONNECT A WORKSTATION',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: context.textMuted,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 10),

            // Link via Oneova Account (Auto-sync)
            _buildConnectMethodTile(
              icon: Icons.sync_rounded,
              title: 'Oneova Account Sync',
              subtitle: 'Auto-pair with any desktop signed in to your account',
              onTap: _isProcessing ? null : _linkViaAccount,
            ),
            const SizedBox(height: 10),

            // Scan QR Code
            _buildConnectMethodTile(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan Workstation QR Code',
              subtitle: 'Scan the pairing QR displayed on your computer',
              onTap: _isProcessing ? null : () => context.push('/qr_scanner'),
            ),
            const SizedBox(height: 10),

            // 6-Digit Session Code Card
            _buildPinEntryCard(),
            const SizedBox(height: 16),

            // Dev Bypass Pill
            Center(
              child: TextButton.icon(
                icon: const Icon(Icons.developer_mode_rounded, size: 14, color: AppColors.brandBlue),
                label: Text(
                  'Dev Bypass Mode (Local Test Host)',
                  style: GoogleFonts.inter(fontSize: 11, color: AppColors.brandBlue, fontWeight: FontWeight.w600),
                ),
                onPressed: _isProcessing ? null : _bypassConnect,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveWorkstationHeroCard(LinkedComputer computer) {
    final isSleeping = computer.isSleeping;
    final isLocked = computer.isLocked;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isSleeping ? AppColors.brandPink.withValues(alpha: 0.5) : AppColors.brandBlue.withValues(alpha: 0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandBlue.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(Icons.desktop_windows_rounded, color: AppColors.brandBlue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      computer.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isSleeping
                                ? Colors.amber
                                : computer.isOnline
                                    ? Colors.greenAccent
                                    : Colors.white24,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isSleeping
                              ? 'Sleep Mode'
                              : isLocked
                                  ? 'Locked'
                                  : computer.isOnline
                                      ? 'Online • Ready to Control'
                                      : 'Offline',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isSleeping
                                ? Colors.amber
                                : computer.isOnline
                                    ? context.textSecondary
                                    : context.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Text(
                  computer.activeWindow ?? 'Finder / Desktop',
                  style: GoogleFonts.inter(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandPink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Primary Launch Display Button (38-42px)
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              icon: const Icon(Icons.fullscreen_rounded, size: 18),
              label: Text(
                'Open Remote Display & Control',
                style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                ref.read(remoteConnectProvider.notifier).setActiveComputer(computer.id);
                context.push('/remote_control');
              },
            ),
          ),

          if (isSleeping || isLocked) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 38,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.6), width: 1.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                icon: _isUnlocking
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandPink))
                    : const Icon(Icons.lock_open_rounded, color: AppColors.brandPink, size: 16),
                label: Text(
                  _isUnlocking ? 'Unlocking...' : 'Wake & Unlock with Passkey',
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brandPink),
                ),
                onPressed: _isUnlocking ? null : () => _handleWakeAndUnlock(computer),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectMethodTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: Icon(icon, color: AppColors.brandBlue, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinEntryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: const Icon(Icons.password_rounded, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pair via 6-Digit Session Code',
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    Text(
                      'Enter code displayed in OneOva Desktop app',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: context.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: context.surfaceMid,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: context.border, width: 1.0),
                  ),
                  child: TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 3,
                      color: context.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: '123456',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14,
                        letterSpacing: 2,
                        color: context.textMuted,
                      ),
                      counterText: '',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  onPressed: _isProcessing ? null : _connectSession,
                  child: _isProcessing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(
                          'Pair',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
