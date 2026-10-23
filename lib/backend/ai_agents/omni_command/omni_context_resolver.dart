import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The minimal context snapshot sent to the AI layer.
/// NEVER include raw DB documents, tokens, or full conversation history.
class OmniContext {
  final String sessionId;
  final String userId;

  /// Primary application surface (e.g. 'inbox', 'chat', 'pro_editor', 'photo_studio')
  final String surface;

  /// Current route, e.g. '/inbox', '/conversation/:id'
  final String? activeRoute;

  /// If the user is inside a conversation
  final String? conversationId;

  /// If a specific message is selected
  final String? messageId;

  /// Active connector/platform filter
  final String? platformId;
  final String? connectorId;

  /// Active search query (if any)
  final String? searchQuery;

  /// Context-specific IDs
  final String? projectId;
  final String? sequenceId;
  final String? clipId;
  final String? assetId;
  final String? selectedMaskId;
  final String? selectedEffectId;
  final String? selectedLutId;
  final String? selectedPresetId;
  final String? selectedContactId;
  final String? selectedChannelId;

  /// IDs of user-selected messages (client-side selection)
  final List<String> selectedMessageIds;

  /// Capabilities available to the AI in this context
  final Set<OmniCapability> capabilities;

  /// The AI mode currently active
  final AiOperatingMode aiMode;

  /// Whether memory is enabled
  final bool memoryEnabled;

  const OmniContext({
    required this.sessionId,
    required this.userId,
    this.surface = 'unknown',
    this.activeRoute,
    this.conversationId,
    this.messageId,
    this.platformId,
    this.connectorId,
    this.searchQuery,
    this.projectId,
    this.sequenceId,
    this.clipId,
    this.assetId,
    this.selectedMaskId,
    this.selectedEffectId,
    this.selectedLutId,
    this.selectedPresetId,
    this.selectedContactId,
    this.selectedChannelId,
    this.selectedMessageIds = const [],
    this.capabilities = const {},
    this.aiMode = AiOperatingMode.assist,
    this.memoryEnabled = true,
  });

  /// Human-readable label for UI context chip
  String get displayContext {
    if (surface == 'pro_editor' || projectId != null) return 'Pro Editor';
    if (surface == 'photo_studio') return 'PhotoStudio';
    if (surface == 'creator_studio') return 'Creator Studio';
    if (conversationId != null) return 'Conversation';
    if (activeRoute?.contains('inbox') == true) return 'Inbox';
    if (activeRoute?.contains('search') == true) return 'Search';
    if (activeRoute?.contains('notifications') == true) return 'Notifications';
    if (activeRoute?.contains('connectors') == true) return 'Connectors';
    return surface != 'unknown' ? surface : 'App';
  }

  OmniContext copyWith({
    String? surface,
    String? activeRoute,
    String? conversationId,
    String? messageId,
    String? platformId,
    String? connectorId,
    String? searchQuery,
    String? projectId,
    String? sequenceId,
    String? clipId,
    String? assetId,
    String? selectedMaskId,
    String? selectedEffectId,
    String? selectedLutId,
    String? selectedPresetId,
    String? selectedContactId,
    String? selectedChannelId,
    List<String>? selectedMessageIds,
    Set<OmniCapability>? capabilities,
    AiOperatingMode? aiMode,
    bool? memoryEnabled,
  }) {
    return OmniContext(
      sessionId: sessionId,
      userId: userId,
      surface: surface ?? this.surface,
      activeRoute: activeRoute ?? this.activeRoute,
      conversationId: conversationId ?? this.conversationId,
      messageId: messageId ?? this.messageId,
      platformId: platformId ?? this.platformId,
      connectorId: connectorId ?? this.connectorId,
      searchQuery: searchQuery ?? this.searchQuery,
      projectId: projectId ?? this.projectId,
      sequenceId: sequenceId ?? this.sequenceId,
      clipId: clipId ?? this.clipId,
      assetId: assetId ?? this.assetId,
      selectedMaskId: selectedMaskId ?? this.selectedMaskId,
      selectedEffectId: selectedEffectId ?? this.selectedEffectId,
      selectedLutId: selectedLutId ?? this.selectedLutId,
      selectedPresetId: selectedPresetId ?? this.selectedPresetId,
      selectedContactId: selectedContactId ?? this.selectedContactId,
      selectedChannelId: selectedChannelId ?? this.selectedChannelId,
      selectedMessageIds: selectedMessageIds ?? this.selectedMessageIds,
      capabilities: capabilities ?? this.capabilities,
      aiMode: aiMode ?? this.aiMode,
      memoryEnabled: memoryEnabled ?? this.memoryEnabled,
    );
  }
}

/// What the AI is allowed to do in the current context.
enum OmniCapability {
  readInbox,
  readConversation,
  readNotifications,
  readConnectorStatus,
  draftReply,
  sendMessage,
  markRead,
  setPriority,
  searchInbox,
  searchMessages,
  summarize,
  translate,
  assignConversation,
  readProject,
  readMedia,
  modifyProject,
  applyEffect,
  exportProject,
  deleteProject,
}

/// Global AI operating mode. Default is assist (conservative).
enum AiOperatingMode {
  /// AI is completely off. No operations allowed.
  off,

  /// AI can read and explain. No mutations.
  assist,

  /// AI may create drafts. No external sends.
  draft,

  /// AI may prepare external actions, but user must confirm each one.
  approval,

  /// AI may execute explicitly allowed actions automatically.
  auto,
}

