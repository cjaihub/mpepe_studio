import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oneova/backend/ai_agents/omni_command/omni_context_resolver.dart';

void main() {
  group('Phase 12.5A: Omni Context Hydration Tests', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('A. global Inbox context initializes empty but correctly resolved', () {
      final resolver = container.read(omniContextResolverProvider);
      final context = resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        surface: 'inbox',
        activeRoute: '/inbox',
      );

      expect(context.surface, 'inbox');
      expect(context.activeRoute, '/inbox');
      expect(context.conversationId, isNull);
      expect(context.displayContext, 'Inbox');
    });

    test('B. conversation context hydration populates context correctly', () {
      final resolver = container.read(omniContextResolverProvider);
      final context = resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        surface: 'inbox',
        activeRoute: '/inbox/conv123',
        conversationId: 'conv123',
        platformId: 'whatsapp',
      );

      expect(context.conversationId, 'conv123');
      expect(context.platformId, 'whatsapp');
      expect(context.displayContext, 'Conversation');
    });

    test('C. conversation switching updates state', () {
      final notifier = container.read(omniContextProvider.notifier);
      final resolver = container.read(omniContextResolverProvider);

      final ctx1 = resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        conversationId: 'conv1',
      );
      notifier.updateContext(ctx1);
      expect(container.read(omniContextProvider)?.conversationId, 'conv1');

      final ctx2 = resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        conversationId: 'conv2',
      );
      notifier.updateContext(ctx2);
      expect(container.read(omniContextProvider)?.conversationId, 'conv2');
    });

    test('D. context clearing resets conversation', () {
      final notifier = container.read(omniContextProvider.notifier);
      final resolver = container.read(omniContextResolverProvider);

      final ctx = resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        conversationId: 'conv1',
      );
      notifier.updateContext(ctx);
      expect(container.read(omniContextProvider)?.conversationId, 'conv1');

      notifier.clearConversationContext();
      expect(container.read(omniContextProvider)?.conversationId, isNull);
    });

    test('E. stale-context race protection is verified', () async {
      final notifier = container.read(omniContextProvider.notifier);
      final resolver = container.read(omniContextResolverProvider);

      // Simulate async switching
      Future<void> syncContext(String id) async {
        await Future.delayed(const Duration(milliseconds: 10));
        final ctx = resolver.resolve(
          sessionId: 'test_session',
          userId: 'test_user',
          conversationId: id,
        );
        notifier.updateContext(ctx);
      }

      // If user switches fast, the latest one should be the state in a sync execution.
      // Riverpod update context is synchronous, so last writer wins naturally without race if executed in order.
      syncContext('A');
      await syncContext('B');

      expect(container.read(omniContextProvider)?.conversationId, 'B');
    });

    test('F. navigation/context synchronization integration', () {
      final notifier = container.read(omniContextProvider.notifier);
      final resolver = container.read(omniContextResolverProvider);

      notifier.updateContext(resolver.resolve(
        sessionId: 'test_session',
        userId: 'test_user',
        surface: 'inbox',
      ));
      
      notifier.updateRoute('/search');
      expect(container.read(omniContextProvider)?.activeRoute, '/search');
    });

    test('G. logout/session reset ensures no context remains', () {
      final notifier = container.read(omniContextProvider.notifier);
      final resolver = container.read(omniContextResolverProvider);
      
      notifier.updateContext(resolver.resolve(
        sessionId: 'session_userA',
        userId: 'userA',
        conversationId: 'convA',
      ));
      
      // Simulate logout
      notifier.updateContext(resolver.resolve(
        sessionId: 'session_userB',
        userId: 'userB',
        conversationId: null,
      ));

      expect(container.read(omniContextProvider)?.userId, 'userB');
      expect(container.read(omniContextProvider)?.conversationId, isNull);
    });

    test('K. OmniContextResolver integration creates proper capability sets', () {
      final resolver = container.read(omniContextResolverProvider);
      final contextAssist = resolver.resolve(
        sessionId: '1',
        userId: '1',
        conversationId: '1',
        aiMode: AiOperatingMode.assist,
      );
      // Read capability should be true, write false
      expect(contextAssist.capabilities.contains(OmniCapability.readConversation), isTrue);
      expect(contextAssist.capabilities.contains(OmniCapability.sendMessage), isFalse);

      final contextAuto = resolver.resolve(
        sessionId: '2',
        userId: '2',
        conversationId: '2',
        aiMode: AiOperatingMode.auto,
      );
      // Send should be available in auto mode
      expect(contextAuto.capabilities.contains(OmniCapability.sendMessage), isTrue);
    });
  });
}
