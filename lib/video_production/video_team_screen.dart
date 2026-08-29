import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class VideoTeamScreen extends StatelessWidget {
  const VideoTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Crew', style: AppTheme.h1Style),
              const SizedBox(height: 14),
              _CrewCard(
                initials: 'BO',
                name: 'Brian O.',
                role: 'Director of Photography • 2 shoots',
                gradient: const LinearGradient(colors: [AppColors.violet, AppColors.violet]),
              ),
              const SizedBox(height: 10),
              _CrewCard(
                initials: 'FN',
                name: 'Faith N.',
                role: 'Editor • 3 projects',
                gradient: const LinearGradient(
                  colors: [Color(0xFFf7971e), Color(0xFFffd200)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              const SizedBox(height: 10),
              _CrewCard(
                initials: 'JM',
                name: 'Josiah M.',
                role: 'Director • 2 shoots',
                gradient: const LinearGradient(
                  colors: [Color(0xFFff512f), Color(0xFFf09819)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              const SizedBox(height: 10),
              _CrewCard(
                initials: 'AK',
                name: 'Amara K.',
                role: 'Sound & Gaffer • 2 shoots',
                gradient: const LinearGradient(
                  colors: [Color(0xFF2193b0), Color(0xFF6dd5ed)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _CrewCard extends StatelessWidget {
  final String initials;
  final String name;
  final String role;
  final Gradient gradient;

  const _CrewCard({
    required this.initials,
    required this.name,
    required this.role,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradient,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                const SizedBox(height: 8),
                Text(role, style: const TextStyle(color: AppColors.dust, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
