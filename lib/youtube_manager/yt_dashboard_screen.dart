import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/components.dart';
import '../shared/widgets/studio_background.dart';
import 'services/youtube_account_store.dart';
import 'services/youtube_api_client.dart';
import 'services/youtube_auth_service.dart' show YouTubeChannel;
import '../../backend/ai_brain_service.dart';

class YtDashboardScreen extends ConsumerWidget {
  const YtDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeAsync = ref.watch(ytAccountStoreProvider);

    return storeAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (err, _) => Scaffold(body: Center(child: Text('Error: $err'))),
      data: (store) {
        final activeChannel = store.activeChannel;

        if (activeChannel == null) {
          return _buildNoChannelState(context);
        }

        // Build a compat YouTubeChannel for the existing analytics providers
        final compatChannel = YouTubeChannel(
          id: activeChannel.id,
          title: activeChannel.title,
          thumbnailUrl: activeChannel.thumbnailUrl,
          subscriberCount: activeChannel.subscriberCount,
        );

        final analyticsAsync = ref.watch(channelAnalyticsProvider(activeChannel.id));
        final recentVideosAsync = ref.watch(recentVideosProvider(activeChannel.id));

        return _buildDashboard(context, compatChannel, analyticsAsync, recentVideosAsync);
      },
    );
  }
  
  Widget _buildNoChannelState(BuildContext context) {
    return StudioBackground(
       backgroundIcons: const [Icons.analytics_outlined, Icons.warning_amber],
       appBar: AppBar(
         backgroundColor: Colors.transparent,
         elevation: 0,
         leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
         ),
       ),
       child: Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
              const Icon(Icons.videocam_off, size: 64, color: Colors.white54),
              const SizedBox(height: 16),
              const Text('No Active Channel Selected', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please link or select a channel in the Channels page.', style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  context.push('/yt/channels');
                },
                icon: const Icon(Icons.list),
                label: const Text('Go to Channels'),
              )
           ],
         ),
       )
    );
  }

  Widget _buildDashboard(BuildContext context, YouTubeChannel channel, AsyncValue<Map<String, dynamic>> analyticsAsync, AsyncValue<List<Map<String, dynamic>>> recentVideosAsync) {
    final numFormat = NumberFormat.compact();
    final avatarColor = AppColors.mpepeMaroon;
    
    return StudioBackground(
      backgroundIcons: const [Icons.analytics_outlined, Icons.trending_up, Icons.diamond_outlined],
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: avatarColor,
                boxShadow: [
                  BoxShadow(color: avatarColor.withValues(alpha: 0.5), blurRadius: 10)
                ],
                border: Border.all(color: AppColors.mpepeGold, width: 1.5),
                image: channel.thumbnailUrl.isNotEmpty 
                  ? DecorationImage(image: NetworkImage(channel.thumbnailUrl), fit: BoxFit.cover)
                  : null,
              ),
              child: channel.thumbnailUrl.isEmpty 
                  ? Center(child: Text(channel.title.isNotEmpty ? channel.title[0] : '?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(channel.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Theme.of(context).colorScheme.onSurface)),
                  Text('${numFormat.format(channel.subscriberCount)} Subscribers', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: AppColors.mpepeGold)),
                ],
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.swap_horiz, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () => context.push('/yt/channels'),
            tooltip: 'Switch Channel',
          ),
          IconButton(
            icon: Icon(Icons.close, color: Theme.of(context).colorScheme.onSurface),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          )
        ],
      ),
      floatingActionButton: Semantics(
        button: true,
        label: 'Upload new video',
        child: FloatingActionButton.extended(
          onPressed: () {
            HapticFeedback.lightImpact();
            context.push('/yt/upload');
          },
          backgroundColor: AppColors.mpepeMaroon,
          icon: const Icon(Icons.cloud_upload_outlined, color: Colors.white),
          label: const Text('Upload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ),
      ).animate().scale(delay: 800.ms, duration: 400.ms, curve: Curves.easeOutBack),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFriendlyHeader(context).animate().fadeIn(duration: 600.ms, curve: Curves.easeOutCirc).slideY(begin: -0.1, curve: Curves.easeOutCirc),
                  const SizedBox(height: 32),
                  
                  analyticsAsync.when(
                    data: (stats) => _buildMainStatsCard(context, stats).animate().fadeIn(delay: 150.ms, duration: 600.ms).slideY(begin: 0.1),
                    loading: () => Padding(padding: const EdgeInsets.all(16.0), child: _buildSkeletonBlock(context, 200)),
                    error: (err, stack) => Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Failed to load analytics: $err'))),
                  ),
                  
                  const SizedBox(height: 32),
                  Text('Quick Actions', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 16),
                  _buildToolsGrid(context).animate().fadeIn(delay: 250.ms),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      ShaderMask(
                        blendMode: BlendMode.srcIn,
                        shaderCallback: (bounds) => AppColors.premiumGradient.createShader(bounds),
                        child: const Icon(Icons.auto_awesome, size: 22),
                      ),
                      const SizedBox(width: 8),
                      Text('AI Studio Insights', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  analyticsAsync.when(
                    data: (stats) => _buildAiInsightsCard(context, stats).animate().fadeIn(delay: 550.ms).scaleXY(begin: 0.98, curve: Curves.easeOutBack),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                  
                  const SizedBox(height: 32),
                  Text('Recent Uploads', style: AppTheme.h2Style.copyWith(color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 16),
                  
                  recentVideosAsync.when(
                    data: (videos) {
                      if (videos.isEmpty) return const Text('No recent videos found.');
                      return Column(
                        children: videos.map((video) {
                           final title = video['title'] as String? ?? 'Unknown';
                           final publishedAt = video['publishedAt'] as String? ?? '';
                           final date = DateTime.tryParse(publishedAt) ?? DateTime.now();
                           final diff = DateTime.now().difference(date);
                           final dateStr = diff.inDays > 0 ? '${diff.inDays} days ago' : '${diff.inHours} hours ago';
                           
                           return _buildVideoItem(context, video, dateStr, channel.title).animate().fadeIn(delay: 350.ms).slideX(begin: 0.05);
                        }).toList(),
                      );
                    },
                    loading: () => Padding(padding: const EdgeInsets.all(16.0), child: _buildSkeletonBlock(context, 100)),
                    error: (err, stack) => Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text('Error loading videos: $err'))),
                  ),
                  
                  const SizedBox(height: 100), // Padding for FAB
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendlyHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Welcome to Studio Hub',
          style: AppTheme.h1Style.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        const SizedBox(height: 6),
        Text(
          'Track cross-platform performance, bulk upload, and get AI insights for all your connected channels.',
          style: AppTheme.bodyStyle.copyWith(fontSize: 15, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
      ],
    );
  }

  Widget _buildMainStatsCard(BuildContext context, Map<String, dynamic> stats) {
    final views = stats['views'] as num? ?? 0;
    final videos = stats['videoCount'] as num? ?? 0;
    final subs = stats['subscribers'] as num? ?? 0;
    
    final numFormat = NumberFormat.compact();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        color: AppColors.mpepeMaroon,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
          BoxShadow(
            color: AppColors.mpepeMaroon.withValues(alpha: 0.3),
            blurRadius: 20,
            spreadRadius: -5,
          )
        ],
        border: Border.all(color: AppColors.mpepeGold.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total Lifetime Views', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.mpepeGold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_tethering, color: AppColors.mpepeGold, size: 14),
                    SizedBox(width: 4),
                    Text('Live Data', style: TextStyle(color: AppColors.mpepeGold, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(numFormat.format(views), style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.5, color: Colors.white)),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text('views', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white.withValues(alpha: 0.6))),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSubStat(context, 'Subscribers', numFormat.format(subs)),
              _buildSubStat(context, 'Videos', numFormat.format(videos)),
              _buildSubStat(context, 'Views', numFormat.format(views)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubStat(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildToolsGrid(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildToolCard(context, Icons.find_in_page_outlined, 'SEO Optimizer', AppColors.mpepeMaroon),
        _buildToolCard(context, Icons.image_outlined, 'A/B Thumbnails', AppColors.mpepeGold),
        _buildToolCard(context, Icons.forum_outlined, 'Auto-Replies', AppColors.mpepeMaroon),
        _buildToolCard(context, Icons.calendar_month_outlined, 'Content Planner', AppColors.mpepeGold),
      ],
    );
  }

  Widget _buildToolCard(BuildContext context, IconData icon, String title, Color color) {
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title tools opening...')));
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 28),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAiInsightsCard(BuildContext context, Map<String, dynamic> stats) {
    final views = stats['views'] as num? ?? 0;
    final watchTime = stats['watchTimeHours'] as num? ?? 0;
    
    String insightTitle = 'Growth Strategy';
    String insightMessage = 'Keep uploading consistently to gather enough data for AI-driven growth recommendations.';
    
    if (views > 1000 && watchTime > 50) {
       insightTitle = 'Audience Retention Strategy';
       insightMessage = 'Your recent videos are showing strong retention. The AI suggests maintaining hooks under 5 seconds to further boost engagement.';
    } else if (views > 0 && views < 500) {
       insightTitle = 'SEO Opportunity Detected';
       insightMessage = 'Your view count is lower than your channel average. The AI recommends optimizing your tags and titles for search discoverability.';
    } else if (views == 0) {
       insightTitle = 'Welcome to Studio Hub';
       insightMessage = 'Upload your first video to unlock advanced AI insights and personalized growth strategies.';
    }

    return MpepeCard(
      borderColor: AppColors.mpepeGold.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.mpepeMaroon.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback: (bounds) => AppColors.premiumGradient.createShader(bounds),
              child: const Icon(Icons.rocket_launch, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(insightTitle, style: AppTheme.bodyStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16, color: Theme.of(context).colorScheme.onSurface)),
                const SizedBox(height: 6),
                Text(
                  insightMessage,
                  style: AppTheme.bodyStyle.copyWith(fontSize: 14, height: 1.5, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoItem(BuildContext context, Map<String, dynamic> video, String dateStr, String channelName) {
    final title = video['title'] as String? ?? 'Unknown';
    final thumbnailUrl = video['thumbnailUrl'] as String? ?? '';
    
    return InkWell(
      onTap: () => _showVideoDetailsSheet(context, video, dateStr, channelName),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 100,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(12),
                image: thumbnailUrl.isNotEmpty ? DecorationImage(
                  image: NetworkImage(thumbnailUrl),
                  fit: BoxFit.cover,
                ) : null,
              ),
              child: thumbnailUrl.isEmpty ? const Center(child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 32)) : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Theme.of(context).colorScheme.onSurface)),
                  const SizedBox(height: 4),
                  Text(dateStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  void _showVideoDetailsSheet(BuildContext context, Map<String, dynamic> video, String dateStr, String channelName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return VideoDetailsSheet(video: video, dateStr: dateStr, channelName: channelName);
      },
    );
  }

  Widget _buildSkeletonBlock(BuildContext context, double height) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 0.7),
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOut,
      builder: (context, val, child) {
        return Opacity(
          opacity: val,
          child: Container(
            width: double.infinity,
            height: height,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        );
      },
    );
  }
}

class VideoDetailsSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> video;
  final String dateStr;
  final String channelName;

  const VideoDetailsSheet({super.key, required this.video, required this.dateStr, required this.channelName});

  @override
  ConsumerState<VideoDetailsSheet> createState() => _VideoDetailsSheetState();
}

