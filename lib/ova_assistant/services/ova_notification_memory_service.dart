import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../backend/notifications/models/app_notification.dart';
import '../../backend/notifications/models/notification_preferences.dart';
import '../core/ova_tool_result.dart';
import 'ova_device_hub.dart';
import 'ova_tool_registry.dart';

/// One notification remembered silently in the background by Ova.
class LearnedNotificationEntry {
  final String id;
  final String sourceApp;
  final String packageName;
  final String category;
  final String sender;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isExternal;
  final bool canReply;
  final String? notificationKey;
  final String? route;

  const LearnedNotificationEntry({
    required this.id,
    required this.sourceApp,
    required this.packageName,
    required this.category,
    required this.sender,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isExternal = false,
    this.canReply = false,
    this.notificationKey,
    this.route,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'sourceApp': sourceApp,
        'packageName': packageName,
        'category': category,
        'sender': sender,
        'title': title,
        'body': body,
        'timestampMs': timestamp.millisecondsSinceEpoch,
        'isExternal': isExternal,
        'canReply': canReply,
        if (notificationKey != null) 'notificationKey': notificationKey,
        if (route != null) 'route': route,
      };

  factory LearnedNotificationEntry.fromMap(Map<String, dynamic> m) {
    final tsMs = (m['timestampMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;
    return LearnedNotificationEntry(
      id: (m['id'] ?? '').toString(),
      sourceApp: (m['sourceApp'] ?? 'Oneova').toString(),
      packageName: (m['packageName'] ?? '').toString(),
      category: (m['category'] ?? 'general').toString(),
      sender: (m['sender'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      body: (m['body'] ?? '').toString(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMs),
      isExternal: m['isExternal'] == true,
      canReply: m['canReply'] == true,
      notificationKey: m['notificationKey'] as String?,
      route: m['route'] as String?,
    );
  }
}

/// Silently learns notifications in the background (without popping up on screen)
/// and syncs them to `users/{uid}/ova_context/notification_digest` so Gemini / Ova
/// is aware of them ONLY when the user asks about previous notifications.
class OvaNotificationMemoryService {
  OvaNotificationMemoryService._();
  static final OvaNotificationMemoryService instance =
      OvaNotificationMemoryService._();

  final List<LearnedNotificationEntry> _entries = [];
  Timer? _syncDebounce;
  bool _loadedFromBackend = false;
  String? _loadedUid;

  List<LearnedNotificationEntry> get entries => List.unmodifiable(_entries);

  static const Set<String> toolNames = {
    'recall_previous_notifications',
    'mute_notification_source',
  };

  List<OvaToolSpec> get specs => [
        const OvaToolSpec(
          'recall_previous_notifications',
          'Recall previous notifications that arrived in the background (from Oneova or other apps) when the user asks about past alerts, messages, or what they missed.',
          properties: {
            'query': {
              'type': 'string',
              'description':
                  'Optional app name, sender name, or keyword to filter previous notifications (e.g. "WhatsApp", "live", "comment")',
            },
            'limit': {
              'type': 'integer',
              'description': 'Max notifications to return (default 10)',
            },
          },
        ),
        const OvaToolSpec(
          'mute_notification_source',
          'Block or mute notifications and background AI learning from a specific app, sender, category, or keyword that the user does not want information from.',
          properties: {
            'target': {
              'type': 'string',
              'description':
                  'App name (e.g. "WhatsApp", "TikTok"), category ("external_apps", "ai_suggestions", "promotions", "social_likes", "comments"), or keyword/sender to mute.',
            },
          },
          required: ['target'],
        ),
      ];

  /// Detects whether the user's prompt is asking about previous notifications,
  /// messages, alerts, or what happened earlier.
  bool isAskingAboutNotifications(String userPrompt) {
    final q = userPrompt.toLowerCase();
    return RegExp(
      r'\b(notification|notifications|alert|alerts|missed|who messaged|who texted|'
      r'previous message|previous notification|last notification|recent notification|'
      r'any message|any messages|what did i get|what came in|other app|whatsapp|telegram|'
      r'inbox|unread|updates|pinged|rang)\b',
    ).hasMatch(q);
  }

  /// Warm the in-memory list from the backend digest once per signed-in user.
  Future<void> warm() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_loadedFromBackend && _loadedUid == uid) return;
    _loadedFromBackend = true;
    _loadedUid = uid;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ova_context')
          .doc('notification_digest')
          .get();
      if (!doc.exists) return;
      final data = doc.data();
      final list = data?['recent'] as List?;
      if (list == null) return;
      final existingIds = _entries.map((e) => e.id).toSet();
      for (final raw in list) {
        if (raw is Map) {
          final entry =
              LearnedNotificationEntry.fromMap(Map<String, dynamic>.from(raw));
          if (entry.id.isNotEmpty && existingIds.add(entry.id)) {
            _entries.add(entry);
          }
        }
      }
      _entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (_entries.length > 40) {
        _entries.removeRange(40, _entries.length);
      }
    } catch (e) {
      debugPrint('[OvaNotificationMemory] warm error: $e');
    }
  }

  /// Silently learns an Oneova in-app notification in the background,
  /// skipping any source/keyword the user blocked.
  void learnAppNotification(
    AppNotification n,
    NotificationPreferences prefs,
  ) {
    final isExt = n.payload?['isExternalApp'] == true;
    final appName = (n.payload?['appName'] ?? 'Oneova').toString();
    final pkg = (n.payload?['packageName'] ?? '').toString();
    final sender = (n.payload?['senderName'] ?? n.title).toString();
    if (prefs.shouldIgnoreNotification(
      category: n.category.name,
      packageName: pkg,
      appName: appName,
      sender: sender,
      title: n.title,
      body: n.body,
      isExternal: isExt,
    )) {
      return;
    }

    _insertEntry(
      LearnedNotificationEntry(
        id: n.id,
        sourceApp: isExt ? appName : 'Oneova',
        packageName: pkg,
        category: n.category.name,
        sender: sender,
        title: n.title,
        body: n.body,
        timestamp: n.createdAt,
        isExternal: isExt,
        canReply: n.payload?['canReply'] == true ||
            n.category == AppNotificationCategory.newMessage,
        notificationKey: n.payload?['notificationKey']?.toString(),
        route: n.route,
      ),
    );
  }

  /// Silently learns an external phone notification in the background,
  /// skipping any blocked app or muted keyword.
  void learnExternalNotification(
    OvaPhoneNotification ext,
    NotificationPreferences prefs,
  ) {
    final appLabel = ext.app.isNotEmpty ? ext.app : 'External App';
    if (prefs.shouldIgnoreNotification(
      packageName: ext.package,
      appName: appLabel,
      sender: ext.title,
      title: ext.title,
      body: ext.text,
      isExternal: true,
    )) {
      return;
    }
    final id = 'ext_${ext.key}_${ext.postTime.millisecondsSinceEpoch}';
    _insertEntry(
      LearnedNotificationEntry(
        id: id,
        sourceApp: appLabel,
        packageName: ext.package,
        category: 'external_app',
        sender: ext.title.isNotEmpty ? ext.title : appLabel,
        title: ext.title.isNotEmpty ? ext.title : appLabel,
        body: ext.text,
        timestamp: ext.postTime,
        isExternal: true,
        canReply: ext.canReply,
        notificationKey: ext.key,
      ),
    );
  }

  void _insertEntry(LearnedNotificationEntry entry) {
    _entries.removeWhere((e) =>
        e.id == entry.id ||
        (entry.notificationKey != null &&
            entry.notificationKey!.isNotEmpty &&
            e.notificationKey == entry.notificationKey &&
            e.body == entry.body));
    _entries.insert(0, entry);
    if (_entries.length > 40) {
      _entries.removeRange(40, _entries.length);
    }
    _scheduleBackendSync();
  }

  /// Removes any already-learned notifications that match newly muted sources/keywords.
  void pruneMuted(NotificationPreferences prefs) {
    _entries.removeWhere(
      (e) => prefs.shouldIgnoreNotification(
        category: e.category,
        packageName: e.packageName,
        appName: e.sourceApp,
        sender: e.sender,
        title: e.title,
        body: e.body,
        isExternal: e.isExternal,
      ),
    );
    _scheduleBackendSync();
  }

  void _scheduleBackendSync() {
    _syncDebounce?.cancel();
    _syncDebounce = Timer(const Duration(seconds: 4), _syncToFirestore);
  }

  Future<void> _syncToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final slice = _entries.take(25).map((e) => e.toMap()).toList();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ova_context')
          .doc('notification_digest')
          .set({
        'updatedAt': FieldValue.serverTimestamp(),
        'count': slice.length,
        'recent': slice,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[OvaNotificationMemory] backend sync error: $e');
    }
  }

  /// Context block injected into Ova's system prompt ONLY when the user asks
  /// about previous notifications or messages.
  String buildOnDemandContext({String? latestUserQuery}) {
    if (latestUserQuery == null ||
        !isAskingAboutNotifications(latestUserQuery)) {
      return 'Background notification memory: ${_entries.length} recent notifications learned silently (call recall_previous_notifications only if the user asks about notifications or messages).';
    }
    if (_entries.isEmpty) {
      return 'Background notification memory: No recent notifications recorded yet.';
    }
    final fmt = DateFormat('HH:mm');
    final lines = _entries.take(12).map((e) {
      final time = fmt.format(e.timestamp);
      return '- [$time · ${e.sourceApp}] ${e.title}: ${e.body}${e.canReply ? ' (can reply)' : ''}';
    }).join('\n');
    return 'Learned previous notifications (user asked about notifications/messages — use this context to answer accurately):\n$lines';
  }

  Future<OvaToolResult> runTool(
    String name,
    Map<String, dynamic> args, {
    required NotificationPreferences prefs,
    required Future<void> Function(Map<String, dynamic> fields) savePrefs,
  }) async {
    await warm();
    if (name == 'recall_previous_notifications') {
      final q = (args['query'] ?? '').toString().trim().toLowerCase();
      final limit = (args['limit'] is num ? (args['limit'] as num).toInt() : 10)
          .clamp(1, 25);
      var filtered = _entries.where((e) => !prefs.shouldIgnoreNotification(
            category: e.category,
            packageName: e.packageName,
            appName: e.sourceApp,
            sender: e.sender,
            title: e.title,
            body: e.body,
            isExternal: e.isExternal,
          ));
      if (q.isNotEmpty) {
        filtered = filtered.where((e) =>
            e.sourceApp.toLowerCase().contains(q) ||
            e.title.toLowerCase().contains(q) ||
            e.body.toLowerCase().contains(q) ||
            e.category.toLowerCase().contains(q));
      }
      final list = filtered.take(limit).toList();
      if (list.isEmpty) {
        return OvaToolResult(
          ok: true,
          title: 'No matching notifications',
          summary: q.isEmpty
              ? 'No previous notifications have arrived in your background digest yet.'
              : 'No previous notifications matching "$q" were found.',
          icon: Icons.notifications_none_rounded,
        );
      }
      final fmt = DateFormat('HH:mm');
      final lines = <String>[];
      final items = <OvaResultItem>[];
      for (final e in list) {
        final t = fmt.format(e.timestamp);
        lines.add('[$t · ${e.sourceApp}] ${e.title}: ${e.body}');
        items.add(
          OvaResultItem(
            title: '${e.sourceApp} · ${e.title}',
            subtitle: '$t — ${e.body}',
            icon: e.isExternal
                ? Icons.phone_android_rounded
                : Icons.notifications_active_rounded,
            onTap: e.route != null
                ? OvaResultAction(
                    label: 'Open',
                    icon: Icons.open_in_new_rounded,
                    route: e.route,
                  )
                : OvaResultAction(
                    label: 'Mute ${e.sourceApp}',
                    icon: Icons.notifications_off_rounded,
                    prompt: 'mute notifications from ${e.sourceApp}',
                  ),
          ),
        );
      }
      return OvaToolResult(
        ok: true,
        title: '${list.length} previous notification${list.length == 1 ? '' : 's'}',
        summary: 'Previous notifications learned in background:\n${lines.join('\n')}',
        icon: Icons.history_rounded,
        items: items,
      );
    }

    if (name == 'mute_notification_source') {
      final target = (args['target'] ?? '').toString().trim();
      if (target.isEmpty) {
        return OvaToolResult.fail('Tell me which app, source, or keyword to mute.');
      }
      final lower = target.toLowerCase();
      const knownSources = {
        'external_apps',
        'ai_suggestions',
        'promotions',
        'social_likes',
        'comments',
        'live_streams',
        'system',
      };
      const knownApps = <String, String>{
        'whatsapp': 'com.whatsapp',
        'instagram': 'com.instagram.android',
        'tiktok': 'com.zhiliaoapp.musically',
        'telegram': 'org.telegram.messenger',
        'youtube': 'com.google.android.youtube',
        'facebook': 'com.facebook.katana',
        'twitter': 'com.twitter.android',
        'x': 'com.twitter.android',
        'messages': 'com.google.android.apps.messaging',
        'sms': 'com.google.android.apps.messaging',
      };

      if (knownSources.contains(lower)) {
        final next = {...prefs.mutedSources, lower}.toList();
        await savePrefs({'mutedSources': next});
      } else if (knownApps.containsKey(lower)) {
        final pkg = knownApps[lower]!;
        final next = {...prefs.blockedExternalPackages, pkg, target}.toList();
        await savePrefs({'blockedExternalPackages': next});
      } else {
        final next = {...prefs.mutedKeywords, target}.toList();
        await savePrefs({'mutedKeywords': next});
      }
      pruneMuted(prefs);
      return OvaToolResult(
        ok: true,
        title: 'Muted "$target"',
        summary:
            'You will no longer get notifications or background updates from "$target".',
        icon: Icons.notifications_off_rounded,
        actions: const [
          OvaResultAction(
            label: 'Manage muted sources',
            icon: Icons.tune_rounded,
            route: '/settings/notifications',
          ),
        ],
      );
    }

    return OvaToolResult.fail('Unknown notification memory tool "$name".');
  }
}
