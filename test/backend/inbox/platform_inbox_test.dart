import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis/youtube/v3.dart' as yt;
import 'package:oneova/backend/connections/linked_accounts.dart';
import 'package:oneova/backend/inbox/platform_inbox.dart';

void main() {
  group('PlatformInboxItem.fromSocialMessage', () {
    final at = DateTime(2026, 10, 20, 9, 30);

    test('maps a delivered Instagram DM', () {
      final i = PlatformInboxItem.fromSocialMessage('m1', {
        'userId': 'u1',
        'platform': 'Instagram',
        'interactionType': 'message',
        'senderName': 'Zawadi',
        'senderAvatarUrl': 'https://a',
        'content': 'Hi! Is this available?',
        'timestamp': Timestamp.fromDate(at),
        'isRead': false,
      })!;
      expect(i.platform, LinkedPlatform.instagram);
      expect(i.kind, InboxItemKind.message);
      expect(i.isComment, isFalse);
      expect(i.timestamp, at);
      expect(i.delivered, isTrue);
      expect(i.isRead, isFalse);
    });

    test('comment and mention types are comments', () {
      Map<String, dynamic> doc(String type) => {'platform': 'facebook', 'interactionType': type, 'content': 'nice'};
      expect(PlatformInboxItem.fromSocialMessage('a', doc('video_comment'))!.kind, InboxItemKind.comment);
      expect(PlatformInboxItem.fromSocialMessage('b', doc('reply'))!.kind, InboxItemKind.comment);
      expect(PlatformInboxItem.fromSocialMessage('c', doc('mention'))!.kind, InboxItemKind.mention);
      expect(PlatformInboxItem.fromSocialMessage('c', doc('mention'))!.isComment, isTrue);
    });

    test('drops unknown platforms and empty content; names a missing sender', () {
      expect(PlatformInboxItem.fromSocialMessage('a', {'platform': 'telegram', 'content': 'x'}), isNull);
      expect(PlatformInboxItem.fromSocialMessage('b', {'platform': 'whatsapp', 'content': '  '}), isNull);
      final i = PlatformInboxItem.fromSocialMessage('c', {'platform': 'whatsapp', 'content': 'Hello'})!;
      expect(i.senderName, 'WhatsApp Business');
      expect(i.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });

  test('fromGmail reads sender, subject, snippet and unread label', () {
    final m = gmail.Message(
      id: 'g1',
      threadId: 't1',
      snippet: 'Your invoice &amp; receipt',
      internalDate: '${DateTime(2026, 10, 21).millisecondsSinceEpoch}',
      labelIds: ['INBOX', 'UNREAD'],
      payload: gmail.MessagePart(headers: [
        gmail.MessagePartHeader(name: 'From', value: '"Jane Doe" <jane@example.com>'),
        gmail.MessagePartHeader(name: 'Subject', value: 'October invoice'),
      ]),
    );
    final i = PlatformInboxItem.fromGmail(m);
    expect(i.platform, LinkedPlatform.gmail);
    expect(i.kind, InboxItemKind.email);
    expect(i.senderName, 'Jane Doe');
    expect(i.title, 'October invoice');
    expect(i.preview, 'Your invoice & receipt');
    expect(i.isRead, isFalse);
    expect(i.targetId, 't1');
    expect(i.delivered, isFalse);

    final plain = PlatformInboxItem.fromGmail(gmail.Message(
      id: 'g2',
      payload: gmail.MessagePart(headers: [gmail.MessagePartHeader(name: 'From', value: 'bot@example.com')]),
    ));
    expect(plain.senderName, 'bot@example.com');
    expect(plain.isRead, isTrue);
  });

  test('fromYoutubeThread maps the top-level comment', () {
    final t = yt.CommentThread(
      id: 'th1',
      snippet: yt.CommentThreadSnippet(
        videoId: 'v1',
        topLevelComment: yt.Comment(
          snippet: yt.CommentSnippet(
            authorDisplayName: 'Viewer',
            textOriginal: 'Great live!',
            publishedAt: DateTime(2026, 10, 22),
          ),
        ),
      ),
    );
    final i = PlatformInboxItem.fromYoutubeThread(t)!;
    expect(i.platform, LinkedPlatform.youtube);
    expect(i.kind, InboxItemKind.comment);
    expect(i.preview, 'Great live!');
    expect(i.targetId, 'v1');
    expect(PlatformInboxItem.fromYoutubeThread(yt.CommentThread(id: 'empty')), isNull);
  });

  test('sortNewest orders newest first and drops duplicates', () {
    PlatformInboxItem item(String id, int day) => PlatformInboxItem(
          id: id,
          platform: LinkedPlatform.youtube,
          kind: InboxItemKind.comment,
          senderName: 's',
          preview: 'p',
          timestamp: DateTime(2026, 10, day),
        );
    final out = PlatformInboxItem.sortNewest([item('a', 1), item('b', 3), item('a', 1), item('c', 2)]);
    expect(out.map((i) => i.id), ['b', 'c', 'a']);
  });
}
