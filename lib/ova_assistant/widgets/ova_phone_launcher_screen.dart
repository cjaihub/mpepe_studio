import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import 'ova_gesture_detector.dart';
import 'ova_assistant_sheet.dart';

/// Interactive Android phone simulator and Ova Assistant playground
/// Replicating the home screen environment and the double-tap & hold 3s access gesture.
class OvaPhoneLauncherScreen extends StatefulWidget {
  const OvaPhoneLauncherScreen({super.key});

  @override
  State<OvaPhoneLauncherScreen> createState() => _OvaPhoneLauncherScreenState();
}

class _OvaPhoneLauncherScreenState extends State<OvaPhoneLauncherScreen> {
  bool _sheetAutoOpened = false;

  @override
  void initState() {
    super.initState();
    // Prompt guidance after a brief delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_sheetAutoOpened && mounted) {
        _sheetAutoOpened = true;
        // Open the sheet initially to showcase the user's requested layout immediately,
        // or the user can dismiss it and test the 3-second hold gesture!
        OvaAssistantSheet.show(context);
      }
    });
  }

  void _summonAssistant() {
    HapticFeedback.heavyImpact();
    OvaAssistantSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return OvaGestureDetector(
      onTriggerOva: _summonAssistant,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            // ── Phone Wallpaper (Stylish gradient + portrait aesthetic) ──
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF0F1E36),
                      Color(0xFF17202A),
                      Color(0xFF0B0D13),
                    ],
                  ),
                ),
                child: Opacity(
                  opacity: 0.25,
                  child: Image.asset(
                    'assets/images/oneova_logo.jpg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),

            SafeArea(
              child: Column(
                children: [
                  // ── Android Top Status Bar (Matching screenshot: 5:51, WhatsApp, Messenger, 4G, 100%) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: Row(
                      children: [
                        // Time
                        const Text(
                          '5:51',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // App notification icons
                        const Icon(Icons.chat_bubble, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        const Icon(Icons.message, color: Colors.white70, size: 14),
                        const SizedBox(width: 4),
                        const Icon(Icons.music_note, color: Colors.white70, size: 14),

                        const Spacer(),

                        // Network and Battery
                        const Text(
                          '1.00 KB/s',
                          style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.network_cell, color: Colors.white, size: 15),
                        const SizedBox(width: 4),
                        const Text(
                          '4G',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 6),
                        // 100% battery pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            '100',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Top Navigation & Instructions Bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
                          tooltip: 'Back to Hub',
                          onPressed: () => context.pop(),
                        ),
                        const Expanded(
                          child: Text(
                            'Android Ova Assistant',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.info_outline, color: Colors.white70),
                          onPressed: () {
                            _showGestureGuidanceDialog(context);
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Android Home Screen App Icons (From Screenshot) ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Owl Icon
                        _buildHomeScreenAppIcon(
                          iconWidget: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1F24),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                            ),
                            child: const Center(
                              child: Icon(Icons.cruelty_free, color: Colors.redAccent, size: 30),
                            ),
                          ),
                          label: 'Learn',
                        ),

                        // Infinity Icon (Meta)
                        _buildHomeScreenAppIcon(
                          iconWidget: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E4E8),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Center(
                              child: Icon(Icons.all_inclusive_rounded, color: Colors.black87, size: 34),
                            ),
                          ),
                          label: 'Meta',
                        ),

                        // OneOva Icon (OR)
                        _buildHomeScreenAppIcon(
                          iconWidget: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.brandBlue, Color(0xFF1E88E5)],
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white30, width: 2),
                            ),
                            child: const Center(
                              child: Icon(Icons.video_library_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                          label: 'OneOva',
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Interactive Gesture Instruction Banner
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.surface.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.brandBlue.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brandBlue.withValues(alpha: 0.25),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.brandPink,
                              ),
                              child: const Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'How to Access Ova Assistant:',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Draw an "O" anywhere on the screen.\n'
                          'Ova opens with what you circled as context. Taps, double taps and swipes never open it.',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.bolt, color: Colors.white, size: 18),
                            label: const Text('Open Ova Assistant Now', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.brandBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _summonAssistant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Android home pill bar
                  Container(
                    width: 120,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreenAppIcon({required Widget iconWidget, required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 68,
          height: 68,
          child: iconWidget,
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(color: Colors.black, blurRadius: 4),
            ],
          ),
        ),
      ],
    );
  }

  void _showGestureGuidanceDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Ova Assistant Gesture', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'Draw an "O" anywhere on the screen to open Ova.\n\n'
          'It is the only gesture that opens Ova, so tapping, double tapping and scrolling never bring it up by accident.',
          style: TextStyle(color: ctx.textSecondary, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Got it'),
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
  }
}
