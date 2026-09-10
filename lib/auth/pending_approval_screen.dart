import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../shared/theme/app_theme.dart';
import 'services/secure_logout_service.dart';
import 'package:url_launcher/url_launcher.dart';

class PendingApprovalScreen extends ConsumerStatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  ConsumerState<PendingApprovalScreen> createState() =>
      _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends ConsumerState<PendingApprovalScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      // Not authenticated — go back to root
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const SizedBox.shrink();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        // Auto-redirect when account is approved
        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final status = data?['status'] as String? ?? 'pending';
          if (status == 'active') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white),
                        SizedBox(width: 12),
                        Text('Account approved! Welcome to MPEPE Studio 🎉'),
                      ],
                    ),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 3),
                  ),
                );
                context.go('/hub/home');
              }
            });
          }
        }

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated hourglass with pulse ring
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        // Outer pulse ring
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (ctx, _) => Container(
                            width: 120 + (_pulseController.value * 30),
                            height: 120 + (_pulseController.value * 30),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(
                                        alpha:
                                            0.15 * (1 - _pulseController.value)),
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        // Icon container
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.2),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.hourglass_top_rounded,
                            size: 60,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        )
                            .animate(onPlay: (c) => c.repeat(reverse: true))
                            .shimmer(duration: 2.seconds, delay: 1.seconds),
                      ],
                    ),

                    const SizedBox(height: 48),

                    Text(
                      'Account Under Review',
                      style: AppTheme.h1Style.copyWith(fontSize: 28),
                      textAlign: TextAlign.center,
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.2),

                    const SizedBox(height: 16),

                    Text(
                      'Thank you for registering with MPEPE Studio.\n\nYour account is pending approval from our administrators. You\'ll be automatically let in the moment it\'s approved — no need to check back manually.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7),
                        height: 1.6,
                      ),
                    ).animate().fadeIn(delay: 600.ms).slideY(begin: 0.2),

                    const SizedBox(height: 32),

                    // Live status indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (ctx, _) => Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: _pulseController.value),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Watching for approval in real-time...',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 700.ms),

                    const SizedBox(height: 48),

                    // Contact support link
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('mailto:support@mpepestudio.com?subject=Account%20Approval%20Inquiry');
                        try {
                          await launchUrl(uri);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open email client. Contact: support@mpepestudio.com'),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.support_agent_rounded, size: 18),
                      label: const Text('Contact Support'),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ).animate().fadeIn(delay: 800.ms),

                    const SizedBox(height: 8),

                    TextButton(
                      onPressed: () async {
                        try {
                          await ref.read(secureLogoutServiceProvider).logout();
                        } finally {
                          if (context.mounted) {
                            context.go('/auth/main_login');
                          }
                        }
                      },
                      child: Text(
                        'Sign Out',
                        style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ).animate().fadeIn(delay: 900.ms),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
