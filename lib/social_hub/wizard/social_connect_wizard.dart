import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../backend/social_connection_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../shared/widgets/studio_background.dart';

class SocialConnectWizard extends ConsumerStatefulWidget {
  final String platform;
  
  const SocialConnectWizard({super.key, required this.platform});

  @override
  ConsumerState<SocialConnectWizard> createState() => _SocialConnectWizardState();
}

class _SocialConnectWizardState extends ConsumerState<SocialConnectWizard> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _agreedToTerms = false;
  String? _selectedAccount;
  bool _isConnecting = false;

  final List<String> _mockAccounts = [
    'Oneova Official',
    'Oneova Gaming',
    'Oneova Vlogs',
  ];

  String _getPlatformLogoPath() {
    switch (widget.platform.toLowerCase()) {
      case 'facebook': return 'assets/logos/facebook.svg';
      case 'instagram': return 'assets/logos/instagram.svg';
      case 'tiktok': return 'assets/logos/tiktok.svg';
      case 'youtube': return 'assets/logos/youtube.svg';
      default: return '';
    }
  }

  Widget _buildPlatformLogo({double size = 48}) {
    final path = _getPlatformLogoPath();
    if (path.isEmpty) return Icon(Icons.link, size: size, color: Theme.of(context).colorScheme.primary);
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
    );
  }

  void _nextStep() {
    if (_currentStep < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep++);
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() => _currentStep--);
    } else {
      context.pop();
    }
  }

  Future<void> _submitConnection() async {
    if (_selectedAccount == null) return;
    
    setState(() => _isConnecting = true);
    
    // Simulate network delay for the wizard effect
    await Future.delayed(const Duration(seconds: 2));
    
    await ref.read(socialConnectionProvider.notifier).addConnection(
      widget.platform,
      _selectedAccount!,
    );
    
    if (mounted) {
      setState(() => _isConnecting = false);
      
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.6),
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OneovaCard(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.neonGreen.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_circle_outline, color: AppColors.neonGreen, size: 48),
                      ).animate().scale(delay: 200.ms, duration: 400.ms, curve: Curves.easeOutBack),
                      const SizedBox(height: 24),
                      Text('Connection Secure', style: AppTheme.h1Style.copyWith(fontSize: 22)),
                      const SizedBox(height: 8),
                      Text(
                        'Your ${widget.platform} account "$_selectedAccount" is now live.',
                        textAlign: TextAlign.center,
                        style: AppTheme.bodyStyle.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: OneovaButton(
                          text: 'Return to Hub',
                          onPressed: () {
                            context.pop(); // pop dialog
                            context.pop(); // pop wizard
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (context, anim1, anim2, child) {
          return FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
              ),
              child: child,
            ),
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: _prevStep,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPlatformLogo(size: 24),
            const SizedBox(width: 12),
            Text('Connect ${widget.platform}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: context.textPrimary)),
          ],
        ),
        centerTitle: true,
      ),
      body: StudioBackground(
        backgroundIcons: const [Icons.link, Icons.security, Icons.cloud_sync],
        child: SafeArea(
          child: Column(
            children: [
              _buildProgressIndicator(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildRequirementsStep(),
                    _buildAccountPickerStep(),
                    _buildSubmissionStep(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: List.generate(3, (index) {
          final isActive = index <= _currentStep;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 4,
              decoration: BoxDecoration(
                color: isActive ? AppColors.brandBlue : context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildRequirementsStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 1 of 3', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Requirements & Agreements', style: AppTheme.h1Style),
          const SizedBox(height: 24),
          Text(
            'To connect your ${widget.platform} account, Oneova Studio requires the following permissions:',
            style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          _buildPermissionItem(Icons.analytics_outlined, 'Read analytics data (views, engagement)'),
          const SizedBox(height: 16),
          _buildPermissionItem(Icons.cloud_upload_outlined, 'Publish and draft videos on your behalf'),
          const SizedBox(height: 16),
          _buildPermissionItem(Icons.comment_outlined, 'Read and respond to comments'),
          const Spacer(),
          OneovaCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Switch(
                  value: _agreedToTerms,
                  activeThumbColor: AppColors.brandBlue,
                  onChanged: (val) {
                    setState(() => _agreedToTerms = val);
                  },
                ),
                Expanded(
                  child: Text(
                    'I agree to the Terms of Service and Privacy Policy.',
                    style: AppTheme.bodyStyle.copyWith(color: context.textPrimary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OneovaButton(
              text: 'Continue',
              onPressed: _agreedToTerms ? _nextStep : () {},
              isPrimary: _agreedToTerms,
            ),
          ),
        ],
      ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.05),
    );
  }

  Widget _buildPermissionItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: AppColors.brandBlue, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: context.textPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountPickerStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 2 of 3', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Select Account', style: AppTheme.h1Style),
          const SizedBox(height: 24),
          Text(
            'Choose which ${widget.platform} account you want to link to your studio.',
            style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: ListView.builder(
              itemCount: _mockAccounts.length,
              itemBuilder: (context, index) {
                final account = _mockAccounts[index];
                final isSelected = _selectedAccount == account;
                return GestureDetector(
                  onTap: () {
                    setState(() => _selectedAccount = account);
                  },
                  child: OneovaCard(
                    padding: const EdgeInsets.all(16),
                    borderColor: isSelected ? AppColors.brandBlue : null,
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.2) : context.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: isSelected ? AppColors.brandBlue : context.border),
                          ),
                          child: Center(
                            child: Text(account[0], style: AppTheme.h2Style.copyWith(color: isSelected ? AppColors.brandBlue : context.textPrimary)),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(account, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: AppColors.brandBlue),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: (index * 100).ms).slideX(begin: 0.1);
              },
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: OneovaButton(
              text: 'Continue',
              onPressed: _selectedAccount != null ? _nextStep : () {},
              isPrimary: _selectedAccount != null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmissionStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Step 3 of 3', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          Text('Confirm Link', style: AppTheme.h1Style),
          const SizedBox(height: 24),
          OneovaCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildPlatformLogo(size: 64),
                const SizedBox(height: 24),
                Text('Ready to link', style: AppTheme.bodyStyle.copyWith(color: context.textSecondary, fontSize: 14)),
                const SizedBox(height: 8),
                Text(
                  _selectedAccount ?? '',
                  style: AppTheme.h2Style.copyWith(fontSize: 20, color: AppColors.brandBlue),
                ),
                const SizedBox(height: 8),
                Text('to Oneova Studio', style: AppTheme.bodyStyle.copyWith(color: context.textSecondary, fontSize: 14)),
              ],
            ),
          ).animate().fadeIn().scaleXY(begin: 0.9),
          const Spacer(),
          if (_isConnecting)
            const Center(child: CircularProgressIndicator(color: AppColors.brandBlue))
          else
            SizedBox(
              width: double.infinity,
              child: OneovaButton(
                text: 'Confirm & Link Account',
                onPressed: _submitConnection,
              ),
            ),
        ],
      ),
    );
  }
}
