import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/search_result.dart';
import '../search_service.dart';

// --- State Classes ---
class SearchState {
  final bool isLoading;
  final List<SearchResult> results;
  final String error;
  final bool isSemanticEnabled;
  final SearchEntityType? selectedFilterType;
  final int currentNonce;
  final bool hasMore;

  SearchState({
    this.isLoading = false,
    this.results = const [],
    this.error = '',
    this.isSemanticEnabled = false,
    this.selectedFilterType,
    this.currentNonce = 0,
    this.hasMore = false,
  });

  SearchState copyWith({
    bool? isLoading,
    List<SearchResult>? results,
    String? error,
    bool? isSemanticEnabled,
    SearchEntityType? selectedFilterType,
    int? currentNonce,
    bool? hasMore,
  }) {
    return SearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error ?? this.error,
      isSemanticEnabled: isSemanticEnabled ?? this.isSemanticEnabled,
      selectedFilterType: selectedFilterType ?? this.selectedFilterType,
      currentNonce: currentNonce ?? this.currentNonce,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

// --- Notifiers ---
class GlobalSearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() {
    return SearchState();
  }

  void toggleSemanticSearch(bool enabled) {
    state = state.copyWith(isSemanticEnabled: enabled);
  }

  void setFilterType(SearchEntityType? type) {
    state = state.copyWith(selectedFilterType: type);
  }

  Future<void> executeSearch(String query, {bool loadMore = false}) async {
    if (query.trim().isEmpty) {
      state = state.copyWith(results: [], error: '', isLoading: false, hasMore: false);
      return;
    }

    final int executionNonce = state.currentNonce + 1;
    state = state.copyWith(isLoading: true, error: '', currentNonce: executionNonce);

    try {
      final searchService = ref.read(searchServiceProvider);
      List<SearchResult> newResults;
      
      // Basic limit implementation for pagination simulation
      final int limit = loadMore ? state.results.length + 20 : 20;

      if (state.isSemanticEnabled) {
        newResults = await searchService.semanticSearch(
          query: query,
          type: state.selectedFilterType,
          limit: limit,
        );
      } else {
        newResults = await searchService.exactSearch(
          query: query,
          type: state.selectedFilterType,
          limit: limit,
        );
      }

      // Stale result protection check
      if (executionNonce == state.currentNonce) {
        state = state.copyWith(
          isLoading: false, 
          results: newResults,
          hasMore: newResults.length == limit,
        );
      }
    } catch (e) {
      if (executionNonce == state.currentNonce) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }
}

final globalSearchProvider = NotifierProvider<GlobalSearchNotifier, SearchState>(() {
  return GlobalSearchNotifier();
});
