import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/security/studio_security_api.dart';
import 'package:oneova/backend/live_studio/security/studio_security_controller.dart';
import 'package:oneova/backend/live_studio/security/studio_security_models.dart';

import 'fakes/fake_security.dart';

void main() {
  late FakeSecuritySource source;
  late FakeCallPort calls;
  late StreamController<StudioSecurityPacket> packets;
  late ProviderContainer c;

  setUp(() {
    source = FakeSecuritySource(advisories: [advisory(id: 'adv_old', atMs: 100)]);
    calls = FakeCallPort();
    packets = StreamController<StudioSecurityPacket>.broadcast(sync: true);
    c = ProviderContainer(overrides: securityOverrides(source: source, calls: calls, packets: packets));
  });

  tearDown(() async {
    c.dispose();
    await packets.close();
  });

  Future<StudioAdvisory?> current() async {
    final sub = c.listen(studioCurrentAdvisoryProvider(kStream), (_, _) {});
    await c.read(studioSecurityAdvisoriesProvider(kStream).future);
    await Future<void>.delayed(Duration.zero);
    final v = c.read(studioCurrentAdvisoryProvider(kStream));
    sub.close();
    return v;
  }

  test('shows the newest advisory; live packets win; dismiss hides it', () async {
    c.listen(studioSecurityControllerProvider(kStream), (_, _) {});
    expect((await current())!.id, 'adv_old');
    packets.add(AdvisoryPacket(advisory(id: 'adv_new', atMs: 500)));
    expect((await current())!.id, 'adv_new');
    c.read(studioSecurityControllerProvider(kStream).notifier).dismiss('adv_new');
    expect((await current())!.id, 'adv_old');
    c.read(studioSecurityControllerProvider(kStream).notifier).dismiss('adv_old');
    expect(await current(), isNull);
  });

  test('key-update packets are not advisories', () async {
    c.listen(studioSecurityControllerProvider(kStream), (_, _) {});
    packets.add(const KeyUpdatePacket(2));
    expect(c.read(studioSecurityControllerProvider(kStream)).live, isEmpty);
  });

  test('nothing runs when the confirmation is cancelled', () async {
    final ctl = c.read(studioSecurityControllerProvider(kStream).notifier);
    final a = advisory();
    final confirm = FakeConfirm(false);
    expect(await ctl.apply(a, a.actions.first, confirm: confirm.call), isFalse);
    expect(confirm.prompts.single.title, 'Mute Ana in chat?');
    expect(calls.calls, isEmpty);
  });

  test('every allow-listed action maps to its callable after confirmation', () async {
    final a = advisory(actions: [
      {'type': 'mute_user', 'targetUid': 'u1', 'targetName': 'Ana'},
    ]);
    final cases = <StudioAdvisoryAction, (String, Map<String, dynamic>)>{
      const StudioAdvisoryAction(StudioAdvisoryActionType.muteUser, targetUid: 'u1'):
          (StudioCallables.muteChat, {'streamId': kStream, 'uid': 'u1', 'minutes': kAdvisoryMuteMinutes}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.removeFromStage, targetUid: 'u2'):
          (StudioCallables.moderate, {'streamId': kStream, 'uid': 'u2', 'action': 'removeFromStage'}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.blockUser, targetUid: 'u3'):
          (StudioCallables.moderate, {'streamId': kStream, 'uid': 'u3', 'action': 'block'}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.slowMode):
          (StudioSecurityWire.setChatMode, {'streamId': kStream, 'mode': 'slow', 'slowSeconds': kAdvisorySlowModeSeconds}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.followersOnly):
          (StudioSecurityWire.setChatMode, {'streamId': kStream, 'mode': 'followers'}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.pauseJoinRequests):
          (StudioSecurityWire.setJoinRequests, {'streamId': kStream, 'open': false}),
      const StudioAdvisoryAction(StudioAdvisoryActionType.endLive): (StudioCallables.end, {'streamId': kStream}),
    };
    final ctl = c.read(studioSecurityControllerProvider(kStream).notifier);
    final confirm = FakeConfirm(true);
    for (final e in cases.entries) {
      calls.calls.clear();
      expect(await ctl.apply(a, e.key, confirm: confirm.call), isTrue, reason: e.key.type.wire);
      expect(calls.calls.single.$1, e.value.$1);
      expect(calls.calls.single.$2, e.value.$2);
      expect(ctl.isDone(a, e.key), isTrue);
    }
    expect(confirm.prompts.length, cases.length); // every action was confirmed
    // Done actions do not run twice.
    calls.calls.clear();
    expect(await ctl.apply(a, cases.keys.first, confirm: confirm.call), isFalse);
    expect(calls.calls, isEmpty);
  });

  test('a failing callable surfaces an error and can be retried', () async {
    calls.on(StudioCallables.muteChat, (_) => throw StateError('boom'));
    final ctl = c.read(studioSecurityControllerProvider(kStream).notifier);
    final a = advisory();
    expect(await ctl.apply(a, a.actions.first, confirm: FakeConfirm(true).call), isFalse);
    expect(c.read(studioSecurityControllerProvider(kStream)).error, isNotNull);
    expect(ctl.isDone(a, a.actions.first), isFalse);
    expect(ctl.isBusy(a, a.actions.first), isFalse);
  });

  test('prompts: destructive except chat modes', () {
    for (final t in StudioAdvisoryActionType.values) {
      final p = advisoryPrompt(StudioAdvisoryAction(t, targetUid: 'u', targetName: 'Bo'));
      final soft = t == StudioAdvisoryActionType.slowMode || t == StudioAdvisoryActionType.followersOnly;
      expect(p.destructive, !soft, reason: t.wire);
      expect(p.title, isNotEmpty);
    }
  });
}