class _VideoDetailsSheetState extends ConsumerState<VideoDetailsSheet> {
  bool _isAnalyzing = false;
  Map<String, dynamic>? _aiAnalysis;
  String? _analysisError;

  Future<void> _analyzeVideo(Map<String, dynamic> stats, List<Map<String, dynamic>> geoData) async {
    setState(() {
      _isAnalyzing = true;
      _aiAnalysis = null;
      _analysisError = null;
    });
    
    try {
      final brain = ref.read(aiBrainProvider);
      final analysis = await brain.analyzeSingleVideo(
        videoId: widget.video['videoId'] ?? '',
        title: widget.video['title'] ?? '',
        description: widget.video['description'] ?? '',
        stats: stats,
        geoData: geoData,
      );
      
      if (mounted) {
        setState(() {
          _aiAnalysis = analysis;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _analysisError = e.toString();
          _isAnalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.video['title'] as String? ?? 'Unknown';
    final desc = widget.video['description'] as String? ?? 'No description available.';
    final thumbnailUrl = widget.video['thumbnailUrl'] as String? ?? '';
    final videoId = widget.video['videoId'] as String? ?? '';
    
    final detailsAsync = ref.watch(videoDetailsProvider(videoId));
    final geoAsync = ref.watch(videoGeographyProvider(videoId));

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (thumbnailUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(thumbnailUrl, width: double.infinity, height: 200, fit: BoxFit.cover),
                    ),
                  const SizedBox(height: 24),
                  Text(title, style: AppTheme.h2Style),
                  const SizedBox(height: 8),
                  Text('${widget.channelName} • ${widget.dateStr}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                  
                  const SizedBox(height: 24),
                  _buildStatsRow(detailsAsync),
                  
                  const SizedBox(height: 24),
                  _buildGeoSection(geoAsync),
                  
                  const SizedBox(height: 24),
                  Text(desc, style: const TextStyle(fontSize: 14, height: 1.5)),
                  
                  if (_aiAnalysis != null || _isAnalyzing || _analysisError != null)
                    _buildAnalysisSection(),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          if (_aiAnalysis == null && !_isAnalyzing)
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: () {
                   final stats = detailsAsync.asData?.value ?? {};
                   final geoData = geoAsync.asData?.value ?? [];
                   _analyzeVideo(stats, geoData);
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyze with Mpepe AI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.mpepeMaroon,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(AsyncValue<Map<String, dynamic>> detailsAsync) {
    return detailsAsync.when(
      data: (stats) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(Icons.visibility, _formatNumber(stats['views'] ?? 0), 'Views'),
          _buildStatItem(Icons.thumb_up, _formatNumber(stats['likes'] ?? 0), 'Likes'),
          _buildStatItem(Icons.comment, _formatNumber(stats['comments'] ?? 0), 'Comments'),
        ],
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error loading stats: $e', style: const TextStyle(color: Colors.red)),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.mpepeMaroon),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  String _formatNumber(num val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(1)}K';
    return val.toString();
  }

  Widget _buildGeoSection(AsyncValue<List<Map<String, dynamic>>> geoAsync) {
    return geoAsync.when(
      data: (geoList) {
        if (geoList.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Top Audience Geography', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: geoList.map((geo) {
                return Chip(
                  label: Text('${geo['country']} (${_formatNumber(geo['views'])})'),
                  backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
  
  Widget _buildAnalysisSection() {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.mpepeMaroon.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.mpepeMaroon.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: AppColors.mpepeMaroon, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Mpepe Intelligence', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5)),
              const Spacer(),
              if (_isAnalyzing) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 20),
          
          if (_analysisError != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_analysisError!, style: const TextStyle(color: Colors.red))),
                ],
              ),
            ),
             
          if (_aiAnalysis != null) ...[
            _buildAiPoint('Performance Summary', _aiAnalysis!['performanceSummary'] ?? '', Icons.insights),
            const Divider(height: 24, color: Colors.white10),
            _buildAiPoint('SEO Critique', _aiAnalysis!['seoCritique'] ?? '', Icons.search),
            const Divider(height: 24, color: Colors.white10),
            _buildAiPoint('Audience Insights', _aiAnalysis!['audienceInsights'] ?? '', Icons.groups),
            const Divider(height: 24, color: Colors.white10),
            
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, color: Colors.amber, size: 20),
                const SizedBox(width: 8),
                const Text('Actionable Tips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            ...((_aiAnalysis!['actionableTips'] as List<dynamic>?) ?? []).map((tip) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(tip.toString(), style: const TextStyle(height: 1.5))),
                  ],
                ),
              );
            }),
          ]
        ],
      ),
    );
  }
  
  Widget _buildAiPoint(String title, String content, IconData icon) {
    if (content.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppColors.mpepeMaroon),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.mpepeMaroon, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(height: 1.5, fontSize: 14)),
        ],
      ),
    );
  }
}

