import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ova_tool_result.dart';
import 'ova_abilities.dart';
import 'ova_device_control.dart';
import 'ova_device_hub.dart';
import 'ova_tool_registry.dart';

Map<String, dynamic> _s(String d, [List<String>? e]) => {'type': 'string', 'description': d, 'enum': ?e};
Map<String, dynamic> _i(String d) => {'type': 'integer', 'description': d};
Map<String, dynamic> _b(String d) => {'type': 'boolean', 'description': d};

/// Device-awareness tools backed by OvaDeviceHub.kt (Android only).
/// Each one checks the user's opt-in in Ova abilities before touching data.
class OvaAndroidTools {
  final Ref ref;
  OvaAndroidTools(this.ref);

  OvaDeviceHub get _hub => ref.read(ovaDeviceHubProvider);
  OvaAbilities get _ab => ref.read(ovaAbilitiesProvider);

  /// Short ids (n1, n2…) the model uses for notifications → system keys.
  final Map<String, String> _noteIds = {};

  static const _abilitiesAction = OvaResultAction(label: 'Ova abilities', icon: Icons.tune_rounded, route: '/ova/abilities');

  static const names = {
    'read_notifications', 'reply_notification', 'open_notification', 'dismiss_notification',
    'device_overview', 'media_control', 'do_not_disturb', 'set_ringer', 'open_quick_panel', 'read_screen',
  };

  List<OvaToolSpec> get specs => [
        OvaToolSpec('read_notifications', 'Read the latest notifications on the phone (messages, apps). Returns ids n1, n2… for reply/open/dismiss.',
            properties: {'app': _s('Optional app name filter, e.g. WhatsApp'), 'limit': _i('How many, default 8')}),
        OvaToolSpec('reply_notification', 'Reply to a message notification directly (WhatsApp, Telegram, SMS…) without opening the app.',
            properties: {'id': _s('Notification id from read_notifications, e.g. n1'), 'text': _s('Reply text')},
            required: ['id', 'text'], risk: OvaRisk.confirm),
        OvaToolSpec('open_notification', 'Open the app a notification belongs to.', properties: {'id': _s('Notification id, e.g. n1')}, required: ['id']),
        OvaToolSpec('dismiss_notification', 'Clear a notification.', properties: {'id': _s('Notification id, e.g. n1')}, required: ['id'], risk: OvaRisk.confirm),
        OvaToolSpec('device_overview',
            'Live device state: battery, network, storage, memory, ringer, Do Not Disturb, in-call, now playing, app in front.'),
        OvaToolSpec('media_control', 'Control whatever music or video is playing on the phone.',
            properties: {'action': _s('Action', ['play_pause', 'play', 'pause', 'next', 'previous', 'stop'])}, required: ['action']),
        OvaToolSpec('do_not_disturb', 'Turn Do Not Disturb on or off.', properties: {'on': _b('true to turn on')}, required: ['on']),
        OvaToolSpec('set_ringer', 'Set the ringer to normal, vibrate or silent.',
            properties: {'mode': _s('Mode', ['normal', 'vibrate', 'silent'])}, required: ['mode']),
        OvaToolSpec('open_quick_panel', 'Open a system panel or settings page so the user can flip it (Android blocks apps from toggling these directly).',
            properties: {
              'panel': _s('Panel', ['wifi', 'internet', 'bluetooth', 'volume', 'nfc', 'battery', 'display', 'location', 'airplane', 'hotspot', 'data_usage', 'storage', 'apps', 'notifications'])
            },
            required: ['panel']),
        OvaToolSpec('read_screen', 'Read the text on the screen of the app currently in front (needs Screen control). Use it to check the result of device_control steps.'),
      ];

