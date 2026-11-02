import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bottom Nav Auto-Hide & Chat Panel Cleanliness', () {
    final routerContent = File('lib/shared/router.dart').readAsStringSync();
    final messagingContent = File('lib/hub/messaging/in_app_messaging_screen.dart').readAsStringSync();
    final chatDetailContent = File('lib/hub/messaging/chat_detail_screen.dart').readAsStringSync();

    test('HubShell hides bottom navigation when not on home or in focus mode', () {
      expect(routerContent, contains('final isHome = widget.navigationShell.currentIndex == 0;'));
      expect(routerContent, contains('final shouldHide = !isHome || isFocusMode;'));
    });

    test('Chat panel and other tabs have no bottom navigation menus rendered under them in HubShell', () {
      expect(routerContent, contains('bottomNavigationBar: !isHome'));
      expect(routerContent, contains('? null'));
    });

    test('InAppMessagingScreen uses top section tabs and removes bottom navigation bar under chat', () {
      // Confirms top tabs are used
      expect(messagingContent, contains('_buildTopSectionTabs(chatsAsync)'));
      // Confirms _buildBottomNavigationBar is not placed at the bottom of the body
      expect(messagingContent, isNot(contains('// WhatsApp Style 4-Tab Bottom Navigation Bar')));
      expect(messagingContent, isNot(contains('_buildBottomNavigationBar(chatsAsync)')));
    });

    test('Promotional banner is not auto-popped in InAppMessagingScreen', () {
      expect(messagingContent, isNot(contains('if (!_isBannerDismissed && showCreatorProBanner)')));
    });

    test('ChatDetailScreen starts with banner collapsed to avoid auto-popping over messages', () {
      expect(chatDetailContent, contains('bool _bannerCollapsed = true;'));
    });
  });
}