/// Resolves the minimal, safe context needed for an Omni Command request.
/// The context is scoped to what the user is currently doing.
/// Sensitive data (messages, tokens) is NEVER included here — only IDs.
class OmniContextResolver {
  /// Build context from the current application state.
  /// [userId] must be the authenticated Firebase UID.
  /// [activeRoute] is the current GoRouter path.
  /// All other parameters are optional and route-dependent.
  OmniContext resolve({
    required String sessionId,
    required String userId,
    String surface = 'unknown',
    String? activeRoute,
    String? conversationId,
    String? messageId,
    String? platformId,
    String? connectorId,
    String? searchQuery,
    String? projectId,
    String? sequenceId,
    String? clipId,
    String? assetId,
    String? selectedMaskId,
    String? selectedEffectId,
    String? selectedLutId,
    String? selectedPresetId,
    String? selectedContactId,
    String? selectedChannelId,
    List<String> selectedMessageIds = const [],
    AiOperatingMode aiMode = AiOperatingMode.assist,
    bool memoryEnabled = true,
  }) {
    final capabilities = _resolveCapabilities(
      surface: surface,
      activeRoute: activeRoute,
      conversationId: conversationId,
      projectId: projectId,
      aiMode: aiMode,
    );

    return OmniContext(
      sessionId: sessionId,
      userId: userId,
      surface: surface,
      activeRoute: activeRoute,
      conversationId: conversationId,
      messageId: messageId,
      platformId: platformId,
      connectorId: connectorId,
      searchQuery: searchQuery,
      projectId: projectId,
      sequenceId: sequenceId,
      clipId: clipId,
      assetId: assetId,
      selectedMaskId: selectedMaskId,
      selectedEffectId: selectedEffectId,
      selectedLutId: selectedLutId,
      selectedPresetId: selectedPresetId,
      selectedContactId: selectedContactId,
      selectedChannelId: selectedChannelId,
      selectedMessageIds: selectedMessageIds,
      capabilities: capabilities,
      aiMode: aiMode,
      memoryEnabled: memoryEnabled,
    );
  }

  Set<OmniCapability> _resolveCapabilities({
    required String surface,
    String? activeRoute,
    String? conversationId,
    String? projectId,
    required AiOperatingMode aiMode,
  }) {
    if (aiMode == AiOperatingMode.off) return const {};

    final caps = <OmniCapability>{
      OmniCapability.readInbox,
      OmniCapability.readNotifications,
      OmniCapability.readConnectorStatus,
      OmniCapability.searchInbox,
      OmniCapability.searchMessages,
    };

    if (surface == 'pro_editor' || surface == 'photo_studio' || surface == 'creator_studio' || projectId != null) {
      caps.add(OmniCapability.readProject);
      caps.add(OmniCapability.readMedia);
    }

    // Context-specific capabilities
    if (conversationId != null) {
      caps.add(OmniCapability.readConversation);
      caps.add(OmniCapability.summarize);
      caps.add(OmniCapability.translate);
    }

    // Write capabilities only above assist mode
    if (aiMode == AiOperatingMode.draft ||
        aiMode == AiOperatingMode.approval ||
        aiMode == AiOperatingMode.auto) {
      caps.add(OmniCapability.draftReply);
      caps.add(OmniCapability.markRead);
      caps.add(OmniCapability.setPriority);
      
      if (surface == 'pro_editor' || surface == 'photo_studio' || surface == 'creator_studio' || projectId != null) {
        caps.add(OmniCapability.modifyProject);
        caps.add(OmniCapability.applyEffect);
      }
    }

    // Send only in approval or auto mode
    if (aiMode == AiOperatingMode.approval || aiMode == AiOperatingMode.auto) {
      caps.add(OmniCapability.sendMessage);
      caps.add(OmniCapability.assignConversation);
      if (surface == 'pro_editor' || surface == 'photo_studio' || surface == 'creator_studio' || projectId != null) {
        caps.add(OmniCapability.exportProject);
        caps.add(OmniCapability.deleteProject);
      }
    }

    return caps;
  }
}

// ---------------------------------------------------------------------------
// Riverpod Provider
// ---------------------------------------------------------------------------

final omniContextResolverProvider = Provider<OmniContextResolver>((ref) {
  return OmniContextResolver();
});

/// Mutable notifier holding the current OmniContext.
/// Updated by the active screen/route whenever context changes.
class OmniContextNotifier extends Notifier<OmniContext?> {
  @override
  OmniContext? build() => null;

  /// Called by the active screen to register its context.
  void updateContext(OmniContext context) {
    state = context;
  }

  void clearConversationContext() {
    final current = state;
    if (current == null) return;
    state = OmniContext(
      sessionId: current.sessionId,
      userId: current.userId,
      surface: current.surface,
      activeRoute: current.activeRoute,
      platformId: current.platformId,
      connectorId: current.connectorId,
      searchQuery: current.searchQuery,
      projectId: current.projectId,
      sequenceId: current.sequenceId,
      clipId: current.clipId,
      assetId: current.assetId,
      selectedMaskId: current.selectedMaskId,
      selectedEffectId: current.selectedEffectId,
      selectedLutId: current.selectedLutId,
      selectedPresetId: current.selectedPresetId,
      selectedContactId: current.selectedContactId,
      selectedChannelId: current.selectedChannelId,
      capabilities: current.capabilities,
      aiMode: current.aiMode,
      memoryEnabled: current.memoryEnabled,
    );
  }

  void updateRoute(String route) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(activeRoute: route);
  }
}

final omniContextProvider =
    NotifierProvider<OmniContextNotifier, OmniContext?>(
  OmniContextNotifier.new,
);

/// Builds a fresh sessionId for a new Omni Command interaction.
String buildOmniSessionId() {
  String uid = 'anonymous';
  try {
    uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonymous';
  } catch (_) {}
  final ts = DateTime.now().millisecondsSinceEpoch;
  return 'omni_${uid}_$ts';
}