  OvaPendingAction? describe(String name, Map<String, dynamic> a) {
    final id = (a['id'] ?? '').toString();
    final n = _note(id);
    switch (name) {
      case 'reply_notification':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.reply_rounded,
          title: 'Reply to ${n?.title.isNotEmpty == true ? n!.title : 'this message'}${n != null ? ' on ${n.app}' : ''}?',
          detail: (a['text'] ?? '').toString(),
          note: 'Sends right away through ${n?.app ?? 'the app'}, without opening it.',
        );
      case 'dismiss_notification':
        return OvaPendingAction(
          toolName: name, args: a, icon: Icons.clear_all_rounded,
          title: 'Clear this notification?', detail: n == null ? id : '${n.app} · ${n.title}\n${n.text}',
        );
    }
    return null;
  }

  OvaPhoneNotification? _note(String id) {
    final key = _noteIds[id];
    if (key == null) return null;
    for (final n in ref.read(ovaDeviceEventsProvider).notifications) {
      if (n.key == key) return n;
    }
    return _cache[key];
  }

  final Map<String, OvaPhoneNotification> _cache = {};

  Future<OvaToolResult> run(String name, Map<String, dynamic> a, BuildContext? context) async {
    if (!OvaDeviceHub.supported) {
      return OvaToolResult.unsupported('iOS does not let apps read notifications, SMS or control system settings, so this only works on Android.');
    }
    String s(String k) => (a[k] ?? '').toString().trim();
    int i(String k, int d) => a[k] is num ? (a[k] as num).toInt() : int.tryParse(s(k)) ?? d;

    switch (name) {
      case 'read_notifications':
        return _readNotifications(s('app'), i('limit', 8));
      case 'reply_notification':
        final key = _noteIds[s('id')];
        if (key == null) return OvaToolResult.fail('I do not know notification "${s('id')}". Read notifications first.');
        try {
          final r = await _hub.reply(key, s('text'));
          switch (r) {
            case 'ok':
              HapticFeedback.mediumImpact();
              return OvaToolResult(ok: true, summary: 'Reply sent: "${s('text')}".', icon: Icons.mark_chat_read_rounded);
            case 'gone':
              return OvaToolResult.fail('That notification is gone, so I cannot reply to it.');
            case 'no_reply':
              return OvaToolResult.fail('That app does not allow replies from notifications. I can open it instead.',
                  icon: Icons.reply_rounded);
            default:
              return OvaToolResult.fail('The reply failed ($r).');
          }
        } on PlatformException catch (e) {
          return _accessError(e);
        }
      case 'open_notification':
        final key = _noteIds[s('id')];
        if (key == null) return OvaToolResult.fail('I do not know notification "${s('id')}".');
        final ok = await _hub.openNotification(key);
        return ok
            ? const OvaToolResult(ok: true, summary: 'Opened it.', icon: Icons.open_in_new_rounded)
            : OvaToolResult.fail('That notification can no longer be opened.');
      case 'dismiss_notification':
        final key = _noteIds[s('id')];
        if (key == null) return OvaToolResult.fail('I do not know notification "${s('id')}".');
        final ok = await _hub.dismissNotification(key);
        return ok
            ? const OvaToolResult(ok: true, summary: 'Notification cleared.', icon: Icons.clear_all_rounded)
            : OvaToolResult.fail('Could not clear it.');
      case 'device_overview':
        return _overview();
      case 'media_control':
        await _hub.mediaKey(s('action').isEmpty ? 'play_pause' : s('action'));
        return OvaToolResult(ok: true, summary: 'Media: ${s('action').replaceAll('_', '/')}.', icon: Icons.play_circle_rounded);
      case 'do_not_disturb':
        final on = a['on'] == true || s('on') == 'true';
        final r = await _hub.setDnd(on);
        if (r == 'ok') {
          return OvaToolResult(ok: true, summary: 'Do Not Disturb ${on ? 'on' : 'off'}.',
              icon: on ? Icons.do_not_disturb_on_rounded : Icons.do_not_disturb_off_rounded);
        }
        return OvaToolResult(
          ok: false,
          summary: 'Allow Oneova to change Do Not Disturb once, then ask again.',
          icon: Icons.do_not_disturb_on_rounded,
          actions: const [OvaResultAction(label: 'Allow access', icon: Icons.lock_open_rounded, url: 'ova://dnd_access')],
        );
      case 'set_ringer':
        final r = await _hub.setRinger(s('mode'));
        if (r == 'ok') return OvaToolResult(ok: true, summary: 'Ringer set to ${s('mode')}.', icon: Icons.vibration_rounded);
        return OvaToolResult(
          ok: false,
          summary: 'Android needs Do Not Disturb access for silent mode.',
          icon: Icons.volume_off_rounded,
          actions: const [OvaResultAction(label: 'Allow access', icon: Icons.lock_open_rounded, url: 'ova://dnd_access')],
        );
      case 'open_quick_panel':
        final ok = await _hub.openPanel(s('panel'));
        return ok
            ? OvaToolResult(ok: true, summary: 'Opened the ${s('panel').replaceAll('_', ' ')} panel. Android only lets you flip it yourself.',
                icon: Icons.tune_rounded)
            : OvaToolResult.fail('This phone has no ${s('panel')} panel.');
      case 'read_screen':
        if (!_ab.screenControl) return _disabled('Screen control');
        final dc = ref.read(ovaDeviceControlProvider);
        if (!await dc.isEnabled()) {
          return const OvaToolResult(
            ok: false,
            summary: 'Turn on "Oneova Ova" in Accessibility settings to let me read the screen.',
            icon: Icons.accessibility_new_rounded,
            actions: [_abilitiesAction],
          );
        }
        final pkg = await dc.foregroundPackage();
        final text = await dc.readScreen();
        final clipped = text.length > 2500 ? '${text.substring(0, 2500)}…' : text;
        return OvaToolResult(ok: true, summary: 'Screen of $pkg:\n$clipped', icon: Icons.chrome_reader_mode_rounded);
    }
    return OvaToolResult.fail('Unknown action "$name".');
  }

  OvaToolResult _disabled(String what) => OvaToolResult(
        ok: false,
        summary: '$what is turned off in Ova abilities.',
        icon: Icons.toggle_off_rounded,
        actions: const [_abilitiesAction],
      );

  OvaToolResult _accessError(PlatformException e) {
    if (e.code == 'NO_ACCESS') {
      return const OvaToolResult(
        ok: false,
        summary: 'Notification access is off for Oneova.',
        icon: Icons.notifications_off_rounded,
        actions: [_abilitiesAction],
      );
    }
    return OvaToolResult.fail(e.message ?? 'Device error.');
  }

  Future<OvaToolResult> _readNotifications(String app, int limit) async {
    if (!_ab.readNotifications) return _disabled('Reading notifications');
    try {
      var list = await _hub.notifications(limit: 30);
      if (app.isNotEmpty) {
        final f = app.toLowerCase();
        list = list.where((n) => n.app.toLowerCase().contains(f) || n.package.toLowerCase().contains(f)).toList();
      }
      list = list.take(limit.clamp(1, 20)).toList();
      if (list.isEmpty) {
        return OvaToolResult(ok: true, summary: app.isEmpty ? 'No notifications right now.' : 'No $app notifications.',
            icon: Icons.notifications_none_rounded);
      }
      _noteIds.clear();
      final lines = <String>[];
      final items = <OvaResultItem>[];
      for (var k = 0; k < list.length; k++) {
        final n = list[k];
        final id = 'n${k + 1}';
        _noteIds[id] = n.key;
        _cache[n.key] = n;
        lines.add('[$id] ${n.app} · ${n.title}: ${n.text}${n.canReply ? ' (can reply)' : ''}');
        items.add(OvaResultItem(
          title: '${n.app} · ${n.title}',
          subtitle: n.text,
          icon: Icons.notifications_rounded,
          onTap: n.canReply
              ? OvaResultAction(label: 'Reply', icon: Icons.reply_rounded, prompt: 'Help me reply to notification $id from ${n.title}')
              : OvaResultAction(label: 'Open', icon: Icons.open_in_new_rounded, prompt: 'open notification $id'),
        ));
      }
      return OvaToolResult(ok: true, title: '${list.length} notifications', summary: 'Notifications:\n${lines.join('\n')}', icon: Icons.notifications_active_rounded, items: items);
    } on PlatformException catch (e) {
      return _accessError(e);
    }
  }

  Future<OvaToolResult> _overview() async {
    if (!_ab.deviceState) return _disabled('Device state');
    try {
      final d = await _hub.deviceState();
      final np = d['nowPlaying'] as Map?;
      final lines = <String>[
        'Battery ${d['battery']}%${d['charging'] == true ? ' (charging)' : ''}',
        'Network ${d['network']}${d['internet'] == true ? '' : ' (no internet)'}${d['airplane'] == true ? ', airplane mode' : ''}',
        'Storage ${d['storageFreeGb']} GB free of ${d['storageTotalGb']} GB',
        'Memory ${d['ramFreeGb']} GB free${d['lowMemory'] == true ? ' (low)' : ''}',
        'Ringer ${d['ringer']}${d['dnd'] == true ? ', Do Not Disturb on' : ''}, media volume ${d['mediaVolume']}%',
        if (d['inCall'] == true) 'On a call now',
        if (np != null && (np['title'] ?? '').toString().isNotEmpty)
          'Now playing: ${np['title']}${(np['artist'] ?? '').toString().isNotEmpty ? ' — ${np['artist']}' : ''}${np['playing'] == true ? '' : ' (paused)'}'
        else if (d['musicActive'] == true)
          'Audio is playing',
        if ((d['foregroundApp'] ?? '').toString().isNotEmpty) 'App in front: ${d['foregroundApp']}',
        '${d['manufacturer']} ${d['model']}, Android ${d['android']}',
      ];
      return OvaToolResult(ok: true, title: 'Phone status', summary: lines.join('\n'), icon: Icons.phone_android_rounded,
          items: [for (final l in lines) OvaResultItem(title: l, icon: Icons.fiber_manual_record_rounded)]);
    } on PlatformException catch (e) {
      return OvaToolResult.fail(e.message ?? 'Could not read the device state.');
    }
  }

}

final ovaAndroidToolsProvider = Provider<OvaAndroidTools>((ref) => OvaAndroidTools(ref));
