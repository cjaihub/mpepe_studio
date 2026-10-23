import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/meta_oauth_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/utils/friendly_error_parser.dart';

// Platform accent colours (card glow / halo only)
const _fbBlue = Color(0xFF0081FB);
const _igStartColor = Color(0xFF833AB4);
const _igEndColor = Color(0xFFE1306C);

class MetaAppWizard extends ConsumerStatefulWidget {
  final String appName;

  const MetaAppWizard({super.key, required this.appName});

  @override
  ConsumerState<MetaAppWizard> createState() => _MetaAppWizardState();
}

class _MetaAppWizardState extends ConsumerState<MetaAppWizard>
    with TickerProviderStateMixin {
  late final MetaApp _app;
  final PageController _pageController = PageController();
  int _currentStep = 0; // 0=welcome, 1=loading, 2=accountPicker, 3=success
  bool _agreedToTerms = false;
  String? _selectedNiche;
  final List<String> _availableNiches = [
    'Tech & Gadgets',
    'Gaming',
    'Beauty & Fashion',
    'Finance & Crypto',
    'Education',
    'Entertainment',
    'Lifestyle',
    'Music',
    'Sports',
    'News & Politics',
    'General/Other'
  ];

  // Animation controllers
  late final AnimationController _pulseController;
  late final AnimationController _progressController;
  int _statusIndex = 0;

  final List<String> _statusMessages = [
    'Opening platform…',
    'Waiting for you to sign in…',
    'Exchanging secure tokens…',
    'Loading your accounts…',
  ];

  @override
  void initState() {
    super.initState();
    _app = MetaApp.fromString(widget.appName);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    // Status message cycling
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      setState(() {
        _statusIndex =
            (_statusIndex + 1) % _statusMessages.length;
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

  Color get _primaryColor =>
      _app == MetaApp.instagram ? _igEndColor : _fbBlue;

  Gradient? get _logoGradient => _app == MetaApp.instagram
      ? const LinearGradient(
          colors: [_igStartColor, _igEndColor],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        )
      : null;

  void _goToStep(int step) {
    if (!mounted) return;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
    setState(() => _currentStep = step);
  }

  // Called when user taps "Continue to [Platform]"
  Future<void> _startOAuth() async {
    _goToStep(1);
    _progressController.forward();

    // Start real OAuth flow
    await ref.read(metaOAuthProvider.notifier).startOAuth(_app);

    // If we got pages, advance to picker. If connected already (error branch), stay.
    if (!mounted) return;
    final oauthState = ref.read(metaOAuthProvider);

    if (oauthState.error != null) {
      // Stay on step 1 but show error — handled via listener below
      _goToStep(0);
    } else if (oauthState.availablePages.isNotEmpty) {
      _goToStep(2);
    }
  }

  Future<void> _confirmConnection() async {
    await ref.read(metaOAuthProvider.notifier).confirmConnection(_app, niche: _selectedNiche ?? 'General/Other');
    if (!mounted) return;
    final oauthState = ref.read(metaOAuthProvider);
    if (oauthState.isConnected) {
      _goToStep(3);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to oauth state changes to auto-advance
    ref.listen(metaOAuthProvider, (prev, next) {
      if (!mounted) return;
      if (next.availablePages.isNotEmpty && _currentStep == 1) {
        _goToStep(2);
      }
      if (next.error != null && _currentStep == 1) {
        // We received an error from OAuth step
        _showErrorSnackbar(FriendlyErrorParser.parse(next.error!));
        _goToStep(0);
      }
    });

    return Scaffold(
      backgroundColor: context.bg,
      body: Stack(
        children: [
          // Ambient glow backdrop
          _buildAmbientGlow(),

          SafeArea(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context),

                // Slim animated progress rail
                _buildProgressRail(context),

                // Page view
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _buildWelcomeStep(context),
                      _buildOAuthLoadingStep(context),
                      _buildAccountPickerStep(context),
                      _buildSuccessStep(context),
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

  // ─── Ambient background glow ──────────────────────────────────────────

  Widget _buildAmbientGlow() {
    return Positioned(
      top: -100,
      left: _app == MetaApp.instagram ? null : -80,
      right: _app == MetaApp.instagram ? -80 : null,
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
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
                    color: _primaryColor.withValues(alpha: 0.10),
                    blurRadius: 140,
                    spreadRadius: 80,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Top bar ─────────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: context.textSecondary, size: 22),
            onPressed: () {
              ref.read(metaOAuthProvider.notifier).reset();
              context.pop();
            },
          ),
          const Spacer(),
          // Step label
          Text(
            'Step ${_currentStep + 1} of 4',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textSecondary,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  // ─── Progress rail ────────────────────────────────────────────────────

  Widget _buildProgressRail(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: List.generate(4, (i) {
          final isActive = i <= _currentStep;
          return Expanded(
            child: AnimatedContainer(
              duration: 400.ms,
              curve: Curves.easeOutCubic,
              margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: isActive
                    ? _primaryColor
                    : context.border,
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: _primaryColor.withValues(alpha: 0.4),
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

  // ─── Step 0: Welcome & Permissions ───────────────────────────────────

  Widget _buildWelcomeStep(BuildContext context) {
    final permissions = _getPermissions();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo with glow halo
          Center(
            child: _buildPlatformHalo(size: 96),
          ).animate().scale(
                duration: 500.ms,
                curve: Curves.easeOutBack,
              ),

          const SizedBox(height: 32),

          // Headline
          Text(
            'Connect your',
            style: GoogleFonts.outfit(
              fontSize: 16,
              color: context.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ).animate().fadeIn(delay: 100.ms),
          Text(
            _app.displayName,
            style: GoogleFonts.outfit(
              fontSize: 38,
              fontWeight: FontWeight.w900,
              color: context.textPrimary,
              letterSpacing: -1.2,
            ),
          ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08),

          const SizedBox(height: 12),

          Text(
            _getSubtitle(),
            style: GoogleFonts.outfit(
              fontSize: 14.5,
              color: context.textSecondary,
              height: 1.6,
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 36),

          // Permissions
          Text(
            'What Oneova will access',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
              letterSpacing: 0.5,
            ),
          ).animate().fadeIn(delay: 250.ms),

          const SizedBox(height: 16),

          ...permissions.asMap().entries.map((entry) {
            return _PermissionRow(
              icon: entry.value.icon,
              title: entry.value.title,
              subtitle: entry.value.subtitle,
              glowColor: _primaryColor,
              delay: (300 + entry.key * 70).ms,
            );
          }),

          const SizedBox(height: 32),

          // Terms agreement
          _buildTermsToggle(context).animate().fadeIn(delay: 550.ms),

          const SizedBox(height: 24),

          // CTA button
          _buildPrimaryButton(
            context,
            label: _agreedToTerms
                ? 'Continue to ${_app.displayName}'
                : 'Agree to continue',
            icon: _agreedToTerms ? Icons.arrow_forward_rounded : Icons.lock_outline_rounded,
            onPressed: _agreedToTerms ? _startOAuth : null,
            delay: 600.ms,
          ),

          const SizedBox(height: 12),
          Center(
            child: Text(
              'We never see your password',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: context.textMuted,
              ),
            ),
          ).animate().fadeIn(delay: 650.ms),
        ],
      ),
    );
  }

  Widget _buildTermsToggle(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
      child: AnimatedContainer(
        duration: 250.ms,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _agreedToTerms
              ? _primaryColor.withValues(alpha: 0.08)
              : context.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _agreedToTerms
                ? _primaryColor.withValues(alpha: 0.35)
                : context.border,
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
                color: _agreedToTerms ? _primaryColor : Colors.transparent,
                border: Border.all(
                  color: _agreedToTerms ? _primaryColor : context.border,
                  width: 1.5,
                ),
              ),
              child: _agreedToTerms
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 14)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.outfit(
                    fontSize: 13.5,
                    color: context.textPrimary,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to '),
                    TextSpan(
                      text: "Meta's Terms of Service",
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(text: ' and Oneova Studio\'s '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: TextStyle(
                        color: _primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
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

  // ─── Step 1: OAuth Loading ────────────────────────────────────────────

  Widget _buildOAuthLoadingStep(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Pulsing logo with ripple rings
          SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ripple rings
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final progress =
                          (_pulseController.value + (i * 0.33)) % 1.0;
                      return Opacity(
                        opacity: (1 - progress) * 0.4,
                        child: Container(
                          width: 90 + (progress * 90),
                          height: 90 + (progress * 90),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _primaryColor.withValues(
                                  alpha: (1 - progress) * 0.5),
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
                // Logo circle
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primaryColor.withValues(alpha: 0.1),
                    border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.4),
                        width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.25),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: SvgPicture.asset(_app.logoAsset,
                        fit: BoxFit.contain),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 48),

          // Status message
          AnimatedSwitcher(
            duration: 500.ms,
            child: Text(
              _statusMessages[_statusIndex],
              key: ValueKey(_statusIndex),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: context.textPrimary,
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
              color: context.textSecondary,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 40),

          // Slim progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: AnimatedBuilder(
              animation: _progressController,
              builder: (context, child) {
                return LinearProgressIndicator(
                  value: null, // indeterminate
                  backgroundColor: context.border,
                  valueColor: AlwaysStoppedAnimation(_primaryColor),
                  minHeight: 3,
                );
              },
            ),
          ),

          const SizedBox(height: 36),

          TextButton.icon(
            onPressed: () {
              ref.read(metaOAuthProvider.notifier).reset();
              _goToStep(0);
            },
            icon: Icon(Icons.arrow_back_rounded,
                size: 16, color: context.textSecondary),
            label: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: context.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 2: Account Picker ────────────────────────────────────────────

  Widget _buildAccountPickerStep(BuildContext context) {
    final oauthState = ref.watch(metaOAuthProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _app == MetaApp.instagram
                ? 'Choose your Account'
                : 'Choose your Page',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: context.textPrimary,
              letterSpacing: -0.8,
            ),
          ).animate().fadeIn().slideY(begin: 0.08),

          const SizedBox(height: 6),

          Text(
            'Select the ${_app == MetaApp.instagram ? 'business account' : 'page'} you want to link to Oneova Studio.',
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: context.textSecondary,
              height: 1.5,
            ),
          ).animate().fadeIn(delay: 80.ms),

          const SizedBox(height: 28),

          // Account list
          Expanded(
            child: oauthState.isLoading
                ? _buildAccountsSkeleton(context)
                : oauthState.availablePages.isEmpty
                    ? _buildNoAccountsState(context)
                    : _buildAccountsList(context, oauthState),
          ),

          // Niche Selection
          const SizedBox(height: 16),
          Text(
            'Select Channel Niche',
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: context.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedNiche,
                hint: Text('Choose a niche for AI Optimization', style: TextStyle(color: context.textSecondary)),
                isExpanded: true,
                dropdownColor: context.surfaceMid,
                icon: const Icon(Icons.arrow_drop_down, color: AppColors.brandBlue),
                items: _availableNiches.map((niche) {
                  return DropdownMenuItem<String>(
                    value: niche,
                    child: Text(niche, style: TextStyle(color: context.textPrimary)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedNiche = val;
                  });
                },
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),

          // CTA
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: _buildPrimaryButton(
              context,
              label: 'Link This Account',
              icon: Icons.link_rounded,
              onPressed: (oauthState.selectedPage != null && _selectedNiche != null)
                  ? _confirmConnection
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountsList(BuildContext context, MetaOAuthState oauthState) {
    return ListView.separated(
      itemCount: oauthState.availablePages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final page = oauthState.availablePages[index];
        final isSelected = oauthState.selectedPage?.id == page.id;

        return GestureDetector(
          onTap: () =>
              ref.read(metaOAuthProvider.notifier).selectPage(page),
          child: AnimatedContainer(
            duration: 250.ms,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? _primaryColor.withValues(alpha: 0.08)
                  : context.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? _primaryColor.withValues(alpha: 0.45)
                    : context.border,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primaryColor.withValues(alpha: 0.12),
                    border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.2)),
                  ),
                  child: page.pictureUrl != null
                      ? ClipOval(
                          child: Image.network(
                            page.pictureUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _initials(page.name),
                          ),
                        )
                      : _initials(page.name),
                ),
                const SizedBox(width: 14),

                // Name + category + follower count
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        page.name,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      if (page.category != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          page.category!,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                      if (page.fanCount != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${_formatCount(page.fanCount!)} followers',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: context.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Check indicator
                AnimatedContainer(
                  duration: 200.ms,
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? _primaryColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? _primaryColor : context.border,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ],
            ),
          ),
        ).animate().fadeIn(delay: (index * 60).ms).slideY(begin: 0.08);
      },
    );
  }

  Widget _buildAccountsSkeleton(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 82,
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
        )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
              duration: 1200.ms,
              color: context.border.withValues(alpha: 0.5),
            ),
      ),
    );
  }

  Widget _buildNoAccountsState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 52, color: context.textMuted),
          const SizedBox(height: 16),
          Text(
            'No pages found',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure you have admin access to a ${_app == MetaApp.instagram ? 'Business Account' : 'Facebook Page'}.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 13,
              color: context.textMuted,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () {
              ref.read(metaOAuthProvider.notifier).reset();
              _goToStep(0);
            },
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('Try Again',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
            style: TextButton.styleFrom(foregroundColor: _primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _initials(String name) {
    return Center(
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: _primaryColor,
        ),
      ),
    );
  }

  // ─── Step 3: Success ──────────────────────────────────────────────────

  Widget _buildSuccessStep(BuildContext context) {
    final oauthState = ref.watch(metaOAuthProvider);
    final page = oauthState.selectedPage;

    return Stack(
      children: [
        // Confetti particles
        ..._buildConfettiParticles(),

        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success check bloom
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00E676).withValues(alpha: 0.12),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.25),
                      blurRadius: 32,
                      spreadRadius: 6,
                    )
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Color(0xFF00E676),
                  size: 50,
                ),
              )
                  .animate()
                  .scale(
                    duration: 500.ms,
                    curve: Curves.easeOutBack,
                    delay: 100.ms,
                  )
                  .fadeIn(),

              const SizedBox(height: 28),

              Text(
                'You\'re live on',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: context.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ).animate().fadeIn(delay: 400.ms),

              Text(
                _app.displayName,
                style: GoogleFonts.outfit(
                  fontSize: 38,
                  fontWeight: FontWeight.w900,
                  color: context.textPrimary,
                  letterSpacing: -1.2,
                ),
              ).animate().fadeIn(delay: 450.ms).slideY(begin: 0.08),

              const SizedBox(height: 24),

              // Account summary card
              if (page != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: context.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _primaryColor.withValues(alpha: 0.12),
                          border: Border.all(
                              color: _primaryColor.withValues(alpha: 0.25)),
                        ),
                        child: page.pictureUrl != null
                            ? ClipOval(
                                child: Image.network(
                                  page.pictureUrl!,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : _initials(page.name),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              page.name,
                              style: GoogleFonts.outfit(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimary,
                              ),
                            ),
                            if (page.fanCount != null)
                              Text(
                                '${_formatCount(page.fanCount!)} followers',
                                style: GoogleFonts.outfit(
                                  fontSize: 12,
                                  color: context.textSecondary,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: const Color(0xFF00E676)
                                  .withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '● Active',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF00E676),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn(delay: 550.ms).slideY(begin: 0.1),

              const Spacer(),

              // CTAs
              _buildPrimaryButton(
                context,
                label: 'Done',
                icon: Icons.check_circle_outline_rounded,
                onPressed: () {
                  ref.read(metaOAuthProvider.notifier).reset();
                  context.push('/social_hub/meta_picker');
                },
                delay: 700.ms,
              ),

              const SizedBox(height: 12),

              TextButton.icon(
                onPressed: () {
                  ref.read(metaOAuthProvider.notifier).reset();
                  context.push('/social_hub');
                },
                icon: Icon(Icons.open_in_new_rounded,
                    size: 16, color: _primaryColor),
                label: Text(
                  'Go to Social Hub',
                  style: GoogleFonts.outfit(
                    color: _primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ).animate().fadeIn(delay: 800.ms),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildConfettiParticles() {
    final random = Random(42);
    final colors = [
      _primaryColor,
      AppColors.brandBlue,
      const Color(0xFF00E676),
      Colors.white.withValues(alpha: 0.5),
    ];

    return List.generate(20, (i) {
      final x = random.nextDouble();
      final y = random.nextDouble() * 0.5;
      final size = 4.0 + random.nextDouble() * 6;
      final color = colors[random.nextInt(colors.length)];
      final delay = (random.nextDouble() * 600).ms;

      return Positioned(
        left: MediaQuery.of(context).size.width * x,
        top: MediaQuery.of(context).size.height * y,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(size / 2),
          ),
        )
            .animate(delay: delay)
            .fadeIn(duration: 300.ms)
            .moveY(
              begin: 0,
              end: 120,
              duration: 1500.ms,
              curve: Curves.easeIn,
            )
            .then()
            .fadeOut(duration: 500.ms),
      );
    });
  }

  // ─── Shared Widgets ───────────────────────────────────────────────────

  Widget _buildPlatformHalo({required double size}) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final glowAlpha = 0.15 + (_pulseController.value * 0.1);
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: _logoGradient != null
                ? null
                : RadialGradient(
                    colors: [
                      _primaryColor.withValues(alpha: glowAlpha),
                      _primaryColor.withValues(alpha: 0),
                    ],
                  ),
            color: _logoGradient != null ? null : Colors.transparent,
            boxShadow: [
              BoxShadow(
                color: _primaryColor.withValues(alpha: glowAlpha),
                blurRadius: 32,
                spreadRadius: 8,
              )
            ],
          ),
          child: _logoGradient != null
              ? Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: _logoGradient,
                    boxShadow: [
                      BoxShadow(
                        color: _igEndColor.withValues(alpha: glowAlpha),
                        blurRadius: 32,
                        spreadRadius: 8,
                      )
                    ],
                  ),
                  padding: EdgeInsets.all(size * 0.22),
                  child: SvgPicture.asset(_app.logoAsset, fit: BoxFit.contain),
                )
              : Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _primaryColor.withValues(alpha: 0.12),
                    border: Border.all(
                        color: _primaryColor.withValues(alpha: 0.3)),
                  ),
                  padding: EdgeInsets.all(size * 0.22),
                  child: SvgPicture.asset(_app.logoAsset, fit: BoxFit.contain),
                ),
        );
      },
    );
  }

  Widget _buildPrimaryButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Duration delay = Duration.zero,
  }) {
    final isEnabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      child: AnimatedContainer(
        duration: 250.ms,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: isEnabled
              ? LinearGradient(
                  colors: _app == MetaApp.instagram
                      ? [_igStartColor, _igEndColor]
                      : [_primaryColor, _primaryColor.withValues(alpha: 0.75)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : null,
          color: isEnabled ? null : context.surface,
          border: isEnabled
              ? null
              : Border.all(color: context.border),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.35),
                    blurRadius: 20,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  )
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isEnabled
                          ? Colors.white
                          : context.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    icon,
                    size: 18,
                    color: isEnabled ? Colors.white : context.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).animate().fadeIn(delay: delay).slideY(
          begin: 0.06,
          delay: delay,
          duration: 400.ms,
        );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  String _getSubtitle() {
    switch (_app) {
      case MetaApp.facebook:
        return 'Let Oneova Studio post on your Pages, track what\'s working, and reply to comments — all without leaving the app.';
      case MetaApp.instagram:
        return 'Publish Reels, manage story insights, and moderate comments on your Instagram Business Account from one place.';
      case MetaApp.whatsapp:
        return 'Connect your WhatsApp Business number to manage broadcast lists and customer replies.';
    }
  }

  List<_Permission> _getPermissions() {
    switch (_app) {
      case MetaApp.facebook:
        return [
          _Permission(
            icon: Icons.bar_chart_rounded,
            title: 'Analytics & Insights',
            subtitle: 'Views, reach, and engagement data from your Pages',
          ),
          _Permission(
            icon: Icons.edit_rounded,
            title: 'Publish Posts',
            subtitle: 'Schedule and publish content on your behalf',
          ),
          _Permission(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Comments & Replies',
            subtitle: 'Read and respond to comments from the inbox',
          ),
          _Permission(
            icon: Icons.list_alt_rounded,
            title: 'Your Pages List',
            subtitle: 'See which pages you manage to let you choose one',
          ),
        ];
      case MetaApp.instagram:
        return [
          _Permission(
            icon: Icons.video_library_outlined,
            title: 'Publish Reels & Posts',
            subtitle: 'Post single images, carousels and Reels',
          ),
          _Permission(
            icon: Icons.insights_rounded,
            title: 'Insights & Analytics',
            subtitle: 'Impressions, reach, and story metrics',
          ),
          _Permission(
            icon: Icons.comment_outlined,
            title: 'Comments',
            subtitle: 'View and reply to comments on your posts',
          ),
          _Permission(
            icon: Icons.business_center_outlined,
            title: 'Business Account Info',
            subtitle: 'Profile, category and linked Facebook Page',
          ),
        ];
      case MetaApp.whatsapp:
        return [
          _Permission(
            icon: Icons.message_outlined,
            title: 'Send Messages',
            subtitle: 'Send template messages to opted-in customers',
          ),
          _Permission(
            icon: Icons.people_outline_rounded,
            title: 'Contact Lists',
            subtitle: 'Manage business contact groups',
          ),
        ];
    }
  }

  String _formatCount(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: GoogleFonts.outfit(color: Colors.white)),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Permission item model
// ─────────────────────────────────────────────

class _Permission {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Permission({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

// ─────────────────────────────────────────────
//  Permission row widget
// ─────────────────────────────────────────────

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
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: glowColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: glowColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: glowColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 12.5,
                    color: context.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: delay).slideX(
          begin: -0.05,
          delay: delay,
          duration: 350.ms,
        );
  }
}
