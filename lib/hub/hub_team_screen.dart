import 'package:flutter/material.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';

class HubTeamScreen extends StatelessWidget {
  const HubTeamScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.people_outline, Icons.dashboard_outlined],
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          children: [
            Text('Team & studio', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.4, color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 14),
            MpepeCard(
              child: Row(
                children: [
                  const MpepeAvatar(
                    text: 'M',
                    size: 48,
                    backgroundColor: Color(0xFFFF6B00),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Riverside Studio', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                        const SizedBox(height: 4),
                        Text('7 channels · 3 members', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), size: 20),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('MEMBERS', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
            const SizedBox(height: 8),
            MpepeCard(
              child: Column(
                children: [
                  _buildMemberRow(
                    context: context,
                    initials: 'YO',
                    name: 'You',
                    role: 'Owner',
                    bgColor: Theme.of(context).colorScheme.primary,
                  ),
                  Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 26),
                  _buildMemberRow(
                    context: context,
                    initials: 'AK',
                    name: 'Amara K.',
                    role: 'Video Editor',
                    bgColor: const Color(0xFF6B21A8),
                  ),
                  Divider(color: Theme.of(context).colorScheme.outlineVariant, height: 26),
                  _buildMemberRow(
                    context: context,
                    initials: 'JM',
                    name: 'Josiah M.',
                    role: 'Community',
                    bgColor: const Color(0xFF2193B0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, style: BorderStyle.solid),
                borderRadius: BorderRadius.circular(18),
                // Using solid line since dash isn't native to basic BoxDecoration without package
              ),
              child: Column(
                children: [
                  Icon(Icons.add, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4), size: 20),
                  const SizedBox(height: 6),
                  Text('Invite a team member', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberRow({required BuildContext context, required String initials, required String name, required String role, Color? bgColor, Gradient? gradient}) {
    return Row(
      children: [
        MpepeAvatar(text: initials, size: 32, backgroundColor: bgColor, gradient: gradient),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface))),
        MpepePill(text: role, isOutline: true),
      ],
    );
  }
}
