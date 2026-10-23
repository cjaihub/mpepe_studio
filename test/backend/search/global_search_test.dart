import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/search/models/search_models.dart';
import 'package:oneova/backend/search/services/search_permission_filter.dart';
import 'package:oneova/backend/search/services/global_search_service.dart';

void main() {
  late SearchPermissionFilter filter;
  late GlobalSearchService searchService;

  setUp(() {
    filter = SearchPermissionFilter();
    searchService = GlobalSearchService(filter);
  });

  test('Privacy filter strictly blocks unauthorized items before returning response', () async {
    const requestor = 'user_123';
    final query = SearchQuery(query: 'test', requestorId: requestor);

    final response = await searchService.search(query);

    // Verify it blocks other people's private videos
    final unauthorizedPrivateVideo = response.results.any((r) => r.id == 'vid_private_other');
    expect(unauthorizedPrivateVideo, false);

    // Verify it allows the requestor's own private video
    final authorizedPrivateVideo = response.results.any((r) => r.id == 'vid_private_$requestor');
    expect(authorizedPrivateVideo, true);

    // Verify it blocks other people's private messages
    final unauthorizedMessage = response.results.any((r) => r.id == 'msg_private_other');
    expect(unauthorizedMessage, false);

    // Verify it blocks other people's external metadata
    final unauthorizedExternal = response.results.any((r) => r.id == 'ext_yt_other');
    expect(unauthorizedExternal, false);

    // The response should be marked as truncated because items were filtered out due to privacy
    expect(response.isTruncated, true);
  });

  test('Filters by entity type properly', () async {
    const requestor = 'user_123';
    final query = SearchQuery(
      query: 'test', 
      requestorId: requestor,
      typeFilters: [SearchEntityType.person, SearchEntityType.hashtag],
    );

    final response = await searchService.search(query);
    
    // It should only return people and hashtags
    for (var result in response.results) {
      expect(
        result.type == SearchEntityType.person || result.type == SearchEntityType.hashtag, 
        true
      );
    }
  });

  test('Sorts by relevance descending', () async {
    const requestor = 'user_123';
    final query = SearchQuery(query: 'test', requestorId: requestor);

    final response = await searchService.search(query);

    for (int i = 0; i < response.results.length - 1; i++) {
      expect(response.results[i].relevanceScore >= response.results[i+1].relevanceScore, true);
    }
  });
}
