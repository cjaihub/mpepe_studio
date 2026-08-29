import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class SocialLoginScreen extends StatelessWidget {
  const SocialLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.red,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.red.withOpacity(0.55),
                      blurRadius: 30,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
                ),
              ),
              const SizedBox(height: 26),
              Text('MPEPE', style: AppTheme.h1Style.copyWith(fontSize: 30)),
              const SizedBox(height: 10),
              const Text(
                'All your channels.\nOne studio, one app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.dust,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildAvatarStack(
                    'RS',
                    const LinearGradient(
                      colors: [Color(0xFF8e2de2), Color(0xFF4a00e0)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  _buildAvatarStack(
                    'CM',
                    const LinearGradient(
                      colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  _buildAvatarStack(
                    'NT',
                    const LinearGradient(
                      colors: [Color(0xFFf7971e), Color(0xFFffd200)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(-30, 0),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface2,
                        border: Border.all(color: AppColors.ink, width: 2),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.line, width: 1.5, style: BorderStyle.solid),
                        ),
                        child: const Center(
                          child: Text(
                            '+7',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.ash,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'Ten channels. One sign-in.',
                style: TextStyle(
                  color: AppColors.dust,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 34),
              SizedBox(
                width: double.infinity,
                child: MpepeButton(
                  label: 'Continue with Google',
                  icon: Icons.account_circle,
                  variant: MpepeButtonVariant.white,
                  onPressed: () {
                    context.go('/yt/dashboard');
                  },
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                "By continuing you agree to MPEPE's Terms\nand confirm you manage rights to these channels.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.dust,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarStack(String initials, Gradient gradient) {
    return Transform.translate(
      offset: const Offset(10, 0),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: gradient,
          border: Border.all(color: AppColors.ink, width: 2),
        ),
        child: Center(
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
