import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/connections/linked_accounts.dart';
import 'package:oneova/backend/live/live_restream_service.dart';

void main() {
  final now = DateTime(2026, 10, 24, 12);

  group('LinkedAccount.fromConnectionDoc', () {
    test('TikTok / Meta records with a token key are connected', () {
      final tt = LinkedAccount.fromConnectionDoc('tiktok', {
        'platform': 'tiktok',
        'accountName': 'Amina',
        'openId': 'open-1',
        'tokenKey': 'tiktok_token_open-1',
      }, now: now)!;
      expect(tt.platform, LinkedPlatform.tiktok);
      expect(tt.status, LinkStatus.connected);
      expect(tt.accountId, 'open-1');

      final ig = LinkedAccount.fromConnectionDoc('instagram', {
        'platform': 'instagram',
        'accountName': 'Studio Page',
        'pageId': 'ig-77',
        'tokenKey': 'meta_token_instagram_1',
        'tokenExpiresAt': Timestamp.fromDate(now.add(const Duration(days: 3))),
      }, now: now)!;
      expect(ig.isUsable, isTrue);
      expect(ig.accountId, 'ig-77');
    });

    test('a record without an OAuth grant needs a reconnect', () {
      // What the old simulated wizards wrote.
      final a = LinkedAccount.fromConnectionDoc('instagram', {'platform': 'instagram', 'accountName': '@oneova_live', 'unreadCount': 10}, now: now)!;
      expect(a.status, LinkStatus.needsReconnect);
      expect(a.isUsable, isFalse);
    });

    test('an expired Meta token is reported as expired', () {
      final a = LinkedAccount.fromConnectionDoc('facebook', {
        'platform': 'facebook',
        'tokenKey': 'k',
        'tokenExpiresAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 1))),
      }, now: now)!;
      expect(a.status, LinkStatus.expired);
    });

    test('Gmail needs the server-kept grant written by gmailConnect', () {
      expect(LinkedAccount.fromConnectionDoc('gmail', {'platform': 'gmail', 'accountName': 'x'}, now: now)!.status, LinkStatus.needsReconnect);
      // Older phone-only grant: no server token, so it must be reconnected.
      expect(
        LinkedAccount.fromConnectionDoc('gmail', {
          'platform': 'gmail',
          'email': 'me@example.com',
          'grantedScopes': ['https://www.googleapis.com/auth/gmail.readonly'],
        }, now: now)!
            .status,
        LinkStatus.needsReconnect,
      );
      final g = LinkedAccount.fromConnectionDoc('gmail', {
        'platform': 'gmail',
        'email': 'me@example.com',
        'grantedScopes': ['https://www.googleapis.com/auth/gmail.readonly'],
        'tokenStore': 'server',
      }, now: now)!;
      expect(g.status, LinkStatus.connected);
      expect(g.accountName, 'me@example.com');
    });

    test('unknown platforms and YouTube rows in social_connections are ignored', () {
      expect(LinkedAccount.fromConnectionDoc('x', {'platform': 'x', 'tokenKey': 'k'}, now: now), isNull);
      expect(LinkedAccount.fromConnectionDoc('youtube', {'platform': 'youtube', 'tokenKey': 'k'}, now: now), isNull);
    });
  });

  test('fromYoutubeDoc names the account by its active channel', () {
    final a = LinkedAccount.fromYoutubeDoc({
      'googleId': 'g1',
      'accountName': 'Amina K',
      'channels': [
        {'id': 'c1', 'title': 'Old', 'isActive': false},
        {'id': 'c2', 'title': 'Amina Live', 'thumbnailUrl': 'https://t', 'isActive': true},
      ],
    })!;
    expect(a.platform, LinkedPlatform.youtube);
    expect(a.accountName, 'Amina Live');
    expect(a.isUsable, isTrue);
    expect(LinkedAccount.fromYoutubeDoc({'accountName': 'no id'}), isNull);
  });

  test('combine joins both collections in platform order', () async {
    final db = FakeFirebaseFirestore();
    final user = db.collection('users').doc('u1');
    await user.collection('social_connections').doc('tiktok').set({'platform': 'tiktok', 'tokenKey': 'k', 'accountName': 'tt'});
    await user.collection('social_connections').doc('gmail').set({'platform': 'gmail', 'email': 'a@b.c', 'grantedScopes': ['s']});
    await user.collection('youtube_accounts').doc('g1').set({'googleId': 'g1', 'accountName': 'yt', 'channels': []});

    final list = LinkedAccount.combine(
      (await user.collection('social_connections').get()).docs,
      (await user.collection('youtube_accounts').get()).docs,
      now: now,
    );
    expect(list.map((a) => a.platform), [LinkedPlatform.gmail, LinkedPlatform.youtube, LinkedPlatform.tiktok]);
  });

  test('restream request keeps only usable accounts with a live API', () {
    const yt = LinkedAccount(platform: LinkedPlatform.youtube, accountId: 'g1', accountName: 'Amina Live', status: LinkStatus.connected);
    const fbExpired = LinkedAccount(platform: LinkedPlatform.facebook, accountId: 'p1', accountName: 'Page', status: LinkStatus.expired);
    const tt = LinkedAccount(platform: LinkedPlatform.tiktok, accountId: 'o1', accountName: 'tt', status: LinkStatus.connected);

    final f = LiveRestreamService.requestFields([yt, fbExpired, tt], now: now);
    expect(f['isMultiPlatform'], isTrue);
    expect(f['linkedPlatforms'], ['youtube']);
    final targets = f['restreamTargets'] as Map;
    expect(targets.keys, ['youtube']);
    expect((targets['youtube'] as Map)['status'], 'requested');

    expect(LiveRestreamService.requestFields([tt], now: now)['isMultiPlatform'], isFalse);
  });
}
