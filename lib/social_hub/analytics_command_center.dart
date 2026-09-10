import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../shared/theme/app_theme.dart';
import '../shared/widgets/studio_background.dart';
import '../youtube_manager/services/youtube_account_store.dart';
import '../backend/tiktok_oauth_service.dart';
import '../backend/analytics_repository.dart';

// Provider to fetch data based on selected tab
final analyticsDataProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, platform) async {
  final repo = ref.watch(analyticsRepositoryProvider);
  return repo.fetchAnalytics(platform: platform);
});

class AnalyticsCommandCenter extends ConsumerStatefulWidget {
  const AnalyticsCommandCenter({super.key});

  @override
  ConsumerState<AnalyticsCommandCenter> createState() => _AnalyticsCommandCenterState();
}

class _AnalyticsCommandCenterState extends ConsumerState<AnalyticsCommandCenter> {
  String _selectedTab = 'all';

  @override
  Widget build(BuildContext context) {
    final ytAccount = ref.watch(ytActiveAccountProvider);
    final tiktokState = ref.watch(tiktokOAuthProvider);
    final hasYt = ytAccount != null;
    final hasTikTok = tiktokState.account != null;

    final tabs = [
      {'id': 'all', 'label': 'All Platforms'},
      if (hasYt) {'id': 'youtube', 'label': 'YouTube'},
      if (hasTikTok) {'id': 'tiktok', 'label': 'TikTok'},
    ];

    // Ensure selected tab is valid
    if (!tabs.any((t) => t['id'] == _selectedTab)) {
      _selectedTab = 'all';
    }

    final dataAsync = ref.watch(analyticsDataProvider(_selectedTab));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: StudioBackground(
        backgroundIcons: const [Icons.analytics, Icons.trending_up, Icons.bar_chart],
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              _buildTabs(tabs),
              Expanded(
                child: dataAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator(color: AppColors.mpepeMaroon)),
                  error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
                  data: (data) => _buildDashboard(context, data, _selectedTab),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.mpepeMaroon,
        onPressed: () => _openMpepeChat(context, dataAsync.value),
        icon: const Icon(Icons.smart_toy, color: Colors.white),
        label: const Text('Analyze with Mpepe', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ).animate().slideY(begin: 1.0, delay: 500.ms),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(), // Fully working back button
              ),
              const SizedBox(width: 8),
              const Text('Cross-Platform Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.download_rounded),
            color: AppColors.mpepeGold,
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report downloading...'), backgroundColor: Colors.green),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(List<Map<String, String>> tabs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 12.0),
      child: Row(
        children: tabs.map((t) {
          final isSelected = _selectedTab == t['id'];
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = t['id']!),
            child: Container(
              margin: const EdgeInsets.only(right: 12),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.mpepeMaroon : AppColors.darkSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: isSelected ? AppColors.mpepeMaroon : AppColors.outline),
              ),
              child: Text(
                t['label']!,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, Map<String, dynamic> data, String platform) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTopMetrics(context, data, platform),
                const SizedBox(height: 24),
                _buildChartSection(context, data, platform),
                const SizedBox(height: 24),
                if (platform == 'all') _buildAudienceOverlap(context),
                if (platform != 'all') _buildAdvancedSections(context, data),
                const SizedBox(height: 80), // Padding for FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTopMetrics(BuildContext context, Map<String, dynamic> data, String platform) {
    if (platform == 'all') {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _buildMetricCard(context, 'Total Reach', data['totalReach'], data['reachChange'], data['reachIsPositive'])),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard(context, 'Avg Engagement', data['avgEngagement'], data['engagementChange'], data['engagementIsPositive'])),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildMetricCard(context, 'YouTube Revenue', data['youtubeRevenue'], '+5%', true)),
              const SizedBox(width: 12),
              Expanded(child: _buildMetricCard(context, 'TikTok Fund', data['tiktokFund'], '-1%', false)),
            ],
          ),
        ],
      ).animate().fade().slideY(begin: 0.1);
    } else {
      return Row(
        children: [
          Expanded(child: _buildMetricCard(context, 'Total Reach', data['totalReach'], data['reachChange'], data['reachIsPositive'])),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard(context, 'Engagement', data['avgEngagement'], data['engagementChange'], data['engagementIsPositive'])),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard(context, 'Revenue', data['revenue'], data['revenueChange'], data['revenueIsPositive'])),
        ],
      ).animate().fade().slideY(begin: 0.1);
    }
  }

  Widget _buildMetricCard(BuildContext context, String label, String value, String change, bool isPositive) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkSurfaceHighlight, AppColors.darkSurface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(isPositive ? Icons.trending_up : Icons.trending_down, color: isPositive ? Colors.green : Colors.red, size: 14),
              const SizedBox(width: 4),
              Text(change, style: TextStyle(color: isPositive ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartSection(BuildContext context, Map<String, dynamic> data, String platform) {
    final ytData = platform == 'youtube' || platform == 'all' ? (data['viewsData'] ?? data['youtubeViewsData']) as List<int>? : null;
    final ttData = platform == 'tiktok' || platform == 'all' ? (data['viewsData'] ?? data['tiktokViewsData']) as List<int>? : null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.mpepeMaroon.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: AppColors.mpepeMaroon.withValues(alpha: 0.1), blurRadius: 20, spreadRadius: -5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Views Comparison (7 Days)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Icon(Icons.more_horiz, color: AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 150,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(7, (index) {
                final height1 = ytData != null ? ytData[index].toDouble() : 0.0;
                final height2 = ttData != null ? ttData[index].toDouble() : 0.0;
                
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (ytData != null)
                          Container(
                            width: 8,
                            height: height1,
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        if (ytData != null && ttData != null) const SizedBox(width: 2),
                        if (ttData != null)
                          Container(
                            width: 8,
                            height: height2,
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('D${index + 1}', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (ytData != null) _buildLegend(context, 'YouTube', Colors.redAccent),
              if (ytData != null && ttData != null) const SizedBox(width: 16),
              if (ttData != null) _buildLegend(context, 'TikTok', Colors.cyanAccent),
            ],
          )
        ],
      ),
    ).animate().fade(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildLegend(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }

  Widget _buildAudienceOverlap(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Audience Overlap', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Users active on both platforms', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5), width: 2),
                ),
                child: const Center(child: Text('YT\n60%', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
              ),
              Transform.translate(
                offset: const Offset(-20, 0),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.cyanAccent.withValues(alpha: 0.2),
                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 2),
                  ),
                  child: const Center(child: Text('TT\n40%', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Center(child: Text('15% Overlap (Super Fans)', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.mpepeGold))),
        ],
      ),
    ).animate().fade(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildAdvancedSections(BuildContext context, Map<String, dynamic> data) {
    return Column(
      children: [
        _buildListSection(context, 'Recent Video Performance', [
          {'title': 'Studio Vlog #42', 'views': '45K', 'icon': Icons.video_library, 'color': AppColors.textPrimary},
          {'title': 'How to Mix Vocals', 'views': '12K', 'icon': Icons.video_library, 'color': AppColors.textPrimary},
        ]),
        const SizedBox(height: 16),
        _buildListSection(context, 'Engagement Highlights', [
          {'title': 'Highest retention drop', 'views': '0:45', 'icon': Icons.warning_amber_rounded, 'color': Colors.orange},
          {'title': 'Most replayed segment', 'views': '2:15', 'icon': Icons.star, 'color': AppColors.mpepeGold},
        ]),
      ],
    ).animate().fade(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildListSection(BuildContext context, String title, List<Map<String, dynamic>> items) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 16),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Icon(item['icon'] as IconData, color: item['color'] as Color?, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.w600))),
                Text(item['views'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  void _openMpepeChat(BuildContext context, Map<String, dynamic>? currentData) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _MpepeChatInterface(data: currentData),
    );
  }
}

