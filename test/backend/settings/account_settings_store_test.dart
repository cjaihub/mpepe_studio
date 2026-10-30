import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/notifications/models/notification_preferences.dart';
import 'package:oneova/backend/settings/account_settings_schema.dart';
import 'package:oneova/backend/settings_service.dart';

void main() {
  // Installs fake_cloud_firestore's FieldValue factory before any test builds
  // a FieldValue (foldLegacy uses FieldValue.delete()).
  setUpAll(FakeFirebaseFirestore.new);

  group('AccountSettingsSchema.merge', () {
    test('deep-merges nested maps and leaves inputs untouched', () {
      final base = {
        'chat': {'a': 1, 'b': 2},
        'x': 1,
      };
      final out = AccountSettingsSchema.merge(base, {
        'chat': {'b': 3},
        'y': 2,
      });
      expect(out, {
        'chat': {'a': 1, 'b': 3},
        'x': 1,
        'y': 2,
      });
      expect(base['chat'], {'a': 1, 'b': 2});
    });
  });

  group('AccountSettingsSchema.resolve', () {
    test('missing doc resolves to the defaults', () {
      final s = AccountSettingsSchema.resolve(null);
      expect(AccountSettingsSchema.category(s, 'notifications')['pushEnabled'], isTrue);
      expect(AccountSettingsSchema.category(s, 'publishing')['crossPostPlatforms'], isEmpty);
      expect(s.containsKey(AccountSettingsSchema.schemaKey), isFalse);
    });

    test('reads renamed notification keys forward', () {
      final s = AccountSettingsSchema.resolve({
        'notifications': {'inAppBannerEnabled': false, 'showNumberBadges': false, 'notificationTone': 'silent'},
      });
      final n = AccountSettingsSchema.category(s, 'notifications');
      expect(n['inAppEnabled'], isFalse);
      expect(n['showBadges'], isFalse);
      expect(n['ringtone'], 'silent');
      expect(n.containsKey('inAppBannerEnabled'), isFalse);
    });

    test('a new key wins over its old name', () {
      final s = AccountSettingsSchema.resolve({
        'notifications': {'inAppBannerEnabled': false, 'inAppEnabled': true},
      });
      expect(AccountSettingsSchema.category(s, 'notifications')['inAppEnabled'], isTrue);
    });
  });

  group('AccountSettingsSchema.foldLegacy', () {
    test('legacy values only fill fields the canonical doc lacks', () {
      final patch = AccountSettingsSchema.foldLegacy(
        {
          'privacy': {'readReceipts': false},
        },
        {
          'prefs': {'readReceipts': true, 'typingStatus': false, 'requirePasskey': true, 'language': 'sw', 'voiceSelection': 'default'},
        },
      );
      expect((patch['privacy'] as Map).containsKey('readReceipts'), isFalse);
      expect((patch['privacy'] as Map)['typingStatus'], isFalse);
      expect((patch['security'] as Map)['requirePasskey'], isTrue);
      expect((patch['appearance'] as Map)['language'], 'sw');
      expect(patch.containsKey('ai'), isFalse, reason: "'default' voice is not a choice");
      expect(patch[AccountSettingsSchema.schemaKey], AccountSettingsSchema.version);
    });

    test('server-read notification doc wins and old keys are deleted', () {
      final patch = AccountSettingsSchema.foldLegacy(
        {
          'notifications': {'inAppBannerEnabled': true, 'pushEnabled': true},
        },
        {
          'notifications': {'inAppEnabled': false, 'pushEnabled': false, 'categoryOverrides': {'mention': false}},
        },
      );
      final n = patch['notifications'] as Map;
      expect(n['inAppEnabled'], isFalse);
      expect(n['pushEnabled'], isFalse);
      expect(n['categoryOverrides'], {'mention': false});
      expect(n['inAppBannerEnabled'], isA<FieldValue>());
    });

    test('old canonical key carries over when no server value exists', () {
      final patch = AccountSettingsSchema.foldLegacy(
        {
          'notifications': {'showNumberBadges': false},
        },
        const {},
      );
      expect((patch['notifications'] as Map)['showBadges'], isFalse);
    });

    test('topic docs land in their own categories', () {
      final patch = AccountSettingsSchema.foldLegacy(const {}, {
        'ai_preferences': {'selectedVoice': 'Nova', 'selectedModel': 'm1'},
        'digital_wellbeing': {'feedMode': 'chronological'},
        'recommendations': {
          'hiddenTopics': ['x'],
        },
        'ai_personalization': {'learningEnabled': true},
        'agent_config': {'isGloballyPaused': true},
      });
      expect(patch['ai'], {'selectedVoice': 'Nova', 'selectedModel': 'm1'});
      expect(patch['wellbeing'], {'feedMode': 'chronological'});
      expect(patch['recommendations'], {
        'hiddenTopics': ['x'],
      });
      expect(patch['aiPersonalization'], {'learningEnabled': true});
      expect(patch['aiAgent'], {'isGloballyPaused': true});
    });
  });

  group('SettingsService (user_settings/{uid})', () {
    late FakeFirebaseFirestore db;
    late SettingsService service;
    const uid = 'u1';

    setUp(() {
      SettingsService.resetMigrationCache();
      db = FakeFirebaseFirestore();
      service = SettingsService(firestore: db);
    });

    test('first read folds the legacy docs into one store', () async {
      await db.doc('users/$uid/settings/prefs').set({'readReceipts': false, 'requirePasskey': true});
      await db.doc('users/$uid/settings/notifications').set({'pushEnabled': false, 'quietHoursStart': 23});
      await db.doc('users/$uid/ai_settings/agent_config').set({'isGloballyPaused': true});
      await db.doc('users/$uid/settings/digital_wellbeing').set({'screenTimeLimitMinutes': 45});

      final s = await service.getSettings(uid);
      expect(AccountSettingsSchema.category(s, 'privacy')['readReceipts'], isFalse);
      expect(AccountSettingsSchema.category(s, 'security')['requirePasskey'], isTrue);
      expect(AccountSettingsSchema.category(s, 'notifications')['pushEnabled'], isFalse);
      expect(AccountSettingsSchema.category(s, 'notifications')['quietHoursStart'], 23);
      expect(AccountSettingsSchema.category(s, 'aiAgent')['isGloballyPaused'], isTrue);
      expect(AccountSettingsSchema.category(s, 'wellbeing')['screenTimeLimitMinutes'], 45);

      final stored = (await db.doc('user_settings/$uid').get()).data()!;
      expect(stored[AccountSettingsSchema.schemaKey], AccountSettingsSchema.version);
      // Defaults were materialized for the new account.
      expect((stored['chat'] as Map)['showComposeFab'], isTrue);
    });

    test('existing doc: renamed keys are moved, not duplicated', () async {
      await db.doc('user_settings/$uid').set({
        'notifications': {'inAppBannerEnabled': false},
        'chat': {'enterIsSend': true},
      });
      await service.getSettings(uid);
      final n = ((await db.doc('user_settings/$uid').get()).data()!['notifications'] as Map);
      expect(n['inAppEnabled'], isFalse);
      expect(n.containsKey('inAppBannerEnabled'), isFalse);
    });

    test('migration runs once; later legacy writes do not override', () async {
      await db.doc('users/$uid/settings/prefs').set({'readReceipts': false});
      await service.getSettings(uid);
      await service.updateSettingsCategory(uid, 'privacy', {'readReceipts': true});
      await db.doc('users/$uid/settings/prefs').set({'readReceipts': false});

      SettingsService.resetMigrationCache();
      final s = await service.getSettings(uid);
      expect(AccountSettingsSchema.category(s, 'privacy')['readReceipts'], isTrue);
    });

    test('notification and agent writes are mirrored for the deployed functions', () async {
      await service.updateSettingsCategory(uid, 'notifications', {
        'pushEnabled': false,
        'categoryOverrides': {'mention': false},
      });
      await service.updateSettingsCategory(uid, 'aiAgent', {'isGloballyPaused': true});
      await service.updateSettingsCategory(uid, 'chat', {'enterIsSend': true});

      expect((await db.doc('users/$uid/settings/notifications').get()).data(), {
        'pushEnabled': false,
        'categoryOverrides': {'mention': false},
      });
      expect((await db.doc('users/$uid/ai_settings/agent_config').get()).data(), {'isGloballyPaused': true});
      expect((await db.doc('users/$uid/settings/chat').get()).exists, isFalse);

      final stored = (await db.doc('user_settings/$uid').get()).data()!;
      expect((stored['chat'] as Map)['enterIsSend'], isTrue);
    });

    test('nested writes merge instead of replacing the map', () async {
      await service.updateSettingsCategory(uid, 'notifications', {
        'categoryOverrides': {'mention': false},
      });
      await service.updateSettingsCategory(uid, 'notifications', {
        'categoryOverrides': {'like': false},
      });
      final s = await service.getSettings(uid);
      expect(AccountSettingsSchema.category(s, 'notifications')['categoryOverrides'], {'mention': false, 'like': false});
    });

    test('a write from one screen reaches every listener of the account', () async {
      await service.getSettings(uid);
      final screenA = service.watchCategory(uid, 'publishing');
      final screenB = service.watchSettings(uid).map((s) => NotificationPreferences.fromMap(Map<String, dynamic>.from(s['notifications'] as Map)));

      final seenA = screenA.firstWhere((p) => (p['crossPostPlatforms'] as List).contains('youtube')).timeout(const Duration(seconds: 5));
      final seenB = screenB.firstWhere((p) => p.pushEnabled == false).timeout(const Duration(seconds: 5));

      await service.updateSettings(uid, {
        'publishing': {
          'crossPostPlatforms': ['youtube'],
        },
        'notifications': {'pushEnabled': false},
      });

      expect((await seenA)['crossPostPlatforms'], ['youtube']);
      expect((await seenB).pushEnabled, isFalse);
    });
  });
}
