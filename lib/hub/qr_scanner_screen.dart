import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/remote_connect_service.dart';
import '../shared/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class QRScannerScreen extends ConsumerStatefulWidget {
  const QRScannerScreen({super.key});

  @override
  ConsumerState<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends ConsumerState<QRScannerScreen> with SingleTickerProviderStateMixin {
  late MobileScannerController controller;
  bool _isProcessing = false;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
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
    controller.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
      final code = barcodes.first.rawValue!;
      if (code.startsWith('MPEPE-') || code.length > 5) {
        setState(() => _isProcessing = true);
        controller.stop();
        
        await ref.read(remoteConnectProvider.notifier).linkComputer(code);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Successfully connected to session!'), backgroundColor: Colors.green),
          );
          context.pop();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          MobileScanner(
            controller: controller,
            onDetect: _onDetect,
          ),
          
          // Premium Overlay Blur & Mask
          _buildOverlay(),
          
          // Header
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                ).animate().fadeIn().scale(),
                Text(
                  'Scan Connection QR',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ).animate().fadeIn(delay: 100.ms),
                IconButton(
                  onPressed: () => controller.toggleTorch(),
                  icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 28),
                ).animate().fadeIn().scale(),
              ],
            ),
          ),
          
          // Scanning Target & Animations
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.mpepeMaroon, width: 4),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Stack(
                children: [
                  // Animated Scanning Line
                  AnimatedBuilder(
                    animation: _animationController,
                    builder: (context, child) {
                      return Positioned(
                        top: _animationController.value * 230,
                        left: 0,
                        right: 0,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.mpepeMaroon,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.mpepeMaroon.withValues(alpha: 0.8),
                                blurRadius: 15,
                                spreadRadius: 5,
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ).animate().scale(delay: 200.ms, curve: Curves.easeOutBack),
          ),
          
          // Processing overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.8),
              child: const Center(
                child: CircularProgressIndicator(color: AppColors.mpepeMaroon),
              ),
            ).animate().fadeIn(),
            
          // Footer Instructions
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 48,
            left: 32,
            right: 32,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkSurface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    'Align the QR code within the frame to link your desktop application automatically.',
                    style: GoogleFonts.inter(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.7), BlendMode.srcOut),
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
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
