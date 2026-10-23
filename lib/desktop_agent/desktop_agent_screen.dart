import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math' as math;
import 'dart:async';
import 'dart:convert';
import 'macos_mouse_ffi.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/studio_background.dart';
import '../backend/secure_pairing/secure_pairing_service.dart';
import '../backend/secure_pairing/crypto_utils.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../backend/telemetry/desktop_telemetry_service.dart';

class DesktopAgentScreen extends ConsumerStatefulWidget {
  const DesktopAgentScreen({super.key});

  @override
  ConsumerState<DesktopAgentScreen> createState() => _DesktopAgentScreenState();
}

class _DesktopAgentScreenState extends ConsumerState<DesktopAgentScreen> {
  final _firestore = FirebaseFirestore.instance;
  final bool _prOnline = false;
  final bool _drOnline = false;
  final String _computerName = Platform.localHostname;
  final List<String> _recentCommands = [];
  String? _manualUid;
  bool _bypassMode = false;
  final TextEditingController _uidController = TextEditingController();

  // ─────────────────────────────────────────────────────────────
  // DEV FLAG: Set to true to skip pairing and auto-register on
  // startup using the machine hostname as a stable UID.
  // Flip to false before shipping the production build.
  // ─────────────────────────────────────────────────────────────
  static const bool _kAutoBypass = true;

  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? _manualUid;
  StreamSubscription? _pairingSubscription;
  StreamSubscription? _commandSubscription;

  @override
  void dispose() {
    _uidController.dispose();
    _pairingSubscription?.cancel();
    _commandSubscription?.cancel();
    ref.read(desktopTelemetryProvider).stop();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initDesktopAgent();
  }

  Future<void> _initDesktopAgent() async {
    final pairingService = ref.read(securePairingProvider.notifier);
    final persistedUid = await pairingService.loadPersistedPairing();
    
    if (persistedUid != null && mounted) {
      setState(() {
        _manualUid = persistedUid;
      });
    }

    if (_currentUid != null) {
      _registerComputer();
      _listenForCommands();
    } else if (_kAutoBypass) {
      // Dev mode: skip pairing screen, go online immediately.
      await _bypassLogin();
    } else {
      _startSecurePairing();
    }
  }

