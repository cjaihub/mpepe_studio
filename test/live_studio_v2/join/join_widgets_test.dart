import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/social_hub/live/studio_v2/join/join.dart';
import 'package:oneova/social_hub/live/studio_v2/theme/live_studio_tokens.dart';

import '../roles/fakes/fake_roles.dart';

class FakeDevicePreview implements StudioDevicePreview {
  FakeDevicePreview(this.perm);
  final StudioDevicePermissions perm;
  final List<String> log = [];
  final level = StreamController<double>.broadcast();

  @override
  Future<StudioDevicePermissions> requestPermissions() async => perm;
  @override
  Future<void> setCamera(bool on) async => log.add('cam:$on');
  @override
  Future<void> setMic(bool on) async => log.add('mic:$on');
  @override
  Widget? buildVideo() => const SizedBox(key: Key('fake-video'));
  @override
  Stream<double> get micLevel => level.stream;
  @override
  Future<void> openSettings() async => log.add('settings');
  @override
  Future<void> dispose() async => log.add('dispose');
}

const _granted = StudioDevicePermissions(camera: StudioDevicePermission.granted, microphone: StudioDevicePermission.granted);

void main() {
  late FakeFirebaseFirestore db;
  late FakeCallPort calls;
  late RecordingRoom room;
  late FakeDevicePreview preview;

  setUp(() {
    db = FakeFirebaseFirestore();
    calls = FakeCallPort();
    room = RecordingRoom();
    preview = FakeDevicePreview(_granted);
  });

  Future<void> pump(WidgetTester tester, Widget child, {LiveStudioTokens tokens = LiveStudioTokens.dark, String uid = 'me'}) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...rolesOverrides(db: db, calls: calls, room: room, rejoiner: FakeRejoiner(publish: true), uid: uid),
        studioDevicePreviewFactoryProvider.overrideWithValue(() => preview),
      ],
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> runAsyncSettle(WidgetTester tester) async {
    await tester.runAsync(() => settle());
    await tester.pumpAndSettle();
  }

  group('RequestToJoinButton', () {
    for (final compact in [false, true]) {
      for (final tokens in [LiveStudioTokens.dark, LiveStudioTokens.light]) {
        testWidgets('request → requested → cancel (${compact ? 'phone' : 'landscape'}, ${tokens.theme.name})',
            (tester) async {
          await pump(tester, RequestToJoinButton(streamId: kStream, tokens: tokens, compact: compact), tokens: tokens);
          final req = find.bySemanticsLabel(RequestToJoinLabels.request);
          expect(req, findsOneWidget);
          expect(tester.getSize(req).height, greaterThanOrEqualTo(44));
          if (!compact) expect(find.text(RequestToJoinLabels.request), findsOneWidget);
          await tester.tap(req);
          await tester.pumpAndSettle();
          expect(calls.count(StudioCallables.requestJoin), 1);
          expect(find.bySemanticsLabel(RequestToJoinLabels.requestedHint), findsOneWidget);
          await tester.tap(find.bySemanticsLabel(RequestToJoinLabels.requestedHint));
          await tester.pumpAndSettle();
          expect(calls.count(StudioCallables.cancelRequest), 1);
          expect(find.bySemanticsLabel(RequestToJoinLabels.request), findsOneWidget);
        });
      }
    }

    testWidgets('approval opens the device check; Go on stage publishes; then Leave stage (confirmed)', (tester) async {
      await pump(tester, const RequestToJoinButton(streamId: kStream, tokens: LiveStudioTokens.dark));
      await tester.runAsync(() => db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'}));
      await runAsyncSettle(tester);
      expect(find.text("You're approved"), findsOneWidget);
      expect(find.byKey(const Key('fake-video')), findsOneWidget);
      expect(preview.log, containsAll(['cam:true', 'mic:true']));

      await tester.tap(find.bySemanticsLabel(DeviceCheckLabels.goOnStage));
      await tester.pumpAndSettle();
      expect(preview.log, contains('dispose'));
      expect(room.log, ['cam:true', 'mic:true']);
      expect(find.text("You're approved"), findsNothing);

      // On stage → Leave stage needs a confirmation; Cancel keeps them on.
      await tester.tap(find.bySemanticsLabel(RequestToJoinLabels.leave));
      await tester.pumpAndSettle();
      expect(find.text('Leave the stage?'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.count(StudioCallables.leaveStage), 0);

      await tester.tap(find.bySemanticsLabel(RequestToJoinLabels.leave));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Leave stage').last);
      await tester.pumpAndSettle();
      expect(calls.count(StudioCallables.leaveStage), 1);
    });

    testWidgets('hidden for the host', (tester) async {
      await pump(tester, const RequestToJoinButton(streamId: kStream, tokens: LiveStudioTokens.dark), uid: 'host');
      await tester.runAsync(() => db.doc(memberPath('host')).set({'uid': 'host', 'role': 'host'}));
      await runAsyncSettle(tester);
      expect(find.bySemanticsLabel(RequestToJoinLabels.request), findsNothing);
    });
  });

  group('DeviceCheckSheet', () {
    testWidgets('denied camera: clear message, mic-only go on stage, settings for permanent denial', (tester) async {
      preview = FakeDevicePreview(const StudioDevicePermissions(
          camera: StudioDevicePermission.permanentlyDenied, microphone: StudioDevicePermission.granted));
      await pump(tester, const RequestToJoinButton(streamId: kStream, tokens: LiveStudioTokens.light));
      await tester.runAsync(() => db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'}));
      await runAsyncSettle(tester);
      expect(find.textContaining('Camera access is off'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(DeviceCheckLabels.openSettings));
      await tester.pump();
      expect(preview.log, contains('settings'));
      await tester.tap(find.bySemanticsLabel(DeviceCheckLabels.goOnStage));
      await tester.pumpAndSettle();
      expect(room.log, ['cam:false', 'mic:true']);
    });

    testWidgets('both denied: Go on stage disabled', (tester) async {
      preview = FakeDevicePreview(
          const StudioDevicePermissions(camera: StudioDevicePermission.denied, microphone: StudioDevicePermission.denied));
      await pump(tester, const RequestToJoinButton(streamId: kStream, tokens: LiveStudioTokens.dark));
      await tester.runAsync(() => db.doc(memberPath('me')).set({'uid': 'me', 'role': 'guest'}));
      await runAsyncSettle(tester);
      await tester.tap(find.bySemanticsLabel(DeviceCheckLabels.goOnStage), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(room.log, isEmpty);
      await tester.tap(find.bySemanticsLabel(DeviceCheckLabels.notNow));
      await tester.pumpAndSettle();
      expect(find.text("You're approved"), findsNothing);
      expect(find.bySemanticsLabel(RequestToJoinLabels.goOnStage), findsOneWidget);
    });
  });

  group('JoinRequestQueueSheet', () {
    for (final tokens in [LiveStudioTokens.dark, LiveStudioTokens.light]) {
      testWidgets('lists pending requests; approve / decline (${tokens.theme.name})', (tester) async {
        await tester.runAsync(() async {
          await db.doc(requestPath('a')).set(requestDoc('a', JoinRequestStatus.pending, at: 1));
          await db.doc(requestPath('b')).set(requestDoc('b', JoinRequestStatus.pending, at: 2));
        });
        await pump(tester, JoinRequestQueueSheet(streamId: kStream, tokens: tokens), tokens: tokens, uid: 'host');
        await runAsyncSettle(tester);
        expect(find.text('User a'), findsOneWidget);
        expect(find.text('User b'), findsOneWidget);
        final approve = find.bySemanticsLabel(JoinQueueLabels.approve('User a'));
        expect(tester.getSize(approve).height, greaterThanOrEqualTo(44));
        await tester.tap(approve);
        await tester.pumpAndSettle();
        expect(calls.calls.last.$2, {'streamId': kStream, 'uid': 'a', 'approve': true});
        expect(find.text('User a'), findsNothing, reason: 'answered rows hide immediately');
        await tester.tap(find.bySemanticsLabel(JoinQueueLabels.decline('User b')));
        await tester.pumpAndSettle();
        expect(calls.calls.last.$2['approve'], false);
        expect(find.text(JoinQueueLabels.empty), findsOneWidget);
      });
    }
  });

  group('ParticipantRowActions', () {
    testWidgets('host menu: block asks for confirmation before calling lsModerate', (tester) async {
      await pump(
        tester,
        const ParticipantRowActions(
          streamId: kStream,
          member: StageMember(uid: 'g', displayName: 'Gina', role: StudioRole.guest),
          myUid: 'host',
          myRole: StudioRole.host,
          onStage: true,
          tokens: LiveStudioTokens.dark,
        ),
        uid: 'host',
      );
      final menu = find.bySemanticsLabel(ParticipantRowActions.semanticsLabel('Gina'));
      expect(tester.getSize(menu).height, greaterThanOrEqualTo(44));
      await tester.tap(menu);
      await tester.pumpAndSettle();
      expect(find.text('Make co-host'), findsOneWidget);
      await tester.tap(find.text('Block from this live'));
      await tester.pumpAndSettle();
      expect(find.text('Block Gina?'), findsOneWidget);
      expect(calls.count(StudioCallables.moderate), 0);
      await tester.tap(find.bySemanticsLabel('Block'));
      await tester.pumpAndSettle();
      expect(calls.calls.single.$2, {'streamId': kStream, 'uid': 'g', 'action': 'block'});
    });

    testWidgets('nothing for a guest viewer of the row', (tester) async {
      await pump(
        tester,
        const ParticipantRowActions(
          streamId: kStream,
          member: StageMember(uid: 'g', displayName: 'Gina', role: StudioRole.guest),
          myUid: 'me',
          myRole: StudioRole.guest,
          onStage: true,
          tokens: LiveStudioTokens.dark,
        ),
      );
      expect(find.bySemanticsLabel(ParticipantRowActions.semanticsLabel('Gina')), findsNothing);
    });
  });
}
