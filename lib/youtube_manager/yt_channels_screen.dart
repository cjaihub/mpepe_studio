import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class YtChannelsScreen extends StatelessWidget {
  const YtChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Linked Channels', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MpepeButton(
            text: 'Link New YouTube Channel',
            isPrimary: true,
            icon: Icons.add_link,
            onPressed: () {
              // TODO: Implement Google Sign-In
            },
          ),
          const SizedBox(height: 24),
          _buildChannelCard('Riverside Studio', 'Main channel · 650K subs'),
          _buildChannelCard('Riverside Shorts', 'Shorts channel · 212K subs'),
          _buildChannelCard('Tech Connect', 'Secondary · 0 subs'),
        ],
      ),
    );
  }

  Widget _buildChannelCard(String name, String meta) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MpepeCard(
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.ytAccent,
              child: Icon(Icons.person, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(meta, style: const TextStyle(color: AppColors.dustText, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.more_vert, color: AppColors.ashText),
          ],
        ),
      ),
    );
  }
}
