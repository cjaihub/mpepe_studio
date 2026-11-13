import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../backend/remote_connect_service.dart';
import '../shared/theme/app_theme.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _animationController;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final rawValue = barcodes.first.rawValue?.trim();
    if (rawValue == null || rawValue.isEmpty) return;

    final pin = RemoteConnectService.extractPairingPin(rawValue);
    final isDirectDeviceToken = rawValue.startsWith('desktop_');
    if (pin == null && !isDirectDeviceToken) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();
    await _controller.stop();

    try {
      if (pin != null) {
        await ref.read(remoteConnectProvider.notifier).pairWithSessionPin(pin);
      } else {
        await ref.read(remoteConnectProvider.notifier).linkComputer(rawValue);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Workstation paired via QR session!'),
          backgroundColor: AppColors.brandBlue,
        ),
      );
      if (context.canPop()) {
        context.pop();
      }
      context.push('/remote_control');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('QR pairing failed: $e'),
          backgroundColor: AppColors.brandPink,
        ),
      );
      setState(() => _isProcessing = false);
      await _controller.start();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          _buildOverlay(),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/hub/home');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 24),
                ).animate().fadeIn().scale(),
                Text(
                  'Scan Workstation QR',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                ).animate().fadeIn(delay: 100.ms),
                IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 22),
                ).animate().fadeIn().scale(),
              ],
            ),
          ),
          Center(
            child: Container(
              width: 244,
              height: 244,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.brandBlue, width: 2.0),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Stack(
                children: [
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Positioned(
                        top: _animationController.value * 232,
                        left: 8,
                        right: 8,
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: AppColors.brandPink,
                            borderRadius: BorderRadius.circular(AppRadius.full),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.brandPink.withValues(alpha: 0.7),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ).animate().scale(delay: 150.ms, curve: Curves.easeOutBack),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.72),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: AppColors.brandBlue),
                    const SizedBox(height: 14),
                    Text(
                      'Establishing E2EE Workstation Session...',
                      style: GoogleFonts.inter(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ).animate().fadeIn(),
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 36,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_2_rounded, color: AppColors.brandBlue, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Point at the QR Session tab on Oneova Computer Agent to sign in & link instantly.',
                      style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.15, end: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.68),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Colors.transparent,
              backgroundBlendMode: BlendMode.dstOut,
            ),
          ),
          Center(
            child: Container(
              width: 244,
              height: 244,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
