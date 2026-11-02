import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../backend/social/models/search_models.dart';
import '../../../backend/social/services/search_service.dart';
import '../../../backend/moderation/services/content_safety_moderation_engine.dart';
import 'package:oneova/shared/theme/app_theme.dart';
import '../../../shared/widgets/oneova_voice_typing_button.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  String _query = '';
  bool _isSearching = false;
  
  List<TrendingItem> _trending = [];
  List<AutocompleteResult> _autocomplete = [];
  List<SearchResult> _results = [];
  
  SearchResultType? _selectedFilter;

  @override
  void initState() {
    super.initState();
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    final trending = await ref.read(searchServiceProvider).getTrending();
    if (mounted) {
      setState(() {
        _trending = trending;
      });
    }
  }

  void _onSearchChanged(String val) async {
    setState(() {
      _query = val;
    });
    
    if (val.isEmpty) {
      setState(() {
        _autocomplete = [];
        _isSearching = false;
      });
      return;
    }

    final ac = await ref.read(searchServiceProvider).getAutocomplete(val);
    if (mounted && _query == val) {
      setState(() {
        _autocomplete = ac;
      });
    }
  }

  void _executeSearch(String query) async {
    _focusNode.unfocus();

    // Zero-tolerance content safety filter on search
    final safetyCheck = ref.read(contentSafetyModerationEngineProvider).filterSearchQuery(query);
    if (!safetyCheck.isAllowed) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(safetyCheck.blockedReason ?? 'Adult or sexual search queries are strictly prohibited on Oneova.'),
            backgroundColor: const Color(0xFFDC2626),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {
          _query = query;
          _isSearching = true;
          _results = [];
        });
      }
      return;
    }

    setState(() {
      _query = query;
      _isSearching = true;
      _searchController.text = query;
    });

    final results = await ref.read(searchServiceProvider).search(
      query,
      filters: _selectedFilter != null ? [_selectedFilter!] : null,
    );
    
    if (mounted) {
      setState(() {
        _results = results;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: context.textPrimary),
          onPressed: () => context.pop(),
        ),
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: context.surfaceMid,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.border),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _focusNode,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search creators, videos, sounds...',
              hintStyle: TextStyle(color: context.textMuted),
              prefixIcon: Icon(Icons.search, color: context.textMuted),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OneovaVoiceTypingButton(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    tooltip: 'Voice search',
                  ),
                  if (_query.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear, color: context.textMuted, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
                ],
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onChanged: _onSearchChanged,
            onSubmitted: _executeSearch,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isSearching) {
      return _buildSearchResults();
    } else if (_query.isNotEmpty) {
      return _buildAutocomplete();
    } else {
      return _buildTrending();
    }
  }

  Widget _buildTrending() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Trending Now',
          style: TextStyle(color: context.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ..._trending.map((item) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: item.imageUrl != null 
                ? Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      image: DecorationImage(
                        image: NetworkImage(item.imageUrl!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                : CircleAvatar(
                    backgroundColor: context.surfaceMid,
                    child: Icon(Icons.trending_up, color: context.textMuted),
                  ),
            title: Text(item.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
            subtitle: Text('${item.subtitle} • ${_formatCount(item.interactionCount)}', style: TextStyle(color: context.textMuted)),
            onTap: () => _executeSearch(item.title),
          );
        }),
      ],
    );
  }

  Widget _buildAutocomplete() {
    return ListView(
      children: _autocomplete.map((ac) {
        return ListTile(
          leading: Icon(Icons.search, color: context.textMuted),
          title: Text(ac.text, style: TextStyle(color: context.textPrimary)),
          onTap: () => _executeSearch(ac.text),
        );
      }).toList(),
    );
  }

  Widget _buildSearchResults() {
    return Column(
      children: [
        // Filters
        SizedBox(
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: SearchResultType.values.map((type) {
              final isSelected = _selectedFilter == type;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: FilterChip(
                  label: Text(type.name.toUpperCase()),
                  selected: isSelected,
                  selectedColor: AppColors.brandBlue,
                  backgroundColor: context.surfaceMid,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : context.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  onSelected: (val) {
                    setState(() {
                      _selectedFilter = val ? type : null;
                    });
                    _executeSearch(_query); // re-fetch with filter
                  },
                ),
              );
            }).toList(),
          ),
        ),
        Divider(color: context.border, height: 1),
        // Results
        Expanded(
          child: _results.isEmpty
              ? Center(child: Text('No results found.', style: TextStyle(color: context.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final res = _results[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: context.border, width: 1.0),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).brightness == Brightness.dark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        leading: res.imageUrl != null
                            ? CircleAvatar(
                                radius: 25,
                                backgroundImage: NetworkImage(res.imageUrl!),
                                backgroundColor: Colors.transparent,
                              )
                            : CircleAvatar(
                                radius: 25,
                                backgroundColor: context.surfaceMid,
                                child: Icon(Icons.image, color: context.textMuted),
                              ),
                        title: Text(res.title, style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold)),
                        subtitle: Text(res.subtitle, style: TextStyle(color: context.textMuted)),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.brandBlue.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            res.type.name.toUpperCase(), 
                            style: const TextStyle(color: AppColors.brandBlue, fontSize: 10, fontWeight: FontWeight.w900),
                          ),
                        ),
                        onTap: () {},
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}
