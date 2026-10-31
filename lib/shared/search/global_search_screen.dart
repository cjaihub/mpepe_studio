import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../backend/search/models/search_result.dart';
import '../../backend/search/providers/search_providers.dart';
import '../../backend/social/services/global_hashtag_service.dart';
import '../../shared/theme/app_theme.dart';
import 'package:oneova/shared/widgets/animated_loading_indicator.dart';

class GlobalSearchScreen extends ConsumerStatefulWidget {
  const GlobalSearchScreen({super.key});

  @override
  ConsumerState<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends ConsumerState<GlobalSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {}); // Updates clear button visibility
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(globalSearchProvider.notifier).executeSearch(query);
    });
  }

  void _onSearchSubmit(String query) {
    _debounce?.cancel();
    ref.read(globalSearchProvider.notifier).executeSearch(query);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    ref.read(globalSearchProvider.notifier).executeSearch('');
  }

  void _onTagChipTapped(String tag) {
    _debounce?.cancel();
    final query = '#$tag';
    _searchController.text = query;
    setState(() {});
    ref.read(globalSearchProvider.notifier).executeSearch(query);
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(globalSearchProvider);
    final notifier = ref.read(globalSearchProvider.notifier);
    final topBarBg = context.topBarBg;
    final topBarFg = context.topBarFg;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: topBarBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: topBarFg),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Container(
          height: 38,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.0),
          ),
          child: TextField(
            controller: _searchController,
            style: GoogleFonts.inter(
              color: topBarFg,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search creators, videos, hashtags...',
              hintStyle: GoogleFonts.inter(
                color: topBarFg.withValues(alpha: 0.65),
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 18,
                color: topBarFg.withValues(alpha: 0.8),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: topBarFg,
                      ),
                      onPressed: _clearSearch,
                    )
                  : null,
              suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: _onSearchSubmit,
          ),
        ),
        actions: [
          Tooltip(
            message: searchState.isSemanticEnabled
                ? 'Smart search is on'
                : 'Turn on smart search',
            child: IconButton(
              icon: Icon(
                searchState.isSemanticEnabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
                color: searchState.isSemanticEnabled
                    ? AppColors.brandPink
                    : topBarFg,
                size: 20,
              ),
              onPressed: () {
                notifier.toggleSemanticSearch(!searchState.isSemanticEnabled);
                if (_searchController.text.isNotEmpty) {
                  _onSearchSubmit(_searchController.text);
                }
              },
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          _buildTrendingBar(context),
          _buildFiltersBar(searchState, notifier),
          Expanded(
            child: _buildResultsArea(searchState),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingBar(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(bottom: BorderSide(color: AppColors.border(context), width: 1.0)),
      ),
      child: StreamBuilder<List<GlobalHashtagModel>>(
        stream: GlobalHashtagService().watchTrendingHashtags(limit: 10),
        builder: (context, snapshot) {
          final tags = snapshot.data ?? [];
          if (tags.isEmpty) {
            return const SizedBox.shrink();
          }

          return ListView.separated(
            scrollDirection: Axis.horizontal,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: tags.length + 1,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              if (index == 0) {
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.trending_up, size: 15, color: AppColors.brandPink),
                      const SizedBox(width: 4),
                      Text(
                        'Trending',
                        style: GoogleFonts.inter(
                          color: AppColors.brandPink,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                );
              }

              final hashtag = tags[index - 1];
              return InkWell(
                borderRadius: BorderRadius.circular(AppRadius.full),
                onTap: () => _onTagChipTapped(hashtag.tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMid(context),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(color: AppColors.border(context), width: 1.0),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '#${hashtag.tag}',
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimaryOf(context),
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.brandPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.full),
                        ),
                        child: Text(
                          '${hashtag.velocityPerHour.toStringAsFixed(1)}/h',
                          style: GoogleFonts.inter(
                            color: AppColors.brandPink,
                            fontWeight: FontWeight.w800,
                            fontSize: 9.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildFiltersBar(SearchState state, GlobalSearchNotifier notifier) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        border: Border(bottom: BorderSide(color: AppColors.border(context), width: 1.0)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          _FilterChip(
            label: 'All',
            isSelected: state.selectedFilterType == null,
            onTap: () => _applyFilter(notifier, null),
          ),
          _FilterChip(
            label: 'Creators',
            isSelected: state.selectedFilterType == SearchEntityType.person,
            onTap: () => _applyFilter(notifier, SearchEntityType.person),
          ),
          _FilterChip(
            label: 'Videos',
            isSelected: state.selectedFilterType == SearchEntityType.video,
            onTap: () => _applyFilter(notifier, SearchEntityType.video),
          ),
          _FilterChip(
            label: 'Hashtags',
            isSelected: state.selectedFilterType == SearchEntityType.hashtag,
            onTap: () => _applyFilter(notifier, SearchEntityType.hashtag),
          ),
        ],
      ),
    );
  }

  void _applyFilter(GlobalSearchNotifier notifier, SearchEntityType? type) {
    notifier.setFilterType(type);
    if (_searchController.text.isNotEmpty) {
      _onSearchSubmit(_searchController.text);
    }
  }

  Widget _buildResultsArea(SearchState state) {
    if (state.isLoading) {
      return const Center(child: AnimatedLoadingIndicator(color: AppColors.brandBlue));
    }

    if (state.error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 36, color: AppColors.brandPink),
              const SizedBox(height: 8),
              Text(
                'Search encountered an issue',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                state.error,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state.results.isEmpty) {
      if (_searchController.text.trim().isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search, size: 48, color: AppColors.textMutedOf(context)),
                const SizedBox(height: 12),
                Text(
                  'Search Oneova',
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Discover top creators, viral short videos, and trending platform tags.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondaryOf(context),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 44, color: AppColors.textMutedOf(context)),
              const SizedBox(height: 12),
              Text(
                'No results found',
                style: GoogleFonts.inter(
                  color: AppColors.textPrimaryOf(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try searching with a different keyword or hashtag.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondaryOf(context),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: state.results.length + (state.hasMore ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == state.results.length) {
          return Center(
            child: TextButton(
              onPressed: () {
                ref
                    .read(globalSearchProvider.notifier)
                    .executeSearch(_searchController.text, loadMore: true);
              },
              child: Text(
                'Load more results',
                style: GoogleFonts.inter(
                  color: AppColors.brandBlue,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          );
        }
        final result = state.results[index];
        return _buildResultCard(result);
      },
    );
  }

  Widget _buildResultCard(SearchResult result) {
    switch (result.type) {
      case SearchEntityType.person:
        return _buildCreatorCard(context, result);
      case SearchEntityType.video:
      case SearchEntityType.post:
        return _buildVideoCard(context, result);
      case SearchEntityType.hashtag:
        return _buildHashtagCard(context, result);
      default:
        return _buildGenericCard(context, result);
    }
  }

  Widget _buildCreatorCard(BuildContext context, SearchResult result) {
    final avatarUrl = (result.metadata['avatarUrl'] as String?) ??
        (result.metadata['profilePhotoUrl'] as String?) ??
        '';
    final displayName = result.title.isNotEmpty ? result.title : 'Creator';
    final rawUsername = (result.metadata['username'] as String?) ??
        result.subtitle?.replaceAll('@', '') ??
        '';
    final username = rawUsername.isNotEmpty ? '@$rawUsername' : '';
    final followerCount = (result.metadata['followerCount'] as num?)?.toInt() ??
        (result.metadata['followers'] as num?)?.toInt() ??
        0;
    final isVerified = result.metadata['isVerified'] == true;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          context.push('/profile/${result.id}');
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border(context), width: 1.0),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: AppColors.surfaceMid(context),
                backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                child: avatarUrl.isEmpty
                    ? Icon(Icons.person, color: AppColors.textSecondaryOf(context), size: 24)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppColors.textPrimaryOf(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                        if (isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified, size: 15, color: AppColors.brandBlue),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (username.isNotEmpty)
                      Text(
                        username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.people_outline, size: 13, color: AppColors.brandPink),
                        const SizedBox(width: 4),
                        Text(
                          '${_formatCount(followerCount)} followers',
                          style: GoogleFonts.inter(
                            color: AppColors.textMutedOf(context),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.brandBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: AppColors.brandBlue.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Text(
                  'View',
                  style: GoogleFonts.inter(
                    color: AppColors.brandBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoCard(BuildContext context, SearchResult result) {
    final thumbUrl = (result.metadata['thumbnailUrl'] as String?) ??
        (result.metadata['posterFrameUrl'] as String?) ??
        (result.metadata['mediaUrl'] as String?);
    final viewCount = (result.metadata['viewCount'] as num?)?.toInt() ?? 0;
    final rawAuthor = (result.metadata['authorHandle'] as String?) ??
        (result.metadata['authorName'] as String?) ??
        (result.metadata['authorId'] as String?) ??
        '';
    final authorHandle =
        rawAuthor.startsWith('@') ? rawAuthor : (rawAuthor.isNotEmpty ? '@$rawAuthor' : '');
    final title = result.title.isNotEmpty ? result.title : result.content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          context.push('/hub/home?v=${result.id}');
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border(context), width: 1.0),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Stack(
                  children: [
                    Container(
                      width: 72,
                      height: 96,
                      color: AppColors.surfaceMid(context),
                      child: (thumbUrl != null && thumbUrl.isNotEmpty)
                          ? Image.network(
                              thumbUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: AppColors.surfaceMid(context),
                                child: Icon(
                                  Icons.play_arrow,
                                  color: AppColors.textMutedOf(context),
                                  size: 32,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.play_arrow,
                              color: AppColors.textMutedOf(context),
                              size: 32,
                            ),
                    ),
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility, size: 9, color: Colors.white),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                _formatCount(viewCount),
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (authorHandle.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.alternate_email, size: 12, color: AppColors.brandPink),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              authorHandle.replaceAll('@', ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppColors.brandPink,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceMid(context),
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            border: Border.all(color: AppColors.border(context), width: 1.0),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.play_circle_outline,
                                size: 12,
                                color: AppColors.brandBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Watch in Feed',
                                style: GoogleFonts.inter(
                                  color: AppColors.brandBlue,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHashtagCard(BuildContext context, SearchResult result) {
    final tag = result.title.startsWith('#') ? result.title : '#${result.title}';
    final postCount = (result.metadata['postCount'] as num?)?.toInt() ?? 0;
    final velocity = (result.metadata['velocityPerHour'] as num?)?.toDouble() ?? 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          _searchController.text = tag;
          _onSearchSubmit(tag);
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border(context), width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.tag, color: AppColors.brandPink, size: 20),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tag,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatCount(postCount)} posts',
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondaryOf(context),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.brandPink.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: AppColors.brandPink.withValues(alpha: 0.3),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.trending_up, size: 12, color: AppColors.brandPink),
                    const SizedBox(width: 4),
                    Text(
                      '${velocity.toStringAsFixed(1)}/h',
                      style: GoogleFonts.inter(
                        color: AppColors.brandPink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenericCard(BuildContext context, SearchResult result) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () {
          if (result.type == SearchEntityType.message) {
            final conversationId = result.metadata['conversationId'];
            if (conversationId != null) {
              context.push('/conversation/$conversationId?anchor=${result.id}');
            }
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface(context),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border(context), width: 1.0),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.brandBlue.withValues(alpha: 0.15),
                child: const Icon(Icons.search, color: AppColors.brandBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.title,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    if (result.content.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        result.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondaryOf(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: isSelected ? AppColors.brandBlue : AppColors.border(context),
            width: 1.0,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.white : AppColors.textSecondaryOf(context),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }
}