  Future<void> _startSecurePairing() async {
    final pairingService = ref.read(securePairingProvider.notifier);
    final pin = pairingService.generatePairingPin();
    final salt = ref.read(securePairingProvider).salt;
    
    // Write pairing intent to Firestore
    await _firestore.collection('desktop_pairing').doc(pin).set({
      'computer_name': _computerName,
      'salt': salt,
      'status': 'waiting',
      'created_at': FieldValue.serverTimestamp(),
    });

    // Listen for mobile response
    _pairingSubscription = _firestore
        .collection('desktop_pairing')
        .doc(pin)
        .collection('responses')
        .snapshots()
        .listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final encryptedUid = data['encrypted_uid'] as String?;
          if (encryptedUid != null) {
            final key = CryptoUtils.deriveKeyFromPin(pin, salt);
            final decryptedUid = CryptoUtils.decryptPayload(encryptedUid, key);
            
              if (decryptedUid != null && decryptedUid.isNotEmpty) {
                // Successfully paired!
                pairingService.setDerivedKey(key);
                await pairingService.persistPairing(decryptedUid, key);
                _pairingSubscription?.cancel();
              
              // Clean up pairing doc
              await _firestore.collection('desktop_pairing').doc(pin).delete();
              
              if (mounted) {
                setState(() {
                  _manualUid = decryptedUid;
                });
              }
              _registerComputer();
              _listenForCommands();
            }
          }
        }
      }
    });
  }

  Future<void> _registerComputer() async {
    final uid = _currentUid;
    if (uid == null) return;

    // Use a hash of the hostname or something unique for this computer per user
    final deviceId = 'desktop_${uid}_${_computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    await _firestore.collection('registered_computers').doc(deviceId).set({
      'owner_uid': uid,
      'computer_name': _computerName,
      'desktop_connected': true,
      'status': 'online',
      'software': {
        'pr': _prOnline ? 'online' : 'offline',
        'dr': _drOnline ? 'online' : 'offline',
      },
      'last_seen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    ref.read(desktopTelemetryProvider).start(deviceId);
  }

  void _listenForCommands() {
    final uid = _currentUid;
    if (uid == null) return;
    
    final deviceId = 'desktop_${uid}_${_computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    _commandSubscription = _firestore
        .collection('registered_computers')
        .doc(deviceId)
        .collection('commands')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _executeCommand(change.doc.id, data);
        }
      }
    });
  }

  Future<void> _executeCommand(String docId, Map<String, dynamic> data) async {
    final softwareId = data['software_id'];
    final command = data['command'] ?? 'Unknown Command';
    
    // Decrypt payload if present
    final encryptedPayload = data['payload_encrypted'] as String?;
    String? decryptedPayloadJson;
    
    if (encryptedPayload != null && encryptedPayload.isNotEmpty) {
      final key = ref.read(securePairingProvider).activeKey;
      if (key != null) {
        decryptedPayloadJson = CryptoUtils.decryptPayload(encryptedPayload, key);
      }
    }
    
    // Add to recent commands for visual feedback
    if (mounted) {
      setState(() {
        final lockIcon = encryptedPayload != null ? '🔒 ' : '';
        _recentCommands.insert(0, '$lockIcon$softwareId: $command');
        if (_recentCommands.length > 5) _recentCommands.removeLast();
      });
    }

    final uid = _currentUid;
    if (uid == null) return;
    final deviceId = 'desktop_${uid}_${_computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';

    if (encryptedPayload != null && decryptedPayloadJson == null) {
      // Failed to decrypt
      await _firestore
          .collection('registered_computers')
          .doc(deviceId)
          .collection('commands')
          .doc(docId)
          .update({
        'status': 'error',
        'result_message': 'Failed to decrypt payload (E2EE validation failed)'
      });
      return;
    }

    Map<String, dynamic> payloadMap = {};
    if (decryptedPayloadJson != null) {
      try {
        payloadMap = jsonDecode(decryptedPayloadJson) as Map<String, dynamic>;
      } catch (_) {}
    } else if (data['payload'] is Map) {
      payloadMap = Map<String, dynamic>.from(data['payload'] as Map);
    }

    if (command == 'wake_and_unlock') {
      final passkey = (payloadMap['passkey'] ?? data['passkey'] ?? '').toString();
      await MacOSMouseController.wakeAndUnlock(passkey);
    } else if (command == 'key_tap') {
      final key = (payloadMap['key'] ?? data['key'] ?? '').toString();
      await MacOSMouseController.tapKey(key);
    } else if (command == 'key_combination') {
      final combo = (payloadMap['combo'] ?? data['combo'] ?? '').toString();
      await MacOSMouseController.sendHotkey(combo);
    } else if (command == 'type_text') {
      final text = (payloadMap['text'] ?? data['text'] ?? '').toString();
      await MacOSMouseController.typeString(text);
    } else if (command == 'mouse_left_down') {
      MacOSMouseController.leftClickDown();
    } else if (command == 'mouse_left_up') {
      MacOSMouseController.leftClickUp();
    } else if (command == 'mouse_left_click') {
      MacOSMouseController.click();
    } else if (command == 'mouse_right_click') {
      MacOSMouseController.rightClick();
    } else if (command == 'mouse_double_click') {
      MacOSMouseController.doubleClick();
    } else if (command == 'mouse_scroll') {
      final rawDy = payloadMap['dy'] ?? data['dy'] ?? 0.0;
      final dy = rawDy is num ? rawDy.toDouble() : 0.0;
      MacOSMouseController.scroll(dy);
    } else if (command == 'mouse_move') {
      final rawDx = payloadMap['dx'] ?? data['dx'] ?? 0.0;
      final rawDy = payloadMap['dy'] ?? data['dy'] ?? 0.0;
      final dx = rawDx is num ? rawDx.toDouble() : 0.0;
      final dy = rawDy is num ? rawDy.toDouble() : 0.0;
      MacOSMouseController.moveBy(dx, dy);
    } else if (command == 'execute_ai_task') {
      final prompt = (payloadMap['prompt'] ?? data['prompt'] ?? '').toString();
      await _handleAiTaskExecution(prompt);
    }

    await _firestore
        .collection('registered_computers')
        .doc(deviceId)
        .collection('commands')
        .doc(docId)
        .update({
      'status': 'completed',
      'result_message': 'Executed on desktop via Flutter Agent'
    });
  }

  Future<void> _handleAiTaskExecution(String prompt) async {
    final lower = prompt.toLowerCase();
    if (lower.contains('finder')) {
      await Process.run('open', ['-a', 'Finder']);
    } else if (lower.contains('render')) {
      // Trigger render combo in active NLE
      await MacOSMouseController.sendHotkey('ctrl+m');
    } else if (lower.contains('sync')) {
      await MacOSMouseController.sendHotkey('ctrl+s');
    } else if (lower.contains('lock')) {
      await Process.run('pmset', ['displaysleepnow']);
    } else if (lower.contains('fullscreen')) {
      await MacOSMouseController.sendHotkey('cmd+ctrl+f');
    }
  }

  void _showOvaAgentModal(BuildContext context) {
    final textController = TextEditingController();

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
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white12, width: 1.0),
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
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
                    ),
                    child: const Icon(Icons.auto_awesome_rounded, color: AppColors.brandPink, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ova AI Desktop Assistant',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Dispatch macros and desktop commands seamlessly',
                          style: GoogleFonts.inter(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildAiQuickChip('🎬 Render Timeline', () => _handleAiTaskExecution('render')),
                    const SizedBox(width: 8),
                    _buildAiQuickChip('🔄 Sync Project', () => _handleAiTaskExecution('sync')),
                    const SizedBox(width: 8),
                    _buildAiQuickChip('📁 Open Finder', () => _handleAiTaskExecution('finder')),
                    const SizedBox(width: 8),
                    _buildAiQuickChip('⚡ Fullscreen App', () => _handleAiTaskExecution('fullscreen')),
                    const SizedBox(width: 8),
                    _buildAiQuickChip('🔒 Sleep Display', () => _handleAiTaskExecution('lock')),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: textController,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.darkSurfaceHighlight,
                  hintText: 'Enter desktop automation command...',
                  hintStyle: GoogleFonts.inter(color: Colors.white30, fontSize: 12),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.brandPink),
                  ),
                ),
                onSubmitted: (val) async {
                  if (val.trim().isNotEmpty) {
                    await _handleAiTaskExecution(val.trim());
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  }
                },
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: const Icon(Icons.bolt_rounded, color: Colors.white, size: 20),
                label: Text(
                  'Dispatch Command',
                  style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                ),
                onPressed: () async {
                  final text = textController.text.trim();
                  if (text.isNotEmpty) {
                    await _handleAiTaskExecution(text);
                    if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAiQuickChip(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: GoogleFonts.inter(fontSize: 11, color: Colors.white70)),
      backgroundColor: AppColors.darkSurfaceHighlight,
      side: const BorderSide(color: Colors.white12),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = _currentUid;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
        title: const Text(
          'Desktop Agent',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.brandBlue, AppColors.brandPink],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brandPink.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
            ),
            tooltip: 'Ova AI Desktop Assistant',
            onPressed: () => _showOvaAgentModal(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StudioBackground(
        child: Center(
          child: Container(
            width: 450,
            padding: const EdgeInsets.all(40),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.darkSurfaceHighlight),
            ),
            child: uid == null ? _buildManualPairingScreen() : _buildAgentScreen(uid),
          ),
        ),
      ),
    );
  }

  Widget _buildManualPairingScreen() {
    final pairingState = ref.watch(securePairingProvider);
    final pin = pairingState.activePin ?? '......';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.security, size: 64, color: AppColors.brandBlue),
        const SizedBox(height: 20),
        const Text(
          "Secure Pairing",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          "Enter this secure pairing code on your OneOva mobile app to authenticate and establish an end-to-end encrypted connection.",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 40),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 2),
          ),
          child: Text(
            pin,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: 10.0,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 30),
        const CircularProgressIndicator(color: AppColors.brandBlue),
        const SizedBox(height: 16),
        const Text(
          "Waiting for mobile app...",
          style: TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        const Divider(color: AppColors.darkSurfaceHighlight),
        const SizedBox(height: 16),
        const Text(
          "DEV / TESTING",
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.5,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.developer_mode_rounded, size: 18, color: Colors.amber),
            label: const Text(
              "Bypass Login (Test Mode)",
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.amber, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _bypassLogin,
          ),
        ),
      ],
    );
  }

  Future<void> _bypassLogin() async {
    // Generate a stable, reproducible UID from the machine hostname so
    // the desktop always registers under the same deviceId across restarts.
    final stableUid = 'dev_bypass_${_computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
    _pairingSubscription?.cancel();
    setState(() {
      _manualUid = stableUid;
      _bypassMode = true;
    });
    _registerComputer();
    _listenForCommands();
  }

  Widget _buildAgentScreen(String uid) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.computer, size: 64, color: AppColors.brandBlue),
        const SizedBox(height: 20),
        const Text(
          "OneOva Desktop Agent",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _bypassMode
            ? "⚡ Dev Bypass Mode — ${uid.substring(0, math.min(16, uid.length))}"
            : "Connected as UID: ${uid.substring(0, math.min(8, uid.length))}...",
          style: TextStyle(
            fontSize: 14,
            color: _bypassMode ? Colors.amber : AppColors.textSecondary,
            fontWeight: _bypassMode ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        const SizedBox(height: 40),
        _buildStatusRow("OneOva Video Engine", _prOnline),
        const SizedBox(height: 16),
        _buildStatusRow("OneOva Timeline Engine", _drOnline),
        
        if (_recentCommands.isNotEmpty) ...[
          const SizedBox(height: 30),
          const Divider(color: AppColors.darkSurfaceHighlight),
          const SizedBox(height: 10),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              "Recent Commands:",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 10),
          ..._recentCommands.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: Row(
              children: [
                const Icon(Icons.bolt, size: 16, color: Colors.amber),
                const SizedBox(width: 8),
                Expanded(child: Text(c, style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ],
            ),
          )),
        ],

        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: () async {
              FirebaseAuth.instance.signOut();
              await ref.read(securePairingProvider.notifier).clearPairing();
              ref.read(desktopTelemetryProvider).stop();
              _commandSubscription?.cancel();
              setState(() {
                _manualUid = null;
              });
              _startSecurePairing();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              side: const BorderSide(color: AppColors.textMuted),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text("Disconnect (Sign Out)"),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRow(String name, bool isOnline) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isOnline ? AppColors.brandBlue.withValues(alpha: 0.18) : AppColors.brandPink.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isOnline ? AppColors.brandBlue.withValues(alpha: 0.4) : AppColors.brandPink.withValues(alpha: 0.4),
              width: 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isOnline ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                size: 16,
                color: isOnline ? AppColors.brandBlue : AppColors.brandPink,
              ),
              const SizedBox(width: 6),
              Text(
                isOnline ? "Online" : "Offline",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isOnline ? AppColors.brandBlue : AppColors.brandPink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
