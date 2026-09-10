import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../backend/remote_connect_service.dart';
import '../backend/secure_pairing/crypto_utils.dart';
import '../shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final TextEditingController _pinController = TextEditingController();
  bool _isProcessing = false;

  // Constructs the same stable bypass device ID the Desktop Agent uses.
  Future<void> _bypassConnect() async {
    setState(() => _isProcessing = true);
    try {
      // Query for any bypass-mode desktop (deviceId starts with 'desktop_dev_bypass_')
      final snapshot = await FirebaseFirestore.instance
          .collection('registered_computers')
          .where('desktop_connected', isEqualTo: true)
          .get();

      final bypassDoc = snapshot.docs.firstWhere(
        (d) => d.id.startsWith('desktop_dev_bypass_'),
        orElse: () => throw Exception('No bypass desktop found. Make sure the Desktop Agent is running in Bypass Mode.'),
      );

      await ref.read(remoteConnectProvider.notifier).linkComputer(bypassDoc.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚡ Connected to Dev Bypass Desktop!'),
            backgroundColor: Colors.amber,
          ),
        );
        context.pushReplacement('/remote_control');
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
      if (user == null) throw Exception('You must be logged in to sync via account.');

      final snapshot = await FirebaseFirestore.instance
          .collection('registered_computers')
          .where('owner_uid', isEqualTo: user.uid)
          .where('desktop_connected', isEqualTo: true)
          .get();

      if (snapshot.docs.isEmpty) {
        throw Exception('No active desktops found linked to your account.');
      }

      final deviceId = snapshot.docs.first.id;
      // Because they share the same account, we bypass AES for WebRTC or rely on WebRTC's own secure DTLS.
      await ref.read(remoteConnectProvider.notifier).linkComputer(deviceId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Linked via MPEPE Account!'), backgroundColor: AppColors.mpepeMaroon),
        );
        context.pushReplacement('/remote_control');
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
        throw Exception('Invalid or expired PIN');
      }
      
      final data = doc.data()!;
      final salt = data['salt'] as String;
      final computerName = data['computer_name'] as String;
      
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('Not logged in');
      
      final key = CryptoUtils.deriveKeyFromPin(pin, salt);
      final encryptedUid = CryptoUtils.encryptPayload(user.uid, key);
      
      // Write response
      await FirebaseFirestore.instance
          .collection('desktop_pairing')
          .doc(pin)
          .collection('responses')
          .doc(user.uid)
          .set({
        'encrypted_uid': encryptedUid,
        'mobile_name': 'MPEPE Mobile',
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      // Link computer in local state
      final deviceId = 'desktop_${user.uid}_${computerName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
      await ref.read(remoteConnectProvider.notifier).linkComputer(deviceId, aesKey: key);
      
      if (mounted) {
        context.pushReplacement('/remote_control');
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

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground.withOpacity(0.8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: AppColors.mpepeMaroon,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.mpepeMaroon.withOpacity(0.4),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "Connect a Studio Application",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Pair your device with DaVinci Resolve, Premiere Pro, Logic Pro, or FL Studio.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Link via Account Button
                  _buildOptionButton(
                    icon: Icons.sync_rounded,
                    title: "Link via MPEPE Account",
                    subtitle: "Auto-connect to any logged-in desktop.",
                    onTap: _isProcessing ? null : _linkViaAccount,
                  ),
                  const SizedBox(height: 16),
                  
                  // Scan QR Code Button
                  _buildOptionButton(
                    icon: Icons.qr_code_scanner_rounded,
                    title: "Scan QR Code",
                    subtitle: "Scan the code shown in your desktop plugin.",
                    onTap: _isProcessing ? null : () => context.push('/qr_scanner'),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Divider
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.3), thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          "OR MANUAL CODE",
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.3), thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  // One-Time Session Code
                  Text(
                    "One-Time Session Code",
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText: "e.g. 123456",
                      hintStyle: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2,
                        color: Colors.white.withOpacity(0.4),
                      ),
                      prefixIcon: const Icon(Icons.password_rounded, color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black.withOpacity(0.2),
                      counterText: "",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Connect Session Button
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.mpepeMaroon,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _isProcessing ? null : _connectSession,
                      child: _isProcessing
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(color: AppColors.mpepeMaroon, strokeWidth: 3),
                            )
                          : Text(
                              "Connect Session",
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                    ),
                  ),

                  // Dev Bypass Section
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10.0),
                        child: Text(
                          "DEV / TESTING",
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.2), thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 46,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.developer_mode_rounded, size: 18, color: Colors.amber),
                      label: Text(
                        "Dev Bypass Connect",
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.amber, width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isProcessing ? null : _bypassConnect,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOptionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white.withOpacity(0.15),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
