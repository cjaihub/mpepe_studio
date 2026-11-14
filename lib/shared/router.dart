import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../auth/security/login_security.dart';
import '../backend/user_service.dart';
import '../shared/theme/app_theme.dart';
import 'package:go_router/go_router.dart';
import '../feed/main_feed_screen.dart';
import '../backend/social/services/video_playback_manager.dart';

import '../hub/messaging/chat_detail_screen.dart';
import '../hub/hub_ai_screen.dart';
import '../ova_assistant/widgets/ova_assistant_sheet.dart';
import '../ova_assistant/widgets/ova_floating_dock.dart' show OvaPopupObserver;

import '../hub/messaging/in_app_messaging_screen.dart';
import '../auth/main_login_screen.dart';
import '../auth/screens/workspace_locked_screen.dart';
import '../auth/services/app_lifecycle_observer.dart';
export '../auth/services/app_lifecycle_observer.dart' show rootNavigatorKey;
import '../desktop_agent/desktop_agent_screen.dart';
import 'splash/animated_splash_screen.dart';
import 'widgets/oneova_bottom_nav.dart';
import 'widgets/creation_type_modal.dart';
import 'widgets/oneova_profile_sidebar_drawer.dart';
import 'widgets/oneova_feature_tour_bubble.dart';
import 'services/oneova_feature_tour_service.dart';
import 'search/global_search_screen.dart';
import '../feed/biz_feed_screen.dart';
import '../social_hub/biz_commerce/checkout_screen.dart';
import '../social_hub/money/payments_history_screen.dart';
import '../social_hub/biz_commerce/order_screens.dart';
import '../shops3d/business/business_insights_screen.dart';
import '../shops3d/business/business_inventory_screen.dart';
import '../shops3d/business/business_orders_screen.dart';
import '../shops3d/business/business_portal_screen.dart';
import '../shops3d/business/business_settings_screen.dart';
import '../shops3d/data/model3d_repository.dart' show PublishedModel;
import '../shops3d/data/share_ref.dart';
import '../shops3d/screens/model_library_screen.dart';
import '../shops3d/screens/product_creator_screen.dart';
import '../shops3d/screens/product_editor_screen.dart';
import '../shops3d/screens/shop_product_screen.dart';
import '../shops3d/screens/shop_setup_wizard_screen.dart';
import '../shops3d/screens/shop_store_screen.dart';
import '../shops3d/screens/shops_feed_screen.dart';
import '../shops3d/widgets/customization_picker.dart' show decodeCustomization;
import '../social_hub/profile/public_profile_screen.dart';
import 'dart:io' show Platform;

import '../auth/signup_wizard_screen.dart';
import '../auth/pending_approval_screen.dart';
import '../auth/linked_devices/linked_devices_screen.dart';
import '../settings/main_settings_screen.dart';
import '../settings/screens/profile_settings_screen.dart';
import '../settings/screens/app_settings_screen.dart';
import '../settings/screens/chat_settings_screen.dart';
import '../settings/screens/notification_settings_screen.dart';
import '../settings/screens/ai_settings_screen.dart';
import '../settings/screens/privacy_security_screen.dart';
import '../settings/screens/follow_requests_screen.dart';
import '../settings/screens/blocked_users_screen.dart';
import '../settings/screens/data_export_screen.dart';
import '../settings/screens/appearance_settings_screen.dart';
import '../settings/screens/accessibility_settings_screen.dart';
import '../settings/screens/reels_playback_settings_screen.dart';
import '../settings/screens/calls_settings_screen.dart';
import '../settings/screens/storage_settings_screen.dart';
import '../settings/screens/camera_and_live_settings_screen.dart';
import '../settings/screens/legal_policies_screen.dart';
import '../settings/screens/admin_docs_cms_screen.dart';
import '../settings/screens/about_screen.dart';
import '../auth/screens/email_code_screen.dart';
import '../social_hub/gmail/gmail_screens.dart';
import '../ai_messaging/screens/live_voice_mode_screen.dart';
import '../ova_assistant/screens/ova_abilities_screen.dart';
import '../ova_assistant/screens/ova_setup_screen.dart';
import '../ova_assistant/screens/ova_trigger_settings_screen.dart';
import '../social_hub/social_integration_dashboard.dart';
import '../social_hub/google/google_services_screen.dart';
import '../social_hub/tiktok_connect_wizard.dart';
import '../social_hub/tiktok_account_screen.dart';
import '../backend/connections/linked_accounts.dart';
import '../backend/tiktok_oauth_service.dart';
import '../backend/meta_oauth_service.dart';
import '../social_hub/meta_platform_picker_screen.dart';
import '../social_hub/wizard/meta_app_wizard.dart';
import '../upload/screens/premium_post_screen.dart';
import '../upload/ai_voice_manager_screen.dart';
import '../create/camera_screen.dart';
import '../create/custom_media_picker_screen.dart';
import '../create/studio/screens/studio_editor_screen.dart';
import '../create/studio/screens/studio_home_screen.dart';
import '../create/studio/screens/studio_media_picker_screen.dart';
import '../feed/post_viewer_screen.dart';
import '../hub/screens/photo_studio/photo_studio_screen.dart';
import '../create/pro_workstation_editor_screen.dart';
import '../social_hub/feed/sound_page_screen.dart';
import '../social_hub/discovery/screens/hashtag_page_screen.dart';
import '../backend/projects/models/oneova_draft_model.dart';
import 'package:uuid/uuid.dart';
import '../social_hub/analytics_command_center.dart';
import '../social_hub/tiktok_ai_assistant_screen.dart';
import '../social_hub/notifications/notification_center_screen.dart';
import '../hub/connect_screen.dart';
import '../hub/qr_scanner_screen.dart';
import '../looks/marketplace/ui/oneova_wallet_screen.dart';
import '../social_hub/money/clip_insights_screen.dart';
import '../social_hub/money/coin_shop_screen.dart';
import '../social_hub/money/creator_insights_screen.dart';
import '../social_hub/money/payout_status_screens.dart';
import '../identity/screens/oneova_id_screen.dart';
import '../identity/screens/business_verify_screen.dart';
import '../identity/screens/id_data_screen.dart';
import '../social_hub/money/plans_screen.dart';
import '../social_hub/money/withdraw_screen.dart';
import '../social_hub/money/scan_to_pay_screens.dart';
import '../social_hub/money/oneova_pay_home_screen.dart';
import '../security/screens/security_center_screen.dart';
import '../auth/security/login_activity_screen.dart';
import '../auth/security/sign_in_methods_screen.dart';
import '../social_hub/creator_studio/monetization/monetization_dashboard.dart';
import '../hub/remote_chat_screen.dart';
import '../hub/remote_monitor_screen.dart';
import '../hub/desktop_remote_screen.dart';
import '../hub/phone_controller/computer_logs_screen.dart';
import '../hub/phone_controller/phone_controller_screen.dart';
import '../inbox/calling/screens/active_call_screen.dart';
import '../social_hub/live/settings/live_destinations_screen.dart';
import '../social_hub/live/settings/live_recordings_screen.dart';
import '../social_hub/live/setup/live_setup_config.dart';
import '../social_hub/live/setup/live_setup_wizard_screen.dart';
import '../social_hub/live/live_room_gate.dart';
import '../social_hub/live/studio_v2/shell/live_studio_v2_screen.dart';
import '../social_hub/live/studio_v2/gaming/gaming_lives_screen.dart';
import '../feed/providers/oneova_focus_mode_provider.dart';
import '../wishes/feedback_sheet.dart';

