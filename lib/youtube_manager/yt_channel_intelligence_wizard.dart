import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../backend/ai_brain_service.dart';
import 'services/youtube_api_client.dart';
import 'services/youtube_auth_service.dart';
import 'models/youtube_channel_profile.dart';
class YtChannelIntelligenceWizard extends ConsumerStatefulWidget {
  final YouTubeChannel channel;

  const YtChannelIntelligenceWizard({super.key, required this.channel});

  @override
  ConsumerState<YtChannelIntelligenceWizard> createState() => _YtChannelIntelligenceWizardState();
}

class _YtChannelIntelligenceWizardState extends ConsumerState<YtChannelIntelligenceWizard> {
  int _currentStep = 0;
  bool _isScanning = true;
  YouTubeChannelProfile? _profile;
  String _statusText = "Initializing Deep Scan...";

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      final apiClient = ref.read(youtubeApiClientProvider);
      final aiBrain = ref.read(aiBrainProvider);

      setState(() { _statusText = "Fetching 28-day Analytics..."; });
      final analytics = await apiClient.fetchChannelAnalytics(widget.channel.id);

      setState(() { _statusText = "Analyzing Recent Videos..."; });
      final recentVideos = await apiClient.fetchRecentVideos(widget.channel.id, maxResults: 15);

      setState(() { _statusText = "Extracting Channel Keywords..."; });
      final keywords = await apiClient.fetchChannelKeywords(widget.channel.id);

      setState(() { _statusText = "AI processing data to build intelligence profile..."; });
      
      final profile = await aiBrain.analyzeYouTubeChannel(
        widget.channel.id,
        widget.channel.title,
        analytics,
        recentVideos,
        keywords,
      );

      if (profile != null) {
        // Save profile locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('yt_profile_${widget.channel.id}', profile.toJson());
        
        setState(() {
          _profile = profile;
          _isScanning = false;
          _currentStep = 1;
        });
      } else {
        setState(() {
          _statusText = "AI Analysis Failed. Please try again later.";
          _isScanning = false;
        });
      }
    } catch (e) {
      setState(() {
        _statusText = "An error occurred during scanning: $e";
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text('Channel Intelligence Wizard'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_currentStep == 0) _buildScanningStep(),
              if (_currentStep == 1 && _profile != null) _buildResultsStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanningStep() {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            ),
            child: _isScanning 
                ? CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)
                : Icon(Icons.error_outline, size: 48, color: Theme.of(context).colorScheme.error),
          ).animate(onPlay: (controller) => controller.repeat()).shimmer(duration: 2.seconds),
          const SizedBox(height: 32),
          Text(
            _isScanning ? 'Deep Scanning Channel...' : 'Scan Failed',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            _statusText,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsStep() {
    return Expanded(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Intelligence Profile Generated!',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.purpleAccent),
            ).animate().fadeIn(duration: 500.ms).slideY(begin: -0.2),
            const SizedBox(height: 8),
            Text(
              'The AI has securely saved this context locally. It will use this to manage your channel going forward.',
              style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 32),
            
            _buildProfileSection(
              icon: Icons.radar,
              title: 'Channel Niche',
              content: _profile!.niche,
            ).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1),
            
            _buildProfileSection(
              icon: Icons.group_outlined,
              title: 'Target Audience',
              content: _profile!.targetAudience,
            ).animate().fadeIn(delay: 400.ms).slideX(begin: 0.1),
            
            _buildProfileSection(
              icon: Icons.record_voice_over_outlined,
              title: 'Tone of Voice',
              content: _profile!.toneOfVoice,
            ).animate().fadeIn(delay: 500.ms).slideX(begin: 0.1),
            
            const SizedBox(height: 16),
            const Text('AI Observations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            ..._profile!.missingElements.map((e) => _buildListItem(e, Icons.warning_amber_rounded, Colors.orange)).toList().animate().fadeIn(delay: 600.ms),
            
            const SizedBox(height: 24),
            const Text('Recommended Actions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 12),
            ..._profile!.recommendedActions.map((e) => _buildListItem(e, Icons.check_circle_outline, Colors.green)).toList().animate().fadeIn(delay: 700.ms),
            
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Finish Setup', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ).animate().fadeIn(delay: 1000.ms).scale(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSection({required IconData icon, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5))),
                const SizedBox(height: 4),
                Text(content, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildListItem(String text, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }
}
