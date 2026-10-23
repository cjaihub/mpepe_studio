import 'package:flutter/material.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class AudioProductionsScreen extends StatelessWidget {
  const AudioProductionsScreen({super.key});

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
              Text('Productions', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              const SizedBox(height: 14),
              const _SegmentedControl(),
              const SizedBox(height: 18),
              _ProductionCard(
                title: '"Late Nights" — Amara J.',
                subtitle: 'Josiah M. • Room B',
                status: 'In production',
                statusColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"Nairobi Nights EP" — The Mbogi',
                subtitle: 'Wanjiru K. • Room A',
                status: 'In production',
                statusColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"Homecoming" — DJ Rue',
                subtitle: 'Wanjiru K. • Room A',
                status: 'In review',
                statusColor: Colors.orange,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"Still Waters" — Amara J.',
                subtitle: 'Josiah M. • Room B',
                status: 'In review',
                statusColor: Colors.orange,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"Golden Hour" — Kito',
                subtitle: 'Josiah M. • Room B',
                status: 'Done',
                statusColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              _ProductionCard(
                title: '"First Light" — Kito',
                subtitle: 'Wanjiru K. • Room A',
                status: 'Done',
                statusColor: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedControl extends StatelessWidget {
  const _SegmentedControl();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _SegButton(label: 'All', isActive: true),
          const SizedBox(width: 8),
          _SegButton(label: 'Production', isActive: false),
          const SizedBox(width: 8),
          _SegButton(label: 'Review', isActive: false),
          const SizedBox(width: 8),
          _SegButton(label: 'Done', isActive: false),
        ],
      ),
    );
  }
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool isActive;

  const _SegButton({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: isActive ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          fontWeight: FontWeight.bold,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ProductionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;

  const _ProductionCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return OneovaCard(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
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