export '../backend/social/services/video_playback_manager.dart'
    show mainFeedRouteObserver, homeBranchRouteObserver;

// StatefulShellRoute shells
class HubShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  const HubShell({super.key, required this.navigationShell});

  @override
  ConsumerState<HubShell> createState() => _HubShellState();
}

class _HubShellState extends ConsumerState<HubShell> with RouteAware {
  VideoPlaybackManager? _playbackManager;
  bool _isRootRouteCurrent = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _playbackManager ??= ref.read(videoPlaybackManagerProvider);
      if (widget.navigationShell.currentIndex != 0 || !_isRootRouteCurrent) {
        _playbackManager?.setScreenActive(false);
      }
      try {
        final shouldShow = await ref.read(featureTourServiceProvider).shouldShowTour();
        if (shouldShow && mounted) {
          ref.read(featureTourCurrentStepProvider.notifier).setStep(0);
          ref.read(featureTourVisibilityProvider.notifier).show();
        }
      } catch (_) {}
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _playbackManager = ref.read(videoPlaybackManagerProvider);
    final modalRoute = ModalRoute.of(context);
    if (modalRoute != null) {
      mainFeedRouteObserver.subscribe(this, modalRoute);
    }
  }

  @override
  void didPushNext() {
    _isRootRouteCurrent = false;
    _playbackManager?.setScreenActive(false);
    super.didPushNext();
  }

  @override
  void didPopNext() {
    _isRootRouteCurrent = true;
    final isReels = widget.navigationShell.currentIndex == 0;
    _playbackManager?.setScreenActive(isReels);
    super.didPopNext();
  }

  @override
  void didPop() {
    _isRootRouteCurrent = false;
    _playbackManager?.setScreenActive(false);
    super.didPop();
  }

  @override
  void dispose() {
    mainFeedRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(HubShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isReels = widget.navigationShell.currentIndex == 0;
    final wasReels = oldWidget.navigationShell.currentIndex == 0;
    if (isReels != wasReels) {
      (_playbackManager ?? ref.read<VideoPlaybackManager>(videoPlaybackManagerProvider))
          .setScreenActive(isReels && _isRootRouteCurrent);
    }
  }

  OneovaTab? get _active {
    switch (widget.navigationShell.currentIndex) {
      case 0:
        return OneovaTab.reels;
      case 2:
        return OneovaTab.chat;
      case 3:
        return OneovaTab.ai;
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFocusMode = ref.watch(oneovaFocusModeProvider);
    final isHome = widget.navigationShell.currentIndex == 0;
    final shouldHide = !isHome || isFocusMode;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(oneovaBottomNavVisibleProvider.notifier).setVisible(isHome && !shouldHide);
      }
    });

    debugPrint('[HubShell build] rendering index: ${widget.navigationShell.currentIndex}, isFocusMode: $isFocusMode');
    return Scaffold(
      extendBody: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          widget.navigationShell,
          OneovaFeatureTourBubble(
            onStepChanged: (stepIndex) {
              if (stepIndex == 3) {
                widget.navigationShell.goBranch(2); // Chat
              } else if (stepIndex == 5) {
                widget.navigationShell.goBranch(3); // AI Lab
              } else if (stepIndex <= 2) {
                widget.navigationShell.goBranch(0); // Reels
              }
            },
            onDismiss: () {
              // Stay on current branch smoothly
            },
          ),
        ],
      ),
      bottomNavigationBar: !isHome
          ? null
          : AnimatedSlide(
              offset: shouldHide ? const Offset(0, 1.4) : Offset.zero,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOutCubic,
              child: AnimatedOpacity(
                opacity: shouldHide ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 220),
                child: IgnorePointer(
                  ignoring: shouldHide,
                  child: OneovaBottomNav(
                    active: _active,
                    onReels: () => widget.navigationShell.goBranch(0, initialLocation: widget.navigationShell.currentIndex == 0),
                    onChat: () => widget.navigationShell.goBranch(2),
                    onStudio: () => CreationTypeModal.show(context),
                    onAi: () => widget.navigationShell.goBranch(3),
                    onMe: () => OneovaProfileSidebarDrawer.show(context),
                  ),
                ),
              ),
            ),
    );
  }
}



