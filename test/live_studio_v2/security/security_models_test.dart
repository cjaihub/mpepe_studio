import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/media/studio_media_api.dart';
import 'package:oneova/backend/live_studio/security/studio_security_models.dart';

void main() {
  final key32 = base64.encode(List<int>.generate(32, (i) => i));

  group('StudioMediaKey', () {
    test('parses a 32-byte key and index', () {
      final k = StudioMediaKey.fromJson({'key': key32, 'keyIndex': 3})!;
      expect(k.bytes.length, 32);
      expect(k.bytes[5], 5);
      expect(k.keyIndex, 3);
    });

    test('rejects malformed keys', () {
      expect(StudioMediaKey.fromJson(null), isNull);
      expect(StudioMediaKey.fromJson({'key': base64.encode([1, 2, 3]), 'keyIndex': 0}), isNull);
      expect(StudioMediaKey.fromJson({'key': '%%%not base64', 'keyIndex': 0}), isNull);
      expect(StudioMediaKey.fromJson({'key': key32}), isNull);
      expect(StudioMediaKey.fromJson({'key': key32, 'keyIndex': -1}), isNull);
    });

    test('lsToken credentials carry the key; absent when E2EE is off', () {
      final on = StudioJoinCredentials.fromJson({'url': 'wss://x', 'token': 't', 'role': 'viewer', 'e2ee': {'key': key32, 'keyIndex': 0}});
      expect(on.e2ee, isNotNull);
      final off = StudioJoinCredentials.fromJson({'url': 'wss://x', 'token': 't', 'role': 'viewer', 'e2ee': null});
      expect(off.e2ee, isNull);
    });
  });

  group('StudioAdvisory', () {
    test('keeps only allow-listed actions with their targets, max 3', () {
      final a = StudioAdvisory.fromJson({
        'id': 'adv_1',
        'atMs': 5,
        'severity': 'critical',
        'assessment': 'Raid.',
        'source': 'ai',
        'actions': [
          {'type': 'delete_everything'},
          {'type': 'block_user'}, // no target
          {'type': 'block_user', 'targetUid': 'u1', 'targetName': 'Bo'},
          {'type': 'slow_mode', 'targetUid': 'ignored'},
          {'type': 'followers_only'},
          {'type': 'end_live'},
        ],
      });
      expect(a.severity, StudioSeverity.critical);
      expect(a.fromAi, isTrue);
      expect(a.actions.map((x) => x.type), [
        StudioAdvisoryActionType.blockUser,
        StudioAdvisoryActionType.slowMode,
        StudioAdvisoryActionType.followersOnly,
      ]);
      expect(a.actions[0].label, 'Block Bo');
      expect(a.actions[1].targetUid, isNull);
    });
  });

  group('StudioSecurityPacket', () {
    List<int> bytes(Object o) => utf8.encode(jsonEncode(o));

    test('key.update carries only the index', () {
      final p = StudioSecurityPacket.decodeBytes(bytes({'v': 1, 'type': 'key.update', 'keyIndex': 4}));
      expect(p, isA<KeyUpdatePacket>());
      expect((p as KeyUpdatePacket).keyIndex, 4);
    });

    test('advisory packet', () {
      final p = StudioSecurityPacket.decodeBytes(bytes({
        'v': 1,
        'type': 'security.advisory',
        'advisory': {'id': 'adv_9', 'atMs': 9, 'severity': 'warn', 'assessment': 'x', 'actions': [], 'source': 'rules'},
      }));
      expect((p as AdvisoryPacket).advisory.id, 'adv_9');
    });

    test('unknown or malformed packets are ignored', () {
      expect(StudioSecurityPacket.decodeBytes(bytes({'type': 'other'})), isNull);
      expect(StudioSecurityPacket.decodeBytes(bytes({'type': 'key.update'})), isNull);
      expect(StudioSecurityPacket.decodeBytes(utf8.encode('not json')), isNull);
      expect(StudioSecurityPacket.decodeBytes(bytes([1, 2])), isNull);
    });
  });
}
