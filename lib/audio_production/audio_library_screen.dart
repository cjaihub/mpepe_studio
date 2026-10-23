import 'package:flutter/material.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class AudioLibraryScreen extends StatelessWidget {
  const AudioLibraryScreen({super.key});

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
              Text('Library', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 8),
              Text('All audio under production', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 13)),
              const SizedBox(height: 18),
              _TrackCard(title: '"Late Nights" — Amara J.', time: '3:42', status: 'Production', statusColor: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              _TrackCard(title: '"Homecoming" — DJ Rue', time: '4:10', status: 'Review', statusColor: Colors.orange),
              const SizedBox(height: 10),
              _TrackCard(title: '"Golden Hour" — Kito', time: '3:15', status: 'Done', statusColor: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              _TrackCard(title: '"First Light" — Kito', time: '2:58', status: 'Done', statusColor: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              _TrackCard(title: '"Nairobi Nights" — The Mbogi', time: '3:33', status: 'Production', statusColor: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 10),
              _TrackCard(title: '"Still Waters" — Amara J.', time: '4:02', status: 'Review', statusColor: Colors.orange),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackCard extends StatelessWidget {
  final String title;
  final String time;
  final String status;
  final Color statusColor;

  const _TrackCard({
    required this.title,
    required this.time,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(time, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
              ],
            ),
          ),
          OneovaPill(
            text: status,
            color: statusColor,
            isGhost: true,
          ),
        ],
      ),
    );
  }
}
