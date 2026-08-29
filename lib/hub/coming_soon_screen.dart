import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';

class ComingSoonScreen extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Gradient iconGradient;

  const ComingSoonScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconGradient,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: iconGradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 18),
              Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.ashText, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.line),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Coming soon', style: TextStyle(color: AppColors.ashText, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 24),
              const Text('Want this sooner? Tell us what matters most.', style: TextStyle(color: AppColors.dustText, fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0x73FF8A00), width: 1.3),
                  foregroundColor: AppColors.studioAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Suggest a feature', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => context.go('/'),
                child: const Text('← Back to Studio Home', style: TextStyle(color: AppColors.studioAccent, fontWeight: FontWeight.w700, fontSize: 12)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
