import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../backend/social/models/story.dart';
import '../../../backend/social/services/story_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class StoryViewScreen extends ConsumerStatefulWidget {
  final String authorId;
  const StoryViewScreen({super.key, required this.authorId});

  @override
  ConsumerState<StoryViewScreen> createState() => _StoryViewScreenState();
}

class _StoryViewScreenState extends ConsumerState<StoryViewScreen> with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  List<Story> _stories = [];
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5), // default duration for photo
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _nextStory();
        }
      });
    _loadStories();
  }

  Future<void> _loadStories() async {
    final groups = await ref.read(storyServiceProvider).getFeedStories();
    final group = groups.firstWhere((g) => g.authorId == widget.authorId, orElse: () => groups.isNotEmpty ? groups.first : UserStoryGroup(authorId: '', authorName: '', authorAvatarUrl: '', stories: [], hasUnviewed: false));
    setState(() {
      _stories = group.stories;
      _isLoading = false;
    });
    _recordCurrentStoryView();
    _progressController.forward();
  }

  void _recordCurrentStoryView() {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null && _currentIndex >= 0 && _currentIndex < _stories.length) {
      ref.read(storyServiceProvider).recordStoryView(_stories[_currentIndex].id, currentUid);
    }
  }

  void _nextStory() {
    if (_currentIndex < _stories.length - 1) {
      setState(() {
        _currentIndex++;
        _progressController.reset();
        _progressController.forward();
      });
      _recordCurrentStoryView();
    } else {
      context.pop();
    }
  }

  void _previousStory() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _progressController.reset();
        _progressController.forward();
      });
      _recordCurrentStoryView();
    } else {
      _progressController.reset();
      _progressController.forward();
    }
  }

  void _onTapDown(TapDownDetails details) {
    _progressController.stop();
    final screenWidth = MediaQuery.of(context).size.width;
    if (details.globalPosition.dx < screenWidth / 3) {
      _previousStory();
    } else {
      _nextStory();
    }
  }

  void _onLongPress() {
    _progressController.stop();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _progressController.forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    if (_stories.isEmpty) {
      return Scaffold(
        backgroundColor: context.bg,
        body: Center(
          child: TextButton(
            onPressed: () => context.pop(),
            child: Text('No stories found', style: TextStyle(color: context.textPrimary)),
          ),
        ),
      );
    }

    final story = _stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: _onTapDown,
        onLongPress: _onLongPress,
        onLongPressEnd: _onLongPressEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Media Background
            Image.network(
              story.mediaUrl,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => Container(color: Colors.grey[900]),
            ),
            
            // Interactive Elements
            for (final el in story.interactiveElements)
              Positioned(
                left: MediaQuery.of(context).size.width * el.x,
                top: MediaQuery.of(context).size.height * el.y,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    el.type == 'location' ? '📍 ${el.data['name']}' : el.type,
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

            // UI Overlay
            SafeArea(
              child: Column(
                children: [
                  // Progress Bars
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                    child: Row(
                      children: List.generate(_stories.length, (index) {
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.0),
                            child: AnimatedBuilder(
                              animation: _progressController,
                              builder: (context, child) {
                                double value = 0.0;
                                if (index < _currentIndex) {
                                  value = 1.0;
                                } else if (index == _currentIndex) {
                                  value = _progressController.value;
                                }
                                return LinearProgressIndicator(
                                  value: value,
                                  backgroundColor: Colors.white30,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                                  minHeight: 2,
                                );
                              },
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundImage: NetworkImage(story.authorAvatarUrl),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          story.authorName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '2h', // Mock time
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => context.pop(),
                        ),
                      ],
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Bottom Bar (Reply / React)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white54),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: const Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    style: TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      hintText: 'Send message',
                                      hintStyle: TextStyle(color: Colors.white70),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.favorite_border, color: Colors.white),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
