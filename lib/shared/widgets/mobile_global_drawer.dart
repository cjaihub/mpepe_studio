import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';

class MobileGlobalDrawer extends StatelessWidget {
  const MobileGlobalDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: context.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: context.bg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.brandBlue,
                  child: Icon(Icons.person, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                Text('ONEOVA', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: AppColors.brandPink),
            title: Text('Ova Assistant', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('Double-tap & hold 3s anywhere', style: TextStyle(color: context.textSecondary, fontSize: 11)),
            onTap: () {
              context.pop();
              context.push('/hub/ova_assistant');
            },
          ),
          ListTile(
            leading: Icon(Icons.settings, color: context.textSecondary),
            title: Text('Settings', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              context.pop();
              context.push('/settings/main');
            },
          ),
          ListTile(
            leading: Icon(Icons.group, color: context.textSecondary),
            title: Text('Team', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              context.pop();
              context.push('/hub/team');
            },
          ),
          ListTile(
            leading: Icon(Icons.link, color: context.textSecondary),
            title: Text('Social Integrations', style: TextStyle(color: context.textPrimary)),
            onTap: () {
              context.pop();
              context.push('/social_hub');
            },
          ),
        ],
      ),
    );
  }
}
