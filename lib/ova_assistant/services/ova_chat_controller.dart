import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../auth/services/app_lifecycle_observer.dart' show rootNavigatorKey;
import '../../backend/ai_brain_service.dart';
import '../../backend/security/secure_api_key_vault.dart';
import '../core/ova_tool_result.dart';
import 'ova_abilities.dart';
import 'ova_android_tools.dart';
import 'ova_context_service.dart';
import 'ova_device_hub.dart';
import 'ova_device_abilities.dart';
import 'ova_geo_tools.dart';
import 'ova_llm_client.dart';
import 'ova_local_intents.dart';
import 'ova_memory_tools.dart';
import 'ova_task_center.dart';
import 'ova_tool_registry.dart';

final ovaToolRegistryProvider = Provider<OvaToolRegistry>((ref) {
  return OvaToolRegistry(ref, OvaDeviceAbilities(ref.read(ovaNativeServiceProvider)));
});

final ovaLlmClientProvider = Provider<OvaLlmClient>((ref) {
  return OvaLlmClient(ref.watch(aiBrainProvider), ref.watch(secureKeyVaultProvider));
});

/// The one Ova conversation for the whole app. It outlives the sheet, so a
/// task keeps running (and reporting progress) while the user browses.
final ovaChatProvider = Provider<OvaChatController>((ref) {
  final c = OvaChatController(
    registry: ref.read(ovaToolRegistryProvider),
    llm: ref.read(ovaLlmClientProvider),
    tasks: ref.read(ovaTaskCenterProvider.notifier),
  );
  ref.onDispose(c.dispose);
  return c;
});

enum OvaItemKind { user, assistant, result, confirm, notice }

enum OvaConfirmState { pending, confirmed, cancelled }

/// One row in the conversation.
class OvaItem {
  final String id;
  final OvaItemKind kind;
  String text;
  bool streaming;
  OvaToolResult? result;
  OvaPendingAction? pending;
  OvaConfirmState confirmState;
  Completer<bool>? _decision;
  final DateTime createdAt = DateTime.now();

  /// A confirmation nobody answered in [confirmTimeout] is cancelled.
  bool expired = false;

  OvaItem._(this.kind, {this.text = '', this.streaming = false, this.result, this.pending})
      : id = '${DateTime.now().microsecondsSinceEpoch}_${kind.name}',
        confirmState = OvaConfirmState.pending;
}

/// How long a confirmation card stays valid.
const Duration confirmTimeout = Duration(minutes: 2);

/// Runs one Ova conversation: local commands, streaming model replies,
/// tool calls and confirmation cards.
class OvaChatController extends ChangeNotifier {
  final OvaToolRegistry registry;
  final OvaLlmClient llm;
  final OvaTaskCenter tasks;

  /// Screen context from whoever opened Ova last (reel, chat).
  OvaInvocationContext invocation = const OvaInvocationContext();

  /// Called after a turn when a tool asked to open an in-app route.
  /// The sheet swaps this in while it is open so it can close itself first.
  void Function(String route)? onNavigate;

  OvaChatController({
    required this.registry,
    required this.llm,
    required this.tasks,
  });

  String? _taskId;

  /// The newest confirmation still waiting for the user, if any.
  OvaItem? get pendingConfirm {
    for (final i in items.reversed) {
      if (i.kind == OvaItemKind.confirm && i.confirmState == OvaConfirmState.pending) return i;
    }
    return null;
  }

  /// The newest tool result (shown in the dock).
  OvaToolResult? get lastResult {
    for (final i in items.reversed) {
      if (i.result != null) return i.result;
    }
    return null;
  }

  /// The newest assistant text.
  String? get lastReply {
    for (final i in items.reversed) {
      if (i.kind == OvaItemKind.assistant && i.text.trim().isNotEmpty) return i.text.trim();
    }
    return null;
  }

