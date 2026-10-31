import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../../providers/settings_provider.dart';
import '../commands/update_setting_command.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../../backend/repair/oneova_self_repair_engine.dart';
import '../../backend/repair/oneova_auto_updater.dart';
import '../widgets/settings_kit.dart';

class AiSettingsScreen extends ConsumerStatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  ConsumerState<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends ConsumerState<AiSettingsScreen> {
  Timer? _sliderDebounce;
  double? _pendingSliderValue;
  double? _sliderOldValue;

  @override
  void dispose() {
    _sliderDebounce?.cancel();
    super.dispose();
  }

  void _onSliderChanged(double oldVal, double newVal) {
    _sliderOldValue ??= oldVal;
    _pendingSliderValue = newVal;
    if (_sliderDebounce?.isActive ?? false) _sliderDebounce!.cancel();
    _sliderDebounce = Timer(const Duration(milliseconds: 600), () {
      if (_pendingSliderValue == null || _sliderOldValue == null) return;
      final command = UpdateSettingCommand(
        ref: ref,
        category: 'ai',
        undoData: {'autoAggressiveness': _sliderOldValue},
        data: {'autoAggressiveness': _pendingSliderValue},
        name: 'Update Automation Level',
      );
      ref.read(undoManagerProvider.notifier).executeAndRegister(command);
      UndoSnackbar.show(context, ref, 'Automation level updated');
      _sliderOldValue = _pendingSliderValue;
      _pendingSliderValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Text('AI Assistant Settings', style: AppTheme.h2Style.copyWith(color: context.topBarFg)),
            const SizedBox(width: 8),
            const SettingsSaveIndicator(),
          ],
        ),
        backgroundColor: AppColors.brandBlue,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: context.topBarFg, size: 18),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final aiSettings = settings['ai'] as Map<String, dynamic>? ?? {};

