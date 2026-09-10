import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../backend/ai_brain_service.dart';

class TikTokAiAssistantScreen extends ConsumerStatefulWidget {
  const TikTokAiAssistantScreen({super.key});

  @override
  ConsumerState<TikTokAiAssistantScreen> createState() => _TikTokAiAssistantScreenState();
}

class _TikTokAiAssistantScreenState extends ConsumerState<TikTokAiAssistantScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isProcessing = false;
  bool _isListening = false; // Mock voice state

  @override
  void initState() {
    super.initState();
    // Initial welcome message
    _messages.add({
      "role": "assistant",
      "content": "I'm your MPEPE TikTok Automation Assistant. You can use your voice or type to command me to crop videos, analyze retention, or inject B-roll.",
      "type": "text",
    });
  }

  void _toggleListening() async {
    HapticFeedback.heavyImpact();
    setState(() {
      _isListening = !_isListening;
    });

    if (_isListening) {
      // Simulate listening for a few seconds then capturing a command
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      setState(() {
        _isListening = false;
        _chatController.text = "Auto crop my latest video for TikTok";
      });
      _sendMessage();
    }
  }

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isProcessing = true;
      _chatController.clear();
    });

    final aiService = ref.read(aiBrainProvider);
    
    // In a real Antigravity style app, we would stream statuses. We simulate it here.
    bool keepProcessing = true;
    
    // Send to brain (which now has tiktok tools)
    // We pass 'tiktok' as taskType to instruct the brain to prioritize TikTok tools
    while (keepProcessing && mounted) {
      final response = await aiService.processRequest(_messages, taskType: 'tiktok');

      if (response is AiTextResponse) {
        setState(() {
          _messages.add({"role": "assistant", "content": response.text, "type": "text"});
          _isProcessing = false;
        });
        keepProcessing = false;
      } else if (response is AiToolCallResponse) {
        // Record tool call as a 'status' message (Antigravity style)
        for (var call in response.toolCalls) {
          final function = call['function'];
          final name = function['name'];
          final id = call['id'];
          
          setState(() {
            _messages.add({
              "role": "status",
              "content": "Executing: $name...",
            });
          });

          // Here the aiBrainProvider actually executes the tool locally or via service
          // Because aiBrainService handles TikTok tool execution internally now (we will update it),
          // We just need to wait for the brain to resolve the tool call in the next iteration.
          
          // Actually, in the current aiBrainService implementation, it just returns the tool call to the UI.
          // Let's execute it here for simplicity and feed the result back, just like hub_ai_screen.
          
          String toolResult = await aiService.executeTikTokTool(name, function['arguments'] ?? "{}");
          
          setState(() {
            _messages.add({
              "role": "tool",
              "content": toolResult,
              "tool_call_id": id,
              "name": name,
            });
          });
        }
      } else {
        keepProcessing = false;
        setState(() { _isProcessing = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StudioBackground(
        backgroundIcons: const [Icons.tiktok, Icons.auto_awesome, Icons.mic],
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: _buildChatArea(),
              ),
              _buildInputArea(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 4),
              const Text('TikTok Automator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const MpepePill(text: 'Voice Ready', isAi: true),
        ],
      ),
    );
  }

  Widget _buildChatArea() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final role = msg['role'];

        if (role == 'user') {
          return _buildUserBubble(msg['content']);
        } else if (role == 'assistant' && msg['type'] == 'text') {
          return _buildAssistantBubble(msg['content']);
        } else if (role == 'status') {
          return _buildStatusBubble(msg['content']);
        } else if (role == 'tool') {
          // Antigravity style: tools returning success show as succinct status updates
          return _buildStatusBubble(msg['content'], isSuccess: true);
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildUserBubble(String text) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 40),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.mpepeMaroon, // Brand Color
          borderRadius: BorderRadius.circular(16).copyWith(bottomRight: const Radius.circular(4)),
        ),
        child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ).animate().fade().slideX(begin: 0.1),
    );
  }

  Widget _buildAssistantBubble(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 40),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(bottomLeft: const Radius.circular(4)),
          border: Border.all(color: AppColors.mpepeGold.withValues(alpha: 0.3)), // Brand Accent
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4)),
      ).animate().fade().slideX(begin: -0.1),
    );
  }

  Widget _buildStatusBubble(String text, {bool isSuccess = false}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSuccess ? Icons.check_circle : Icons.sync,
              size: 14,
              color: isSuccess ? Colors.greenAccent : AppColors.mpepeGold,
            ).animate(onPlay: (controller) => isSuccess ? null : controller.repeat()).rotate(duration: 1000.ms),
            const SizedBox(width: 8),
            Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 12,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ).animate().fade(),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), // Extra padding for safe area
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Column(
        children: [
          if (_isProcessing)
            LinearProgressIndicator(
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.mpepeMaroon.withValues(alpha: 0.5)),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              GestureDetector(
                onTap: _toggleListening,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? AppColors.mpepeMaroon : AppColors.mpepeGold.withValues(alpha: 0.2),
                    boxShadow: _isListening
                        ? [BoxShadow(color: AppColors.mpepeMaroon.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 4)]
                        : null,
                  ),
                  child: Icon(
                    Icons.mic,
                    color: _isListening ? Colors.white : AppColors.mpepeGold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: TextField(
                    controller: _chatController,
                    onSubmitted: (_) => _sendMessage(),
                    decoration: const InputDecoration(
                      hintText: 'Type a command...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: AppColors.mpepeMaroon),
                onPressed: _isProcessing ? null : _sendMessage,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
