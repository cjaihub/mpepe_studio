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
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: Text('AI Assistant Settings', style: AppTheme.h2Style),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new),
          onPressed: () => context.pop(),
        ),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
        data: (settings) {
          final aiSettings = settings['ai'] as Map<String, dynamic>? ?? {};

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              _buildSettingsGroup(
                context,
                'Model Selection',
                [
                  _buildDropdown(context, aiSettings, Icons.psychology, 'Default Model', 'defaultModel',
                      ['gemini-1.5-pro', 'gemini-1.5-flash', 'gpt-4o', 'claude-3-opus'], true),
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
        MpepeCard(
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
            dropdownColor: AppColors.darkSurfaceHighlight,
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
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
                  activeTrackColor: AppColors.mpepeMaroon,
                  thumbColor: AppColors.mpepeGold,
                  overlayColor: AppColors.mpepeMaroon.withValues(alpha: 0.15),
                  inactiveTrackColor: AppColors.mpepeMaroon.withValues(alpha: 0.2),
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
}