          final vault = ref.watch(secureKeyVaultProvider);
          final repairEngine = ref.watch(oneOvaSelfRepairEngineProvider);
          final updater = ref.watch(oneOvaAutoUpdaterProvider);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildSettingsGroup(
                context,
                'Ova & account check',
                [
                  // Bring-your-own key is a developer option only.
                  if (kDebugMode) ...[
                    _buildGeminiKeyTile(context, vault),
                    Divider(height: 1, indent: 20, endIndent: 20, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
                  ],
                  _buildSelfRepairTile(context, repairEngine),
                  Divider(height: 1, indent: 20, endIndent: 20, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
                  _buildAutoUpdateTile(context, updater),
                ],
              ),
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'Model Selection',
                [
                  _buildDropdown(context, aiSettings, Icons.psychology, 'Default Model', 'defaultModel',
                      ['gemini-2.5-flash', 'gemini-1.5-pro', 'gpt-4o', 'claude-3-opus'], true),
                  _buildDropdown(context, aiSettings, Icons.record_voice_over, 'Assistant Tone', 'assistantTone',
                      ['Professional', 'Casual', 'Creative', 'Direct'], false),
                ],
              ),
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'Automation',
                [
                  _buildSlider(context, aiSettings, Icons.speed, 'Automation Aggressiveness', 'autoAggressiveness', false),
                ],
              ),
              const SizedBox(height: 24),
              _buildSettingsGroup(
                context,
                'System-Wide Ova Assistant & Triggers',
                [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.brandBlue, size: 22),
                    ),
                    title: Text(
                      'Ways to open Ova',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Draw "O", button shortcut, lock screen, over other apps',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () => context.push('/ova/triggers'),
                  ),
                  const Divider(height: 1, indent: 20, endIndent: 20),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.accessibility_new_rounded, color: AppColors.brandPink, size: 22),
                    ),
                    title: Text(
                      'Accessibility Device Control & Permissions',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
                    ),
                    subtitle: Text(
                      'Grant permissions to tap, type, scroll, and navigate apps',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                    onTap: () => context.push('/ova/setup'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingsGroup(BuildContext context, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 12),
          child: Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
        ),
        OneovaCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildDropdown(BuildContext context, Map<String, dynamic> aiSettings, IconData icon, String title, String key, List<String> options, bool showDivider) {
    String oldValue = aiSettings[key]?.toString() ?? options.first;
    if (!options.contains(oldValue)) oldValue = options.first;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
          ),
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
          trailing: DropdownButton<String>(
            value: oldValue,
            underline: const SizedBox(),
            dropdownColor: context.surface,
            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
            items: options.map((String opt) {
              return DropdownMenuItem<String>(value: opt, child: Text(opt));
            }).toList(),
            onChanged: (newVal) {
              if (newVal != null && newVal != oldValue) {
                final command = UpdateSettingCommand(
                  ref: ref,
                  category: 'ai',
                  undoData: {key: oldValue},
                  data: {key: newVal},
                  name: 'Update $title',
                );
                ref.read(undoManagerProvider.notifier).executeAndRegister(command);
                UndoSnackbar.show(context, ref, '$title set to $newVal');
              }
            },
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }

  Widget _buildSlider(BuildContext context, Map<String, dynamic> aiSettings, IconData icon, String title, String key, bool showDivider) {
    // Use pending value for live responsiveness, fall back to persisted value
    final persistedValue = (aiSettings[key] as num?)?.toDouble() ?? 0.5;
    final displayValue = _pendingSliderValue ?? persistedValue;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 15)),
                        Text(
                          '${(displayValue * 100).round()}%',
                          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.brandBlue,
                  thumbColor: AppColors.brandBlue,
                  overlayColor: AppColors.brandBlue.withValues(alpha: 0.15),
                  inactiveTrackColor: AppColors.brandBlue.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: displayValue,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  label: '${(displayValue * 100).round()}%',
                  onChanged: (val) {
                    setState(() => _pendingSliderValue = val);
                    _onSliderChanged(persistedValue, val);
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Conservative', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                  Text('Aggressive', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1), indent: 70, endIndent: 20),
      ],
    );
  }

  Widget _buildGeminiKeyTile(BuildContext context, SecureKeyVault vault) {
    return FutureBuilder<String>(
      future: vault.getGeminiApiKey(),
      builder: (context, snapshot) {
        final key = snapshot.data ?? '';
        final hasKey = key.isNotEmpty;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.key_rounded, color: AppColors.brandBlue, size: 22),
          ),
          title: Text(
            'Google Gemini API Key (Hardware Vault)',
            style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
          ),
          subtitle: Text(
            hasKey ? 'Secured in Keystore: ${vault.maskKey(key)}' : 'Using .env or OpenRouter fallback',
            style: TextStyle(fontSize: 12, color: hasKey ? Colors.green : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          onTap: () => _showGeminiKeyDialog(context, vault, key),
        );
      },
    );
  }

  Widget _buildSelfRepairTile(BuildContext context, OneOvaSelfRepairEngine repairEngine) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.healing_rounded, color: AppColors.brandPink, size: 22),
      ),
      title: Text(
        'Autonomous Diagnostics & Self-Repair',
        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      ),
      subtitle: Text(
        'Scan health, heal backend schemas & flush broken caches',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: () => _runSelfRepairModal(context, repairEngine),
    );
  }

  Widget _buildAutoUpdateTile(BuildContext context, OneOvaAutoUpdater updater) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.system_update_rounded, color: AppColors.brandBlue, size: 22),
      ),
      title: Text(
        'Background Updates & Version Sync',
        style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface, fontSize: 14),
      ),
      subtitle: Text(
        'v${OneOvaAutoUpdater.currentVersion}+${OneOvaAutoUpdater.currentBuildNumber} • ${updater.updateChannel} channel',
        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: () => _showUpdateDialog(context, updater),
    );
  }

  void _showGeminiKeyDialog(BuildContext context, SecureKeyVault vault, String currentKey) {
    final controller = TextEditingController(text: currentKey);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.key_rounded, color: AppColors.brandBlue, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Gemini API Key Configuration',
                      style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Stored in Android Keystore / iOS Keychain. Never transmitted to unverified endpoints.',
                  style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  obscureText: true,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIzaSy...',
                    filled: true,
                    fillColor: context.surfaceMid,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (currentKey.isNotEmpty)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            await vault.storeGeminiApiKey('');
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              setState(() {});
                            }
                          },
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
                          child: const Text('Clear Key'),
                        ),
                      ),
                    if (currentKey.isNotEmpty) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: () async {
                          final text = controller.text.trim();
                          await vault.storeGeminiApiKey(text);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            setState(() {});
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Save to Keystore'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _runSelfRepairModal(BuildContext context, OneOvaSelfRepairEngine repairEngine) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
          ),
          child: SafeArea(
            child: FutureBuilder<SystemHealthReport>(
              future: () async {
                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (uid != null) await repairEngine.repairUserProfile(uid);
                await repairEngine.repairInterfaceAndCache();
                return await repairEngine.runSystemHealthScan();
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(color: AppColors.brandPink),
                      const SizedBox(height: 16),
                      Text('Running Autonomous Diagnostics & Healer…', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: context.textPrimary)),
                      const SizedBox(height: 20),
                    ],
                  );
                }

                final report = snapshot.data;
                if (report == null) {
                  return Text('Diagnostics failed to complete.', style: TextStyle(color: context.textPrimary));
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4.5,
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('System Health & Repair', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800, color: context.textPrimary)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${report.overallScore}% Score', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w800, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ...report.checks.map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(item.component, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                              ),
                              Text(item.latencyMs > 0 ? '${item.latencyMs}ms' : 'OK', style: TextStyle(fontSize: 11, color: context.textMuted)),
                            ],
                          ),
                        )),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white),
                        child: const Text('Close Diagnostics'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showUpdateDialog(BuildContext context, OneOvaAutoUpdater updater) async {
    final info = await updater.checkForUpdates();
    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: context.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: AppColors.brandBlue, size: 22),
              const SizedBox(width: 8),
              Text('Oneova App Updates', style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Installed Version: v${info.currentVersion}+${OneOvaAutoUpdater.currentBuildNumber}', style: TextStyle(fontSize: 13, color: context.textSecondary)),
              Text('Channel: ${info.channel}', style: TextStyle(fontSize: 13, color: context.textSecondary)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(info.hasUpdate ? Icons.notification_important_rounded : Icons.check_circle_rounded,
                        color: info.hasUpdate ? AppColors.brandPink : Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info.hasUpdate ? 'Upgrade available: v${info.latestVersion}' : 'Up to date with server registry.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              if (info.hasUpdate) ...[
                const SizedBox(height: 8),
                Text(info.releaseNotes, style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
  }
}