  void _defaultNavigate(String route) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null) GoRouter.of(ctx).push(route);
  }

  final List<OvaItem> items = [];
  final List<Map<String, dynamic>> _history = [];
  bool busy = false;
  bool _disposed = false;
  int _turn = 0;

  /// Context used for permission prompts (set by the sheet).
  BuildContext? _permissionContext;
  set permissionContext(BuildContext? c) => _permissionContext = c;
  BuildContext? get permissionContext {
    final c = _permissionContext;
    if (c != null && c.mounted) return c;
    return rootNavigatorKey.currentContext;
  }

  bool get isEmpty => items.isEmpty;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in items) {
      if (i._decision != null && !i._decision!.isCompleted) i._decision!.complete(false);
    }
    super.dispose();
  }

  void reset() {
    stop();
    items.clear();
    _history.clear();
    _notify();
  }

  /// Stops the current turn (streaming text stays as-is).
  void stop() {
    _turn++;
    for (final i in items) {
      i.streaming = false;
      if (i._decision != null && !i._decision!.isCompleted) {
        i.confirmState = OvaConfirmState.cancelled;
        i._decision!.complete(false);
      }
    }
    busy = false;
    final t = _taskId;
    if (t != null) tasks.finish(t, ok: false, cancelled: true);
    _taskId = null;
    _notify();
  }

  void decide(OvaItem item, bool confirmed) {
    if (item._decision == null || item._decision!.isCompleted) return;
    item.confirmState = confirmed ? OvaConfirmState.confirmed : OvaConfirmState.cancelled;
    item._decision!.complete(confirmed);
    _notify();
  }

  /// Runs one tool directly (suggestion buttons), as its own task.
  Future<void> runDirect(String label, String tool, Map<String, dynamic> args) =>
      send(label, direct: OvaLocalIntent(tool, args));

  Future<void> send(String input, {String? imageBase64, OvaLocalIntent? direct}) async {
    final text = input.trim();
    if (text.isEmpty || busy) return;
    final turn = ++_turn;
    busy = true;
    _taskId = tasks.start(text.length > 70 ? '${text.substring(0, 70)}…' : text);
    items.add(OvaItem._(OvaItemKind.user, text: text));
    _history.add({'role': 'user', 'content': text});
    _notify();

    String? navigateTo;
    final replyLog = StringBuffer();
    try {
      final local = direct ?? (imageBase64 == null ? OvaLocalIntents.parse(text) : null);
      if (local != null) {
        final res = await _runTool(local.tool, local.args, turn);
        if (res != null) {
          navigateTo = res.navigateTo;
          replyLog.write(res.summary);
          _history.add({'role': 'assistant', 'content': res.summary});
        }
      } else if (!await llm.hasKey()) {
        const msg = 'Chat answers need an AI key. Commands like "call Mum", "flashlight on", '
            '"set a 5 min timer", "search #music" or "go live" work without one.';
        items.add(OvaItem._(
          OvaItemKind.notice,
          text: msg,
          result: const OvaToolResult(
            ok: false,
            summary: msg,
            icon: Icons.key_rounded,
            actions: [OvaResultAction(label: 'Add AI key', icon: Icons.key_rounded, route: '/settings/ai')],
          ),
        ));
        replyLog.write(msg);
      } else {
        navigateTo = await _modelLoop(turn, imageBase64, replyLog);
      }
    } catch (e) {
      debugPrint('[OvaChatController] turn error: $e');
      items.add(OvaItem._(OvaItemKind.notice, text: 'Something went wrong: $e'));
    }

    if (turn != _turn) return;
    busy = false;
    final taskId = _taskId;
    _taskId = null;
    if (taskId != null) {
      final failed = items.isNotEmpty && (items.last.kind == OvaItemKind.notice || (items.last.result?.ok == false));
      final reply = lastReply;
      final summary = items.isNotEmpty && items.last.kind == OvaItemKind.assistant
          ? reply
          : (items.isNotEmpty ? (items.last.result?.summary ?? items.last.text) : null);
      tasks.finish(taskId, ok: !failed, summary: summary == null ? null : (summary.length > 160 ? '${summary.substring(0, 160)}…' : summary));
    }
    _notify();
    _log(text, replyLog.toString());
    if (navigateTo != null && !_disposed) (onNavigate ?? _defaultNavigate)(navigateTo);
  }

  Future<String?> _modelLoop(int turn, String? imageBase64, StringBuffer replyLog) async {
    String? navigateTo;
    await OvaMemoryTools.instance.warm();
    for (var round = 0; round < 8; round++) {
      final bubble = OvaItem._(OvaItemKind.assistant, streaming: true);
      items.add(bubble);
      _notify();

      final calls = <OvaToolCall>[];
      String? error;
      await for (final ev in llm.stream(
        system: _systemPrompt(),
        history: _history,
        tools: registry.specs,
        imageBase64: round == 0 ? imageBase64 : null,
      )) {
        if (turn != _turn) return null;
        switch (ev) {
          case OvaTextDelta():
            bubble.text += ev.text;
            _notify();
          case OvaToolCallsEvent():
            calls.addAll(ev.calls);
          case OvaLlmError():
            error = ev.message;
        }
      }
      bubble.streaming = false;
      if (bubble.text.trim().isEmpty) items.remove(bubble);
      replyLog.write(bubble.text);

      if (error != null) {
        items.add(OvaItem._(OvaItemKind.notice, text: error));
        _notify();
        return navigateTo;
      }

      _history.add({
        'role': 'assistant',
        'content': bubble.text,
        if (calls.isNotEmpty)
          'tool_calls': calls
              .map((c) => {
                    'id': c.id,
                    'type': 'function',
                    'function': {'name': c.name, 'arguments': jsonEncode(c.args)},
                  })
              .toList(),
      });
      if (calls.isEmpty) return navigateTo;

      for (final c in calls) {
        final res = await _runTool(c.name, c.args, turn);
        if (turn != _turn) return null;
        navigateTo ??= res?.navigateTo;
        _history.add({
          'role': 'tool',
          'tool_call_id': c.id,
          'name': c.name,
          'content': res?.summary ?? 'The user cancelled this action.',
        });
      }
      // A navigation ends the turn: the sheet closes and the screen opens.
      if (navigateTo != null) return navigateTo;
    }
    return navigateTo;
  }

  /// Runs one tool, asking for confirmation first when it is risky.
  /// Returns null when the user cancelled.
  Future<OvaToolResult?> _runTool(String name, Map<String, dynamic> args, int turn) async {
    final spec = registry.spec(name);
    if (spec == null) {
      final r = OvaAndroidTools.names.contains(name) || name == 'device_control'
          ? OvaToolResult.unsupported('This works on Android only. iOS does not let apps read notifications, SMS or control other apps.')
          : OvaToolResult.fail('That action is not available here.');
      items.add(OvaItem._(OvaItemKind.result, result: r));
      _notify();
      return r;
    }
    final taskId = _taskId;
    final label = _stepLabel(name, args);
    var step = -1;
    if (spec.risk == OvaRisk.confirm) {
      final card = OvaItem._(OvaItemKind.confirm, pending: registry.describe(name, args));
      card._decision = Completer<bool>();
      items.add(card);
      // Stale approvals are dangerous: an unanswered card expires.
      Timer(confirmTimeout, () {
        if (card.confirmState == OvaConfirmState.pending) {
          card.expired = true;
          decide(card, false);
        }
      });
      if (taskId != null) step = tasks.addStep(taskId, 'Waiting for you: ${card.pending!.title}', card.pending!.icon, status: OvaStepStatus.waiting);
      _notify();
      final ok = await card._decision!.future;
      if (taskId != null) tasks.updateStep(taskId, step, ok ? OvaStepStatus.running : OvaStepStatus.failed, label: ok ? label : 'Cancelled: $label');
      if (!ok || turn != _turn) return null;
    } else if (taskId != null) {
      step = tasks.addStep(taskId, label, Icons.bolt_rounded);
    }
    final working = OvaItem._(OvaItemKind.result, streaming: true, text: '$label…');
    items.add(working);
    _notify();
    final res = await registry.run(name, args, permissionContext, invocation);
    if (name == 'set_reminder' || name == 'cancel_reminder') OvaMemoryTools.instance.invalidate();
    working
      ..streaming = false
      ..result = res;
    if (taskId != null && step >= 0) tasks.updateStep(taskId, step, res.ok ? OvaStepStatus.done : OvaStepStatus.failed);
    _notify();
    return res;
  }

  static String _stepLabel(String name, Map<String, dynamic> a) {
    final pretty = name.replaceAll('_', ' ');
    final cap = pretty[0].toUpperCase() + pretty.substring(1);
    final hint = a.values.whereType<String>().where((v) => v.trim().isNotEmpty).take(1).join();
    if (hint.isEmpty) return cap;
    final h = hint.length > 28 ? '${hint.substring(0, 28)}…' : hint;
    return '$cap · $h';
  }

  String _systemPrompt() {
    final now = DateTime.now();
    final platform = kIsWeb ? 'web' : (Platform.isIOS ? 'iOS' : (Platform.isAndroid ? 'Android' : Platform.operatingSystem));
    final phone = registry.ref.read(ovaContextProvider);
    return '''
You are Ova, the assistant inside the Oneova app (a short-video, live and creator studio app).
You can act on the user's phone and in the app through the tools provided.

Rules:
- Use a tool whenever the user asks you to do something. Never say you did something unless a tool result says so.
- Do things in the background with tools (message, follow, like, reply, settings…). Only call open_screen or open_app when the user asks to see or open something.
- For multi-step tasks, call one tool per step and check each result before the next. After the last step, reply in one short sentence.
- You can act on the user's own accounts: Gmail (gmail_*), YouTube (youtube_*), their connected Facebook Page (facebook_*) and WhatsApp (whatsapp_*). List first, then use the short ids (g1, y1, v1, f1, c1) the list returns. Draft replies yourself, then call the send/reply tool; the user approves on a card.
- On Android you can work inside other apps: open_app, then device_control steps, then read_screen to check. Use read_notifications / reply_notification to answer messages without opening apps.
- Sending, calling, following, messaging and posting show a confirmation card automatically. Do not ask "are you sure" yourself.
- If a tool result says something is unsupported on this platform, say so plainly and offer the closest alternative.
- If a needed detail is missing (who, what time), ask one short question.
- Keep answers short and friendly. Use Markdown lists only when they help.
- Location: use get_location for "where am I", find_nearby for places around them, navigate_to for directions. These show a live map in your reply, so do not repeat coordinates; give one useful line (closest open place, travel time, weak signal warning).
- Memory: use recent_activity when the user asks what they were doing or what to do next, and use it to make suggestions personal.
- Reminders: set_reminder needs a clock time. For "remind me when…" without a time, ask what time. list_reminders and cancel_reminder manage them.
- Times for tools are ISO 8601 local time. Now: ${DateFormat("yyyy-MM-dd'T'HH:mm (EEEE)").format(now)}.

Context:
- Platform: $platform. Battery ${(phone.batteryLevel * 100).round()}%${phone.isCharging ? ' (charging)' : ''}.
- Ova abilities the user allowed: ${_abilitiesLine()}.
- ${OvaGeoTools.instance.contextLine()}
- ${OvaMemoryTools.instance.contextLine()}
- ${invocation.contentId != null ? 'The user opened you from a reel, so like_current_reel and comment_current_reel work.' : 'No reel is open, so like/comment tools will not work.'}
- ${invocation.chatId != null ? 'The user opened you from a chat; help them draft replies when asked.' : ''}
''';
  }

  String _abilitiesLine() {
    final ab = registry.ref.read(ovaAbilitiesProvider);
    if (!OvaDeviceHub.supported) return 'iOS (no notification, SMS or screen access possible)';
    final on = <String>[
      if (ab.readNotifications) 'read/reply notifications',
      if (ab.deviceState) 'device state',
      if (ab.screenControl) 'screen control',
    ];
    final fresh = ab.readNotifications ? registry.ref.read(ovaDeviceEventsProvider).notifications.length : 0;
    return '${on.isEmpty ? 'basic only' : on.join(', ')}${fresh > 0 ? '; $fresh new notifications since Ova started' : ''}';
  }

  void _log(String query, String reply) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || reply.trim().isEmpty) return;
    FirebaseFirestore.instance.collection('users').doc(user.uid).collection('ai_interactions').add({
      'query': query,
      'response': reply,
      'status': 'completed',
      'kind': 'ova_assistant',
      'timestamp': FieldValue.serverTimestamp(),
    }).then<void>((_) {}, onError: (Object e) => debugPrint('[OvaChatController] history write failed: $e'));
  }
}