class SessionRouteObserver extends NavigatorObserver {
  final Ref ref;
  SessionRouteObserver(this.ref);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _updateSession(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (newRoute != null) _updateSession(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _updateSession(previousRoute);
  }

  void _updateSession(Route<dynamic> route) {
    if (route.settings.name != null && !route.settings.name!.startsWith('/auth')) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Debounce or just fire and forget
        ref.read(userProvider.notifier).updateLastActiveRoute(user.uid, route.settings.name!);
      }
    }
  }
}

bool get _isDesktopAgentPlatform => !kIsWeb && (Platform.isMacOS || Platform.isWindows);

/// Sign-in gate shared by the global redirect and per-route guards.
///
/// Public routes (Reels feed `/hub/home`, discover `/hub/discover`, biz feed,
/// legal/about, sounds, hashtags) open immediately for everyone—even first-time
/// installs or guests without an account.
/// Users log in once and stay logged in permanently.
String? _authGate(GoRouterState state) {
  final path = state.uri.path;
  if (_isDesktopAgentPlatform) return null; // Desktop agent pairs via secure pairing.

  // 1. Public guest routes: open directly to all users without a login wall.
  final isPublicRoute = LoginSecurity.isGuestRoute(path) ||
      path == '/hub/home' ||
      path == '/biz_feed' ||
      path == '/hub/discover' ||
      path.startsWith('/sound/') ||
      path.startsWith('/social/explore') ||
      path == '/legal' ||
      path == '/about' ||
      path == '/privacy' ||
      path == '/splash' ||
      path.startsWith('/auth');

  if (isPublicRoute) return null;

  // 2. Protected personal routes: require a valid user account.
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) {
    return '/auth/main_login';
  }

  // 3. Authenticated user has full persistent access.
  return null;
}

// Auth guard helper: redirects to login if not authenticated / not verified
String? _requireAuth(BuildContext context, GoRouterState state) => _authGate(state);

