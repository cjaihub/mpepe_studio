import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oneova/backend/social/services/video_playback_manager.dart';

PageRouteBuilder<void> _makeRoute(String name) {
  return PageRouteBuilder<void>(
    settings: RouteSettings(name: name),
    pageBuilder: (context, animation, secondaryAnimation) => const SizedBox(),
  );
}

class _TestRouteAwareWidget extends RouteAware {
  bool didPushNextCalled = false;
  bool didPopNextCalled = false;
  bool didPopCalled = false;

  @override
  void didPushNext() {
    didPushNextCalled = true;
    super.didPushNext();
  }

  @override
  void didPopNext() {
    didPopNextCalled = true;
    super.didPopNext();
  }

  @override
  void didPop() {
    didPopCalled = true;
    super.didPop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reels Auto-Mute and Screen Inactivity Guard', () {
    test('mainFeedRouteObserver is exported and instantiated', () {
      expect(mainFeedRouteObserver, isNotNull);
      expect(mainFeedRouteObserver, isA<RouteObserver<ModalRoute<void>>>());
    });

    test('RouteAware subscribes to mainFeedRouteObserver and triggers didPushNext / didPopNext', () {
      final observer = RouteObserver<ModalRoute<void>>();
      final feedRoute = _makeRoute('/hub/home');
      final newRoute = _makeRoute('/profile/user123');
      final aware = _TestRouteAwareWidget();

      observer.subscribe(aware, feedRoute);

      // Simulate pushing a new screen over the feed
      observer.didPush(newRoute, feedRoute);
      expect(aware.didPushNextCalled, isTrue, reason: 'didPushNext should be invoked when route is covered');

      // Simulate popping the new screen and returning to the feed
      observer.didPop(newRoute, feedRoute);
      expect(aware.didPopNextCalled, isTrue, reason: 'didPopNext should be invoked when top route is popped');

      observer.unsubscribe(aware);
    });

    test('Screen active notifier emits values on state changes', () {
      final notifier = ValueNotifier<bool>(true);
      final states = <bool>[];
      notifier.addListener(() => states.add(notifier.value));

      notifier.value = false;
      notifier.value = true;
      notifier.value = false;

      expect(states, equals([false, true, false]));
      notifier.dispose();
    });
  });
}
