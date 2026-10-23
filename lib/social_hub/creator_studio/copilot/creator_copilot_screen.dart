import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/creator_copilot/models/copilot_models.dart';
import '../../../../backend/creator_copilot/services/creator_copilot_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CreatorCopilotScreen extends ConsumerStatefulWidget {
  const CreatorCopilotScreen({super.key});

  @override
  ConsumerState<CreatorCopilotScreen> createState() => _CreatorCopilotScreenState();
}

class _CreatorCopilotScreenState extends ConsumerState<CreatorCopilotScreen> {
  bool _isLoading = false;
  List<CopilotSuggestion> _suggestions = [];
  final String _activeNiche = 'Tech Reviews'; // Mock selected context

  Future<void> _triggerBrainstorm() async {
    setState(() => _isLoading = true);
    final copilot = ref.read(creatorCopilotProvider);
    
    // Fire off multiple suggestion generators
    final results = await Future.wait([
      copilot.generateContentIdeas(_activeNiche),
      copilot.generateVideoMetadata('vid_123', 'My New Setup'),
      copilot.suggestPostingWindow().then((value) => [value]),
      copilot.generateCommunitySummary('user_123').then((value) => [value]),
    ]);

    if (mounted) {
      setState(() {
        _suggestions = results.expand((list) => list).toList();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
            const SizedBox(width: 8),
            Text('Creator Copilot', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header / Control Area
          Container(
            padding: const EdgeInsets.all(16),
            color: context.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your AI Creative Assistant',
                  style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Generate hooks, scripts, captions, and editing suggestions. Copilot only suggests — you control publishing.',
                  style: TextStyle(color: context.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _triggerBrainstorm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: _isLoading 
                      ? const SizedBox(width: 16, height: 16, child: AnimatedLoadingIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.bolt, color: Colors.white),
                    label: Text(_isLoading ? 'Analyzing...' : 'Generate New Ideas', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          
          // Results Area
          Expanded(
            child: _suggestions.isEmpty && !_isLoading
                ? Center(
                    child: Text('Tap generate to brainstorm new content.', style: TextStyle(color: context.textMuted)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _suggestions.length,
                    itemBuilder: (context, index) {
                      final suggestion = _suggestions[index];
                      return _buildSuggestionCard(suggestion);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionCard(CopilotSuggestion suggestion) {
    IconData getIcon() {
      switch (suggestion.capability) {
        case CopilotCapability.contentIdeas: return Icons.lightbulb_outline;
        case CopilotCapability.hooks: return Icons.catching_pokemon;
        case CopilotCapability.hashtags: return Icons.tag;
        case CopilotCapability.titles: return Icons.title;
        case CopilotCapability.bestPostingWindows: return Icons.access_time;
        case CopilotCapability.communitySummaries: return Icons.people_outline;
        default: return Icons.auto_awesome;
      }
    }

    return Card(
      color: context.surface,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(getIcon(), color: AppColors.brandBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  suggestion.capability.name.toUpperCase(),
                  style: const TextStyle(color: AppColors.brandBlue, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              suggestion.title,
              style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              suggestion.content,
              style: TextStyle(color: context.textSecondary, fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // Logic to copy or discard
                  },
                  child: Text('Discard', style: TextStyle(color: context.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Logic to apply the suggestion to the draft
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.surfaceMid,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Use This', style: TextStyle(color: context.textPrimary)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
