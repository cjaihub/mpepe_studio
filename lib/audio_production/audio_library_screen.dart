import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class AudioLibraryScreen extends StatelessWidget {
  const AudioLibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Library', style: AppTheme.h1Style),
              const SizedBox(height: 8),
              const Text('All audio under production', style: TextStyle(color: AppColors.dust, fontSize: 13)),
              const SizedBox(height: 18),
              _TrackCard(title: '"Late Nights" — Amara J.', time: '3:42', status: 'Production', statusColor: AppColors.teal),
              const SizedBox(height: 10),
              _TrackCard(title: '"Homecoming" — DJ Rue', time: '4:10', status: 'Review', statusColor: AppColors.orange),
              const SizedBox(height: 10),
              _TrackCard(title: '"Golden Hour" — Kito', time: '3:15', status: 'Done', statusColor: AppColors.mint),
              const SizedBox(height: 10),
              _TrackCard(title: '"First Light" — Kito', time: '2:58', status: 'Done', statusColor: AppColors.mint),
              const SizedBox(height: 10),
              _TrackCard(title: '"Nairobi Nights" — The Mbogi', time: '3:33', status: 'Production', statusColor: AppColors.teal),
              const SizedBox(height: 10),
              _TrackCard(title: '"Still Waters" — Amara J.', time: '4:02', status: 'Review', statusColor: AppColors.orange),
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
    return MpepeCard(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.teal,
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                Text(time, style: const TextStyle(color: AppColors.dust, fontSize: 11)),
              ],
            ),
          ),
          MpepePill(
            label: status,
            color: statusColor,
            isGhost: true,
          ),
        ],
      ),
    );
  }
}
