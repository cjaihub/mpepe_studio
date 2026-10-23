import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/ai_agents/omni_command/omni_command_service.dart';
import '../../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../../backend/ai_agents/omni_command/omni_tool_registry.dart';
import '../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// ---------------------------------------------------------------------------
// Entry point: show the Omni Command sheet
// ---------------------------------------------------------------------------

Future<void> showOmniCommand(
  BuildContext context,
  WidgetRef ref, {
  OmniContext? omniContext,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    useRootNavigator: true,
    builder: (_) => ProviderScope(
      child: OmniCommandSheet(providedContext: omniContext),
    ),
  );
}

// ---------------------------------------------------------------------------
// Omni Command Sheet
// ---------------------------------------------------------------------------

class OmniCommandSheet extends ConsumerStatefulWidget {
  final OmniContext? providedContext;
  const OmniCommandSheet({super.key, this.providedContext});

  @override
  ConsumerState<OmniCommandSheet> createState() => _OmniCommandSheetState();
}

class _OmniCommandSheetState extends ConsumerState<OmniCommandSheet>
    with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scrollController = ScrollController();
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late OmniContext _lockedContext;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Lock the context once to prevent background navigations from shifting execution target
    if (!_isContextLocked) {
      _lockContext();
    }
  }

  bool _isContextLocked = false;
  void _lockContext() {
    if (widget.providedContext != null) {
      _lockedContext = widget.providedContext!;
    } else {
      final existingContext = ref.read(omniContextProvider);
      if (existingContext != null) {
        _lockedContext = existingContext;
      } else {
        final settings = ref.read(aiSettingsProvider);
        final notifier = ref.read(aiSettingsProvider.notifier);
        _lockedContext = OmniContext(
          sessionId: buildOmniSessionId(),
          userId: 'local_user', // Replaced by FirebaseAuth.currentUser!.uid in production
          aiMode: notifier.effectiveMode,
          memoryEnabled: settings.memoryEnabled,
        );
      }
    }
    _isContextLocked = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    ref.read(omniCommandServiceProvider.notifier).process(text, _lockedContext);
    _controller.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(omniCommandServiceProvider);
    final settings = ref.watch(aiSettingsProvider);

    // Scroll when history changes
    ref.listen(omniCommandServiceProvider, (prev, next) {
      if (next.history.length != (prev?.history.length ?? 0)) {
        _scrollToBottom();
      }
    });

    return FadeTransition(
      opacity: _fadeAnimation,
      child: DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        snap: true,
        snapSizes: const [0.5, 0.88, 0.95],
        builder: (ctx, scrollCtrl) => _SheetBody(
          state: state,
          settings: settings,
          controller: _controller,
          focus: _focus,
          historyScrollController: _scrollController,
          sheetScrollController: scrollCtrl,
          context: _lockedContext,
          onSubmit: _submit,
          onCancel: () => ref.read(omniCommandServiceProvider.notifier).cancel(),
          onConfirm: () => ref
              .read(omniCommandServiceProvider.notifier)
              .confirmPendingAction(_lockedContext),
          onRejectConfirmation: () =>
              ref.read(omniCommandServiceProvider.notifier).cancelPendingAction(),
          onSuggestion: (s) {
            _controller.text = s;
            _focus.requestFocus();
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sheet Body
// ---------------------------------------------------------------------------

class _SheetBody extends ConsumerWidget {
  final OmniCommandState state;
  final AiSettings settings;
  final TextEditingController controller;
  final FocusNode focus;
  final ScrollController historyScrollController;
  final ScrollController sheetScrollController;
  final OmniContext context;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final VoidCallback onRejectConfirmation;
  final ValueChanged<String> onSuggestion;

  const _SheetBody({
    required this.state,
    required this.settings,
    required this.controller,
    required this.focus,
    required this.historyScrollController,
    required this.sheetScrollController,
    required this.context,
    required this.onSubmit,
    required this.onCancel,
    required this.onConfirm,
    required this.onRejectConfirmation,
    required this.onSuggestion,
  });

  @override
  Widget build(BuildContext ctx, WidgetRef ref) {
    final isOff = settings.mode == AiOperatingMode.off || !settings.aiEnabled;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildHandle(),
            _buildHeader(ctx, ref, isOff),
            if (context.conversationId != null || context.platformId != null)
              _buildContextChip(),
            const SizedBox(height: 4),
            Expanded(
              child: state.history.isEmpty && !_isWorking()
                  ? _buildEmptyState(isOff)
                  : _buildHistory(ctx),
            ),
            if (_isWorking()) _buildProgressBar(),
            if (state.status == OmniRequestStatus.awaitingConfirmation &&
                state.pendingConfirmation != null)
              _buildConfirmationBanner(ctx),
            if (state.suggestions.isNotEmpty && state.history.isEmpty)
              _buildSuggestions(),
            _buildInputBar(ctx, isOff),
          ],
        ),
      ),
    );
  }

  bool _isWorking() =>
      state.status == OmniRequestStatus.classifying ||
      state.status == OmniRequestStatus.planning ||
      state.status == OmniRequestStatus.executing ||
      state.status == OmniRequestStatus.generating;

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext ctx, WidgetRef ref, bool isOff) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isOff
                  ? AppColors.darkSurfaceHighlight
                  : AppColors.brandBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isOff ? Icons.smart_toy_outlined : Icons.bolt,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Omni Command',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              Text(
                isOff
                    ? 'AI is disabled'
                    : 'Mode: ${settings.mode.name}',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: isOff
                      ? AppColors.textSecondary
                      : AppColors.brandBlue,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (state.history.isNotEmpty)
            IconButton(
              onPressed: () =>
                  ref.read(omniCommandServiceProvider.notifier).clearHistory(),
              icon: const Icon(Icons.refresh_rounded, color: AppColors.textSecondary, size: 20),
              tooltip: 'Clear',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 22),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildContextChip() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.my_location_rounded,
                size: 12, color: AppColors.brandBlue),
            const SizedBox(width: 6),
            Text(
              context.displayContext,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isOff) {
    if (isOff) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.smart_toy_outlined,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'AI is disabled',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Enable AI in Settings to use Omni Command.',
              style: GoogleFonts.inter(
                fontSize: 13,
                color: AppColors.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Ask anything',
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Search your inbox, summarize conversations,\ndraft replies, and more.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          ..._defaultSuggestions().map((s) => _SuggestionChip(
                label: s,
                onTap: () => onSuggestion(s),
              )),
        ],
      ),
    );
  }

  List<String> _defaultSuggestions() => [
        'Show conversations that need replies',
        'Summarize this conversation',
        'Which platforms are disconnected?',
        'Draft a polite response',
        'Find unread WhatsApp messages',
      ];

  Widget _buildHistory(BuildContext ctx) {
    return ListView.builder(
      controller: historyScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.history.length,
      itemBuilder: (_, i) {
        final msg = state.history[i];
        return _MessageBubble(message: msg);
      },
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: AnimatedLoadingIndicator(
              strokeWidth: 2,
              color: AppColors.brandBlue,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              state.progressLabel ?? 'Working...',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: Text(
              'Cancel',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.brandBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationBanner(BuildContext ctx) {
    final pending = state.pendingConfirmation!;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurfaceHighlight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.brandBlue.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.brandBlue, size: 16),
              const SizedBox(width: 6),
              Text(
                'Confirm Action',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pending.progressLabel,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onRejectConfirmation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.textMuted),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Confirm',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.white)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestions() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: state.suggestions
            .map((s) => _SuggestionChip(label: s, onTap: () => onSuggestion(s)))
            .toList(),
      ),
    );
  }

  Widget _buildInputBar(BuildContext ctx, bool isOff) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, MediaQuery.of(ctx).viewInsets.bottom + 8),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.darkSurfaceHighlight, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceHighlight,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: TextField(
                controller: controller,
                focusNode: focus,
                enabled: !isOff,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.white,
                ),
                decoration: InputDecoration(
                  hintText: isOff
                      ? 'AI is disabled'
                      : 'Ask anything...',
                  hintStyle: GoogleFonts.inter(
                    fontSize: 14,
                    color: AppColors.textMuted,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSubmit(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isOff ? AppColors.darkSurfaceHighlight : AppColors.brandBlue,
              borderRadius: BorderRadius.circular(22),
            ),
            child: IconButton(
              onPressed: isOff ? null : onSubmit,
              icon: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message Bubble
// ---------------------------------------------------------------------------

class _MessageBubble extends StatelessWidget {
  final OmniTurnMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAvatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.brandBlue
                    : AppColors.darkSurfaceHighlight,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isUser
                      ? const Radius.circular(16)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.content,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.white,
                      height: 1.4,
                    ),
                  ),
                  if (message.toolResults != null &&
                      message.toolResults!.isNotEmpty)
                    _buildToolResultIndicators(message.toolResults!),
                ],
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.brandBlue,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.bolt, color: Colors.white, size: 16),
    );
  }

  Widget _buildToolResultIndicators(List<ToolResult> results) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: results.map((r) {
          final color = r.success ? const Color(0xFF22C55E) : const Color(0xFFEF4444);
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
            ),
            child: Text(
              r.executionState.name.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestion Chip
// ---------------------------------------------------------------------------

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceHighlight,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.darkSurfaceHighlight,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Mode Badge (reusable widget for app header)
// ---------------------------------------------------------------------------

class OmniCommandButton extends ConsumerWidget {
  final OmniContext? omniContext;
  const OmniCommandButton({super.key, this.omniContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final isOff = !settings.aiEnabled || settings.mode == AiOperatingMode.off;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        showOmniCommand(context, ref, omniContext: omniContext);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isOff
              ? AppColors.darkSurfaceHighlight
              : AppColors.brandBlue.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isOff
                ? AppColors.textMuted.withValues(alpha: 0.3)
                : AppColors.brandBlue.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bolt,
              size: 15,
              color: isOff ? AppColors.textMuted : AppColors.brandBlue,
            ),
            const SizedBox(width: 5),
            Text(
              'Ask AI',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isOff ? AppColors.textMuted : AppColors.brandBlue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
