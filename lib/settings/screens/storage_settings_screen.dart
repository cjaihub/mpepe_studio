import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/services/auto_cache_cleaner.dart';
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
        const _CacheSection(),
      ],
    );
  }
}

/// Automatic clean-up (on this phone only) and a "Clean up now" button.
class _CacheSection extends StatefulWidget {
  const _CacheSection();

  @override
  State<_CacheSection> createState() => _CacheSectionState();
}

class _CacheSectionState extends State<_CacheSection> {
  final _cleaner = AutoCacheCleaner.instance;
  bool _on = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cleaner.enabled().then((v) {
      if (mounted) setState(() => _on = v);
    });
  }

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 10 * 1024 * 1024 ? 1 : 0)} MB';

  String _when(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  Future<void> _cleanNow() async {
    setState(() => _busy = true);
    final r = await _cleaner.run(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r == null ? 'Couldn’t clean up right now.' : 'Freed ${_mb(r.freedBytes)}. Cache is now ${_mb(r.sizeAfterBytes)}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CacheCleanReport?>(
      valueListenable: _cleaner.lastReport,
      builder: (context, r, _) => SettingsSection(
        label: 'Keep Oneova light',
        footer: 'Removes old leftovers and caches that download again when needed. Your messages, drafts, '
            'downloads and saved media are never touched.',
        children: [
          SettingsSwitchTile(
            icon: Icons.auto_delete_outlined,
            title: 'Automatic clean-up',
            subtitle: r == null ? 'Keeps the cache under ${_mb(AutoCacheCleaner.budgetBytes)}' : 'Last: ${_when(r.at)} · freed ${_mb(r.freedBytes)} · now ${_mb(r.sizeAfterBytes)}',
            value: _on,
            onChanged: (v) async {
              setState(() => _on = v);
              await _cleaner.setEnabled(v);
            },
          ),
          SettingsNavTile(
            icon: Icons.cleaning_services_outlined,
            title: _busy ? 'Cleaning…' : 'Clean up now',
            subtitle: 'Frees space right away',
            onTap: () {
              if (!_busy) _cleanNow();
            },
          ),
        ],
      ),
    );
  }
}
