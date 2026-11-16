import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oneova/backend/messaging_repository.dart';
import 'package:oneova/hub/messaging/widgets/chat_local_preview_store.dart';
import 'package:oneova/hub/messaging/widgets/chat_reaction_strip.dart';
import 'package:oneova/shared/theme/app_theme.dart';

void main() {
  group('ChatModel read/delivery & typing state', () {
    test('new outgoing message is not falsely marked read before recipient opens it', () {
      final t1 = Timestamp.fromDate(DateTime(2026, 11, 17, 10, 0));
      final chat = ChatModel(
        id: 'c1',
        participants: const ['alice', 'bob'],
        lastMessage: 'hi',
        unreadCounts: const {'alice': 0, 'bob': 1},
      );
      final msgEmptyReadBy = MessageModel(
        id: 'm1',
        senderId: 'alice',
        text: 'hi',
        timestamp: t1,
        readBy: const [],
      );
      final msgLegacySelfRead = msgEmptyReadBy.copyWith(readBy: const ['alice']);

      expect(chat.isMessageReadByOther(msgEmptyReadBy, 'alice'), isFalse);
      expect(chat.isMessageReadByOther(msgLegacySelfRead, 'alice'), isFalse);
      expect(chat.isMessageDeliveredToOther(msgEmptyReadBy, 'alice'), isFalse);
    });

    test('read and delivered watermarks mark earlier outgoing messages accurately', () {
      final tMsg = Timestamp.fromDate(DateTime(2026, 11, 17, 10, 0, 0));
      final tDelivered = Timestamp.fromDate(DateTime(2026, 11, 17, 10, 0, 5));
      final tRead = Timestamp.fromDate(DateTime(2026, 11, 17, 10, 0, 10));

      final msg = MessageModel(
        id: 'm2',
        senderId: 'alice',
        text: 'hello',
        timestamp: tMsg,
        readBy: const [],
      );

      final deliveredOnlyChat = ChatModel(
        id: 'c1',
        participants: const ['alice', 'bob'],
        lastMessage: 'hello',
        unreadCounts: const {'alice': 0, 'bob': 1},
        deliveredWatermarks: {'bob': tDelivered},
      );
      expect(deliveredOnlyChat.isMessageDeliveredToOther(msg, 'alice'), isTrue);
      expect(deliveredOnlyChat.isMessageReadByOther(msg, 'alice'), isFalse);

      final readChat = deliveredOnlyChat.copyWith(readWatermarks: {'bob': tRead});
      expect(readChat.isMessageReadByOther(msg, 'alice'), isTrue);
    });

    test('activeTypingUsers ignores self and expires stale typing heartbeats (>10s)', () {
      final nowMs = 1_000_000;
      final chat = ChatModel(
        id: 'c2',
        participants: const ['me', 'freshUser', 'staleUser'],
        lastMessage: '',
        unreadCounts: const {},
        typingUsers: const ['me', 'freshUser', 'staleUser'],
        typingAt: {
          'me': nowMs,
          'freshUser': nowMs - 3000,
          'staleUser': nowMs - 15000,
        },
      );

      expect(chat.activeTypingUsers('me', nowMs: nowMs), equals(['freshUser']));
    });

    test('MessageModel.copyWith preserves safety, edited, expiresAt and localStatus', () {
      final expires = Timestamp.fromDate(DateTime(2026, 11, 18));
      final original = MessageModel(
        id: 'm3',
        senderId: 'u1',
        text: 'check',
        timestamp: Timestamp.now(),
        readBy: const [],
        safety: const {'verdict': 'warn'},
        edited: true,
        expiresAt: expires,
        localStatus: 'failed',
      );
      final updated = original.copyWith(text: 'check 2');
      expect(updated.safety, equals({'verdict': 'warn'}));
      expect(updated.edited, isTrue);
      expect(updated.expiresAt, equals(expires));
      expect(updated.localStatus, equals('failed'));
    });
  });

  group('ChatLocalPreviewStore', () {
    test('stores encrypted preview locally and expires when newer server message arrives', () async {
      SharedPreferences.setMockInitialValues({});
      await ChatLocalPreviewStore.instance.ensureLoaded();
      await ChatLocalPreviewStore.instance.save('chat_e2ee', 'Meet at 5', 10000);

      expect(ChatLocalPreviewStore.instance.previewFor('chat_e2ee', 10000), 'Meet at 5');
      expect(ChatLocalPreviewStore.instance.previewFor('chat_e2ee', 25000), isNull);

      await ChatLocalPreviewStore.instance.remove('chat_e2ee');
      expect(ChatLocalPreviewStore.instance.previewFor('chat_e2ee', 10000), isNull);
    });
  });

  group('ChatReactionStrip UI (Light & Dark)', () {
    testWidgets('groups duplicate emojis with counts and toggles own reaction on tap', (tester) async {
      String? tappedEmoji;
      String? tappedMine;

      Widget wrap(ThemeData theme) {
        return MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ChatReactionStrip(
              reactions: const {'u1': '❤️', 'u2': '❤️', 'u3': '🔥'},
              myUid: 'u1',
              getUser: (_) async => null,
              onToggle: (emoji, mine) {
                tappedEmoji = emoji;
                tappedMine = mine;
              },
            ),
          ),
        );
      }

      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(wrap(theme));
        expect(find.text('❤️'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('🔥'), findsOneWidget);
      }

      await tester.tap(find.text('❤️'));
      expect(tappedEmoji, '❤️');
      expect(tappedMine, '❤️');
    });
  });
}
