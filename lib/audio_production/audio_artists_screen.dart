import 'package:flutter/material.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class AudioArtistsScreen extends StatelessWidget {
  const AudioArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.mic_none, Icons.music_note, Icons.headphones],
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Artists', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text('Registered artists & their requests', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
              const SizedBox(height: 18),
              _ArtistCard(
                initials: 'AJ',
                name: 'Amara J.',
                meta: '2 songs • 1 pending request',
                color: const Color(0xFF11998e),
                isNew: true,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'DR',
                name: 'DJ Rue',
                meta: '1 song • in review',
                color: const Color(0xFF6B21A8),
                isNew: false,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'K',
                name: 'Kito',
                meta: '2 songs • both done',
                color: const Color(0xFFf7971e),
                isNew: false,
              ),
              const SizedBox(height: 10),
              _ArtistCard(
                initials: 'TM',
                name: 'The Mbogi',
                meta: '1 song • 1 pending request',
                color: const Color(0xFF2193b0),
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
  final Color color;
  final bool isNew;

  const _ArtistCard({
    required this.initials,
    required this.name,
    required this.meta,
    required this.color,
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
              color: color,
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
                Text(name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(meta, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
              ],
            ),
          ),
          if (isNew)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'New',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
