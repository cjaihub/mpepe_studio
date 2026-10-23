import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/remote_connect_service.dart';
import '../shared/theme/app_theme.dart';

class RemoteChatScreen extends ConsumerStatefulWidget {
  const RemoteChatScreen({super.key});

  @override
  ConsumerState<RemoteChatScreen> createState() => _RemoteChatScreenState();
}

class _RemoteChatScreenState extends ConsumerState<RemoteChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  final List<Map<String, dynamic>> _messages = [];

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'id': DateTime.now().toString(), 'sender': 'user', 'text': text});
    });
    _messageController.clear();
    _scrollToBottom();

    final remoteService = ref.read(remoteConnectProvider.notifier);
    
    final commandId = await remoteService.sendCommand('nlp', 'parse_text', {'text': text});
    
    if (commandId != null) {
      _updateBotResponse(commandId, 'Sending...', true);
      
      final stream = remoteService.listenToCommand(commandId);
      if (stream != null) {
        stream.listen((snapshot) {
          if (snapshot.exists && mounted) {
            final data = snapshot.data() as Map<String, dynamic>?;
            if (data != null) {
              final status = data['status'] as String?;
              final resultMsg = data['result_message'] as String?;
              
              if (resultMsg != null) {
                _updateBotResponse(
                  commandId, 
                  resultMsg, 
                  status == 'processing' || status == 'pending'
                );
              }
            }
          }
        });
      }
    } else {
      _updateBotResponse(DateTime.now().toString(), 'Not connected to a studio.', false);
    }
  }
  
  void _updateBotResponse(String id, String text, bool isProcessing) {
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m['id'] == id);
        if (idx != -1) {
          _messages[idx]['text'] = text;
          _messages[idx]['isProcessing'] = isProcessing;
        } else {
          _messages.add({
            'id': id,
            'sender': 'bot',
            'text': text,
            'isProcessing': isProcessing,
          });
        }
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final remoteState = ref.watch(remoteConnectProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Remote Studio AI',
          style: GoogleFonts.inter(fontWeight: FontWeight.w900),
        ),
        backgroundColor: AppColors.darkSurface,
        elevation: 4,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (remoteState.status == ConnectionStatus.connected)
            IconButton(
              icon: const Icon(Icons.desktop_mac_rounded, color: Colors.white),
              tooltip: 'Launch Monitor',
              onPressed: () {
                context.push('/remote_monitor');
              },
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            decoration: BoxDecoration(
              color: remoteState.status == ConnectionStatus.connected 
                  ? Colors.green.withValues(alpha: 0.15)
                  : Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: remoteState.status == ConnectionStatus.connected 
                    ? Colors.greenAccent.withValues(alpha: 0.5)
                    : Colors.redAccent.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  remoteState.status == ConnectionStatus.connected
                      ? Icons.wifi
                      : Icons.wifi_off,
                  size: 16,
                  color: remoteState.status == ConnectionStatus.connected
                      ? Colors.greenAccent
                      : Colors.redAccent,
                ).animate(
                  onPlay: (controller) => controller.repeat(reverse: true),
                ).scaleXY(end: 1.1, duration: 1.seconds, curve: Curves.easeInOut),
                const SizedBox(width: 8),
                Text(
                  remoteState.status == ConnectionStatus.connected ? 'Online' : 'Offline',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: remoteState.status == ConnectionStatus.connected
                        ? Colors.greenAccent
                        : Colors.redAccent,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
      backgroundColor: AppColors.darkBackground,
      body: Column(
        children: [
          // Telemetry banner
          if (remoteState.status == ConnectionStatus.connected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceHighlight,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (remoteState.activeComputerId != null) ...[
                      Builder(builder: (context) {
                        final computer = remoteState.linkedComputers.firstWhere(
                          (c) => c.id == remoteState.activeComputerId,
                          orElse: () => LinkedComputer(id: 'unknown', name: 'Unknown', isOnline: false)
                        );
                        final isOnline = computer.isOnline;
                        return Container(
                          margin: const EdgeInsets.only(right: 12.0),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.darkBackground,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOnline ? Colors.greenAccent.withValues(alpha: 0.3) : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.circle, size: 8, color: isOnline ? Colors.greenAccent : Colors.grey),
                              const SizedBox(width: 6),
                              Text(
                                computer.name,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isOnline ? Colors.white : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                    ]
                  ],
                ),
              ),
            ),
          
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['sender'] == 'user';
                
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.brandBlue : AppColors.darkSurface,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                      borderRadius: BorderRadius.circular(20).copyWith(
                        bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                        bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            msg['text'],
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (msg['isProcessing'] == true) ...[
                          const SizedBox(width: 12),
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0, duration: 300.ms, curve: Curves.easeOutBack);
              },
            ),
          ),
          
          // Input field
          Container(
            padding: const EdgeInsets.all(16).copyWith(bottom: MediaQuery.of(context).padding.bottom + 16),
            decoration: const BoxDecoration(
              color: AppColors.darkSurface,
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: GoogleFonts.inter(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ask Oneova Studio to do something...',
                      hintStyle: GoogleFonts.inter(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: AppColors.darkBackground,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.mic, color: Colors.white),
                    onPressed: () {
                      // Placeholder for voice recording
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.brandBlue,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
