import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/models/content.dart';
import 'package:oneova/backend/social/services/derivative_service.dart';
import 'package:uuid/uuid.dart';

void main() {
  late DerivativeService derivativeService;

  setUp(() {
    derivativeService = DerivativeService();
  });

  Content createContent({
    required String visibility,
    required CreatorPermissions permissions,
  }) {
    return Content(
      id: const Uuid().v4(),
      authorId: 'original_creator',
      description: 'Original video',
      mediaUrl: 'https://video.com/123.mp4',
      mediaMetadata: MediaMetadata(),
      visibility: visibility,
      permissions: permissions,
      attribution: ContentAttribution(),
      createdAt: DateTime.now(),
    );
  }

  test('Creates duet successfully when allowed', () async {
    final original = createContent(
      visibility: 'public',
      permissions: CreatorPermissions(allowDuet: true),
    );

    final derivative = await derivativeService.createDerivative(
      originalContent: original,
      currentUserId: 'remixer_1',
      type: DerivativeType.duet,
      newDescription: 'My awesome duet!',
    );

    expect(derivative.authorId, 'remixer_1');
    expect(derivative.attribution!.originalContentId, original.id);
    expect(derivative.attribution!.originalAuthorId, 'original_creator');
    expect(derivative.attribution!.derivativeType, DerivativeType.duet);
  });

  test('Blocks duet if disabled by creator', () async {
    final original = createContent(
      visibility: 'public',
      permissions: CreatorPermissions(allowDuet: false),
    );

    expect(
      () => derivativeService.createDerivative(
        originalContent: original,
        currentUserId: 'remixer_1',
        type: DerivativeType.duet,
        newDescription: 'Trying to duet anyway',
      ),
      throwsA(isA<DerivativeAuthorizationException>()),
    );
  });

  test('Blocks stitch if disabled by creator', () async {
    final original = createContent(
      visibility: 'public',
      permissions: CreatorPermissions(allowStitch: false),
    );

    expect(
      () => derivativeService.createDerivative(
        originalContent: original,
        currentUserId: 'remixer_1',
        type: DerivativeType.stitch,
        newDescription: 'Trying to stitch anyway',
      ),
      throwsA(isA<DerivativeAuthorizationException>()),
    );
  });

  test('Blocks private content leak', () async {
    final original = createContent(
      visibility: 'friends', // Not public
      permissions: CreatorPermissions(allowDuet: true), // Duets are technically ON, but it's private
    );

    expect(
      () => derivativeService.createDerivative(
        originalContent: original,
        currentUserId: 'remixer_1',
        type: DerivativeType.duet,
        newDescription: 'Leaking private content',
      ),
      throwsA(isA<DerivativeAuthorizationException>()),
    );
  });
}
