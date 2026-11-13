import 'package:flutter/material.dart';
import '../../../backend/social/models/post.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class FeedReelPlayer extends StatefulWidget {
  final Post post;

  const FeedReelPlayer({super.key, required this.post});

  @override
  State<FeedReelPlayer> createState() => _FeedReelPlayerState();
}

class _FeedReelPlayerState extends State<FeedReelPlayer> with SingleTickerProviderStateMixin {
  bool _isPlaying = true;
  bool _showPlayPauseIcon = false;
  late AnimationController _iconAnimationController;

  @override
  void initState() {
    super.initState();
    _iconAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _iconAnimationController.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    setState(() {
      _isPlaying = !_isPlaying;
      _showPlayPauseIcon = true;
    });

    _iconAnimationController.forward(from: 0.0).then((_) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _showPlayPauseIcon = false;
          });
        }
      });
    });
  }

  void _handleDoubleTap() {
    // We will trigger a heart animation here and call the like provider
    // The actual like logic is handled by the Engagement Overlay, but 
    // the visual burst happens here.
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = widget.post.attachments.isNotEmpty ? widget.post.attachments.first : null;

    return GestureDetector(
      onTap: _togglePlayPause,
      onDoubleTap: _handleDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl == null)
            Container(color: Colors.grey[900])
          else
          Image.network(
            imageUrl,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return const Center(child: AnimatedLoadingIndicator(color: Colors.white24));
            },
            errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[900]),
          ),
          
          if (_showPlayPauseIcon)
            Center(
              child: FadeTransition(
                opacity: Tween<double>(begin: 1.0, end: 0.0).animate(_iconAnimationController),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.5).animate(
                    CurvedAnimation(parent: _iconAnimationController, curve: Curves.easeOutCubic),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.play_arrow : Icons.pause,
                      size: 64,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
