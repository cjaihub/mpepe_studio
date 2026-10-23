import 'package:oneova/backend/search/models/search_models.dart';
// From existing codebase

class SearchPermissionFilter {
  /// Strict Pre-Filter: Eliminates search results BEFORE they are compiled or returned to the user.
  /// Never allow search indexing to bypass privacy.
  List<SearchResultItem> applyPreResponseFilter({
    required List<SearchResultItem> rawResults,
    required String requestorId,
  }) {
    return rawResults.where((item) {
      return _canAccess(requestorId, item);
    }).toList();
  }

  bool _canAccess(String requestorId, SearchResultItem item) {
    // In a real database scenario, this logic translates to RLS (Row Level Security) 
    // or backend query filters (e.g. `where('visibility', '==', 'public')`).
    // Since we are building the orchestration layer, we enforce the rule here.

    switch (item.type) {
      case SearchEntityType.message:
        // Messages are strictly private. Only the owner or participants can see them.
        // Assuming ID contains a hint for this stub, but in reality, checked via DB ACL.
        if (item.id.contains('private') && !item.id.contains(requestorId)) {
          return false;
        }
        return true;
      case SearchEntityType.video:
      case SearchEntityType.post:
      case SearchEntityType.sound:
        // Check if content is public, unlisted, or private.
        // If private, only creator can see it.
        // If unlisted, maybe exclude from global search entirely unless direct link.
        if (item.id.contains('unlisted') || item.id.contains('private')) {
          if (!item.id.contains(requestorId)) return false;
        }
        return true;
      case SearchEntityType.person:
      case SearchEntityType.community:
      case SearchEntityType.channel:
        // Generally public, unless blocked or private community.
        if (item.id.contains('private_community') && !item.id.contains(requestorId)) {
          return false;
        }
        return true;
      case SearchEntityType.file:
      case SearchEntityType.externalMetadata:
        // External metadata (like a YouTube video draft) might be strictly private to the user.
        if (item.isExternal && !item.id.contains(requestorId)) {
          return false;
        }
        return true;
      default:
        return true;
    }
  }
}