final routerProvider = Provider<GoRouter>((ref) {
  final isDesktopDebug = kDebugMode && (Platform.isMacOS || Platform.isWindows);
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    debugLogDiagnostics: true,
    initialLocation: isDesktopDebug ? '/desktop_agent' : '/splash',
    observers: [
      SessionRouteObserver(ref),
      OvaPopupObserver(),
      mainFeedRouteObserver,
    ],
    refreshListenable: LoginSecurity.instance,
    errorBuilder: (context, state) => Scaffold(
      backgroundColor: context.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.brandBlue),
            const SizedBox(height: 24),
            Text('Page Not Found', style: AppTheme.h1Style.copyWith(color: context.textPrimary)),
            const SizedBox(height: 16),
            Text(
              'The screen you are looking for does not exist.',
              style: TextStyle(color: context.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () => context.go('/auth/main_login'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandBlue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Go Home', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    ),
    redirect: (context, state) {
      debugPrint('[Router global redirect] evaluating path: ${state.uri.path}');
      final user = FirebaseAuth.instance.currentUser;
      final isAuthRoute = state.uri.path.startsWith('/auth') ||
          state.uri.path == '/splash' ||
          state.uri.path == '/legal' ||
          state.uri.path == '/tiktok-callback' ||
          state.uri.path == '/meta-callback';
      
      final isDesktopDebug = kDebugMode && (Platform.isMacOS || Platform.isWindows);

      if (!isAuthRoute) {
        final gate = _authGate(state);
        if (gate != null) {
          debugPrint('[Router global redirect] ${state.uri.path} -> $gate (sign-in gate)');
          return gate;
        }
      }
      
      if (isDesktopDebug && state.uri.path == '/auth/main_login') {
        return '/desktop_agent';
      }

      // If user is logged in on macOS/Windows, force them to the Desktop Agent screen
      // instead of the mobile Hub home, since the desktop app acts as the agent.
      if (user != null && !kIsWeb && (Platform.isMacOS || Platform.isWindows)) {
        if (state.uri.path == '/' || state.uri.path == '/hub/home') {
          return '/desktop_agent';
        }
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/call/active',
        redirect: _requireAuth,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          final callId = extra['callId'] as String? ?? state.uri.queryParameters['callId'] ?? '';
          final otherUserId = extra['otherUserId'] as String? ?? state.uri.queryParameters['otherUserId'];
          final otherUserName = extra['otherUserName'] as String? ?? state.uri.queryParameters['otherUserName'];
          final otherUserAvatar = extra['otherUserAvatar'] as String? ?? state.uri.queryParameters['otherUserAvatar'];
          final isVideo = extra['isVideo'] == true || state.uri.queryParameters['isVideo'] == 'true';
          final isCaller = extra['isCaller'] != false && state.uri.queryParameters['isCaller'] != 'false';

          return ActiveCallScreen(
            callId: callId,
            otherUserId: otherUserId,
            otherUserName: otherUserName,
            otherUserAvatar: otherUserAvatar,
            isVideo: isVideo,
            isCaller: isCaller,
          );
        },
      ),
      GoRoute(path: '/biz_feed', redirect: _requireAuth, builder: (context, state) => const BizFeedScreen()),
      // Biz payments (Oneova Pay escrow): checkout, orders, payouts.
      GoRoute(path: '/biz/checkout/:productId', redirect: _requireAuth, builder: (context, state) => CheckoutScreen(productId: state.pathParameters['productId']!, variantId: state.uri.queryParameters['variant'], customization: decodeCustomization(state.uri.queryParameters['custom']))),
      GoRoute(path: '/biz/orders', redirect: _requireAuth, builder: (context, state) => const OrdersScreen()),
      // ── Oneova 3D Shops (specific paths before /shops/:id) ──
      // ── Business portal (sellers) ──
      GoRoute(path: '/business', redirect: _requireAuth, builder: (context, state) => const BusinessPortalScreen()),
      GoRoute(path: '/business/orders', redirect: _requireAuth, builder: (context, state) => const BusinessOrdersScreen()),
      GoRoute(path: '/business/inventory', redirect: _requireAuth, builder: (context, state) => const BusinessInventoryScreen()),
      GoRoute(path: '/business/insights', redirect: _requireAuth, builder: (context, state) => const BusinessInsightsScreen()),
      GoRoute(
        path: '/business/settings',
        redirect: _requireAuth,
        builder: (context, state) => BusinessSettingsScreen(initialTab: state.uri.queryParameters['tab'] == 'codes' ? 1 : 0),
      ),
      GoRoute(path: '/shops', redirect: _requireAuth, builder: (context, state) => const ShopsFeedScreen()),
      GoRoute(path: '/shops/saved', redirect: _requireAuth, builder: (context, state) => const SavedProductsScreen()),
      GoRoute(path: '/shops/setup', redirect: _requireAuth, builder: (context, state) => const ShopSetupWizardScreen()),
      GoRoute(path: '/shops/product/new', redirect: _requireAuth, builder: (context, state) => const ProductCreatorScreen()),
      GoRoute(path: '/shops/models', redirect: _requireAuth, pageBuilder: (context, state) => MaterialPage<PublishedModel>(key: state.pageKey, child: ModelLibraryScreen(pickForProductId: state.uri.queryParameters['pick']))),
      GoRoute(path: '/shops/product/edit', redirect: _requireAuth, builder: (context, state) => ProductEditorScreen(productId: state.uri.queryParameters['id'])),
      GoRoute(path: '/shops/p/:productId', redirect: _requireAuth, builder: (context, state) => ShopProductScreen(productId: state.pathParameters['productId']!, variantId: state.uri.queryParameters['variant'], shareCode: state.uri.queryParameters['ref'])),
      GoRoute(path: '/shops/:id', redirect: _requireAuth, builder: (context, state) => ShopStoreScreen(shopId: state.pathParameters['id']!)),
      GoRoute(path: '/shops/:id/stage', redirect: _requireAuth, builder: (context, state) {
        ShareRef.note(state.uri.queryParameters['ref']);
        return ShopStageScreen(shopId: state.pathParameters['id']!);
      }),
      GoRoute(path: '/biz/orders/:id', redirect: _requireAuth, builder: (context, state) => OrderDetailScreen(orderId: state.pathParameters['id']!)),
      GoRoute(path: '/biz/payouts', redirect: _requireAuth, builder: (context, state) => const PayoutsScreen()),
      GoRoute(path: '/hub/discover', redirect: _requireAuth, builder: (context, state) => const GlobalSearchScreen()),
      GoRoute(path: '/profile/earnings', redirect: _requireAuth, builder: (context, state) => const OneovaWalletScreen()),
      GoRoute(path: '/wallet', redirect: _requireAuth, builder: (context, state) => const OneovaWalletScreen()),
      GoRoute(path: '/wallet/coins', redirect: _requireAuth, builder: (context, state) => const CoinShopScreen()),
      GoRoute(path: '/wallet/plans', redirect: _requireAuth, builder: (context, state) => const PlansScreen()),
      GoRoute(path: '/wallet/withdraw', redirect: _requireAuth, builder: (context, state) => const WithdrawScreen()),
      GoRoute(path: '/wallet/scan', redirect: _requireAuth, builder: (context, state) => const ScanToPayScreen()),
      GoRoute(path: '/pay', redirect: _requireAuth, builder: (context, state) => const OneovaPayHomeScreen()),
      GoRoute(path: '/pay/business', redirect: _requireAuth, builder: (context, state) => const OneovaPayHomeScreen(business: true)),
      GoRoute(path: '/wallet/receive', redirect: _requireAuth, builder: (context, state) => const ReceivePayScreen()),
      GoRoute(path: '/wallet/verify', redirect: _requireAuth, builder: (context, state) => const KycScreen()),
      GoRoute(path: '/wallet/payments', redirect: _requireAuth, builder: (context, state) => const PaymentsHistoryScreen()),
      // Back from a partner's payment page (oneova://app/pay/done).
      GoRoute(path: '/pay/done', redirect: (context, state) => '/wallet/payments'),
      GoRoute(path: '/id', redirect: _requireAuth, builder: (context, state) => OneovaIdScreen(openShare: state.uri.queryParameters['share'] == '1')),
      GoRoute(path: '/id/business', redirect: _requireAuth, builder: (context, state) => const BusinessVerifyScreen()),
      GoRoute(path: '/id/data', redirect: _requireAuth, builder: (context, state) => const IdDataScreen()),
      GoRoute(path: '/wallet/withdrawals', redirect: _requireAuth, builder: (context, state) => const WithdrawalsScreen()),
      GoRoute(path: '/wallet/withdrawals/:id', redirect: _requireAuth, builder: (context, state) => WithdrawalDetailScreen(id: state.pathParameters['id']!)),
      GoRoute(path: '/creator/insights', redirect: _requireAuth, builder: (context, state) => const CreatorInsightsScreen()),
      GoRoute(path: '/creator/insights/clip/:id', redirect: _requireAuth, builder: (context, state) => ClipInsightsScreen(id: state.pathParameters['id']!)),
      GoRoute(path: '/profile/security', redirect: _requireAuth, builder: (context, state) => const SecurityCenterScreen()),
      GoRoute(path: '/social_hub/gmail', redirect: _requireAuth, builder: (context, state) => const GmailInboxScreen()),
      GoRoute(path: '/social_hub/gmail/:id', redirect: _requireAuth, builder: (context, state) => GmailMessageScreen(id: state.pathParameters['id']!)),
      GoRoute(path: '/auth/email_code', redirect: _requireAuth, builder: (context, state) => EmailCodeScreen(purpose: state.uri.queryParameters['purpose'] ?? 'verify_email')),
      GoRoute(path: '/profile/monetization', redirect: _requireAuth, builder: (context, state) => const MonetizationDashboard()),
      GoRoute(path: '/profile/me', redirect: _requireAuth, builder: (context, state) => const PublicProfileScreen(targetUserId: 'current')),
      GoRoute(path: '/profile/:uid', redirect: _requireAuth, builder: (context, state) => PublicProfileScreen(targetUserId: state.pathParameters['uid']!)),
      GoRoute(path: '/hub/ova_assistant', redirect: _requireAuth, builder: (context, state) => const OvaAssistantScreen()),
      GoRoute(path: '/ova', redirect: _requireAuth, builder: (context, state) => const OvaAssistantScreen()),
      GoRoute(path: '/splash', builder: (context, state) => const AnimatedSplashScreen()),
      // ──────────────────────────────────────────────────────────────────
      // ROOT & AUTH ROUTES (no guard — anyone can access these)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/',
        redirect: (context, state) => '/auth/main_login',
      ),
      GoRoute(
        path: '/auth/locked',
        builder: (context, state) => const WorkspaceLockedScreen(),
      ),
      GoRoute(
        path: '/auth/main_login',
        name: '/auth/main_login',
        builder: (context, state) {
          debugPrint('[Router] building MainLoginScreen for state: ${state.uri}');
          return const MainLoginScreen();
        },
      ),
      GoRoute(
        path: '/auth/signup_wizard',
        builder: (context, state) => const SignupWizardScreen(),
      ),
      GoRoute(
        path: '/auth/pending',
        builder: (context, state) => const PendingApprovalScreen(),
      ),
      GoRoute(
        path: '/qr_scanner',
        builder: (context, state) => const QRScannerScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // LEGACY: /auth/youtube was the YouTube OAuth connector — NOT app auth.
      // Redirect existing links to the social hub (connected accounts).
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/auth/youtube',
        redirect: (context, state) {
          if (FirebaseAuth.instance.currentUser == null) return '/auth/main_login';
          return '/social_hub';
        },
      ),

      // ──────────────────────────────────────────────────────────────────
      // SOCIAL HUB — Platform Connection Routes (GUARDED)
      // These are for connecting YouTube/Instagram/TikTok to the user profile
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/social_hub',
        redirect: _requireAuth,
        builder: (context, state) => const SocialIntegrationDashboard(),
      ),
      // Google services kept with the account (Gmail, YouTube, Drive, …).
      GoRoute(
        path: '/social_hub/google',
        redirect: _requireAuth,
        builder: (context, state) => const GoogleServicesScreen(),
      ),
      // Old simulated connect wizard: forward to the platform's real OAuth
      // wizard (or the connected-accounts page).
      GoRoute(
        path: '/social_hub/connect_wizard',
        redirect: (context, state) {
          final auth = _requireAuth(context, state);
          if (auth != null) return auth;
          final p = LinkedPlatform.fromId(state.uri.queryParameters['platform'] ?? (state.extra is String ? state.extra as String : null));
          return (p == null ? null : LinkedAccountsController.wizardRoute(p)) ?? '/social_hub';
        },
      ),
      GoRoute(
        path: '/social_hub/meta_picker',
        redirect: _requireAuth,
        builder: (context, state) => const MetaPlatformPickerScreen(),
      ),
      GoRoute(
        path: '/social_hub/meta_wizard/:app',
        redirect: _requireAuth,
        builder: (context, state) {
          final app = state.pathParameters['app'] ?? 'instagram';
          return MetaAppWizard(appName: app);
        },
      ),
      GoRoute(
        path: '/social_hub/tiktok_wizard',
        redirect: _requireAuth,
        builder: (context, state) => const TikTokConnectWizard(),
      ),
      GoRoute(
        path: '/social_hub/tiktok',
        redirect: _requireAuth,
        builder: (context, state) => const TikTokAccountScreen(),
      ),
      GoRoute(
        path: '/tiktok-callback',
        builder: (context, state) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(tiktokOAuthProvider.notifier).handleOAuthCallback(state.uri);
          });
          return Scaffold(
            backgroundColor: context.bg,
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      ),
      GoRoute(
        path: '/meta-callback',
        builder: (context, state) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(metaOAuthProvider.notifier).handleOAuthCallback(state.uri);
          });
          return Scaffold(
            backgroundColor: context.bg,
            body: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        },
      ),
      // There is one inbox: /hub/messages. Old links land there, optionally
      // on one linked platform (?platform=gmail|youtube|instagram|...).
      GoRoute(
        path: '/social_hub/unified_inbox',
        redirect: (context, state) {
          final auth = _requireAuth(context, state);
          if (auth != null) return auth;
          final p = LinkedPlatform.fromId(state.uri.queryParameters['platform']);
          return p == null ? '/hub/messages' : '/hub/messages?platform=${p.id}';
        },
      ),
      GoRoute(path: '/inbox', redirect: (context, state) => '/social_hub/unified_inbox'),
      GoRoute(
        path: '/social_hub/analytics',
        redirect: _requireAuth,
        builder: (context, state) => const AnalyticsCommandCenter(),
      ),
      GoRoute(
        path: '/social_hub/tiktok_assistant',
        redirect: _requireAuth,
        builder: (context, state) => const TikTokAiAssistantScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // UPLOAD ROUTES (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/upload/ai_voice_manager',
        redirect: _requireAuth,
        builder: (context, state) => const AiVoiceManagerScreen(),
      ),
      GoRoute(
        path: '/create/camera',
        redirect: _requireAuth,
        builder: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return CameraScreen(initialMode: mode);
        },
      ),
      GoRoute(
        path: '/photo/studio',
        redirect: _requireAuth,
        builder: (context, state) => const PhotoStudioScreen(),
      ),
      GoRoute(
        path: '/create/picker',
        redirect: _requireAuth,
        builder: (context, state) => const CustomMediaPickerScreen(),
      ),
      // Studio: create -> edit -> export -> post / story.
      GoRoute(
        path: '/create/studio',
        redirect: _requireAuth,
        builder: (context, state) => StudioHomeScreen(initialTool: state.uri.queryParameters['tool']),
      ),
      GoRoute(
        path: '/create/studio/picker',
        redirect: _requireAuth,
        builder: (context, state) {
          final q = state.uri.queryParameters;
          return StudioMediaPickerScreen(
            mode: StudioPickMode.values.firstWhere((m) => m.name == q['mode'], orElse: () => StudioPickMode.any),
            multiple: q['multi'] != '0',
          );
        },
      ),
      GoRoute(
        path: '/create/studio/editor',
        redirect: (context, state) => state.extra is StudioEditorArgs ? _requireAuth(context, state) : '/create/studio',
        builder: (context, state) => StudioEditorScreen(args: state.extra! as StudioEditorArgs),
      ),
      GoRoute(
        path: '/post/:id',
        redirect: _requireAuth,
        builder: (context, state) => PostViewerScreen(contentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ai_studio',
        redirect: (context, state) => '/hub/ai',
      ),
      GoRoute(
        path: '/create/editor',
        redirect: _requireAuth,
        builder: (context, state) {
          final draft = state.extra as OneovaDraft?;
          if (draft != null) {
            return ProWorkstationEditorScreen(draft: draft);
          }
          return ProWorkstationEditorScreen(
            draft: OneovaDraft(
              id: const Uuid().v4(),
              title: 'New Project',
              mediaPath: '',
              isVideo: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        },
      ),

      GoRoute(
        path: '/sound/:id',
        redirect: _requireAuth,
        builder: (context, state) => SoundPageScreen(soundId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/social/sound/:id',
        redirect: _requireAuth,
        builder: (context, state) => SoundPageScreen(soundId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/social/explore/hashtag/:tag',
        redirect: _requireAuth,
        builder: (context, state) => HashtagPageScreen(hashtag: state.pathParameters['tag']!),
      ),

      // ──────────────────────────────────────────────────────────────────
      // CONNECT & REMOTE (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/connect',
        redirect: _requireAuth,
        builder: (context, state) => const ConnectScreen(),
      ),
      GoRoute(
        path: '/remote_chat',
        redirect: _requireAuth,
        builder: (context, state) => const RemoteChatScreen(),
      ),
      GoRoute(
        path: '/remote_monitor',
        redirect: _requireAuth,
        builder: (context, state) => const RemoteMonitorScreen(),
      ),
      GoRoute(
        path: '/remote_control',
        redirect: _requireAuth,
        builder: (context, state) => const DesktopRemoteScreen(),
      ),
      GoRoute(
        path: '/desktop-remote',
        redirect: (context, state) => '/remote_control',
      ),
      GoRoute(
        path: '/desktop_agent',
        redirect: _requireAuth,
        builder: (context, state) => const DesktopAgentScreen(),
      ),
      GoRoute(
        path: '/phone_controller/:deviceId',
        redirect: _requireAuth,
        builder: (context, state) => PhoneControllerScreen(
          deviceId: state.pathParameters['deviceId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/computer_logs',
        redirect: _requireAuth,
        builder: (context, state) => const ComputerLogsScreen(),
      ),
      // Setup wizard: the one way to go live (mode → details → camera →
      // layout → audience → review), then the Live Studio.
      GoRoute(
        path: '/live/setup',
        redirect: _requireAuth,
        builder: (context, state) => LiveSetupWizardScreen(
          initialMode: LiveSetupMode.fromQuery(state.uri.queryParameters['mode']),
        ),
      ),
      // Old "Go Live" screen → the wizard (keeps ?mode=studio|gaming links).
      GoRoute(
        path: '/live/broadcast',
        redirect: (context, state) {
          final mode = state.uri.queryParameters['mode'];
          return mode == null ? '/live/setup' : '/live/setup?mode=$mode';
        },
      ),
      // Game Live discovery: game lives on air right now.
      GoRoute(
        path: '/live/gaming',
        redirect: _requireAuth,
        builder: (context, state) => const GamingLivesScreen(),
      ),
      // Followers' entry point (feed live ring, "is LIVE" alerts, deep links).
      // Opens the full-screen vertical viewer, or the Live Studio when the
      // host went live in Studio mode.
      GoRoute(
        path: '/live/viewer/:streamId',
        redirect: _requireAuth,
        builder: (context, state) =>
            LiveRoomGate(streamId: state.pathParameters['streamId']!),
      ),
      // Old v1 studio links → the viewer gate (opens the right studio).
      GoRoute(
        path: '/live/studio/:streamId',
        redirect: (context, state) => '/live/viewer/${state.pathParameters['streamId']}',
      ),
      // The Live Studio (hosts arrive here from /live/setup).
      GoRoute(
        path: '/live/studio2/:streamId',
        redirect: _requireAuth,
        builder: (context, state) =>
            LiveStudioV2Screen(streamId: state.pathParameters['streamId']!),
      ),
      GoRoute(
        path: '/auth/linked_devices',
        redirect: _requireAuth,
        builder: (context, state) => const LinkedDevicesScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // SETTINGS (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/settings',
        redirect: (context, state) => '/settings/main',
      ),
      GoRoute(
        path: '/settings/main',
        redirect: _requireAuth,
        builder: (context, state) => const MainSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/profile',
        redirect: _requireAuth,
        builder: (context, state) => const ProfileSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/app',
        redirect: _requireAuth,
        builder: (context, state) => const AppSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/chat',
        redirect: _requireAuth,
        builder: (context, state) => const ChatSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/notifications',
        redirect: _requireAuth,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/ai',
        redirect: _requireAuth,
        builder: (context, state) => const AiSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/privacy',
        redirect: _requireAuth,
        builder: (context, state) => const PrivacySecurityScreen(),
      ),
      GoRoute(
        path: '/settings/follow-requests',
        redirect: _requireAuth,
        builder: (context, state) => const FollowRequestsScreen(),
      ),
      GoRoute(
        path: '/settings/blocked-users',
        redirect: _requireAuth,
        builder: (context, state) => const BlockedUsersScreen(),
      ),
      GoRoute(
        path: '/settings/data-export',
        redirect: _requireAuth,
        builder: (context, state) => const DataExportScreen(),
      ),
      GoRoute(
        path: '/settings/login-activity',
        redirect: _requireAuth,
        builder: (context, state) => const LoginActivityScreen(),
      ),
      GoRoute(
        path: '/settings/sign-in-methods',
        redirect: _requireAuth,
        builder: (context, state) => const SignInMethodsScreen(),
      ),
      GoRoute(
        path: '/settings/appearance',
        redirect: _requireAuth,
        builder: (context, state) => const AppearanceSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/accessibility',
        redirect: _requireAuth,
        builder: (context, state) => const AccessibilitySettingsScreen(),
      ),
      GoRoute(
        path: '/settings/reels',
        redirect: _requireAuth,
        builder: (context, state) => const ReelsPlaybackSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/calls',
        redirect: _requireAuth,
        builder: (context, state) => const CallsSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/storage',
        redirect: _requireAuth,
        builder: (context, state) => const StorageSettingsScreen(),
      ),
      GoRoute(
        path: '/settings/live_recordings',
        redirect: _requireAuth,
        builder: (context, state) => const LiveRecordingsScreen(),
      ),
      GoRoute(
        path: '/settings/live_destinations',
        redirect: _requireAuth,
        builder: (context, state) => const LiveDestinationsScreen(),
      ),
      GoRoute(
        path: '/settings/camera_and_live',
        redirect: _requireAuth,
        builder: (context, state) => const CameraAndLiveSettingsScreen(),
      ),
      // Feedback opens as a pop-up sheet over the current screen (not a page).
      GoRoute(
        path: '/feedback',
        redirect: _requireAuth,
        pageBuilder: (context, state) => FeedbackSheetPage(
          key: state.pageKey,
          openIdeaId: state.uri.queryParameters['idea'],
        ),
      ),
      GoRoute(
        path: '/legal',
        builder: (context, state) => LegalPoliciesScreen(
          initialTab: state.uri.queryParameters['tab'],
        ),
      ),
      GoRoute(
        path: '/settings/legal',
        redirect: _requireAuth,
        builder: (context, state) => LegalPoliciesScreen(
          initialTab: state.uri.queryParameters['tab'],
        ),
      ),
      GoRoute(
        path: '/settings/admin-cms',
        redirect: _requireAuth,
        builder: (context, state) => AdminDocsCmsScreen(
          initialDocId: state.uri.queryParameters['doc'],
        ),
      ),
      GoRoute(
        path: '/settings/about',
        redirect: _requireAuth,
        builder: (context, state) => const AboutScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // NOTIFICATIONS (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      GoRoute(
        path: '/notifications',
        redirect: _requireAuth,
        builder: (context, state) => const NotificationCenterScreen(),
      ),

      GoRoute(
        path: '/ova/setup',
        redirect: _requireAuth,
        builder: (context, state) => const OvaSetupScreen(),
      ),

      GoRoute(
        path: '/ova/triggers',
        redirect: _requireAuth,
        builder: (context, state) => const OvaTriggerSettingsScreen(),
      ),
      // Ova Live: Gemini Live on Vertex AI. Opens only from an explicit tap.
      GoRoute(
        path: '/ova/live',
        redirect: _requireAuth,
        builder: (context, state) => const LiveVoiceModeScreen(),
      ),
      GoRoute(
        path: '/ova/abilities',
        redirect: _requireAuth,
        builder: (context, state) => const OvaAbilitiesScreen(),
      ),

      // ──────────────────────────────────────────────────────────────────
      // HUB (GUARDED)
      // ──────────────────────────────────────────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          debugPrint('[StatefulShellRoute HubShell builder] state: ${state.uri}');
          return HubShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            observers: [homeBranchRouteObserver],
            routes: [GoRoute(
              path: '/hub/home', 
              redirect: _requireAuth,
              builder: (context, state) {
                final videoId = state.uri.queryParameters['v'];
                debugPrint('[GoRoute /hub/home builder] building ShortVideoFeedScreen for state: ${state.uri}');
                return ShortVideoFeedScreen(initialVideoId: videoId);
              }
            )],
          ),
          StatefulShellBranch(routes: [GoRoute(
            path: '/upload/global', 
            redirect: _requireAuth,
            builder: (context, state) => const PremiumPostScreen()
          )]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/hub/messages', 
              redirect: _requireAuth,
              builder: (context, state) => InAppMessagingScreen(initialPlatform: state.uri.queryParameters['platform']),
              routes: [
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (context, state) => ChatDetailScreen(chatId: state.pathParameters['id']!),
                ),
              ],
            )
          ]),
          StatefulShellBranch(routes: [GoRoute(
            path: '/hub/ai', 
            redirect: _requireAuth,
            builder: (context, state) => const HubAiScreen()
          )]),
        ],
      ),

      // Studio management was removed in this version (see
      // .agents/rules/oneova_build_vision.md). Old links go to the nearest kept screen.
      GoRoute(path: '/hub/team', redirect: (context, state) => '/hub/home'),
      GoRoute(path: '/yt/:rest', redirect: (context, state) => '/social_hub'),
      GoRoute(path: '/video/:rest', redirect: (context, state) => '/create/studio'),
      GoRoute(path: '/audio/:rest', redirect: (context, state) => '/create/studio'),
    ],
  );
});
