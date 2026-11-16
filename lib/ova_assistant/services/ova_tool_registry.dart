import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../backend/calling/providers/active_call_controller.dart';
import '../../backend/messaging_repository.dart';
import '../../backend/remote_connect_service.dart';
import '../../backend/search/models/search_result.dart';
import '../../backend/search/search_service.dart';
import '../../backend/social/models/comment.dart';
import '../../backend/social/repositories/interaction_repository.dart';
import '../../backend/social/repositories/relationship_repository.dart';
import '../../backend/social/services/comment_service.dart';
import '../../backend/notifications/models/notification_preferences.dart';
import '../../backend/notifications/providers/notification_service.dart';
import '../../shared/theme/theme_provider.dart';
import '../core/ova_tool_result.dart';
import 'ova_abilities.dart';
import 'ova_android_tools.dart';
import 'ova_connected_tools.dart';
import 'ova_context_service.dart';
import 'ova_device_abilities.dart';
import 'ova_device_control.dart';
import 'ova_geo_tools.dart';
import 'ova_instagram_tools.dart';
import 'ova_memory_tools.dart';
import 'ova_notification_memory_service.dart';
import 'ova_studio_tools.dart';

/// Screen-level context handed to the assistant by the screen that opened it.
class OvaInvocationContext {
  /// The reel being watched when Ova was opened from the feed.
  final String? contentId;

  /// The chat open when Ova was opened from a conversation.
  final String? chatId;

  const OvaInvocationContext({this.contentId, this.chatId});
}

/// Definition of one tool the model (or the local parser) can call.
class OvaToolSpec {
  final String name;
  final String description;
  final Map<String, dynamic> properties;
  final List<String> required;
  final OvaRisk risk;

  const OvaToolSpec(
    this.name,
    this.description, {
    this.properties = const {},
    this.required = const [],
    this.risk = OvaRisk.safe,
  });

  Map<String, dynamic> toOpenAi() => {
        'type': 'function',
        'function': {
          'name': name,
          'description': description,
          'parameters': {
            'type': 'object',
            'properties': properties,
            'required': required,
          },
        },
      };

  Map<String, dynamic> toGemini() => {
        'name': name,
        'description': description,
        'parameters': properties.isEmpty
            ? {'type': 'OBJECT', 'properties': {'_': {'type': 'STRING', 'description': 'unused'}}}
            : {
                'type': 'OBJECT',
                'properties': properties.map((k, v) => MapEntry(k, _geminiSchema(v as Map<String, dynamic>))),
                'required': required,
              },
      };

  static Map<String, dynamic> _geminiSchema(Map<String, dynamic> s) => {
        ...s,
        'type': (s['type'] as String).toUpperCase(),
      };
}

Map<String, dynamic> _str(String d, [List<String>? enumValues]) =>
    {'type': 'string', 'description': d, 'enum': ?enumValues};
Map<String, dynamic> _int(String d) => {'type': 'integer', 'description': d};
Map<String, dynamic> _bool(String d) => {'type': 'boolean', 'description': d};

/// In-app destinations Ova may open. Every one is a real go_router route.
const Map<String, String> ovaScreens = {
  'home': '/hub/home',
  'messages': '/hub/messages',
  'ai_lab': '/hub/ai',
  'discover': '/hub/discover',
  'biz_feed': '/biz_feed',
  'notifications': '/notifications',
  'my_profile': '/profile/me',
  'settings': '/settings',
  'ai_settings': '/settings/ai',
  'privacy_settings': '/settings/privacy',
  'notification_settings': '/settings/notifications',
  'camera': '/create/camera',
  'upload': '/upload/global',
  'drafts': '/create/picker',
  'photo_studio': '/photo/studio',
  'ai_studio': '/ai_studio',
  'go_live': '/live/setup',
  'live_studio': '/live/setup?mode=studio',
  'connect_pc': '/connect',
  'social_inbox': '/hub/messages',
  'social_analytics': '/social_hub/analytics',
  'youtube': '/social_hub',
  'ova_triggers': '/ova/triggers',
  'ova_setup': '/ova/setup',
  'ova_abilities': '/ova/abilities',
  'verify_email': '/auth/email_code?purpose=verify_email',
  'security': '/profile/security',
};

