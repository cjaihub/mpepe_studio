import 'package:flutter/foundation.dart';

/// Share of what a remix earns (in gifts on the remix) that goes to the
/// original creator, taken from the remixer's part. Same value as
/// `REMIX_ORIGINAL_SHARE` in functions/src/remix_logic.ts.
const double kRemixOriginalShare = 0.25;

/// The post a remix is made from (saved with the Studio project and on the
/// published post as `remixOf`).
@immutable
class RemixSource {
  final String contentId;
  final String authorId;
  final String authorName;

  const RemixSource({required this.contentId, required this.authorId, this.authorName = ''});

  Map<String, dynamic> toJson() => {'contentId': contentId, 'authorId': authorId, 'authorName': authorName};

  static RemixSource? fromJson(Object? raw) {
    if (raw is! Map || raw['contentId'] is! String || raw['authorId'] is! String) return null;
    return RemixSource(
      contentId: raw['contentId'] as String,
      authorId: raw['authorId'] as String,
      authorName: raw['authorName'] as String? ?? '',
    );
  }
}
