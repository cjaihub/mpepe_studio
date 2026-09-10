import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../shared/widgets/studio_background.dart';

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
    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
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
              Text(title, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 10),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('Coming soon', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 24),
              Text('Want this sooner? Tell us what matters most.', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), fontSize: 11, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5), width: 1.3),
                  foregroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text('Suggest a feature', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => context.push('/'),
                child: Text('← Back to Studio Home', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
