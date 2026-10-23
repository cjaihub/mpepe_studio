import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/ai_personalization/models/ai_memory_models.dart';
import '../../../../backend/ai_personalization/services/ai_memory_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiMemoryManagerScreen extends ConsumerStatefulWidget {
  const AiMemoryManagerScreen({super.key});

  @override
  ConsumerState<AiMemoryManagerScreen> createState() => _AiMemoryManagerScreenState();
}

class _AiMemoryManagerScreenState extends ConsumerState<AiMemoryManagerScreen> {
  bool _learningEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final enabled = await ref.read(aiMemoryServiceProvider).isLearningEnabled();
    if (mounted) {
      setState(() {
        _learningEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLearning(bool value) async {
    setState(() => _learningEnabled = value);
    await ref.read(aiMemoryServiceProvider).setLearningEnabled(value);
  }

  Future<void> _resetMemories() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Reset AI Memory?', style: TextStyle(color: ctx.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
          'This will permanently delete everything the AI has learned about your style, tone, and preferences. This action cannot be undone.',
          style: TextStyle(color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            child: const Text('Reset', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(aiMemoryServiceProvider).resetAllMemories();
    }
  }

  void _editMemory(AiMemoryNode node) {
    final controller = TextEditingController(text: node.value);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        title: Text('Edit ${node.category.name}', style: TextStyle(color: ctx.textPrimary)),
        content: TextField(
          controller: controller,
          style: TextStyle(color: ctx.textPrimary),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ctx.border)),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref.read(aiMemoryServiceProvider).updateMemory(node.id, controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    final memoriesAsync = ref.watch(aiMemoryServiceProvider).streamMemories();

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Text('AI Personalization Memory', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          // Global Control
          Container(
            padding: const EdgeInsets.all(16),
            color: context.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Enable AI Learning', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                  subtitle: Text('Allow the AI to learn your communication style over time.', style: TextStyle(color: context.textSecondary)),
                  activeThumbColor: AppColors.brandBlue,
                  value: _learningEnabled,
                  onChanged: _toggleLearning,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _resetMemories,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.brandBlue),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Reset All Memory', style: TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Memory List
          Expanded(
            child: StreamBuilder<List<AiMemoryNode>>(
              stream: memoriesAsync,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
                }
                
                final memories = snapshot.data ?? [];
                
                if (memories.isEmpty) {
                  return Center(
                    child: Text('The AI has not learned anything about your style yet.', style: TextStyle(color: context.textMuted)),
                  );
                }

                return ListView.builder(
                  itemCount: memories.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (context, index) {
                    final node = memories[index];
                    return Card(
                      color: context.surface,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(node.category.name.toUpperCase(), style: const TextStyle(color: AppColors.brandBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(node.value, style: TextStyle(color: context.textPrimary)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, color: context.textMuted),
                              onPressed: () => _editMemory(node),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: AppColors.brandBlue),
                              onPressed: () => ref.read(aiMemoryServiceProvider).deleteMemory(node.id),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
