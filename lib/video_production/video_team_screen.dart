import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class VideoTeamScreen extends StatelessWidget {
  const VideoTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.videocam_outlined, Icons.movie_creation_outlined, Icons.camera_alt_outlined],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Crew', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 24),
              _CrewCard(
                initials: 'BO',
                name: 'Brian O.',
                role: 'Director of Photography • 2 shoots',
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              const _CrewCard(
                initials: 'FN',
                name: 'Faith N.',
                role: 'Editor • 3 projects',
                color: Color(0xFFf7971e),
              ),
              const SizedBox(height: 16),
              const _CrewCard(
                initials: 'JM',
                name: 'Josiah M.',
                role: 'Director • 2 shoots',
                color: Color(0xFFff512f),
              ),
              const SizedBox(height: 16),
              const _CrewCard(
                initials: 'AK',
                name: 'Amara K.',
                role: 'Sound & Gaffer • 2 shoots',
                color: Color(0xFF2193b0),
              ),
              const SizedBox(height: 40),
            ].animate(interval: 50.ms).fade(duration: 400.ms, curve: Curves.easeOut).slideY(begin: 0.1, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
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
  final Color color;

  const _CrewCard({
    required this.initials,
    required this.name,
    required this.role,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(role, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
