import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/components.dart';
import '../models/omnichannel_upload_task.dart';
import '../services/omnichannel_upload_engine.dart';

class AbTestingDashboard extends ConsumerStatefulWidget {
  final OmnichannelUploadTask task;

  const AbTestingDashboard({super.key, required this.task});

  @override
  ConsumerState<AbTestingDashboard> createState() => _AbTestingDashboardState();
}

class _AbTestingDashboardState extends ConsumerState<AbTestingDashboard> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  List<dynamic> _variations = [];
  String? _error;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _generateTests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('generateAbTests');
      final result = await callable.call({
        'contextPrompt': 'Video titled: ${widget.task.title}. Description: ${widget.task.description}. Tags: ${widget.task.tags.join(', ')}'
      });

      setState(() {
        _variations = result.data['variations'] as List<dynamic>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyVariation(Map<String, dynamic> variation) {
    ref.read(omnichannelUploadEngineProvider.notifier).updateTaskMetadata(
      widget.task.id,
      title: variation['title'] as String?,
      description: variation['description'] as String?,
      tags: (variation['hashtags'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'AI-Driven A/B Tests',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: AppColors.brandBlue,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.brandBlue),
      ),
      body: _variations.isEmpty ? _buildEmptyState() : _buildVariationsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isLoading)
              ScaleTransition(
                scale: _pulseAnimation,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brandBlue.withValues(alpha: 0.2),
                    boxShadow: [
                      BoxShadow(color: AppColors.brandBlue.withValues(alpha: 0.5), blurRadius: 40, spreadRadius: 10),
                    ]
                  ),
                  child: const Icon(Icons.auto_awesome, color: AppColors.brandBlue, size: 48),
                ),
              )
            else
              Icon(Icons.science, color: context.textMuted, size: 64),
            
            const SizedBox(height: 32),
            Text(
              _isLoading ? 'AI is analyzing your content...' : 'Generate A/B Test Variations',
              style: AppTheme.h2Style.copyWith(color: context.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _isLoading 
                ? 'Crafting highly viral titles and descriptions based on your niche.'
                : 'Instantly generate 3 different AI thumbnail & title combinations. See which one fits your audience best.',
              style: TextStyle(color: context.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (_error != null) ...[
              Text('Error: $_error', style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            if (!_isLoading)
              OneovaButton(
                text: 'Generate Tests',
                onPressed: _generateTests,
                isPrimary: true,
              )
          ],
        ),
      ),
    );
  }

  Widget _buildVariationsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: _variations.length,
      itemBuilder: (context, index) {
        final variant = _variations[index] as Map<String, dynamic>;
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Variation ${String.fromCharCode(65 + index)}', style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                    const Icon(Icons.star_border, color: AppColors.brandBlue, size: 16),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(variant['title'] ?? 'No title', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(variant['description'] ?? 'No description', style: TextStyle(color: context.textSecondary, fontSize: 14)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: (variant['hashtags'] as List<dynamic>? ?? []).map((t) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('#$t', style: const TextStyle(color: AppColors.brandBlue, fontSize: 12)),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    OneovaButton(
                      text: 'Apply Variation',
                      onPressed: () => _applyVariation(variant),
                      isPrimary: false,
                    )
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
