// Guard test: fails if an agent reverts the locked Oneova home/nav/brand.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String read(String p) => File(p).readAsStringSync();

void main() {
  final router = read('lib/shared/router.dart');
  final theme = read('lib/shared/theme/app_theme.dart');

  test('/hub/home renders ShortVideoFeedScreen', () {
    final i = router.indexOf("path: '/hub/home'");
    expect(i, greaterThan(0));
    // The home builder reads a few deep-link parameters (reel, comments) first.
    expect(router.substring(i, i + 900), contains('ShortVideoFeedScreen'));
    expect(router, isNot(contains('HubHomeScreen()')));
  });

  test('splash is the initial route and registered', () {
    expect(router, contains("'/splash'"));
    expect(router, contains('AnimatedSplashScreen'));
  });

  test('HubShell uses OneovaBottomNav', () {
    expect(router, contains('OneovaBottomNav('));
  });

  test('required routes exist', () {
    for (final r in ['/biz_feed', '/hub/discover', '/notifications', '/profile/me', '/hub/messages', '/hub/ai']) {
      expect(router, contains("'$r'"), reason: 'missing route $r');
    }
  });

  test('nav labels intact', () {
    final nav = read('lib/shared/widgets/oneova_bottom_nav.dart');
    for (final l in ["'Reels'", "'Chat'", "'STUDIO'", "'Wallet'", "'Me'"]) {
      expect(nav, contains(l));
    }
  });

  test('brand colors: blue primary, pink accent, no maroon', () {
    expect(theme, contains('brandBlue = Color(0xFF0C4FA8)'));
    expect(theme, contains('brandPink'));
    expect(theme.toLowerCase(), isNot(contains('mpepemaroon')));
  });

  test('banned lucide_icons not used', () {
    expect(read('pubspec.yaml'), isNot(contains('lucide_icons')));
  });
}
