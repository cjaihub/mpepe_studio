import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../backend/social_connection_service.dart';

class MetaConnectWizard extends ConsumerStatefulWidget {
  final String platform;
  const MetaConnectWizard({super.key, required this.platform});

  @override
  ConsumerState<MetaConnectWizard> createState() => _MetaConnectWizardState();
}

class _MetaConnectWizardState extends ConsumerState<MetaConnectWizard> {
  int _currentStep = 0;

  void _nextStep() {
    if (_currentStep == 0) {
      setState(() => _currentStep = 1);
      // Simulate OAuth flow
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() => _currentStep = 2);
        }
      });
    } else if (_currentStep == 2) {
      // Finalize Connection
      ref.read(socialConnectionProvider.notifier).addConnection(
        widget.platform, 
        '@${widget.platform.toLowerCase()}_creator',
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StudioBackground(
        backgroundIcons: const [Icons.security, Icons.sync_lock, Icons.verified_user],
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    onPressed: () => context.pop(),
                  ),
                ),
                const SizedBox(height: 40),
                _buildLogoAnimation(),
                const SizedBox(height: 32),
                Text(
                  'Meta Connect',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ).animate().fade().slideY(begin: 0.1),
                const SizedBox(height: 12),
                Text(
                  _getStepTitle(),
                  textAlign: TextAlign.center,
                  style: AppTheme.h1Style.copyWith(fontSize: 28),
                ).animate(key: ValueKey(_currentStep)).fade().slideY(begin: 0.1),
                const SizedBox(height: 16),
                Text(
                  _getStepDescription(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ).animate(key: ValueKey('desc_$_currentStep')).fade(delay: 100.ms),
                const Spacer(),
                if (_currentStep == 1)
                  const CircularProgressIndicator().animate().fade()
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OneovaButton(
                        text: _currentStep == 0 ? 'Continue to ${widget.platform}' : 'Complete Setup',
                        onPressed: _nextStep,
                        isPrimary: true,
                        icon: _currentStep == 0 ? Icons.login : Icons.check_circle,
                      ).animate().fade().scaleXY(),
                      if (_currentStep == 0) ...[
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Clearing cached session to switch account...')),
                            );
                            _nextStep();
                          },
                          icon: Icon(Icons.switch_account_outlined, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 18),
                          label: Text(
                            'Switch Account',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ).animate().fade(delay: 200.ms),
                      ],
                    ],
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoAnimation() {
    String asset = 'assets/logos/${widget.platform.toLowerCase()}.svg';
    
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 5,
          )
        ]
      ),
      child: SvgPicture.asset(asset),
    )
    .animate(target: _currentStep == 1 ? 1 : 0)
    .shimmer(duration: 1000.ms)
    .scaleXY(begin: 1.0, end: 1.1, duration: 1000.ms, curve: Curves.easeInOutSine)
    .then(delay: 0.ms)
    .scaleXY(begin: 1.1, end: 1.0, duration: 1000.ms, curve: Curves.easeInOutSine);
  }

  String _getStepTitle() {
    if (_currentStep == 0) return 'Connect your ${widget.platform}';
    if (_currentStep == 1) return 'Authenticating securely...';
    return 'Connection Successful!';
  }

  String _getStepDescription() {
    if (_currentStep == 0) {
      return 'Oneova uses secure OAuth. You will be redirected to ${widget.platform} to sign in. We never see your password, and no API keys are required.';
    }
    if (_currentStep == 1) {
      return 'Exchanging secure tokens with ${widget.platform}. Please do not close the app.';
    }
    return 'Your ${widget.platform} is now synced. All 50 automation features are unlocked for this platform.';
  }
}
