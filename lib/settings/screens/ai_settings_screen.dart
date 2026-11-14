import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../backend/ai_brain_service.dart';
import '../../backend/repair/oneova_auto_updater.dart';
import '../../backend/repair/oneova_self_repair_engine.dart';
import '../../backend/security/oneova_ai_gateway.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../../providers/settings_provider.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/undo/undo_manager.dart';
import '../../shared/undo/undo_snackbar.dart';
import '../../shared/widgets/components.dart';
import '../commands/update_setting_command.dart';
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
  bool _testingConnection = false;
  String? _connectionStatusLabel;
  bool? _connectionLiveCloud;

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

  Future<void> _testAiConnection() async {
    if (_testingConnection) return;
    HapticFeedback.lightImpact();
    setState(() {
      _testingConnection = true;
      _connectionStatusLabel = 'Testing live AI Brain connection…';
    });

    OneovaAiGateway.resetCooldown();
    final sw = Stopwatch()..start();
    try {
      final res = await ref.read(aiBrainProvider).processRequest(
        const [
          {'role': 'user', 'content': 'Reply with OK.'},
        ],
      );
      sw.stop();
      if (!mounted) return;
      if (res is AiTextResponse) {
        final live = !res.isDegraded;
        setState(() {
          _testingConnection = false;
          _connectionLiveCloud = live;
          _connectionStatusLabel = live
              ? 'Live Cloud AI Connected (${sw.elapsedMilliseconds}ms)'
              : '${res.diagnostic!.badgeLabel} (${sw.elapsedMilliseconds}ms) — ${res.diagnostic!.detail}';
        });
      } else {
        setState(() {
          _testingConnection = false;
          _connectionLiveCloud = true;
          _connectionStatusLabel = 'Live Cloud AI Connected (${sw.elapsedMilliseconds}ms)';
        });
      }
    } catch (e) {
      sw.stop();
      if (!mounted) return;
      setState(() {
        _testingConnection = false;
        _connectionLiveCloud = false;
        _connectionStatusLabel = 'Local Ova Active — $e';
      });
    }
  }

  Future<bool> _confirmClearKey(BuildContext context, String providerLabel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: context.border, width: 1.0),
        ),
        title: Text(
          'Clear $providerLabel Key?',
          style: GoogleFonts.inter(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        content: Text(
          'This removes your saved $providerLabel API key from hardware storage. Ova will automatically use other configured providers or Local Ova mode.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.38, color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: context.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: AppColors.brandWhite,
              minimumSize: const Size(88, 38),
            ),
            child: Text('Clear Key', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: Row(
          children: [
            Flexible(
              child: Text(
                'AI Assistant Settings',
                style: AppTheme.h2Style.copyWith(color: context.topBarFg),
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.brandBlue)),
        error: (e, s) => Center(
          child: Text('Error loading settings: $e', style: GoogleFonts.inter(color: context.textPrimary)),
        ),
        data: (settings) {
          final aiSettings = settings['ai'] as Map<String, dynamic>? ?? {};

          final vault = ref.watch(secureKeyVaultProvider);
          final repairEngine = ref.watch(oneOvaSelfRepairEngineProvider);
          final updater = ref.watch(oneOvaAutoUpdaterProvider);

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              _buildSettingsGroup(
                context,
                'Ova Brain & Credentials',
                [
                  _buildOpenRouterKeyTile(context, vault),
                  Divider(height: 1, indent: 20, endIndent: 20, color: context.border),
                  _buildConnectionTestTile(context),
                  Divider(height: 1, indent: 20, endIndent: 20, color: context.border),
                  _buildSelfRepairTile(context, repairEngine),
                  Divider(height: 1, indent: 20, endIndent: 20, color: context.border),
                  _buildAutoUpdateTile(context, updater),
                ],
              ),
              const SizedBox(height: 20),
              _buildSettingsGroup(
                context,
                'Model Selection',
                [
                  _buildDropdown(
                    context,
                    aiSettings,
                    Icons.psychology,
                    'Default Model',
                    'defaultModel',
                    const [
                      'google/gemini-2.5-flash',
                      'gpt-4o',
                      'claude-3.5-sonnet',
                    ],
                    true,
                    onApplied: (newVal) => vault.setPreferredOpenRouterModel(newVal),
                  ),
                  _buildDropdown(
                    context,
                    aiSettings,
                    Icons.record_voice_over,
                    'Assistant Tone',
                    'assistantTone',
                    const ['Professional', 'Casual', 'Creative', 'Direct'],
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSettingsGroup(
                context,
                'Automation',
                [
                  _buildSlider(
                    context,
                    aiSettings,
                    Icons.speed,
                    'Automation Aggressiveness',
                    'autoAggressiveness',
                    false,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildSettingsGroup(
                context,
                'System-Wide Ova Assistant & Triggers',
                [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.brandBlue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(Icons.picture_in_picture_alt_rounded, color: AppColors.brandBlue, size: 20),
                    ),
                    title: Text(
                      'Ways to open Ova',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Draw "O", button shortcut, lock screen, over other apps',
                      style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: context.textMuted),
                    onTap: () => context.push('/ova/triggers'),
                  ),
                  Divider(height: 1, indent: 20, endIndent: 20, color: context.border),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: AppColors.brandPink.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: const Icon(Icons.accessibility_new_rounded, color: AppColors.brandPink, size: 20),
                    ),
                    title: Text(
                      'Accessibility Device Control & Permissions',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Grant permissions to tap, type, scroll, and navigate apps',
                      style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: context.textMuted),
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
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.inter(
              color: AppColors.brandBlue,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 0.2,
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

  Widget _buildDropdown(
    BuildContext context,
    Map<String, dynamic> aiSettings,
    IconData icon,
    String title,
    String key,
    List<String> options,
    bool showDivider, {
    void Function(String)? onApplied,
  }) {
    String oldValue = aiSettings[key]?.toString() ?? options.first;
    if (!options.contains(oldValue)) oldValue = options.first;

    return Column(
      children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: AppColors.brandBlue, size: 20),
          ),
          title: Text(
            title,
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
          ),
          trailing: DropdownButton<String>(
            value: oldValue,
            underline: const SizedBox(),
            dropdownColor: context.surface,
            style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
            items: options.map((String opt) {
              return DropdownMenuItem<String>(value: opt, child: Text(opt));
            }).toList(),
            onChanged: (newVal) {
              if (newVal != null && newVal != oldValue) {
                onApplied?.call(newVal);
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
        if (showDivider) Divider(height: 1, color: context.border, indent: 64, endIndent: 20),
      ],
    );
  }

  Widget _buildSlider(
    BuildContext context,
    Map<String, dynamic> aiSettings,
    IconData icon,
    String title,
    String key,
    bool showDivider,
  ) {
    final persistedValue = (aiSettings[key] as num?)?.toDouble() ?? 0.5;
    final displayValue = _pendingSliderValue ?? persistedValue;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, color: AppColors.brandBlue, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            color: context.textPrimary,
                            fontSize: 13.5,
                          ),
                        ),
                        Text(
                          '${(displayValue * 100).round()}%',
                          style: GoogleFonts.inter(
                            color: AppColors.brandBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                  Text('Conservative', style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                  Text('Aggressive', style: GoogleFonts.inter(fontSize: 11, color: context.textMuted)),
                ],
              ),
            ],
          ),
        ),
        if (showDivider) Divider(height: 1, color: context.border, indent: 64, endIndent: 20),
      ],
    );
  }

  Widget _buildOpenRouterKeyTile(BuildContext context, SecureKeyVault vault) {
    return FutureBuilder<String>(
      future: vault.getOpenRouterApiKey(),
      builder: (context, snapshot) {
        final key = snapshot.data ?? '';
        final hasKey = key.isNotEmpty;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.hub_rounded, color: AppColors.brandPink, size: 20),
          ),
          title: Text(
            'OpenRouter API Key',
            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
          ),
          subtitle: Text(
            hasKey
                ? 'Active in Hardware Vault · ${vault.maskKey(key)}'
                : 'Optional multi-model key (Gemini, Claude, GPT-4o, Llama)',
            style: GoogleFonts.inter(
              fontSize: 11.5,
              color: hasKey ? AppColors.brandBlue : context.textSecondary,
              fontWeight: hasKey ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: context.textMuted),
          onTap: () => _showKeyVaultSheet(
            context,
            title: 'OpenRouter API Key',
            hint: 'sk-or-v1-...',
            helperText: 'Saved in Android Keystore / iOS Keychain. Bypasses cloud proxy congestion.',
            currentKey: key,
            providerLabel: 'OpenRouter',
            onSave: (val) async {
              await vault.storeOpenRouterApiKey(val);
              ref.read(aiBrainProvider).setApiKey(val);
              OneovaAiGateway.resetCooldown();
            },
          ),
        );
      },
    );
  }

  Widget _buildConnectionTestTile(BuildContext context) {
    final statusColor = _connectionLiveCloud == null
        ? context.textSecondary
        : (_connectionLiveCloud! ? AppColors.brandBlue : AppColors.brandPink);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: _testingConnection
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
              )
            : const Icon(Icons.network_check_rounded, color: AppColors.brandBlue, size: 20),
      ),
      title: Text(
        'Test AI Brain Connection',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        _connectionStatusLabel ?? 'Verify live Cloud AI latency & reset proxy cooldown',
        style: GoogleFonts.inter(
          fontSize: 11.5,
          color: statusColor,
          fontWeight: _connectionStatusLabel != null ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
      trailing: Icon(Icons.refresh_rounded, size: 18, color: AppColors.brandBlue),
      onTap: _testAiConnection,
    );
  }

  Widget _buildSelfRepairTile(BuildContext context, OneOvaSelfRepairEngine repairEngine) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.brandPink.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Icon(Icons.healing_rounded, color: AppColors.brandPink, size: 20),
      ),
      title: Text(
        'Autonomous Diagnostics & Self-Repair',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        'Scan health, heal backend schemas & flush broken caches',
        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: context.textMuted),
      onTap: () => _runSelfRepairModal(context, repairEngine),
    );
  }

  Widget _buildAutoUpdateTile(BuildContext context, OneOvaAutoUpdater updater) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Icon(Icons.system_update_rounded, color: AppColors.brandBlue, size: 20),
      ),
      title: Text(
        'Background Updates & Version Sync',
        style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: context.textPrimary, fontSize: 13.5),
      ),
      subtitle: Text(
        'v${OneOvaAutoUpdater.currentVersion}+${OneOvaAutoUpdater.currentBuildNumber} • ${updater.updateChannel} channel',
        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
      ),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 15, color: context.textMuted),
      onTap: () => _showUpdateDialog(context, updater),
    );
  }

  void _showKeyVaultSheet(
    BuildContext context, {
    required String title,
    required String hint,
    required String helperText,
    required String currentKey,
    required String providerLabel,
    required Future<void> Function(String) onSave,
  }) {
    final controller = TextEditingController(text: currentKey);

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.brandBlack.withValues(alpha: 0),
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.border,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.key_rounded, color: AppColors.brandBlue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: GoogleFonts.inter(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  helperText,
                  style: GoogleFonts.inter(fontSize: 12, height: 1.35, color: context.textSecondary),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  obscureText: true,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    labelText: title,
                    hintText: hint,
                    filled: true,
                    fillColor: context.surfaceMid,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.0),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (currentKey.isNotEmpty) ...[
                      Expanded(
                        child: SizedBox(
                          height: 40,
                          child: OutlinedButton(
                            onPressed: () async {
                              final ok = await _confirmClearKey(context, providerLabel);
                              if (!ok) return;
                              await onSave('');
                              if (ctx.mounted) {
                                Navigator.pop(ctx);
                                setState(() {});
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brandPink,
                              side: BorderSide(color: AppColors.brandPink.withValues(alpha: 0.5), width: 1.0),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                            ),
                            child: Text('Clear Key', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 40,
                        child: ElevatedButton(
                          onPressed: () async {
                            HapticFeedback.lightImpact();
                            final text = controller.text.trim();
                            await onSave(text);
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              setState(() {});
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            foregroundColor: AppColors.brandWhite,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                          child: Text(
                            'Save to Keystore',
                            style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ),
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
      backgroundColor: AppColors.brandBlack.withValues(alpha: 0),
      isScrollControlled: true,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: SafeArea(
            child: FutureBuilder<SystemHealthReport>(
              future: () async {
                OneovaAiGateway.resetCooldown();
                final uid = Firebase.apps.isNotEmpty ? FirebaseAuth.instance.currentUser?.uid : null;
                if (uid != null) await repairEngine.repairUserProfile(uid);
                await repairEngine.repairInterfaceAndCache();
                return await repairEngine.runSystemHealthScan();
              }(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 18),
                      const CircularProgressIndicator(color: AppColors.brandPink),
                      const SizedBox(height: 14),
                      Text(
                        'Running Autonomous Diagnostics & Healer…',
                        style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary),
                      ),
                      const SizedBox(height: 18),
                    ],
                  );
                }

                final report = snapshot.data;
                if (report == null) {
                  return Text('Diagnostics failed to complete.', style: GoogleFonts.inter(color: context.textPrimary));
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: context.border,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'System Health & Repair',
                          style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w800, color: context.textPrimary),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            '${report.overallScore}% Score',
                            style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w800, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...report.checks.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: AppColors.brandBlue, size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item.component,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.textPrimary,
                                ),
                              ),
                            ),
                            Text(
                              item.latencyMs > 0 ? '${item.latencyMs}ms' : 'OK',
                              style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 40,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandBlue,
                          foregroundColor: AppColors.brandWhite,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                        child: Text('Close Diagnostics', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: context.border, width: 1.0),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update_rounded, color: AppColors.brandBlue, size: 20),
              const SizedBox(width: 8),
              Text(
                'Oneova App Updates',
                style: GoogleFonts.inter(color: context.textPrimary, fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Installed Version: v${info.currentVersion}+${OneOvaAutoUpdater.currentBuildNumber}',
                style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
              ),
              Text(
                'Channel: ${info.channel}',
                style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Row(
                  children: [
                    Icon(
                      info.hasUpdate ? Icons.notification_important_rounded : Icons.check_circle_rounded,
                      color: info.hasUpdate ? AppColors.brandPink : AppColors.brandBlue,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info.hasUpdate
                            ? 'Upgrade available: v${info.latestVersion}'
                            : 'Up to date with server registry.',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              if (info.hasUpdate) ...[
                const SizedBox(height: 8),
                Text(info.releaseNotes, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Dismiss', style: GoogleFonts.inter(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    );
  }
}
