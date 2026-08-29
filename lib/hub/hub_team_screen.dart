import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';

class HubTeamScreen extends StatelessWidget {
  const HubTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            const Text('Team & studio', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
            const SizedBox(height: 14),
            MpepeCard(
              child: Row(
                children: [
                  const MpepeAvatar(
                    text: 'M',
                    size: 48,
                    gradient: LinearGradient(colors: [Color(0xFFFF8A00), Color(0xFFFF3D00)]),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Riverside Studio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        SizedBox(height: 4),
                        Text('7 channels · 3 members', style: TextStyle(color: AppColors.dustText, fontSize: 11)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.dustText, size: 20),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text('MEMBERS', style: TextStyle(color: AppColors.dustText, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            MpepeCard(
              child: Column(
                children: [
                  _buildMemberRow(
                    initials: 'YO',
                    name: 'You',
                    role: 'Owner',
                    bgColor: AppColors.studioAccent,
                  ),
                  const Divider(color: AppColors.line, height: 26),
                  _buildMemberRow(
                    initials: 'AK',
                    name: 'Amara K.',
                    role: 'Video Editor',
                    gradient: const LinearGradient(colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)]),
                  ),
                  const Divider(color: AppColors.line, height: 26),
                  _buildMemberRow(
                    initials: 'JM',
                    name: 'Josiah M.',
                    role: 'Community',
                    gradient: const LinearGradient(colors: [Color(0xFF2193B0), Color(0xFF6DD5ED)]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.line, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(18),
                // Using solid line since dash isn't native to basic BoxDecoration without package
              ),
              child: Column(
                children: [
                  const Icon(Icons.add, color: AppColors.ashText, size: 20),
                  const SizedBox(height: 6),
                  const Text('Invite a team member', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ashText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow({required String initials, required String name, required String role, Color? bgColor, Gradient? gradient}) {
    return Row(
      children: [
        MpepeAvatar(text: initials, size: 32, backgroundColor: bgColor, gradient: gradient),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        MpepePill(text: role, isOutline: true),
      ],
    );
  }
}
