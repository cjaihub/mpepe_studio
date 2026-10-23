import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings_kit.dart';

/// Auto-saves every toggle to `user_settings/{uid}.storage`.
class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CompactSettingsScaffold(
      title: 'Storage & Data',
      children: [
        SettingsAsyncBody(builder: (settings) {
          final data = settingsCategory(settings, 'storage');
          Widget toggle(IconData icon, String key, String label, String subtitle, {bool fallback = false}) {
            return SettingsSwitchTile(
              icon: icon,
              title: label,
              subtitle: subtitle,
              value: data[key] as bool? ?? fallback,
              onChanged: (v) =>
                  settingsWrite(ref, category: 'storage', current: data, key: key, value: v, label: label),
            );
          }

          return SettingsSection(
            label: 'Media auto-download',
            children: [
              toggle(Icons.wifi_rounded, 'autoDownloadWifi', 'On Wi-Fi', 'Download photos and videos automatically', fallback: true),
              toggle(Icons.signal_cellular_alt_rounded, 'autoDownloadCellular', 'On cellular', 'May use significant data'),
              toggle(Icons.photo_library_rounded, 'saveToGallery', 'Save to gallery', 'Keep incoming media in your device gallery'),
            ],
          );
        }),
      ],
    );
  }
}
