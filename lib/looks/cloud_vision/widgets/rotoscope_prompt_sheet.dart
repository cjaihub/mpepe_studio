import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/theme/app_theme.dart';
import '../controllers/cloud_vision_controller.dart';

/// Interactive sheet for natural-language & interactive SAM 2 rotoscoping.
class RotoscopePromptSheet extends ConsumerStatefulWidget {
  final VoidCallback onExecute;

  const RotoscopePromptSheet({
    super.key,
    required this.onExecute,
  });

  @override
  ConsumerState<RotoscopePromptSheet> createState() => _RotoscopePromptSheetState();
}

class _RotoscopePromptSheetState extends ConsumerState<RotoscopePromptSheet> {
  late final TextEditingController _textController;

  static const List<String> _quickPrompts = [
    'Isolate Main Subject',
    "Speaker's Hair",
    'Clothing & Jacket',
    'Vehicle / Car',
    'Background Only',
    'Hands & Instruments',
  ];

  @override
  void initState() {
    super.initState();
    final current = ref.read(cloudVisionControllerProvider).rotoscopePrompt;
    _textController = TextEditingController(text: current);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cloudVisionControllerProvider);
    final notifier = ref.read(cloudVisionControllerProvider.notifier);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high_rounded, size: 16, color: AppColors.brandPink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'AI Natural-Language Rotoscoping',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brandPink.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.3)),
              ),
              child: Text(
                'SAM 2 • Hiera Large',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandPink,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  onChanged: notifier.setRotoscopePrompt,
                  style: TextStyle(fontSize: 13, color: context.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'e.g. isolate speaker, select red car, mask jacket...',
                    hintStyle: TextStyle(fontSize: 12, color: context.textMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              if (_textController.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  onPressed: () {
                    _textController.clear();
                    notifier.setRotoscopePrompt('');
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _quickPrompts.map((prompt) {
            final isSelected = state.rotoscopePrompt == prompt;
            return GestureDetector(
              onTap: () {
                _textController.text = prompt;
                notifier.setRotoscopePrompt(prompt);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.brandBlue.withValues(alpha: 0.2)
                      : context.surfaceMid,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.brandBlue : context.border,
                    width: 1.0,
                  ),
                ),
                child: Text(
                  prompt,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.brandBlue : context.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Track Object Across Video Timeline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textPrimary,
              ),
            ),
            Switch.adaptive(
              value: state.rotoscopeTracking,
              activeTrackColor: AppColors.brandBlue,
              onChanged: notifier.setRotoscopeTracking,
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: state.isProcessing ? null : widget.onExecute,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (state.isProcessing)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                else
                  const Icon(Icons.auto_fix_high_rounded, size: 16),
                const SizedBox(width: 8),
                Text(
                  state.isProcessing ? 'Segmenting with SAM 2...' : 'Generate AI Mask (1 Credit)',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
