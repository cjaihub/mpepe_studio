import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import '../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  List<dynamic> _discoverPosts = [];
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _fetchDiscoverFeed();
  }

  Future<void> _fetchDiscoverFeed() async {
    try {
      final response = await http.get(Uri.parse('http://localhost:8000/api/discover?limit=20'));
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            _discoverPosts = json.decode(response.body);
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load discover feed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    if (_hasError) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.brandBlue),
              const SizedBox(height: 16),
              const Text('Failed to load Discover feed.'),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _hasError = false;
                  });
                  _fetchDiscoverFeed();
                },
                child: const Text('Retry', style: TextStyle(color: AppColors.brandBlue)),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        title: const Text('Discover', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _fetchDiscoverFeed,
        color: AppColors.brandBlue,
        child: MasonryGridView.count(
          padding: const EdgeInsets.all(2),
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          itemCount: _discoverPosts.length,
          itemBuilder: (context, index) {
            final post = _discoverPosts[index];
            final bool isVideo = post['content_type'] == 'video';
            final String? thumbnailUrl = post['thumbnail_url'];
            final List<dynamic> mediaUrls = post['media_urls'] ?? [];
            final String imageUrl = thumbnailUrl ?? (mediaUrls.isNotEmpty ? mediaUrls.first : '');
            final double aspectRatio = post['aspect_ratio'] ?? 1.0;
            
            // To make staggered grid dynamic, we can use the aspect ratio or alternate
            // For a masonry grid, the aspect ratio naturally staggers if items have different heights
            // We just let the image dictate its height or set a dynamic height
            
            return _DiscoverTile(
              imageUrl: imageUrl,
              isVideo: isVideo,
              aspectRatio: aspectRatio,
              likeCount: (post['like_count'] as num?)?.toInt() ?? 0,
              commentCount: (post['comment_count'] as num?)?.toInt() ?? 0,
            );
          },
        ),
      ),
    );
  }
}

class _DiscoverTile extends StatefulWidget {
  final String imageUrl;
  final bool isVideo;
  final double aspectRatio;
  final int likeCount;
  final int commentCount;

  const _DiscoverTile({
    required this.imageUrl,
    required this.isVideo,
    required this.aspectRatio,
    required this.likeCount,
    required this.commentCount,
  });

  static String _compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    return '$n';
  }

  @override
  State<_DiscoverTile> createState() => _DiscoverTileState();
}

class _DiscoverTileState extends State<_DiscoverTile> {
  bool _isPressed = false;

  void _handleTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
  }

  void _handleTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    HapticFeedback.selectionClick();
    // TODO: Navigate to this post in feed
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AspectRatio(
          aspectRatio: widget.aspectRatio < 0.8 ? 0.8 : widget.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.imageUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: Colors.grey.shade900),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey.shade900,
                    child: const Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              
              // Premium Gradient for readability
              Positioned(
                bottom: 0, left: 0, right: 0,
                height: 80,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
                    ),
                  ),
                ),
              ),

              if (widget.isVideo)
                const Positioned(
                  top: 8,
                  right: 8,
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 24,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                ),

              // Bottom Stats (real counts from the post)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Row(
                  children: [
                    const Icon(Icons.favorite, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(_DiscoverTile._compact(widget.likeCount),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    const Icon(Icons.chat_bubble, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(_DiscoverTile._compact(widget.commentCount),
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