class _MpepeChatInterface extends StatefulWidget {
  final Map<String, dynamic>? data;
  const _MpepeChatInterface({this.data});

  @override
  State<_MpepeChatInterface> createState() => _MpepeChatInterfaceState();
}

class _MpepeChatInterfaceState extends State<_MpepeChatInterface> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _controller = TextEditingController();
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _messages.add({
      'sender': 'mpepe',
      'text': 'Hi! I am Mpepe, your AI Analytics Assistant. I can see you are looking at your latest stats (Reach: ${widget.data?['totalReach'] ?? '...'}). What would you like to know?',
    });
  }

  void _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;
    
    final text = _controller.text;
    setState(() {
      _messages.add({'sender': 'user', 'text': text});
      _controller.clear();
      _isTyping = true;
    });

    // Simulate AI thinking (ChatGPT model simulation)
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;
    setState(() {
      _isTyping = false;
      _messages.add({
        'sender': 'mpepe',
        'text': 'Based on this chart, your audience retention is strong on YouTube, but TikTok shows a drop around day 3. I recommend cross-posting your best performing YouTube shorts to TikTok to boost that fund!',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.darkBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(bottom: BorderSide(color: AppColors.outline)),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: AppColors.mpepeMaroon,
                  child: Icon(Icons.smart_toy, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Mpepe AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('Voice Mode Enabled (ChatGPT)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(color: AppColors.mpepeMaroon, strokeWidth: 2),
                    ),
                  );
                }
                final msg = _messages[index];
                final isMe = msg['sender'] == 'user';
                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: EdgeInsets.only(bottom: 12, left: isMe ? 40 : 0, right: isMe ? 0 : 40),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.mpepeMaroon : AppColors.darkSurfaceHighlight,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
                        bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
                      ),
                    ),
                    child: Text(msg['text']!, style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
            decoration: const BoxDecoration(
              color: AppColors.darkSurface,
              border: Border(top: BorderSide(color: AppColors.outline)),
            ),
            child: Row(
              children: [
                IconButton(icon: const Icon(Icons.mic, color: AppColors.mpepeMaroon), onPressed: () {}),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Ask Mpepe...',
                      filled: true,
                      fillColor: AppColors.darkBackground,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send, color: AppColors.mpepeMaroon),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
