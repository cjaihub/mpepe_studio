import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/models/comment.dart';
import 'package:oneova/backend/social/models/comment_settings.dart';
import 'package:oneova/backend/social/services/comment_service.dart';
import 'package:uuid/uuid.dart';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';

void main() {
  late CommentService commentService;

  setUp(() {
    final firestore = FakeFirebaseFirestore();
    firestore.collection('posts').doc('test_post').set({'commentCount': 0});
    commentService = CommentService(firestore: firestore);
  });

  Comment createComment(String postId, String authorId, String content) {
    return Comment(
      id: const Uuid().v4(),
      postId: postId,
      authorId: authorId,
      content: content,
      type: CommentType.text,
      createdAt: DateTime.now(),
    );
  }

  test('Comments disabled throws exception', () async {
    final postId = 'post_1';
    await commentService.updateSettings(CommentSettings(
      postId: postId,
      permission: CommentPermission.nobody,
    ));

    final comment = createComment(postId, 'user_2', 'Hello');
    
    expect(
      () => commentService.addComment(comment),
      throwsA(isA<CommentAuthorizationException>()),
    );
  });
  
  test('Creator can bypass disabled comments', () async {
    final postId = 'post_2';
    await commentService.updateSettings(CommentSettings(
      postId: postId,
      permission: CommentPermission.nobody,
    ));

    final comment = createComment(postId, 'creator_1', 'Hello');
    await commentService.addComment(comment, isCreator: true); // Should succeed

    final comments = await commentService.watchComments(postId).first;
    expect(comments.length, 1);
  });

  test('Blocked words throw exception', () async {
    final postId = 'post_3';
    await commentService.updateSettings(CommentSettings(
      postId: postId,
      blockedWords: ['spam', 'scam'],
    ));

    final comment = createComment(postId, 'user_1', 'This is a S c A m! Wait, no: scam.');
    
    expect(
      () => commentService.addComment(comment),
      throwsA(isA<CommentAuthorizationException>()),
    );
  });

  test('Keyword filters trigger moderation', () async {
    final postId = 'post_4';
    await commentService.updateSettings(CommentSettings(
      postId: postId,
      keywordFilters: ['review'],
    ));

    final comment = createComment(postId, 'user_1', 'Please review my video.');
    await commentService.addComment(comment);
    
    // Should be added but hidden from public getComments because it's moderated
    final comments = await commentService.watchComments(postId).first;
    expect(comments.isEmpty, true);
  });

  test('Slow mode blocks rapid comments', () async {
    final postId = 'post_5';
    await commentService.updateSettings(CommentSettings(
      postId: postId,
      slowModeDelay: const Duration(seconds: 10),
    ));

    final comment1 = createComment(postId, 'user_1', 'First');
    await commentService.addComment(comment1);

    final comment2 = createComment(postId, 'user_1', 'Second');
    expect(
      () => commentService.addComment(comment2),
      throwsA(isA<CommentAuthorizationException>()),
    );
  });
}
