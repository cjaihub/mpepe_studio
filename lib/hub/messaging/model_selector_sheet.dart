import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../../backend/ai_brain_service.dart';
import '../../shared/theme/app_theme.dart';
import 'openrouter_models_provider.dart';

class ModelSelectorSheet extends ConsumerStatefulWidget {
  const ModelSelectorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ModelSelectorSheet(),
    );
  }

  @override
  ConsumerState<ModelSelectorSheet> createState() => _ModelSelectorSheetState();
}

class _ModelSelectorSheetState extends ConsumerState<ModelSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  ModelCategory _selectedCategory = ModelCategory.vision; // Default to Vision models for multimodal spotlight!
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showApiKeyDialog() {
    final vault = ref.read(secureKeyVaultProvider);
    final brain = ref.read(aiBrainProvider);
    final keyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return FutureBuilder<String>(
          future: vault.getOpenRouterApiKey(),
          builder: (context, snapshot) {
            final activeKey = snapshot.data ?? brain.openRouterKey;
            final isConfigured = activeKey.isNotEmpty;

            return AlertDialog(
              backgroundColor: context.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: BorderSide(color: context.border, width: 1.0),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(Icons.key_rounded, color: AppColors.brandBlue, size: 18),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'OpenRouter API Key',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimary,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isConfigured
                        ? 'Active Key: ${vault.maskKey(activeKey)}'
                        : 'Enter your personal OpenRouter API key to enable live cloud vision and reasoning models.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isConfigured ? AppColors.brandBlue : context.textSecondary,
                      fontWeight: isConfigured ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyController,
                    obscureText: true,
                    style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'sk-or-v1-...',
                      hintStyle: GoogleFonts.inter(fontSize: 12, color: context.textMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border, width: 1.0),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: BorderSide(color: context.border, width: 1.0),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  ),
                  onPressed: () async {
                    final entered = keyController.text.trim();
                    if (entered.isNotEmpty) {
                      final messenger = ScaffoldMessenger.of(context);
                      await vault.storeOpenRouterApiKey(entered);
                      brain.setApiKey(entered);
                      HapticFeedback.lightImpact();
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'OpenRouter API Key safely saved to Secure Vault!',
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                          backgroundColor: AppColors.brandBlue,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  },
                  child: Text('Save Key', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final modelsAsync = ref.watch(openRouterModelsProvider);
    final selectedModel = ref.watch(selectedAiModelProvider);
    final double sheetHeight = MediaQuery.of(context).size.height * 0.82;

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: context.border, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: context.isDark ? 0.4 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        children: [
          // 1. Sleek Handle
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 2. Header Row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.brandBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.3), width: 1.0),
                  ),
                  child: const Icon(Icons.hub_rounded, color: AppColors.brandBlue, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OpenRouter AI Architecture',
                        style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Access all multimodal vision & reasoning models',
                        style: GoogleFonts.inter(
                          color: context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Configure API Key',
                  icon: const Icon(Icons.key_rounded, size: 18, color: AppColors.brandBlue),
                  onPressed: _showApiKeyDialog,
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: Icon(Icons.close_rounded, size: 18, color: context.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 3. Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: context.surfaceMid,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.border, width: 1.0),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  Icon(Icons.search_rounded, size: 17, color: context.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search 400+ models (e.g. Gemini 2.5, GPT-4o, Claude)...',
                        hintStyle: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, size: 16, color: context.textMuted),
                      onPressed: () => _searchController.clear(),
                    ),
                ],
              ),
            ),
          ),

          // 4. Category Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildCategoryChip(
                  category: ModelCategory.vision,
                  label: '👁️ Vision & Multimodal',
                  badge: 'HOT',
                  isAccent: true,
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  category: ModelCategory.all,
                  label: 'All Models',
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  category: ModelCategory.reasoning,
                  label: '🧠 Top Reasoning',
                ),
                const SizedBox(width: 6),
                _buildCategoryChip(
                  category: ModelCategory.free,
                  label: '⚡ Fast & Free',
                ),
              ],
            ),
          ),

          Divider(color: context.border, height: 1.0),

          // 5. Models List
          Expanded(
            child: modelsAsync.when(
              data: (models) {
                // Apply Category and Search filtering
                final filtered = models.where((m) {
                  // Category match
                  if (_selectedCategory == ModelCategory.vision && !m.isVision && m.id != 'auto') {
                    return false;
                  }
                  if (_selectedCategory == ModelCategory.reasoning && !m.isReasoning && m.id != 'auto') {
                    return false;
                  }
                  if (_selectedCategory == ModelCategory.free && !m.isFree && m.id != 'auto') {
                    return false;
                  }

                  // Search match
                  if (_searchQuery.isNotEmpty) {
                    final q = _searchQuery;
                    final matches = m.id.toLowerCase().contains(q) ||
                        m.name.toLowerCase().contains(q) ||
                        m.provider.toLowerCase().contains(q) ||
                        m.description.toLowerCase().contains(q);
                    if (!matches) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.search_off_rounded, size: 36, color: context.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'No models found matching "$_searchQuery"',
                          style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchController.clear();
                              _selectedCategory = ModelCategory.all;
                            });
                          },
                          child: Text(
                            'Show All Models',
                            style: GoogleFonts.inter(fontSize: 12, color: AppColors.brandBlue, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => Divider(color: context.border.withValues(alpha: 0.5), height: 1),
                  itemBuilder: (context, index) {
                    final model = filtered[index];
                    final isSelected = selectedModel.id == model.id;

                    return _buildModelCard(model, isSelected);
                  },
                );
              },
              loading: () => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
                    const SizedBox(height: 12),
                    Text(
                      'Connecting to OpenRouter Catalog...',
                      style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              error: (err, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, color: AppColors.brandPink, size: 36),
                    const SizedBox(height: 8),
                    Text('Failed to load online models', style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13)),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
                      onPressed: () => ref.refresh(openRouterModelsProvider),
                      child: const Text('Retry Connection'),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 6. Bottom Selected Indicator & Key Action
          _buildBottomStatusRail(selectedModel),
        ],
      ),
    );
  }

  Widget _buildCategoryChip({
    required ModelCategory category,
    required String label,
    String? badge,
    bool isAccent = false,
  }) {
    final isSelected = _selectedCategory == category;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        setState(() => _selectedCategory = category);
      },
      borderRadius: BorderRadius.circular(AppRadius.full),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isAccent ? AppColors.brandPink : AppColors.brandBlue)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected
                ? (isAccent ? AppColors.brandPink : AppColors.brandBlue)
                : context.border,
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : context.textPrimary,
              ),
            ),
            if (badge != null && !isSelected) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.brandPink,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  badge,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModelCard(OpenRouterModel model, bool isSelected) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        ref.read(selectedAiModelProvider.notifier).updateModel(model);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: isSelected
              ? Border.all(color: AppColors.brandBlue.withValues(alpha: 0.4), width: 1.0)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Radio / Check Icon
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                color: isSelected ? AppColors.brandBlue : context.textMuted,
                size: 18,
              ),
            ),

            // Middle: Name, Provider, Description, and Badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          model.name,
                          style: GoogleFonts.inter(
                            color: isSelected ? AppColors.brandBlue : context.textPrimary,
                            fontSize: 13.0,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (model.isVision)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandPink.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.remove_red_eye_rounded, size: 10, color: AppColors.brandPink),
                              const SizedBox(width: 3),
                              Text(
                                'VISION',
                                style: GoogleFonts.inter(
                                  color: AppColors.brandPink,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (model.isFree)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4), width: 1.0),
                          ),
                          child: Text(
                            'FREE',
                            style: GoogleFonts.inter(
                              color: const Color(0xFF10B981),
                              fontSize: 8.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),

                  // Model ID / Provider & Context Tag
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        model.id,
                        style: GoogleFonts.inter(
                          color: context.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (model.contextLength > 0) ...[
                        const SizedBox(width: 6),
                        Text('•', style: TextStyle(color: context.textMuted, fontSize: 10)),
                        const SizedBox(width: 6),
                        Text(
                          _formatContext(model.contextLength),
                          style: GoogleFonts.inter(
                            color: context.textSecondary,
                            fontSize: 10.0,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Description if present
                  if (model.description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      model.description,
                      style: GoogleFonts.inter(
                        color: context.textSecondary,
                        fontSize: 11.0,
                        height: 1.25,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusRail(OpenRouterModel selectedModel) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: context.surfaceMid,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 14, color: AppColors.brandBlue),
              const SizedBox(width: 6),
              Text(
                'Active: ',
                style: GoogleFonts.inter(fontSize: 11, color: context.textMuted),
              ),
              Text(
                selectedModel.name.length > 24 ? '${selectedModel.name.substring(0, 24)}…' : selectedModel.name,
                style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: context.textPrimary),
              ),
            ],
          ),
          InkWell(
            onTap: _showApiKeyDialog,
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_outlined, size: 12, color: AppColors.brandBlue),
                  const SizedBox(width: 4),
                  Text(
                    'API Key',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brandBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatContext(int tokens) {
    if (tokens >= 1000000) {
      return '${(tokens / 1000000).toStringAsFixed(tokens % 1000000 == 0 ? 0 : 1)}M ctx';
    } else if (tokens >= 1000) {
      return '${(tokens / 1000).round()}K ctx';
    }
    return '$tokens ctx';
  }
}
