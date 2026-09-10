import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../backend/remote_connect_service.dart';
import '../backend/webrtc_desktop_service.dart';
import '../shared/theme/app_theme.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter/services.dart';
import 'messaging/remote_chat_view.dart';
import '../backend/voice_assistant_service.dart';
import '../shared/widgets/voice_wave_visualizer.dart';
import 'telemetry_dashboard_screen.dart';

class DesktopRemoteScreen extends ConsumerStatefulWidget {
  const DesktopRemoteScreen({super.key});

  @override
  ConsumerState<DesktopRemoteScreen> createState() => _DesktopRemoteScreenState();
}

class _DesktopRemoteScreenState extends ConsumerState<DesktopRemoteScreen> {
  bool _isRendering = false;
  bool _isVoiceActive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;
      if (activeComputerId != null) {
        ref.read(webrtcDesktopProvider.notifier).connect(activeComputerId);
      }
    });
  }

  void _sendCommand(String command, String commandName) async {
    final activeComputerId = ref.read(remoteConnectProvider).activeComputerId;

    if (activeComputerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active computer found!'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isRendering = command == 'render_and_send');

    final commandId = await ref.read(remoteConnectProvider.notifier).sendCommand(
      'dr', // Hardcoded software for now, should be dynamic later
      command, 
      {}
    );

    if (commandId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Command "$commandName" sent!'), 
          backgroundColor: AppColors.mpepeMaroon
        ),
      );
      
      if (command == 'render_and_send') {
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isRendering = false);
        });
      }
    } else {
      if (mounted) setState(() => _isRendering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send command.'), backgroundColor: Colors.redAccent),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remoteState = ref.watch(remoteConnectProvider);
    final webrtcState = ref.watch(webrtcDesktopProvider);
    
    final activeComputerId = remoteState.activeComputerId;
    final connection = activeComputerId != null ? webrtcState.connections[activeComputerId] : null;
    final isConnected = connection?.status == WebRTCStatus.connected;
    
    final computer = remoteState.linkedComputers.firstWhere(
      (c) => c.id == activeComputerId,
      orElse: () => LinkedComputer(id: 'unknown', name: 'Unknown Computer', isOnline: false),
    );

    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;

        // Immersive Fullscreen Stream in Landscape
        if (isLandscape && isConnected && connection?.renderer != null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              children: [
                Positioned.fill(
                  child: RTCVideoView(
                    connection!.renderer!,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  child: SafeArea(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.fullscreen_exit_rounded, color: Colors.white, size: 28),
                        onPressed: () {
                          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // Standard Portrait Mode
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: AppColors.darkBackground,
            appBar: AppBar(
              backgroundColor: AppColors.darkBackground,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                onPressed: () {
                  ref.read(remoteConnectProvider.notifier).disconnect();
                  context.pop();
                },
              ),
              title: Column(
                children: [
                  Text(
                    computer.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    isConnected ? 'Connected' : 'Offline',
                    style: GoogleFonts.inter(
                      color: isConnected ? Colors.greenAccent : Colors.white30,
                      fontSize: 12,
                    ),
                  )
                ],
              ),
              centerTitle: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.speed_rounded, color: Colors.white70),
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const TelemetryDashboardScreen()));
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.cast_connected_rounded, 
                    color: isConnected ? Colors.greenAccent : Colors.white30
                  ),
                  onPressed: () {
                    if (!isConnected && activeComputerId != null) {
                      ref.read(webrtcDesktopProvider.notifier).connect(activeComputerId);
                    }
                  },
                ),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: _buildStreamOnly(isConnected, connection),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.55,
                    decoration: BoxDecoration(
                      color: AppColors.darkBackground.withOpacity(0.85),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                      border: const Border(top: BorderSide(color: Colors.white12, width: 1)),
                    ),
                    child: Column(
                      children: [
                        const TabBar(
                          indicatorColor: AppColors.mpepeMaroon,
                          labelColor: AppColors.mpepeMaroon,
                          unselectedLabelColor: Colors.white54,
                          tabs: [
                            Tab(icon: Icon(Icons.touch_app_rounded), text: "Controls"),
                            Tab(icon: Icon(Icons.chat_bubble_rounded), text: "Chat"),
                            Tab(icon: Icon(Icons.graphic_eq_rounded), text: "Voice"),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildControlsTab(),
                              _buildChatTab(activeComputerId),
                              _buildVoiceTab(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStreamOnly(bool isConnected, dynamic connection) {
    return Container(
      color: Colors.black,
      child: isConnected && connection?.renderer != null
          ? RTCVideoView(
              connection!.renderer!,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (connection?.status == WebRTCStatus.connecting) ...[
                  const CircularProgressIndicator(color: AppColors.mpepeMaroon),
                  const SizedBox(height: 16),
                  Text(
                    'Connecting to Desktop...',
                    style: GoogleFonts.inter(color: Colors.white70, fontSize: 16),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.mpepeMaroon.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.desktop_mac_rounded, size: 48, color: AppColors.mpepeMaroon),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    connection?.status == WebRTCStatus.error ? 'Connection Error' : 'Connection Offline',
                    style: GoogleFonts.inter(
                      color: Colors.white54,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildControlsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(Icons.movie_creation_rounded, 'Render', () => _sendCommand('render_and_send', 'Render')),
              _buildActionButton(Icons.play_arrow_rounded, 'Play/Pause', () => _sendCommand('play_pause', 'Play')),
              _buildActionButton(Icons.sync_rounded, 'Sync', () => _sendCommand('sync_project', 'Sync')),
            ],
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.darkSurfaceHighlight,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Colors.white12, width: 1),
            ),
          ),
          onPressed: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatTab(String? activeComputerId) {
    if (activeComputerId == null) {
      return const Center(child: Text("No computer connected", style: TextStyle(color: Colors.white54)));
    }
    return RemoteChatView(deviceId: activeComputerId);
  }

  Widget _buildVoiceTab() {
    final voiceState = ref.watch(voiceAssistantProvider);
    final isVoiceActive = voiceState.state != VoiceState.idle;
    
    String statusText = "Tap to speak";
    if (voiceState.state == VoiceState.listening) {
      statusText = "Aria is listening...";
    } else if (voiceState.state == VoiceState.processing) {
      statusText = "Aria is thinking...";
    } else if (voiceState.state == VoiceState.speaking) {
      statusText = "Aria is speaking...";
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // AI Avatar
          Container(
             width: 140,
             height: 140,
             decoration: BoxDecoration(
               shape: BoxShape.circle,
               border: Border.all(color: AppColors.mpepeMaroon, width: 2),
               image: const DecorationImage(
                 image: AssetImage('assets/images/ai_avatar.jpg'),
                 fit: BoxFit.cover,
               ),
               boxShadow: [
                 if (isVoiceActive)
                   BoxShadow(
                     color: AppColors.mpepeMaroon.withOpacity(0.5),
                     blurRadius: 20,
                     spreadRadius: 2,
                   )
               ]
             )
          ).animate(target: isVoiceActive ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
          const SizedBox(height: 32),
          
          VoiceWaveVisualizer(isSpeaking: isVoiceActive, height: 60),
          
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () {
              final voiceNotifier = ref.read(voiceAssistantProvider.notifier);
              if (voiceState.state == VoiceState.idle) {
                voiceNotifier.startListening(continuous: true);
              } else if (voiceState.state == VoiceState.listening) {
                voiceNotifier.stopListening(force: true);
              } else {
                voiceNotifier.stopSpeaking(force: true);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              decoration: BoxDecoration(
                color: isVoiceActive ? AppColors.mpepeMaroon : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: isVoiceActive ? Colors.transparent : AppColors.darkSurfaceHighlight, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isVoiceActive ? Icons.mic : Icons.mic_off,
                    size: 24,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    statusText,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ).animate(target: isVoiceActive ? 1 : 0).scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05)),
          ),
          if (voiceState.currentText.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                '"${voiceState.currentText}"',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: Colors.white70,
                  fontStyle: FontStyle.italic,
                  fontSize: 14,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ).animate().fadeIn(),
          ]
        ],
      ),
    );
  }
}

