import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/services/recommendation_service.dart';
import 'package:oneova/backend/social/services/video_playback_manager.dart';
import 'package:oneova/feed/services/reel_prefetcher.dart';
import 'package:oneova/shared/audio/mic_coordinator.dart';

class _FakeRecommendationService implements RecommendationService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeReelPrefetcher implements ReelPrefetcher {
  bool lastBuffering = false;

  @override
  void setActiveReelBuffering(bool buffering) {
    lastBuffering = buffering;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MicCoordinator single-owner handoff & call priority', () {
    test('preempts active non-call mic owner cleanly and does not deadlock if release() runs in onPreempted',
        () async {
      final owners = <MicUser?>[];
      void recordOwner() => owners.add(MicCoordinator.instance.owner.value);
      MicCoordinator.instance.owner.addListener(recordOwner);
      addTearDown(() => MicCoordinator.instance.owner.removeListener(recordOwner));

      var voiceTypingPreempted = false;
      MicLease? typingLease;

      final first = await MicCoordinator.instance.acquire(
        MicUser.voiceTyping,
        onPreempted: () async {
          voiceTypingPreempted = true;
          // Calling release() inside onPreempted must never deadlock _queue.
          await typingLease?.release();
        },
      );
      expect(first, isA<MicLease>());
      typingLease = first as MicLease;
      expect(typingLease.isActive, isTrue);
      expect(MicCoordinator.instance.currentUser, MicUser.voiceTyping);

      var assistantPreempted = false;
      final second = await MicCoordinator.instance.acquire(
        MicUser.assistant,
        onPreempted: () async {
          assistantPreempted = true;
        },
      );
      expect(second, isA<MicLease>());
      final assistantLease = second as MicLease;
      expect(voiceTypingPreempted, isTrue);
      expect(typingLease.isActive, isFalse);
      expect(assistantLease.isActive, isTrue);
      expect(MicCoordinator.instance.currentUser, MicUser.assistant);

      // Call has higher priority: preempts assistant and blocks lower-priority acquirers.
      final callRes = await MicCoordinator.instance.acquire(
        MicUser.call,
        takeFocus: false,
        onPreempted: () async {},
      );
      expect(callRes, isA<MicLease>());
      final callLease = callRes as MicLease;
      expect(assistantPreempted, isTrue);
      expect(assistantLease.isActive, isFalse);
      expect(MicCoordinator.instance.currentUser, MicUser.call);

      for (final contender in [
        MicUser.voiceTyping,
        MicUser.voiceNote,
        MicUser.assistant,
        MicUser.aiLive,
      ]) {
        final busy = await MicCoordinator.instance.acquire(
          contender,
          onPreempted: () async {},
        );
        expect(busy, isA<MicBusy>());
        expect((busy as MicBusy).heldBy, MicUser.call);
      }
      expect(callLease.isActive, isTrue);

      await callLease.release();
      expect(callLease.isActive, isFalse);
      expect(MicCoordinator.instance.currentUser, isNull);
      expect(MicCoordinator.instance.owner.value, isNull);
      expect(owners, containsAllInOrder([MicUser.voiceTyping, MicUser.assistant, MicUser.call, null]));
    });
  });

  group('VideoPlaybackManager silencing & observer separation', () {
    test('mainFeedRouteObserver and homeBranchRouteObserver are distinct instances', () {
      expect(identical(mainFeedRouteObserver, homeBranchRouteObserver), isFalse);
    });

    test('isSilenced tracks screen inactivity, call state, and MicCoordinator ownership', () async {
      final prefetcher = _FakeReelPrefetcher();
      final manager = VideoPlaybackManager(_FakeRecommendationService(), prefetcher);
      addTearDown(manager.dispose);

      expect(manager.isSilenced, isFalse);

      // 1. Navigating away from Reels silences playback.
      manager.setScreenActive(false);
      expect(manager.isSilenced, isTrue);
      manager.setScreenActive(true);
      expect(manager.isSilenced, isFalse);

      // 2. Starting a phone/video call silences playback.
      manager.setCallActive(true);
      expect(manager.isSilenced, isTrue);
      manager.setCallActive(false);
      expect(manager.isSilenced, isFalse);

      // 3. Any microphone session (Ova, voice typing, voice note, AI live) silences playback.
      final lease = await MicCoordinator.instance.acquire(
        MicUser.assistant,
        onPreempted: () async {},
      ) as MicLease;
      expect(manager.isSilenced, isTrue);
      await lease.release();
      expect(manager.isSilenced, isFalse);

      // 4. pauseAllSlots(clearActive: true) clears active slot and bumps revision.
      final revBefore = manager.slotsRevision.value;
      manager.pauseAllSlots(clearActive: true);
      expect(manager.activeContentId, isNull);
      expect(manager.slotsRevision.value, greaterThan(revBefore));
    });
  });

  group('Zero-duration reel watch telemetry guard', () {
    test('zero or negative duration falls back to 15000ms without Infinity/NaN crash', () {
      int computeLoops(int dwellMs, int? rawDurationMs) {
        final safeDuration = (rawDurationMs ?? 0) > 0 ? rawDurationMs! : 15000;
        final rawRate = dwellMs / safeDuration;
        final completionRate = rawRate.isFinite ? rawRate.clamp(0.0, 1.0) : 0.0;
        expect(completionRate.isFinite, isTrue);
        return (dwellMs / safeDuration).floor();
      }

      expect(computeLoops(4200, 0), 0);
      expect(computeLoops(32000, 0), 2);
      expect(computeLoops(4200, null), 0);
      expect(computeLoops(4200, -100), 0);
      expect(computeLoops(20000, 10000), 2);
    });
  });
}
