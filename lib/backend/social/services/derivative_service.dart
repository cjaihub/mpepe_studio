import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../models/content.dart';

final derivativeServiceProvider = Provider<DerivativeService>((ref) {
  return DerivativeService();
});

class DerivativeAuthorizationException implements Exception {
  final String message;
  DerivativeAuthorizationException(this.message);
  
  @override
  String toString() => 'DerivativeAuthorizationException: $message';
}

class DerivativeService {
  /// Creates a derivative object (repost, duet, remix, etc.)
  /// Validates against the original content's creator permissions and visibility.
  Future<Content> createDerivative({
    required Content originalContent,
    required String currentUserId,
    required DerivativeType type,
    required String newDescription,
    String? newMediaUrl,
    MediaMetadata? newMediaMetadata,
  }) async {
    // 1. Validate Privacy Leak
    // Do not allow private content to leak through derivatives.
    if (originalContent.visibility != 'public') {
      throw DerivativeAuthorizationException(
        'Cannot create a derivative of private or restricted content.',
      );
    }

    // 2. Validate Creator Permissions
    switch (type) {
      case DerivativeType.duet:
        if (!originalContent.permissions.allowDuet) {
          throw DerivativeAuthorizationException('Creator has disabled duets.');
        }
        break;
      case DerivativeType.stitch:
        if (!originalContent.permissions.allowStitch) {
          throw DerivativeAuthorizationException('Creator has disabled stitches.');
        }
        break;
      case DerivativeType.remix:
        if (!originalContent.permissions.allowRemix) {
          throw DerivativeAuthorizationException('Creator has disabled remixes.');
        }
        break;
      case DerivativeType.repost:
      case DerivativeType.quote_repost:
        if (!originalContent.permissions.allowSharing) {
          throw DerivativeAuthorizationException('Creator has disabled sharing/reposts.');
        }
        break;
      case DerivativeType.video_reply:
      case DerivativeType.reaction_video:
      case DerivativeType.green_screen:
      case DerivativeType.split_screen:
        // Generally requires duet/remix permissions to use the original media
        if (!originalContent.permissions.allowRemix && !originalContent.permissions.allowDuet) {
          throw DerivativeAuthorizationException('Creator has disabled media reuse for reactions/replies.');
        }
        break;
    }

    // 3. Construct the Attribution block
    // Every derivative object must preserve: original creator, original content ID, derivative creator, relationship, attribution.
    final attribution = ContentAttribution(
      originalContentId: originalContent.id,
      originalAuthorId: originalContent.authorId,
      derivativeType: type,
    );

    // 4. Create the new Content object
    final derivativeContent = Content(
      id: const Uuid().v4(),
      authorId: currentUserId,
      description: newDescription,
      type: ContentType.short_video, // Default, can be overridden based on newMedia
      mediaUrl: newMediaUrl ?? originalContent.mediaUrl, // Repost might reuse URL
      mediaMetadata: newMediaMetadata ?? originalContent.mediaMetadata,
      visibility: 'public', 
      permissions: CreatorPermissions(), // Derivative creator can set their own down-stream permissions
      attribution: attribution,
      createdAt: DateTime.now(),
    );

    // In a real app: await _firestore.collection('content').doc(derivativeContent.id).set(derivativeContent.toMap());
    await Future.delayed(const Duration(milliseconds: 300));
    
    return derivativeContent;
  }
}
