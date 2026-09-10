import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/tiktok_oauth_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/friendly_error_parser.dart';

const _tiktokCyan = Color(0xFF00F2FE);
const _tiktokPink = Color(0xFFFE0979);

class TikTokConnectWizard extends ConsumerStatefulWidget {
  const TikTokConnectWizard({super.key});

  @override
  ConsumerState<TikTokConnectWizard> createState() => _TikTokConnectWizardState();
}

class _TikTokConnectWizardState extends ConsumerState<TikTokConnectWizard>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0=welcome, 1=loading, 2=success
  bool _agreedToTerms = false;

  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  int _statusIndex = 0;

  final List<String> _statusMessages = [
    'Opening TikTok…',
    'Waiting for you to authorize…',
    'Exchanging secure tokens…',
    'Loading your account…',
  ];

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      setState(() {
        _statusIndex = (_statusIndex + 1) % _statusMessages.length;
      });
      return _currentStep == 1;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (!mounted) return;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    setState(() => _currentStep = step);
  }

  Future<void> _startOAuth() async {
    _goToStep(1);
    _progressController.forward();

    await ref.read(tiktokOAuthProvider.notifier).startOAuth();

    if (!mounted) return;
    final oauthState = ref.read(tiktokOAuthProvider);

    if (oauthState.error != null) {
      _goToStep(0);
    } else if (oauthState.account != null) {
      // Automatically confirm connection since TikTok usually implies 1 account
      await _confirmConnection();
    }
  }

  Future<void> _confirmConnection() async {
    await ref.read(tiktokOAuthProvider.notifier).confirmConnection();
    if (!mounted) return;
    final oauthState = ref.read(tiktokOAuthProvider);
    if (oauthState.isConnected) {
      _goToStep(2);
    }
  }

  void _showErrorSnackbar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error, style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(tiktokOAuthProvider, (prev, next) {
      if (!mounted) return;
      if (next.error != null && _currentStep == 1) {
        // We received an error from OAuth step
        _showErrorSnackbar(FriendlyErrorParser.parse(next.error!));
        _goToStep(0);
      }
    });

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Stack(
        children: [
          _buildAmbientGlow(),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildProgressRail(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomeStep(),
                      _buildOAuthLoadingStep(),
                      _buildSuccessStep(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientGlow() {
    return Positioned(
      top: -100,
      right: -80,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (_, __) {
          final scale = 1.0 + (_pulseController.value * 0.06);
          return Transform.scale(
            scale: scale,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _tiktokCyan.withValues(alpha: 0.10),
                    blurRadius: 140,
                    spreadRadius: 80,
                  ),
                  BoxShadow(
                    color: _tiktokPink.withValues(alpha: 0.05),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary, size: 22),
            onPressed: () {
              ref.read(tiktokOAuthProvider.notifier).reset();
              context.pop();
            },
          ),
          const Spacer(),
          Text(
            'Step ${_currentStep + 1} of 3',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildProgressRail() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: List.generate(3, (i) {
          final isActive = i <= _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: 400.ms,
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: isActive
                    ? const LinearGradient(colors: [_tiktokCyan, _tiktokPink])
                    : null,
                color: isActive ? null : AppColors.outline,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: _tiktokCyan.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        )
                      ]
                    : null,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWelcomeStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: _buildPlatformHalo(size: 96),
          ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 32),
          Text(
            'Connect your',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ).animate().fadeIn(delay: 100.ms),
          Text(
            'TikTok Account',
            style: GoogleFonts.outfit(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -1.2,
            ),
          ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08),
          const SizedBox(height: 12),
          Text(
            'Link your TikTok to sync videos and leverage MPEPE AI for shorts.',
            style: GoogleFonts.outfit(
              fontSize: 14.5,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 36),
          Text(
            'What MPEPE will access',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: 0.5,
            ),
          ).animate().fadeIn(delay: 250.ms),
          const SizedBox(height: 16),
          _PermissionRow(
            icon: Icons.person_outline_rounded,
            title: 'Profile Information',
            subtitle: 'Read your display name and avatar',
            glowColor: _tiktokCyan,
            delay: 300.ms,
          ),
          _PermissionRow(
            icon: Icons.video_library_outlined,
            title: 'Video Library',
            subtitle: 'Read your published videos',
            glowColor: _tiktokPink,
            delay: 370.ms,
          ),
          const SizedBox(height: 32),
          _buildTermsToggle().animate().fadeIn(delay: 550.ms),
          const SizedBox(height: 24),
          _buildPrimaryButton(
            label: _agreedToTerms ? 'Continue to TikTok' : 'Agree to continue',
            icon: _agreedToTerms ? Icons.arrow_forward_rounded : Icons.lock_outline_rounded,
            onPressed: _agreedToTerms ? _startOAuth : null,
            delay: 600.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildPlatformHalo({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _tiktokCyan.withValues(alpha: 0.1),
        border: Border.all(color: _tiktokPink.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _tiktokCyan.withValues(alpha: 0.25),
            blurRadius: 24,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: SvgPicture.asset('assets/logos/tiktok.svg', fit: BoxFit.contain, colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn)),
      ),
    );
  }

  Widget _buildTermsToggle() {
    return GestureDetector(
      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _agreedToTerms ? _tiktokCyan.withValues(alpha: 0.08) : AppColors.darkSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _agreedToTerms ? _tiktokCyan.withValues(alpha: 0.35) : AppColors.outline,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: 200.ms,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _agreedToTerms ? _tiktokCyan : Colors.transparent,
                border: Border.all(
                  color: _agreedToTerms ? _tiktokCyan : AppColors.outline,
                  width: 1.5,
                ),
              ),
              child: _agreedToTerms ? const Icon(Icons.check_rounded, color: Colors.black, size: 14) : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to '),
                    TextSpan(
                      text: "TikTok's Terms of Service",
                      style: TextStyle(color: _tiktokPink, fontWeight: FontWeight.w600),
                    ),
                    const TextSpan(text: ' and MPEPE Studio\'s '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(color: _tiktokCyan, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOAuthLoadingStep() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) {
                      final progress = (_pulseController.value + (i * 0.33)) % 1.0;
                      return Opacity(
                        opacity: (1 - progress) * 0.4,
                        child: Container(
                          width: 90 + (progress * 90),
                          height: 90 + (progress * 90),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: i % 2 == 0 ? _tiktokCyan : _tiktokPink,
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
                _buildPlatformHalo(size: 90),
              ],
            ),
          ),
          const SizedBox(height: 48),
          AnimatedSwitcher(
            duration: 500.ms,
            child: Text(
              _statusMessages[_statusIndex],
              key: ValueKey(_statusIndex),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Please complete the sign-in in your browser.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (_, __) {
                return LinearProgressIndicator(
                  value: null,
                  backgroundColor: AppColors.outline,
                  valueColor: AlwaysStoppedAnimation(_tiktokCyan),
                  minHeight: 3,
                );
              },
            ),
          ),
          const SizedBox(height: 36),
          TextButton.icon(
            onPressed: () {
              ref.read(tiktokOAuthProvider.notifier).reset();
              _goToStep(0);
            },
            icon: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.textSecondary),
            label: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    final oauthState = ref.watch(tiktokOAuthProvider);
    final account = oauthState.account;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_tiktokCyan, _tiktokPink]),
              boxShadow: [
                BoxShadow(
                  color: _tiktokCyan.withValues(alpha: 0.3),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
          ).animate().scale(duration: 500.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 32),
          Text(
            'Connection Successful!',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
              letterSpacing: -0.5,
            ),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
          const SizedBox(height: 12),
          Text(
            'Your TikTok account is now securely linked to MPEPE Studio.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 300.ms),
          const SizedBox(height: 32),
          if (account != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: account.avatarUrl != null ? NetworkImage(account.avatarUrl!) : null,
                    backgroundColor: _tiktokCyan.withValues(alpha: 0.2),
                    child: account.avatarUrl == null ? const Icon(Icons.person, color: Colors.white) : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.displayName,
                          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text('TikTok User', style: GoogleFonts.outfit(color: AppColors.textSecondary, fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
          const SizedBox(height: 48),
          _buildPrimaryButton(
            label: 'Go to Dashboard',
            icon: Icons.dashboard_rounded,
            onPressed: () {
              ref.read(tiktokOAuthProvider.notifier).reset();
              context.push('/social_hub');
            },
            delay: 500.ms,
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Duration delay = Duration.zero,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? AppColors.darkSurfaceHighlight : AppColors.textPrimary,
          foregroundColor: AppColors.darkBackground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        icon: Icon(icon, size: 20),
        label: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
    ).animate().fadeIn(delay: delay).slideY(begin: 0.2, delay: delay);
  }
}

class _PermissionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color glowColor;
  final Duration delay;

  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.glowColor,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: glowColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glowColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: glowColor, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay).slideX(begin: 0.1, delay: delay);
  }
}
