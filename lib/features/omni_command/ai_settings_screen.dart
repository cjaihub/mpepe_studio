import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/ai_agents/omni_command/personal_memory_engine.dart';
import '../../backend/ai_agents/omni_command/omni_command_service.dart';
import '../../backend/ai_agents/omni_command/omni_context_resolver.dart';
import '../../shared/theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

// ---------------------------------------------------------------------------
// AI Memory Management Screen
// User can view, edit, delete, disable, and reset AI memory.
// ---------------------------------------------------------------------------

class AiMemoryScreen extends ConsumerStatefulWidget {
  const AiMemoryScreen({super.key});

  @override
  ConsumerState<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends ConsumerState<AiMemoryScreen> {
  List<SemanticMemory>? _memories;
  bool _loading = true;
  String? _error;

  String get _userId => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _loadMemories();
  }

  Future<void> _loadMemories() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final engine = ref.read(personalMemoryEngineProvider);
      final mems = await engine.retrieveRelevantMemories(_userId, '');
      setState(() {
        _memories = mems;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load memories.';
        _loading = false;
      });
    }
  }

  Future<void> _deleteMemory(SemanticMemory memory) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Delete Memory',
      body: 'Are you sure you want to delete this memory?\n\n"${memory.content}"',
      confirmLabel: 'Delete',
      isDestructive: true,
    );
    if (!confirmed) return;
    await ref.read(personalMemoryEngineProvider).deleteMemory(_userId, memory.id);
    _loadMemories();
  }

  Future<void> _resetAllMemories() async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Reset All Memory',
      body:
          'This will permanently delete all AI memory. '
          'Your AI assistant will no longer remember your preferences. '
          '\n\nThis cannot be undone.',
      confirmLabel: 'Reset All',
      isDestructive: true,
    );
    if (!confirmed) return;
    await ref.read(personalMemoryEngineProvider).resetAllMemories(_userId);
    _loadMemories();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'AI Memory',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_memories != null && _memories!.isNotEmpty)
            TextButton(
              onPressed: _resetAllMemories,
              child: Text(
                'Reset All',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Memory toggle
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.memory, color: AppColors.brandBlue, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Memory Enabled',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'AI remembers your approved preferences.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.memoryEnabled,
                  activeThumbColor: AppColors.brandBlue,
                  onChanged: (v) =>
                      ref.read(aiSettingsProvider.notifier).setMemoryEnabled(v),
                ),
              ],
            ),
          ),

          // Memory list
          Expanded(
            child: _loading
                ? const Center(
                    child: AnimatedLoadingIndicator(
                      color: AppColors.brandBlue,
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Text(
                          _error!,
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondary, fontSize: 14),
                        ),
                      )
                    : _memories == null || _memories!.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            onRefresh: _loadMemories,
                            color: AppColors.brandBlue,
                            backgroundColor: AppColors.darkSurface,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              itemCount: _memories!.length,
                              itemBuilder: (_, i) =>
                                  _MemoryCard(
                                    memory: _memories![i],
                                    onDelete: () => _deleteMemory(_memories![i]),
                                  ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.psychology_outlined,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 16),
          Text(
            'No memory stored',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Approved preferences and style settings\nwill appear here.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textMuted,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MemoryCard extends StatelessWidget {
  final SemanticMemory memory;
  final VoidCallback onDelete;
  const _MemoryCard({required this.memory, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  memory.type.name.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brandBlue,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              if (memory.confirmedByUser)
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFF22C55E)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline,
                    size: 18, color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            memory.content,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: Colors.white,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _formatDate(memory.updatedAt),
            style: GoogleFonts.inter(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// AI Settings Screen
// ---------------------------------------------------------------------------

class AiSettingsScreen extends ConsumerWidget {
  const AiSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final notifier = ref.read(aiSettingsProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'AI Settings',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Master AI toggle
          _buildSection(
            title: 'PERSONAL AI',
            children: [
              _SettingsTile(
                icon: Icons.smart_toy_outlined,
                title: 'Enable AI',
                subtitle: 'Allow AI to assist with your inbox and tasks.',
                value: settings.aiEnabled,
                onChanged: notifier.setAiEnabled,
                danger: false,
              ),
              if (settings.aiEnabled) ...[
                const SizedBox(height: 4),
                _ModeSelector(
                  current: settings.mode,
                  onChanged: notifier.setMode,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Memory
          _buildSection(
            title: 'MEMORY & LEARNING',
            children: [
              _SettingsTile(
                icon: Icons.memory,
                title: 'AI Memory',
                subtitle: 'Remember approved preferences and communication style.',
                value: settings.memoryEnabled,
                onChanged: notifier.setMemoryEnabled,
                danger: false,
              ),
              _SettingsTile(
                icon: Icons.brush_outlined,
                title: 'Style Learning',
                subtitle: 'AI adapts to your approved communication style.',
                value: settings.styleLearningEnabled,
                onChanged: notifier.setStyleLearning,
                danger: false,
              ),
              _SettingsTile(
                icon: Icons.forum_outlined,
                title: 'Conversation Learning',
                subtitle: 'AI uses conversation context to improve responses.',
                value: settings.conversationLearningEnabled,
                onChanged: notifier.setConversationLearning,
                danger: false,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Permissions
          _buildSection(
            title: 'PERMISSIONS',
            children: [
              _SettingsTile(
                icon: Icons.send_outlined,
                title: 'Allow External Actions',
                subtitle:
                    'AI may prepare external sends. Always requires confirmation.',
                value: settings.externalActionsEnabled,
                onChanged: notifier.setExternalActions,
                danger: false,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Memory Management link
          _buildSection(
            title: 'MANAGE',
            children: [
              _SettingsNavTile(
                icon: Icons.psychology_outlined,
                title: 'AI Memory',
                subtitle: 'View, edit, delete, or reset stored memories.',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiMemoryScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // STOP AI
          if (settings.aiEnabled)
            GestureDetector(
              onTap: () => _showStopAiDialog(context, ref),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.block, color: AppColors.brandBlue, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stop Personal AI',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandBlue,
                            ),
                          ),
                          Text(
                            'Disable all AI operations immediately.',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.brandBlue, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSection(
      {required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Future<void> _showStopAiDialog(BuildContext context, WidgetRef ref) async {
    final confirmed = await _showConfirmDialog(
      context,
      title: 'Stop Personal AI',
      body: 'This will immediately disable all AI features. '
          'No AI operations will be permitted.\n\n'
          'You can re-enable AI in Settings at any time.',
      confirmLabel: 'Stop AI',
      isDestructive: true,
    );
    if (!confirmed) return;
    ref.read(aiSettingsProvider.notifier).setAiEnabled(false);
  }
}

// ---------------------------------------------------------------------------
// AI Mode Selector
// ---------------------------------------------------------------------------

class _ModeSelector extends StatelessWidget {
  final AiOperatingMode current;
  final ValueChanged<AiOperatingMode> onChanged;
  const _ModeSelector({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Mode',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          ...AiOperatingMode.values
              .where((m) => m != AiOperatingMode.off)
              .map((mode) => _ModeOption(
                    mode: mode,
                    isSelected: current == mode,
                    onTap: () => onChanged(mode),
                  )),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final AiOperatingMode mode;
  final bool isSelected;
  final VoidCallback onTap;
  const _ModeOption(
      {required this.mode, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final desc = switch (mode) {
      AiOperatingMode.assist => 'Explain and suggest only. No mutations.',
      AiOperatingMode.draft => 'Create drafts. No external sends.',
      AiOperatingMode.approval =>
        'Prepare external actions. Requires confirmation.',
      AiOperatingMode.auto => 'Execute explicitly allowed actions automatically.',
      _ => '',
    };

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandBlue.withValues(alpha: 0.12)
              : AppColors.darkSurfaceHighlight,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.brandBlue.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.name[0].toUpperCase() + mode.name.substring(1),
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? AppColors.brandBlue : Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  size: 18, color: AppColors.brandBlue),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared Settings Tiles
// ---------------------------------------------------------------------------

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool danger;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(icon,
              color: danger ? AppColors.brandBlue : AppColors.textSecondary,
              size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.brandBlue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared confirmation dialog
// ---------------------------------------------------------------------------

Future<bool> _showConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.darkSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        title,
        style: GoogleFonts.inter(
            fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
      ),
      content: Text(
        body,
        style: GoogleFonts.inter(
            fontSize: 13, color: AppColors.textSecondary, height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel',
              style: GoogleFonts.inter(
                  color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            confirmLabel,
            style: GoogleFonts.inter(
              color: isDestructive ? AppColors.brandBlue : Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