/// Registry of every tool Ova can run, with a real handler for each.
class OvaToolRegistry {
  final Ref ref;
  final OvaDeviceAbilities device;

  OvaToolRegistry(this.ref, this.device);

  static bool get _android => !kIsWeb && Platform.isAndroid;

  List<OvaToolSpec> get specs => [
        // ── In-app ──
        OvaToolSpec('open_screen', 'Open a screen inside the Oneova app.', properties: {
          'screen': _str('Which screen', ovaScreens.keys.toList()),
        }, required: ['screen']),
        OvaToolSpec('search_oneova', 'Search Oneova for people, hashtags and posts. Shows tappable results.', properties: {
          'query': _str('Search text, e.g. a username or #tag'),
        }, required: ['query']),
        OvaToolSpec('open_profile', 'Open a creator profile by username.', properties: {
          'username': _str('Username without @'),
        }, required: ['username']),
        OvaToolSpec('open_hashtag', 'Open a hashtag page.', properties: {
          'tag': _str('Hashtag without #'),
        }, required: ['tag']),
        OvaToolSpec('follow_user', 'Follow a creator on Oneova (by username, or user_id when known).', properties: {
          'username': _str('Username without @'),
          'user_id': _str('Oneova user id, if known instead of username'),
        }, risk: OvaRisk.confirm),
        OvaToolSpec('unfollow_user', 'Unfollow a creator on Oneova.', properties: {
          'username': _str('Username without @'),
          'user_id': _str('Oneova user id, if known'),
        }, risk: OvaRisk.confirm),
        OvaToolSpec('start_app_call', 'Start an Oneova voice or video call with a user (opens the call screen once it rings).', properties: {
          'username': _str('Username without @'),
          'user_id': _str('Oneova user id, if known'),
          'video': _bool('true for video call'),
        }, risk: OvaRisk.confirm),
        OvaToolSpec('set_app_theme', 'Switch the Oneova app theme in the background.', properties: {
          'mode': _str('Theme', ['light', 'dark', 'system']),
        }, required: ['mode']),
        OvaToolSpec('send_app_message', 'Send a direct message to a person on Oneova, in the background.', properties: {
          'username': _str('Recipient username without @'),
          'user_id': _str('Recipient user id, if known'),
          'text': _str('Message text'),
        }, required: ['text'], risk: OvaRisk.confirm),
        OvaToolSpec('like_current_reel', 'Like the reel the user is watching (only when Ova was opened from a reel).'),
        OvaToolSpec('comment_current_reel', 'Post a comment on the reel the user is watching.', properties: {
          'text': _str('Comment text'),
        }, required: ['text'], risk: OvaRisk.confirm),
        OvaToolSpec('pc_command', 'Send a command to the paired computer (Oneova desktop agent).', properties: {
          'command': _str('Command', ['switch_window', 'take_screenshot', 'render_timeline', 'sleep']),
        }, required: ['command'], risk: OvaRisk.confirm),
        // ── Phone ──
        OvaToolSpec('call_phone', 'Call a phone number or a contact by name. Opens the dialer.', properties: {
          'to': _str('Phone number or contact name'),
        }, required: ['to'], risk: OvaRisk.confirm),
        OvaToolSpec('send_sms', 'Write an SMS to a number or contact. Opens the Messages composer.', properties: {
          'to': _str('Phone number or contact name'),
          'body': _str('Message text'),
        }, required: ['to', 'body'], risk: OvaRisk.confirm),
        OvaToolSpec('send_whatsapp', 'Write a WhatsApp message to a number or contact.', properties: {
          'to': _str('Phone number with country code, or contact name'),
          'text': _str('Message text'),
        }, required: ['to', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('send_email', 'Write an email. Opens the mail app with a draft.', properties: {
          'to': _str('Email address'),
          'subject': _str('Subject'),
          'body': _str('Body'),
        }, required: ['to', 'subject', 'body'], risk: OvaRisk.confirm),
        OvaToolSpec('find_contact', 'Look up a contact phone number by name.', properties: {
          'name': _str('Contact name'),
        }, required: ['name']),
        OvaToolSpec('open_app', 'Open another app on the phone.', properties: {
          'app': _str('App name, e.g. whatsapp, youtube, instagram, maps, spotify, settings'),
        }, required: ['app']),
        OvaToolSpec('open_url', 'Open a web link in the browser.', properties: {
          'url': _str('https URL'),
        }, required: ['url']),
        OvaToolSpec('take_photo', 'Open the camera to take a photo.'),
        OvaToolSpec('share_text', 'Open the share sheet with some text or a link.', properties: {
          'text': _str('Text to share'),
        }, required: ['text']),
        OvaToolSpec('copy_text', 'Copy text to the clipboard.', properties: {
          'text': _str('Text to copy'),
        }, required: ['text']),
        OvaToolSpec('read_clipboard', 'Read the text currently on the clipboard.'),
        OvaToolSpec('add_calendar_event', 'Add an event to the calendar (opens the system editor to save).', properties: {
          'title': _str('Event title'),
          'start': _str('Start in ISO 8601 local time, e.g. 2026-10-16T15:00'),
          'end': _str('Optional end in ISO 8601 local time'),
          'location': _str('Optional location'),
          'notes': _str('Optional notes'),
        }, required: ['title', 'start']),
        OvaToolSpec('set_alarm', 'Set an alarm.', properties: {
          'hour': _int('Hour 0-23'),
          'minute': _int('Minute 0-59'),
          'label': _str('Optional label'),
        }, required: ['hour', 'minute']),
        OvaToolSpec('set_timer', 'Start a countdown timer.', properties: {
          'seconds': _int('Length in seconds'),
          'label': _str('Optional label'),
        }, required: ['seconds']),
        OvaToolSpec('flashlight', 'Turn the flashlight on or off.', properties: {
          'on': _bool('true to turn on'),
        }, required: ['on']),
        OvaToolSpec('set_volume', 'Set media volume.', properties: {
          'percent': _int('0-100'),
        }, required: ['percent']),
        OvaToolSpec('set_brightness', 'Set screen brightness while Oneova is open.', properties: {
          'percent': _int('5-100'),
        }, required: ['percent']),
        ...OvaGeoTools.instance.specs,
        ...OvaMemoryTools.instance.specs,
        ...OvaNotificationMemoryService.instance.specs,
        ...ref.read(ovaStudioToolsProvider).specs,
        OvaToolSpec('device_status', 'Read battery level and charging state.'),
        OvaToolSpec('open_settings', 'Open the phone Settings app.'),
        if (_android) ...ref.read(ovaAndroidToolsProvider).specs,
        ...ref.read(ovaConnectedToolsProvider).specs,
        ...ref.read(ovaInstagramToolsProvider).specs,
        if (_android)
          OvaToolSpec(
            'device_control',
            'Android only: control the phone screen through the Ova accessibility service '
                '(back, home, recent apps, open notifications, quick settings, screenshot, scroll up/down, tap <text>, type <text>, lock the phone). '
                'Chain it with open_app and read_screen to work inside other apps; check read_screen after each step.',
            properties: {'command': _str('The command in plain words, e.g. "scroll down" or "tap Send"')},
            required: ['command'],
          ),
      ];

  OvaToolSpec? spec(String name) {
    for (final s in specs) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// Builds the confirmation card for a risky tool.
  /// Builds the confirmation card for a risky tool, with its service badge,
  /// verb and whether it needs press-and-hold.
  OvaPendingAction describe(String name, Map<String, dynamic> a) {
    final base = _describeBase(name, a);
    const style = <String, (String, String, bool)>{
      'call_phone': ('phone', 'Call', false),
      'send_sms': ('phone', 'Open', false),
      'send_whatsapp': ('whatsapp', 'Open', false),
      'send_email': ('phone', 'Open', false),
      'follow_user': ('oneova', 'Follow', false),
      'unfollow_user': ('oneova', 'Unfollow', false),
      'start_app_call': ('oneova', 'Call', false),
      'send_app_message': ('oneova', 'Send', false),
      'comment_current_reel': ('oneova', 'Post', true),
      'pc_command': ('oneova', 'Run', false),
      'reply_notification': ('phone', 'Reply', false),
      'dismiss_notification': ('phone', 'Clear', false),
    };
    final st = style[name];
    if (st == null || base.service != 'oneova' || base.confirmLabel != 'Confirm') return base;
    final to = (a['to'] ?? a['username'] ?? '').toString().trim();
    return OvaPendingAction(
      toolName: base.toolName,
      args: base.args,
      title: base.title,
      detail: base.detail,
      icon: base.icon,
      note: base.note,
      service: st.$1,
      confirmLabel: st.$2,
      hold: st.$3,
      target: to.isEmpty ? null : (a['username'] != null ? '@${_handle(to)}' : to),
    );
  }

  OvaPendingAction _describeBase(String name, Map<String, dynamic> a) {
    String s(String k) => (a[k] ?? '').toString();
    switch (name) {
      case 'call_phone':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.call_rounded,
          title: 'Call ${s('to')}?', detail: 'Opens your dialer with this number.',
          note: Platform.isIOS ? 'iOS will ask once more before calling.' : 'You press the green button to start the call.',
        );
      case 'send_sms':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.sms_rounded,
          title: 'Text ${s('to')}?', detail: s('body'),
          note: 'Opens Messages with this text. You tap send.',
        );
      case 'send_whatsapp':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.chat_rounded,
          title: 'WhatsApp ${s('to')}?', detail: s('text'),
          note: 'Opens WhatsApp with this text. You tap send.',
        );
      case 'send_email':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.email_rounded,
          title: 'Email ${s('to')}?', detail: '${s('subject')}\n\n${s('body')}',
          note: 'Opens your mail app with this draft.',
        );
      case 'follow_user':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.person_add_alt_1_rounded,
          title: 'Follow ${_who(a)}?', detail: 'You will see their posts in Following.',
        );
      case 'unfollow_user':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.person_remove_alt_1_rounded,
          title: 'Unfollow ${_who(a)}?', detail: 'Their posts leave your Following feed.',
        );
      case 'start_app_call':
        return OvaPendingAction(
          toolName: name, args: a, icon: a['video'] == true ? Icons.videocam_rounded : Icons.call_rounded,
          title: '${a['video'] == true ? 'Video' : 'Voice'} call ${_who(a)}?', detail: 'Rings them on Oneova now.',
        );
      case 'send_app_message':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.send_rounded,
          title: 'Message ${_who(a)}?', detail: s('text'),
          note: 'Sends right away as you on Oneova.',
        );
      case 'comment_current_reel':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.mode_comment_rounded,
          title: 'Post this comment?', detail: s('text'),
          note: 'Posts publicly on this reel as you.',
        );
      case 'pc_command':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.desktop_windows_rounded,
          title: 'Run "${s('command')}" on your computer?', detail: 'Sends the command to your paired workstation.',
        );
      default:
        if (OvaStudioTools.names.contains(name)) return ref.read(ovaStudioToolsProvider).describe(name, a);
        final connected = ref.read(ovaConnectedToolsProvider).describe(name, a);
        if (connected != null) return connected;
        final instagram = ref.read(ovaInstagramToolsProvider).describe(name, a);
        if (instagram != null) return instagram;
        final android = ref.read(ovaAndroidToolsProvider).describe(name, a);
        if (android != null) return android;
        return OvaPendingAction(toolName: name, args: a, icon: Icons.bolt_rounded, title: 'Run $name?', detail: a.toString());
    }
  }

  /// Runs a tool. [context] is used for permission prompts only.
  Future<OvaToolResult> run(
    String name,
    Map<String, dynamic> a,
    BuildContext? context,
    OvaInvocationContext inv,
  ) async {
    String s(String k) => (a[k] ?? '').toString().trim();
    int i(String k, [int d = 0]) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;

    if (OvaGeoTools.names.contains(name)) return OvaGeoTools.instance.run(name, a);
    if (OvaStudioTools.names.contains(name)) return ref.read(ovaStudioToolsProvider).run(name, a);
    if (OvaMemoryTools.names.contains(name)) {
      return OvaMemoryTools.instance.run(name, a, device, context != null && context.mounted ? context : null);
    }
    switch (name) {
      case 'open_screen':
        final route = ovaScreens[s('screen')];
        if (route == null) return OvaToolResult.fail('I do not know the screen "${s('screen')}".');
        return OvaToolResult(ok: true, summary: 'Opening ${s('screen').replaceAll('_', ' ')}.', icon: Icons.open_in_new_rounded, navigateTo: route);
      case 'search_oneova':
        return _search(s('query'));
      case 'open_profile':
        final user = await _findUser(s('username'));
        if (user == null) return _search(s('username'));
        return OvaToolResult(ok: true, summary: 'Opening @${user.username}.', icon: Icons.person_rounded, navigateTo: '/profile/${user.uid}');
      case 'open_hashtag':
        final tag = s('tag').replaceAll('#', '').trim();
        if (tag.isEmpty) return OvaToolResult.fail('Which hashtag?');
        return OvaToolResult(ok: true, summary: 'Opening #$tag.', icon: Icons.tag_rounded, navigateTo: '/social/explore/hashtag/${Uri.encodeComponent(tag)}');
      case 'follow_user':
        return _follow(s('username'), uid: s('user_id'));
      case 'unfollow_user':
        return _unfollow(s('username'), uid: s('user_id'));
      case 'start_app_call':
        return _call(s('username'), uid: s('user_id'), video: a['video'] == true || s('video') == 'true');
      case 'set_app_theme':
        final mode = switch (s('mode')) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
        await ref.read(themeProvider.notifier).setThemeMode(mode);
        return OvaToolResult(ok: true, summary: 'Theme set to ${mode.name}.', icon: Icons.dark_mode_rounded);
      case 'send_app_message':
        return _sendAppMessage(s('username'), s('text'), uid: s('user_id'));
      case 'like_current_reel':
        return _like(inv);
      case 'comment_current_reel':
        return _comment(inv, s('text'));
      case 'pc_command':
        return _pcCommand(s('command'));

      case 'call_phone':
        final n = await device.resolveNumber(context, s('to'));
        if (n == null) return OvaToolResult.fail('I could not find a number for "${s('to')}".', icon: Icons.person_search_rounded);
        return device.dial(n);
      case 'send_sms':
        final n = await device.resolveNumber(context, s('to'));
        if (n == null) return OvaToolResult.fail('I could not find a number for "${s('to')}".', icon: Icons.person_search_rounded);
        return device.composeSms(n, s('body'));
      case 'send_whatsapp':
        final n = await device.resolveNumber(context, s('to'));
        if (n == null) return OvaToolResult.fail('I could not find a number for "${s('to')}".', icon: Icons.person_search_rounded);
        return device.whatsapp(n, s('text'));
      case 'send_email':
        return device.composeEmail(s('to'), s('subject'), s('body'));
      case 'find_contact':
        return device.findContacts(context, s('name'));
      case 'open_app':
        return device.openApp(s('app'));
      case 'open_url':
        return device.openUrl(s('url'));
      case 'take_photo':
        return device.takePhoto(context);
      case 'share_text':
        return device.share(s('text'));
      case 'copy_text':
        return device.copy(s('text'));
      case 'read_clipboard':
        return device.readClipboard();
      case 'add_calendar_event':
        final start = DateTime.tryParse(s('start'));
        if (start == null) return OvaToolResult.fail('I need a start time for the event.');
        return device.addCalendarEvent(
          title: s('title'),
          start: start,
          end: DateTime.tryParse(s('end')),
          location: s('location').isEmpty ? null : s('location'),
          notes: s('notes').isEmpty ? null : s('notes'),
        );
      case 'set_alarm':
        return device.setAlarm(context, i('hour').clamp(0, 23), i('minute').clamp(0, 59), s('label'));
      case 'set_timer':
        final secs = i('seconds');
        if (secs <= 0) return OvaToolResult.fail('How long should the timer be?');
        return device.setTimer(context, secs, s('label'));
      case 'flashlight':
        final on = a['on'] == true || s('on') == 'true';
        return device.flashlight(on);
      case 'set_volume':
        return device.setVolume(i('percent', 50));
      case 'set_brightness':
        return device.setBrightness(i('percent', 60));
      case 'device_status':
        await ref.read(ovaContextProvider.notifier).refresh();
        return device.deviceStatus();
      case 'open_settings':
        return device.openSystemSettings();
      case 'device_control':
        if (!_android) return OvaToolResult.unsupported('Screen control is only available on Android.');
        if (!ref.read(ovaAbilitiesProvider).screenControl) {
          return const OvaToolResult(ok: false, summary: 'Screen control is turned off in Ova abilities.', icon: Icons.toggle_off_rounded,
              actions: [OvaResultAction(label: 'Ova abilities', icon: Icons.tune_rounded, route: '/ova/abilities')]);
        }
        final res = await ref.read(ovaDeviceControlProvider).execute(s('command'));
        if (res == null) return OvaToolResult.fail('I did not understand that screen command.');
        return OvaToolResult(ok: res.ok, summary: res.message, icon: res.ok ? Icons.touch_app_rounded : Icons.error_outline_rounded,
            actions: res.ok ? const [] : const [OvaResultAction(label: 'Ova setup', icon: Icons.tune_rounded, route: '/ova/setup')]);
    }
    if (OvaNotificationMemoryService.toolNames.contains(name)) {
      final prefs = ref.read(notificationPreferencesProvider).value ?? NotificationPreferences();
      return OvaNotificationMemoryService.instance.runTool(
        name,
        a,
        prefs: prefs,
        savePrefs: (fields) => ref.read(notificationServiceProvider).updatePreferenceFields(fields),
      );
    }
    if (OvaConnectedTools.names.contains(name)) {
      return ref.read(ovaConnectedToolsProvider).run(name, a, context != null && context.mounted ? context : null);
    }
    if (OvaInstagramTools.names.contains(name)) {
      return ref.read(ovaInstagramToolsProvider).run(name, a);
    }
    if (OvaAndroidTools.names.contains(name)) {
      return ref.read(ovaAndroidToolsProvider).run(name, a, context != null && context.mounted ? context : null);
    }
    return OvaToolResult.fail('Unknown action "$name".');
  }

  // ── In-app handlers ────────────────────────────────────────────────────

  String? get _uid {
    final u = FirebaseAuth.instance.currentUser;
    if (u == null || u.isAnonymous) return null;
    return u.uid;
  }

  static const _signIn = OvaResultAction(label: 'Sign in', icon: Icons.login_rounded, route: '/auth/main_login');

  static String _handle(String raw) => raw.replaceAll('@', '').trim().toLowerCase();

  Future<_FoundUser?> _findUser(String raw) async {
    final h = _handle(raw);
    if (h.isEmpty) return null;
    final snap = await FirebaseFirestore.instance.collection('users').where('username', isEqualTo: h).limit(1).get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return _FoundUser(d.id, (d.data()['username'] as String?) ?? h, (d.data()['displayName'] as String?) ?? h);
  }

  Future<OvaToolResult> _search(String query) async {
    if (query.isEmpty) return OvaToolResult.fail('What should I search for?');
    try {
      final results = await ref.read(searchServiceProvider).exactSearch(query: query, limit: 8);
      if (results.isEmpty) {
        return OvaToolResult(ok: true, summary: 'Nothing on Oneova matches "$query".', icon: Icons.search_off_rounded);
      }
      final items = <OvaResultItem>[];
      for (final r in results.take(8)) {
        String? route;
        IconData icon = Icons.article_rounded;
        switch (r.type) {
          case SearchEntityType.person:
            route = '/profile/${r.id}';
            icon = Icons.person_rounded;
            break;
          case SearchEntityType.hashtag:
            route = '/social/explore/hashtag/${Uri.encodeComponent(r.id)}';
            icon = Icons.tag_rounded;
            break;
          case SearchEntityType.video:
          case SearchEntityType.post:
            route = '/hub/home?v=${r.id}';
            icon = Icons.play_circle_rounded;
            break;
          default:
            break;
        }
        final avatar = r.metadata['avatarUrl'];
        items.add(OvaResultItem(
          title: r.title,
          subtitle: r.subtitle,
          icon: icon,
          imageUrl: avatar is String && avatar.isNotEmpty ? avatar : null,
          onTap: route == null ? null : OvaResultAction(label: 'Open', icon: icon, route: route),
        ));
      }
      return OvaToolResult(
        ok: true,
        summary: 'Found ${results.length} results for "$query": ${results.take(5).map((r) => r.title).join(', ')}.',
        icon: Icons.search_rounded,
        items: items,
      );
    } catch (e) {
      return OvaToolResult.fail('Search failed: $e');
    }
  }

  static String _who(Map<String, dynamic> a) {
    final u = (a['username'] ?? '').toString().trim();
    if (u.isNotEmpty) return '@${_handle(u)}';
    final n = (a['display_name'] ?? '').toString().trim();
    return n.isNotEmpty ? n : 'this creator';
  }

  Future<_FoundUser?> _resolve(String username, String uid) async {
    if (uid.isNotEmpty) {
      final d = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!d.exists) return null;
      final m = d.data() ?? const {};
      final un = (m['username'] as String?) ?? '';
      return _FoundUser(d.id, un.isEmpty ? (m['displayName'] as String? ?? 'creator') : un, (m['displayName'] as String?) ?? un);
    }
    return _findUser(username);
  }

  Future<OvaToolResult> _unfollow(String username, {String uid = ''}) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in first.', icon: Icons.lock_rounded, actions: [_signIn]);
    final user = await _resolve(username, uid);
    if (user == null) return OvaToolResult.fail('I could not find that creator.', icon: Icons.person_off_rounded);
    try {
      await ref.read(relationshipRepositoryProvider).unfollowUser(me, user.uid);
      return OvaToolResult(ok: true, summary: 'You unfollowed @${user.username}.', icon: Icons.person_remove_alt_1_rounded);
    } catch (e) {
      return OvaToolResult.fail('Could not unfollow: $e');
    }
  }

  Future<OvaToolResult> _call(String username, {String uid = '', required bool video}) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in to call.', icon: Icons.lock_rounded, actions: [_signIn]);
    final user = await _resolve(username, uid);
    if (user == null) return OvaToolResult.fail('I could not find that creator.', icon: Icons.person_off_rounded);
    try {
      await ref.read(activeCallControllerProvider.notifier).startCall(targetUserIds: [user.uid], isVideo: video, title: user.displayName);
      return OvaToolResult(ok: true, summary: 'Calling @${user.username}…', icon: video ? Icons.videocam_rounded : Icons.call_rounded, navigateTo: '/call/active');
    } catch (e) {
      return OvaToolResult.fail(e is StateError ? e.message : 'Could not start the call: $e');
    }
  }

  Future<OvaToolResult> _follow(String username, {String uid = ''}) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in to follow creators.', icon: Icons.lock_rounded, actions: [_signIn]);
    final user = await _resolve(username, uid);
    if (user == null) return OvaToolResult.fail('No Oneova user is called @${_handle(username)}.', icon: Icons.person_off_rounded);
    if (user.uid == me) return OvaToolResult.fail('That is your own account.');
    try {
      await ref.read(relationshipRepositoryProvider).followUser(me, user.uid);
      return OvaToolResult(
        ok: true,
        summary: 'You now follow @${user.username}.',
        icon: Icons.person_add_alt_1_rounded,
        actions: [OvaResultAction(label: 'View profile', icon: Icons.person_rounded, route: '/profile/${user.uid}')],
      );
    } catch (e) {
      return OvaToolResult.fail('Could not follow @${user.username}: $e');
    }
  }

  Future<OvaToolResult> _sendAppMessage(String username, String text, {String uid = ''}) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in to send messages.', icon: Icons.lock_rounded, actions: [_signIn]);
    if (text.isEmpty) return OvaToolResult.fail('The message is empty.');
    final user = await _resolve(username, uid);
    if (user == null) return OvaToolResult.fail('No Oneova user is called @${_handle(username)}.', icon: Icons.person_off_rounded);
    try {
      final repo = ref.read(messagingRepositoryProvider);
      final chatId = await repo.getOrCreateDirectChat(me, user.uid);
      await repo.sendMessage(chatId, me, text, recipientId: user.uid);
      return OvaToolResult(
        ok: true,
        summary: 'Sent to @${user.username}.',
        icon: Icons.mark_chat_read_rounded,
        actions: [OvaResultAction(label: 'Open chat', icon: Icons.chat_bubble_rounded, route: '/hub/messages/$chatId')],
      );
    } catch (e) {
      return OvaToolResult.fail('Message not sent: $e');
    }
  }

  Future<OvaToolResult> _like(OvaInvocationContext inv) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in to like reels.', icon: Icons.lock_rounded, actions: [_signIn]);
    final id = inv.contentId;
    if (id == null) return OvaToolResult.fail('Open Ova from a reel (the Ova button on the video) so I know which one to like.');
    try {
      final repo = ref.read(interactionRepositoryProvider);
      if (await repo.isContentLikedBy(me, id)) {
        return const OvaToolResult(ok: true, summary: 'You already like this reel.', icon: Icons.favorite_rounded);
      }
      await repo.likeContent(me, id);
      return const OvaToolResult(ok: true, summary: 'Liked this reel.', icon: Icons.favorite_rounded);
    } catch (e) {
      return OvaToolResult.fail('Could not like the reel: $e');
    }
  }

  Future<OvaToolResult> _comment(OvaInvocationContext inv, String text) async {
    final me = _uid;
    if (me == null) return const OvaToolResult(ok: false, summary: 'Sign in to comment.', icon: Icons.lock_rounded, actions: [_signIn]);
    final id = inv.contentId;
    if (id == null) return OvaToolResult.fail('Open Ova from a reel so I know where to comment.');
    if (text.isEmpty) return OvaToolResult.fail('The comment is empty.');
    try {
      await ref.read(commentServiceProvider).addComment(
            Comment(id: '', postId: id, authorId: me, content: text, createdAt: DateTime.now()),
          );
      return const OvaToolResult(ok: true, summary: 'Comment posted.', icon: Icons.mode_comment_rounded);
    } catch (e) {
      return OvaToolResult.fail('Comment not posted: $e');
    }
  }

  Future<OvaToolResult> _pcCommand(String command) async {
    final state = ref.read(remoteConnectProvider);
    if (state.linkedComputers.isEmpty) {
      return const OvaToolResult(
        ok: false,
        summary: 'No computer is paired yet.',
        icon: Icons.desktop_access_disabled_rounded,
        actions: [OvaResultAction(label: 'Pair a computer', icon: Icons.link_rounded, route: '/connect')],
      );
    }
    final notifier = ref.read(remoteConnectProvider.notifier);
    if (state.activeComputerId == null) notifier.setActiveComputer(state.linkedComputers.first.id);
    if (command == 'sleep') {
      await notifier.sleepWorkstation();
      return const OvaToolResult(ok: true, summary: 'Sleep sent to your computer.', icon: Icons.bedtime_rounded);
    }
    final id = await notifier.executeComputerCommand(command);
    return id != null
        ? OvaToolResult(ok: true, summary: 'Sent "$command" to your computer.', icon: Icons.desktop_windows_rounded)
        : OvaToolResult.fail('Your computer did not accept "$command".');
  }
}

class _FoundUser {
  final String uid;
  final String username;
  final String displayName;
  _FoundUser(this.uid, this.username, this.displayName);
}
