import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/social/models/collection.dart';
import '../../../backend/social/services/collection_service.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class CollectionViewScreen extends ConsumerStatefulWidget {
  final String collectionId;
  const CollectionViewScreen({super.key, required this.collectionId});

  @override
  ConsumerState<CollectionViewScreen> createState() => _CollectionViewScreenState();
}

class _CollectionViewScreenState extends ConsumerState<CollectionViewScreen> {
  MediaCollection? _collection;
  UserCollectionProgress? _progress;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final service = ref.read(collectionServiceProvider);
    final collection = await service.getCollection(widget.collectionId);
    final progress = await service.getProgress(widget.collectionId);
    setState(() {
      _collection = collection;
      _progress = progress;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.bg,
        body: const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue)),
      );
    }

    if (_collection == null) {
      return Scaffold(
        backgroundColor: context.bg,
        body: Center(child: Text('Collection not found', style: TextStyle(color: context.textPrimary))),
      );
    }

    final c = _collection!;
    
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.share, color: context.textPrimary),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.bookmark_border, color: context.textPrimary),
            onPressed: () {},
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Image
            Stack(
              children: [
                Image.network(
                  c.coverUrl,
                  width: double.infinity,
                  height: 300,
                  fit: BoxFit.cover,
                ),
                Container(
                  width: double.infinity,
                  height: 300,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        context.bg.withValues(alpha: 0.5),
                        Colors.transparent,
                        context.bg,
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 16,
                  right: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.brandBlue,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          c.type == CollectionType.premiumSeries ? 'PREMIUM SERIES' : 'PLAYLIST',
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.title,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    c.description,
                    style: TextStyle(color: context.textSecondary, fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  
                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            // Resume or Play First
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brandBlue,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _progress != null ? 'Resume Playback' : 'Play All',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      if (c.accessPolicy == AccessPolicy.premium) ...[
                        const SizedBox(width: 12),
                        OutlinedButton(
                          onPressed: () {},
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: context.border),
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            '\$${c.price}',
                            style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  Text(
                    'Episodes',
                    style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  
                  // Item List
                  ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: c.items.length,
                    itemBuilder: (context, index) {
                      final item = c.items[index];
                      final isCompleted = _progress?.completedPostIds.contains(item.postId) ?? false;
                      
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 80,
                          height: 60,
                          decoration: BoxDecoration(
                            color: context.surfaceMid,
                            borderRadius: BorderRadius.circular(8),
                            image: const DecorationImage(
                              image: NetworkImage('https://picsum.photos/200/150'), // mock thumbnail
                              fit: BoxFit.cover,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.play_circle_outline, color: Colors.white, size: 24),
                          ),
                        ),
                        title: Text(
                          'Episode ${item.orderIndex + 1}',
                          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '10:32', // mock duration
                          style: TextStyle(color: context.textMuted),
                        ),
                        trailing: isCompleted 
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : Icon(Icons.more_vert, color: context.textMuted),
                        onTap: () {
                          // Navigate to viewer
                        },
                      );
                    },
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
