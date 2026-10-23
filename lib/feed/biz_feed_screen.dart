import 'package:oneova/shared/widgets/animated_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import '../shared/theme/app_theme.dart';

class BizFeedScreen extends StatefulWidget {
  const BizFeedScreen({super.key});

  @override
  State<BizFeedScreen> createState() => _BizFeedScreenState();
}

class _BizFeedScreenState extends State<BizFeedScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filters = ['All', 'Electronics', 'Fashion', 'Digital', 'Music', 'Services'];

  @override
  void initState() {
    super.initState();
    _seedIfEmpty();
  }

  Future<void> _seedIfEmpty() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    final coll = FirebaseFirestore.instance.collection('biz_products');
    final snap = await coll.limit(1).get();
    if (snap.docs.isEmpty) {
      await coll.add({
        'title': 'Premium Studio Headphones',
        'description': 'High fidelity audio for professional studio use with noise cancellation.',
        'price': 299.99,
        'imageUrl': 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?q=80&w=1000&auto=format&fit=crop',
        'seller': 'AudioPro',
        'category': 'Electronics',
        'createdAt': FieldValue.serverTimestamp(),
        'ownerId': uid,
      });
      await coll.add({
        'title': 'Mechanical Keyboard',
        'description': 'Clicky tactile switches for rapid typing and aesthetic studio setups.',
        'price': 149.50,
        'imageUrl': 'https://images.unsplash.com/photo-1595225476474-87563907a212?q=80&w=1000&auto=format&fit=crop',
        'seller': 'KeyTech',
        'category': 'Electronics',
        'createdAt': FieldValue.serverTimestamp(),
        'ownerId': uid,
      });
      await coll.add({
        'title': 'Studio Microphone',
        'description': 'Crystal clear voice capture for podcasting and music production.',
        'price': 199.00,
        'imageUrl': 'https://images.unsplash.com/photo-1590602847861-f357a9332bbc?q=80&w=1000&auto=format&fit=crop',
        'seller': 'MicMasters',
        'category': 'Digital',
        'createdAt': FieldValue.serverTimestamp(),
        'ownerId': uid,
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topBarBg = context.topBarBg;
    final topBarFg = context.topBarFg;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: topBarBg,
        title: Text('Digital Marketplace', style: AppTheme.h3Style.copyWith(color: topBarFg)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: topBarFg),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/hub/home');
            }
          },
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.darkSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.outline, width: 2),
              ),
              child: TextField(
                controller: _searchController,
                style: AppTheme.bodyStyle.copyWith(color: AppColors.textPrimary),
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val.toLowerCase();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search products, creators...',
                  hintStyle: AppTheme.bodyStyle.copyWith(color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          
          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _filters.map((filter) {
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedFilter = filter;
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brandBlue : AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? AppColors.brandBlue : AppColors.outline,
                          width: 2,
                        ),
                      ),
                      child: Text(
                        filter,
                        style: AppTheme.bodyStyle.copyWith(
                          color: isSelected ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const SizedBox(height: 8),
          
          // Grid
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('biz_products')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: const AnimatedLoadingIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading feed',
                      style: AppTheme.bodyStyle.copyWith(color: AppColors.textPrimary),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                
                // Filter logic
                final filteredDocs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final title = (data['title'] as String? ?? '').toLowerCase();
                  final category = data['category'] as String? ?? 'All';
                  
                  final matchesSearch = title.contains(_searchQuery);
                  final matchesFilter = _selectedFilter == 'All' || category == _selectedFilter;
                  
                  return matchesSearch && matchesFilter;
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text(
                      'No products found.',
                      style: AppTheme.bodyStyle.copyWith(color: AppColors.textSecondary),
                    ),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.68,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final data = filteredDocs[index].data() as Map<String, dynamic>;
                    return _ProductCard(data: data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> data;

  const _ProductCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final imageUrl = data['imageUrl'] as String? ?? '';
    final title = data['title'] as String? ?? 'Product';
    final price = data['price']?.toString() ?? '0.00';
    final seller = data['seller'] as String? ?? 'Seller';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outline, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image portion
          Expanded(

            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl.isNotEmpty)
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Center(child: const AnimatedLoadingIndicator());
                    },
                    errorBuilder: (context, error, stackTrace) => Container(color: AppColors.darkSurfaceHighlight),
                  )
                else
                  Container(color: AppColors.darkSurfaceHighlight),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.bookmark_border, color: Colors.white, size: 16),
                  ),
                ),
              ],
            ),
          ),
          
          // Details portion
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTheme.bodyStyle.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w900),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@$seller',
                        style: AppTheme.bodyStyle.copyWith(color: AppColors.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '\$$price',
                        style: AppTheme.bodyStyle.copyWith(color: AppColors.brandBlue, fontWeight: FontWeight.w900),
                      ),
                      GestureDetector(
                        onTap: () => _showConfirmation(context, title),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 16),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showConfirmation(BuildContext context, String title) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.outline, width: 2),
        ),
        title: Text('Buy $title?', style: AppTheme.h3Style.copyWith(color: Colors.white)),
        content: Text('Do you want to proceed to checkout?', style: AppTheme.bodyStyle.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTheme.bodyStyle.copyWith(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Proceed with checkout logic
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              minimumSize: const Size(120, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
            child: Text('Confirm', style: AppTheme.bodyStyle.copyWith(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
