import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import '../backend/ai_brain_service.dart';
import '../backend/project_repository.dart';
import '../backend/remote_connect_service.dart';
import '../backend/agents/youtube_agent.dart';
import 'dart:convert';
import 'voice_assistant_overlay.dart';

class HubAiScreen extends ConsumerStatefulWidget {
  const HubAiScreen({super.key});

  @override
  ConsumerState<HubAiScreen> createState() => _HubAiScreenState();
}

class _HubAiScreenState extends ConsumerState<HubAiScreen> {
  int _selectedMode = 0; // 0 = Chat, 1 = Pre-Production

  // Chat State
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isChatLoading = false;

  // Breakdown State
  final TextEditingController _scriptController = TextEditingController();
  ScriptBreakdown? _breakdown;
  bool _isBreakdownLoading = false;

  void _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isChatLoading = true;
      _chatController.clear();
    });

    final taskType = text.toLowerCase().contains('audio') || text.toLowerCase().contains('voice') ? 'audio' : 'general';
    final aiService = ref.read(aiBrainProvider);
    final remoteConnectState = ref.read(remoteConnectProvider);
    final remoteConnect = ref.read(remoteConnectProvider.notifier);
    
    bool keepProcessing = true;
    
    while(keepProcessing && mounted) {
      final response = await aiService.processRequest(_messages, taskType: taskType);

      if (response is AiTextResponse) {
        setState(() {
          _messages.add({"role": "assistant", "content": response.text, "type": "text"});
          _isChatLoading = false;
        });
        keepProcessing = false;
      } else if (response is AiWidgetResponse) {
        setState(() {
          _messages.add({
            "role": "assistant", 
            "content": "", 
            "type": "widget", 
            "widgetType": response.widgetType, 
            "data": response.data
          });
          _isChatLoading = false;
        });
        keepProcessing = false;
      } else if (response is AiToolCallResponse) {
        setState(() {
          _messages.add({
            "role": "assistant",
            "content": null,
            "type": "tool_call",
            "tool_calls": response.toolCalls,
          });
        });
        
        for (var call in response.toolCalls) {
          final function = call['function'];
          final name = function['name'];
          final id = call['id'];
          final arguments = function['arguments'] != null ? jsonDecode(function['arguments']) : {};
          
          String toolResult = "";
          
          if (name == 'get_studio_calendar') {
             toolResult = "Studio Calendar: Today you have a shoot at 10 AM, and an editing session at 2 PM.";
          } else if (['apply_lut', 'add_marker', 'color_match', 'auto_balance', 'apply_film_emulation'].contains(name)) {
             // Default to DaVinci for mockup since software is now tied to the remote computer
             String targetSoftwareId = 'dr';
             remoteConnect.sendCommand(targetSoftwareId, name, arguments);
             toolResult = "Success: Executed $name on target software.";
          } else if (name == 'fetch_latest_comments') {
             final ytAgent = ref.read(youtubeAgentProvider);
             final comments = await ytAgent.fetchLatestComments(arguments['channel_id']);
             toolResult = jsonEncode(comments);
          } else if (name == 'reply_to_comment') {
             final ytAgent = ref.read(youtubeAgentProvider);
             final success = await ytAgent.replyToComment(arguments['comment_id'], arguments['text']);
             toolResult = success ? "Success: Replied to comment." : "Error: Failed to reply.";
          } else if (name == 'create_studio_project') {
             toolResult = await aiService.executeStudioTool(name, function['arguments'] ?? '{}');
          } else if (name == 'research_trending_topics') {
             final ytAgent = ref.read(youtubeAgentProvider);
             final topics = await ytAgent.researchTrendingTopics(arguments['query']);
             toolResult = jsonEncode(topics);
          } else {
             toolResult = "Error: Unknown tool $name";
          }
          
          setState(() {
            _messages.add({
              "role": "tool",
              "content": toolResult,
              "tool_call_id": id,
              "name": name,
            });
          });
        }
      }
    }
  }

  void _generateBreakdown() async {
    final text = _scriptController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isBreakdownLoading = true;
      _breakdown = null;
    });

    final aiService = ref.read(aiBrainProvider);
    final result = await aiService.breakdownScript(text);

    setState(() {
      _breakdown = result;
      _isBreakdownLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StudioBackground(
      backgroundIcons: const [Icons.hub_outlined, Icons.auto_awesome_outlined, Icons.movie_filter_outlined],
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildToggleBar(),
              const SizedBox(height: 18),
              Expanded(
                child: _selectedMode == 0 ? _buildChatMode() : _buildBreakdownMode(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                HapticFeedback.lightImpact();
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/hub/home');
                }
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 12),
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => AppColors.aiGradient.createShader(bounds),
              child: const Icon(Icons.auto_awesome, size: 24),
            ),
            const SizedBox(width: 8),
            Text('Mpepe AI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface)),
          ],
        ),
        Row(
          children: [
            const MpepePill(text: 'Mpepe Model', isAi: true),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.more_vert),
              color: Colors.white70,
              onPressed: () {
                HapticFeedback.lightImpact();
                context.push('/settings/ai');
              },
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildToggleBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _buildToggleButton("Chat Assistant", 0)),
          Expanded(child: _buildToggleButton("Pre-Production", 1)),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String title, int index) {
    final isSelected = _selectedMode == index;
    return Semantics(
      button: true,
      label: 'Switch to $title mode',
      selected: isSelected,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedMode = index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white10 : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white54,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChatMode() {
    final visibleMessages = _messages.where((m) => m['role'] == 'user' || (m['role'] == 'assistant' && (m['type'] == 'text' || m['type'] == 'widget'))).toList();

    return Column(
      children: [
        Expanded(
          child: visibleMessages.isEmpty
              ? _buildChatEmptyState()
              : ListView.builder(
                  itemCount: visibleMessages.length,
                  itemBuilder: (context, index) {
                    final msg = visibleMessages[index];
                    final isUser = msg['role'] == 'user';
                    
                    if (msg['type'] == 'widget' && msg['widgetType'] == 'chart') {
                      return _buildChartWidget(msg['data']);
                    }
                    
                    return _buildChatBubble(msg['content'] as String? ?? '', isUser);
                  },
                ),
        ),
        if (_isChatLoading) _buildChatSkeleton(),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Semantics(
                button: true,
                label: 'Attach file',
                child: IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 22),
                  color: Colors.white54,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    // Future implementation: File picker
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('File attachments coming soon.')),
                    );
                  },
                ),
              ),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: TextField(
                    controller: _chatController,
                    maxLines: null,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Message Mpepe AI...',
                      hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Voice Assistant',
                child: IconButton(
                  icon: const Icon(Icons.mic, size: 22),
                  color: Colors.white70,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => const VoiceAssistantOverlay(),
                    );
                  },
                ),
              ),
              Semantics(
                button: true,
                label: 'Send message',
                child: Padding(
                  padding: const EdgeInsets.only(right: 4, bottom: 4),
                  child: GestureDetector(
                    onTap: _isChatLoading ? null : _sendMessage,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, 
                        color: _isChatLoading ? Colors.grey[800] : AppColors.mpepeMaroon,
                      ),
                      child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBreakdownMode() {
    return Column(
      children: [
        if (_breakdown == null && !_isBreakdownLoading) ...[
          Expanded(
            child: TextField(
              controller: _scriptController,
              maxLines: null,
              expands: true,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5),
              decoration: InputDecoration(
                hintText: 'Paste scene script here (e.g. INT. STUDIO - DAY\\n\\nJohn walks in holding a COFFEE CUP...)',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white10)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.orange)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.orange)),
              ),
              icon: const Icon(Icons.auto_awesome, color: Colors.orange),
              label: const Text('Generate Script Breakdown', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              onPressed: () {
                HapticFeedback.lightImpact();
                _generateBreakdown();
              },
            ),
          ),
        ] else if (_isBreakdownLoading) ...[
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TweenAnimationBuilder(
                    tween: Tween<double>(begin: 0.5, end: 1.0),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeInOut,
                    builder: (context, val, child) {
                      return Transform.scale(
                        scale: val,
                        child: Opacity(
                          opacity: val,
                          child: const Icon(Icons.auto_awesome, color: Colors.orange, size: 48),
                        ),
                      );
                    },
                    onEnd: () {}, // loop handled natively or by user visually 
                  ),
                  const SizedBox(height: 16),
                  const Text('AI is analyzing the script...', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          )
        ] else if (_breakdown != null) ...[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Analysis Complete', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  MpepeCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Project Title: ${_breakdown!.title}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
                        const SizedBox(height: 16),
                        const Text('Characters:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        Text(_breakdown!.characters.join(', '), style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        const Text('Props Needed:', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        Text(_breakdown!.props.join(', '), style: const TextStyle(color: Colors.white70)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Shot List:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ..._breakdown!.shotList.map((shot) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                          child: Text(shot['shot'] ?? 'SHOT', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(shot['description'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                      ],
                    ),
                  )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() => _breakdown = null);
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white38)),
                  child: const Text('Reset', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () async {
                    if (_breakdown == null) return;
                    HapticFeedback.mediumImpact();
                    
                    // Automatically generate Storyboard visuals using Pollinations AI
                    List<String> generatedStoryboardUrls = _breakdown!.shotList.map((shot) {
                      final prompt = "${_breakdown!.title}, ${shot['shot']}, ${shot['description']}, cinematic, photorealistic, 8k resolution, highly detailed, storyboard style, dramatic lighting";
                      final encoded = Uri.encodeComponent(prompt);
                      return "https://image.pollinations.ai/prompt/$encoded?width=1920&height=1080&nologo=true";
                    }).toList();

                    final repo = ref.read(projectRepositoryProvider);
                    await repo.addProject(StudioProject(
                      id: '',
                      category: 'Video', // Assume pre-production breakdown is video by default
                      title: _breakdown!.title,
                      status: 'Scripting',
                      completedSteps: 1,
                      characters: _breakdown!.characters,
                      props: _breakdown!.props,
                      storyboardUrls: generatedStoryboardUrls,
                      createdAt: DateTime.now(),
                    ));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Project created! Go to the Projects tab to see it.')));
                    }
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.black),
                  child: const Text('Create Project', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              )
            ],
          )
        ],
      ],
    );
  }

  Widget _buildChatEmptyState() {
    return MpepeCard(
      borderColor: const Color(0x40FF6A00),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MpepeAvatar(text: '', gradient: AppColors.aiGradient, size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Mpepe AI is ready", style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 8),
                Text("I am your intelligent studio assistant. Attach files, talk to me via voice, or type a request about Mpepe or social media management.", style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 11, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(String text, bool isUser) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2) : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 13)),
      ),
    );
  }

  Widget _buildChartWidget(Map<String, dynamic> data) {
    final title = data['title'] ?? 'Chart';
    final chartData = data['data'] as Map<String, dynamic>? ?? {};

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 16),
          if (chartData.isEmpty)
            const Text('No data available', style: TextStyle(color: Colors.white54))
          else
            Column(
              children: chartData.entries.map((e) {
                // Determine a relative percentage for the bar width (mocked visually)
                final value = e.value.toString();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text(e.key, style: const TextStyle(fontSize: 12))),
                      Expanded(
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: 0.7, // Hardcoded visual for demo, AI provides raw values
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildChatSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      alignment: Alignment.centerLeft,
      child: const _AiThinkingIndicator(),
    );
  }
}

class _AiThinkingIndicator extends StatefulWidget {
  const _AiThinkingIndicator();

  @override
  State<_AiThinkingIndicator> createState() => _AiThinkingIndicatorState();
}

class _AiThinkingIndicatorState extends State<_AiThinkingIndicator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _statuses = ["Thinking...", "Searching projects...", "Generating response..."];
  int _statusIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    
    _cycleStatus();
  }
  
  void _cycleStatus() {
    if (!mounted) return;
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _statusIndex = (_statusIndex + 1) % _statuses.length;
      });
      _cycleStatus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: 0.8 + (_controller.value * 0.4),
              child: Opacity(
                opacity: 0.5 + (_controller.value * 0.5),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: AppColors.mpepeMaroon,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: Text(
            _statuses[_statusIndex],
            key: ValueKey(_statusIndex),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
