import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class AudioArtistsScreen extends StatelessWidget {
  const AudioArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Artists', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              const Text('Registered artists & their requests', style: TextStyle(color: AppColors.dust, fontSize: 13)),
              const SizedBox(height: 18),
              _ArtistCard(
                initials: 'AJ',
                name: 'Amara J.',
                meta: '2 songs • 1 pending request',
                gradient: const LinearGradient(
                  colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                isNew: true,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'DR',
                name: 'DJ Rue',
                meta: '1 song • in review',
                gradient: const LinearGradient(
                  colors: [Color(0xFF8e2de2), Color(0xFF4a00e0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                isNew: false,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'K',
                name: 'Kito',
                meta: '2 songs • both done',
                gradient: const LinearGradient(
                  colors: [Color(0xFFf7971e), Color(0xFFffd200)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                isNew: false,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'TM',
                name: 'The Mbogi',
                meta: '1 song • 1 pending request',
                gradient: const LinearGradient(
                  colors: [Color(0xFF2193b0), Color(0xFF6dd5ed)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                isNew: true,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtistCard extends StatelessWidget {
  final String initials;
  final String name;
  final String meta;
  final Gradient gradient;
  final bool isNew;

  const _ArtistCard({
    required this.initials,
    required this.name,
    required this.meta,
    required this.gradient,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    return MpepeCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
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
                Text(meta, style: const TextStyle(color: AppColors.dust, fontSize: 12)),
              ],
            ),
          ),
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.orange.withOpacity(0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'New',
                style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
