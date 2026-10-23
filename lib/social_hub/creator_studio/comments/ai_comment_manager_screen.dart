import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../backend/comments/services/ai_comment_service.dart';
import '../../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class AiCommentManagerScreen extends ConsumerStatefulWidget {
  const AiCommentManagerScreen({super.key});

  @override
  ConsumerState<AiCommentManagerScreen> createState() => _AiCommentManagerScreenState();
}

class _AiCommentManagerScreenState extends ConsumerState<AiCommentManagerScreen> {
  bool _isLoading = false;
  Map<String, dynamic>? _summary;
  List<String> _recurringQuestions = [];
  String? _draftReply;

  // Mock comment data
  final String _mockCommentId = 'c123';
  final String _mockCommentText = 'Incredible video! What camera lens did you use?';

  Future<void> _analyzeVideo() async {
    setState(() => _isLoading = true);
    final service = ref.read(aiCommentServiceProvider);
    
    final summaryResult = await service.summarizeComments('vid_mock');
    final questionsResult = await service.detectRecurringQuestions('vid_mock');

    if (mounted) {
      setState(() {
        _summary = summaryResult;
        _recurringQuestions = questionsResult;
        _isLoading = false;
      });
    }
  }

  Future<void> _generateReply() async {
    final service = ref.read(aiCommentServiceProvider);
    final reply = await service.suggestReply(_mockCommentId, _mockCommentText);
    if (mounted) {
      setState(() => _draftReply = reply);
    }
  }

  void _publishReply() {
    // In production, this would send the reply to Firestore/Backend.
    // Enforcing: "Never auto-send without permission" - this requires explicit user tap.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reply published safely.'), backgroundColor: AppColors.brandBlue),
    );
    setState(() => _draftReply = null);
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
        title: Text('AI Comment Manager', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Analytics Header
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _analyzeVideo,
              icon: _isLoading 
                ? const SizedBox(width: 16, height: 16, child: AnimatedLoadingIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.analytics, color: Colors.white),
              label: Text(_isLoading ? 'Analyzing Comments...' : 'Summarize Video Comments', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            
            if (_summary != null) ...[
              Text('Comment Sentiment Summary', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sentiment: ${_summary!['sentiment']}', style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(_summary!['summary'], style: TextStyle(color: context.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            if (_recurringQuestions.isNotEmpty) ...[
              Text('Recurring Questions', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._recurringQuestions.map((q) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.help_outline, color: context.textMuted, size: 18),
                    const SizedBox(width: 12),
                    Expanded(child: Text(q, style: TextStyle(color: context.textPrimary))),
                  ],
                ),
              )),
              const SizedBox(height: 24),
            ],

            // Priority Comment Simulation
            Text('Priority Comment (AI Flagged)', style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange, width: 1), // Highlight priority
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.star, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Text('High Priority Viewer', style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_mockCommentText, style: TextStyle(color: context.textPrimary)),
                  const SizedBox(height: 16),
                  if (_draftReply == null)
                    OutlinedButton.icon(
                      onPressed: _generateReply,
                      icon: const Icon(Icons.auto_awesome, color: AppColors.brandBlue),
                      label: const Text('Suggest Reply', style: TextStyle(color: AppColors.brandBlue)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.brandBlue)),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.surfaceMid,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AI Draft (Not Sent)', style: TextStyle(color: context.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(_draftReply!, style: TextStyle(color: context.textPrimary)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _draftReply = null),
                          child: Text('Discard', style: TextStyle(color: context.textMuted)),
                        ),
                        ElevatedButton(
                          onPressed: _publishReply,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandBlue),
                          child: const Text('Publish Reply', style: TextStyle(color: Colors.white)),
                        ),
                      ],
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
}
