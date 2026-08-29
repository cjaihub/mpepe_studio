import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';

class YtSettingsScreen extends StatelessWidget {
  const YtSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Google Account'),
          _buildSettingsTile(Icons.account_circle, 'Linked Accounts', 'Manage connected Google accounts'),
          _buildSettingsTile(Icons.security, 'Permissions', 'View what MPEPE can access'),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Upload Defaults'),
          _buildSettingsTile(Icons.privacy_tip, 'Default Privacy', 'Private'),
          _buildSettingsTile(Icons.category, 'Default Category', 'Science & Technology'),
          
          const SizedBox(height: 24),
          _buildSectionTitle('Notifications'),
          _buildSettingsTile(Icons.notifications, 'Upload Alerts', 'Enabled'),
          _buildSettingsTile(Icons.comment, 'Comments & Mentions', 'Disabled'),
          
          const SizedBox(height: 32),
          TextButton(
            onPressed: () {},
            child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: const TextStyle(color: AppColors.ytAccent, fontWeight: FontWeight.bold, fontSize: 13),
      ),
    );
  }

  Widget _buildSettingsTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: AppColors.ashText),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.dustText, fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.dustText),
      contentPadding: EdgeInsets.zero,
    );
  }
}
