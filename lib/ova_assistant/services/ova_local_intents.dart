import 'dart:io';

import 'package:flutter/foundation.dart';

import 'ova_tool_registry.dart';

/// A tool call recognised without the model.
class OvaLocalIntent {
  final String tool;
  final Map<String, dynamic> args;
  const OvaLocalIntent(this.tool, this.args);
}

/// Recognises clear, direct commands on-device so they work instantly and
/// without an AI key ("call mom", "flashlight on", "open messages").
/// Anything ambiguous returns null and goes to the model.
class OvaLocalIntents {
  static const Map<String, String> _screenAliases = {
    'home': 'home', 'feed': 'home', 'reels': 'home',
    'messages': 'messages', 'chats': 'messages', 'inbox': 'messages', 'chat': 'messages',
    'ai lab': 'ai_lab', 'discover': 'discover', 'explore': 'discover', 'biz': 'biz_feed', 'business feed': 'biz_feed',
    'notifications': 'notifications', 'alerts': 'notifications',
    'my profile': 'my_profile', 'profile': 'my_profile', 'me': 'my_profile',
    'oneova settings': 'settings', 'app settings': 'settings',
    'ai settings': 'ai_settings', 'ai key': 'ai_settings', 'api key': 'ai_settings', 'ai keys': 'ai_settings',
    'privacy settings': 'privacy_settings', 'notification settings': 'notification_settings',
    'camera': 'camera', 'upload': 'upload', 'drafts': 'drafts', 'photo studio': 'photo_studio', 'ai studio': 'ai_studio',
    'social inbox': 'social_inbox', 'analytics': 'social_analytics', 'youtube studio': 'youtube',
    'ova settings': 'ova_triggers', 'ova triggers': 'ova_triggers', 'ova setup': 'ova_setup',
    'pc': 'connect_pc', 'computer': 'connect_pc', 'workstation': 'connect_pc',
  };

  static OvaLocalIntent? parse(String input) {
    final raw = input.trim();
    final p = raw.toLowerCase().replaceAll(RegExp(r'^(hey |ok )?ova[,!]?\s*'), '').replaceAll(RegExp(r'[.!?]+$'), '').trim();
    if (p.isEmpty) return null;
    RegExpMatch? m;

    // Live
    if (RegExp(r'^(start|go|open)\s+(a\s+)?(live\s+studio|studio\s+live|multi.?cam live)').hasMatch(p)) {
      return const OvaLocalIntent('open_screen', {'screen': 'live_studio'});
    }
    if (RegExp(r'^(go live|start (a )?live( stream)?|start streaming|broadcast)$').hasMatch(p)) {
      return const OvaLocalIntent('open_screen', {'screen': 'go_live'});
    }
    if (RegExp(r'^(post|upload)( a)?( video| photo| something| reel)?$').hasMatch(p)) {
      return const OvaLocalIntent('open_screen', {'screen': 'upload'});
    }
    if (RegExp(r'^(record|film|shoot)( a)? (video|reel)$').hasMatch(p)) {
      return const OvaLocalIntent('open_screen', {'screen': 'camera'});
    }

    // Phone
    if ((m = RegExp(r'^(call|dial|ring|phone)\s+(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('call_phone', {'to': _orig(raw, m!.group(2)!)});
    }
    if ((m = RegExp(r'^(?:text|sms)\s+(.+?)\s+(?:saying|that|:)\s*(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('send_sms', {'to': _orig(raw, m!.group(1)!), 'body': _orig(raw, m.group(2)!)});
    }
    if ((m = RegExp(r'^whatsapp\s+(.+?)\s+(?:saying|that|:)\s*(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('send_whatsapp', {'to': _orig(raw, m!.group(1)!), 'text': _orig(raw, m.group(2)!)});
    }
    if ((m = RegExp(r'^(?:message|dm)\s+@(\w[\w.]*)\s+(?:saying\s+|that\s+|:\s*)?(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('send_app_message', {'username': m!.group(1)!, 'text': _orig(raw, m.group(2)!)});
    }
    if ((m = RegExp(r"^(?:find|look up|what'?s)\s+(?:the\s+)?(?:contact|number|phone number)\s+(?:for|of)\s+(.+)$").firstMatch(p)) != null) {
      return OvaLocalIntent('find_contact', {'name': _orig(raw, m!.group(1)!)});
    }

    // Social
    if ((m = RegExp(r'^follow\s+@?(\w[\w.]*)$').firstMatch(p)) != null) {
      return OvaLocalIntent('follow_user', {'username': m!.group(1)!});
    }
    if (RegExp(r'^like (this|it|this reel|this video)$').hasMatch(p)) {
      return const OvaLocalIntent('like_current_reel', {});
    }
    if ((m = RegExp(r'^comment\s+(?:on this\s+)?(?:saying\s+|:\s*)?(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('comment_current_reel', {'text': _orig(raw, m!.group(1)!)});
    }
    if ((m = RegExp(r'^search\s+(?:for\s+|oneova for\s+)?(.+)$').firstMatch(p)) != null ||
        (m = RegExp(r'^find\s+([@#]\S+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('search_oneova', {'query': _orig(raw, m!.group(1)!)});
    }
    if ((m = RegExp(r'^(?:open|show)\s+#(\w+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('open_hashtag', {'tag': m!.group(1)!});
    }
    if ((m = RegExp(r'^(?:open|show|go to)\s+@(\w[\w.]*)$').firstMatch(p)) != null) {
      return OvaLocalIntent('open_profile', {'username': m!.group(1)!});
    }

    // Connected accounts
    if (RegExp(r"^(check|read|show)( me)?( my)? (e-?mails?|gmail|inbox)$|^(any )?(new|unread) e-?mails?$").hasMatch(p)) {
      return const OvaLocalIntent('gmail_inbox', {});
    }
    if (RegExp(r'^(show |check )?(my )?youtube (stats|channel|analytics)$').hasMatch(p)) {
      return const OvaLocalIntent('youtube_channel', {});
    }
    if (RegExp(r'^(show |check |read )?(my )?(latest )?youtube comments$').hasMatch(p)) {
      return const OvaLocalIntent('youtube_comments', {});
    }
    if (RegExp(r'^(show )?(my )?(latest )?youtube videos$').hasMatch(p)) {
      return const OvaLocalIntent('youtube_videos', {});
    }
    if (RegExp(r'^(show |check )?(my )?facebook (page|stats|posts)$').hasMatch(p)) {
      return const OvaLocalIntent('facebook_page', {});
    }
    if (RegExp(r'^(show |check |read )?(my )?(latest )?facebook comments$').hasMatch(p)) {
      return const OvaLocalIntent('facebook_comments', {});
    }

    // Device awareness & Background Notification Memory
    if (RegExp(r"^(read|show|check|recall)( me)?( my)? (previous |past |recent )?(notifications|alerts)$|^(what'?s new|any new (messages|notifications)|what did i miss|what was my (last|previous) notification)$").hasMatch(p)) {
      return const OvaLocalIntent('recall_previous_notifications', {});
    }
    if ((m = RegExp(r'^(?:mute|block|stop)\s+(?:notifications?|alerts?|info|information)\s+(?:from|about)\s+(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('mute_notification_source', {'target': _orig(raw, m!.group(1)!)});
    }
    if ((m = RegExp(r'^(?:read|show|check)\s+(?:my\s+)?(\w+)\s+(?:notifications|messages)$').firstMatch(p)) != null &&
        !const {'my', 'the', 'new', 'sms', 'text'}.contains(m!.group(1))) {
      return OvaLocalIntent('read_notifications', {'app': m.group(1)!});
    }
    if (RegExp(r'^(pause|stop)( the)? (music|song|video|playback)$|^pause$').hasMatch(p)) {
      return const OvaLocalIntent('media_control', {'action': 'pause'});
    }
    if (RegExp(r'^(play|resume)( the)? (music|song|playback)$|^resume$').hasMatch(p)) {
      return const OvaLocalIntent('media_control', {'action': 'play'});
    }
    if (RegExp(r'^(next|skip)( the)?( song| track)?$').hasMatch(p)) {
      return const OvaLocalIntent('media_control', {'action': 'next'});
    }
    if (RegExp(r'^previous( song| track)?$').hasMatch(p)) {
      return const OvaLocalIntent('media_control', {'action': 'previous'});
    }
    if ((m = RegExp(r'^(?:turn\s+)?(on|off)\s+(?:do not disturb|dnd)$|^(?:turn\s+)?(?:do not disturb|dnd)\s+(on|off)$').firstMatch(p)) != null) {
      return OvaLocalIntent('do_not_disturb', {'on': (m!.group(1) ?? m.group(2)) == 'on'});
    }
    if ((m = RegExp(r'^(?:set\s+)?(?:the\s+)?(?:phone\s+)?(?:to\s+)?(silent|vibrate|normal|ring)\s+mode$|^(silent|vibrate)$').firstMatch(p)) != null) {
      final mode = m!.group(1) ?? m.group(2)!;
      return OvaLocalIntent('set_ringer', {'mode': mode == 'ring' ? 'normal' : mode});
    }
    if ((m = RegExp(r'^(?:switch to |turn on |use )?(dark|light) (?:mode|theme)$').firstMatch(p)) != null) {
      return OvaLocalIntent('set_app_theme', {'mode': m!.group(1)!});
    }
    if ((m = RegExp(r'^(?:turn (?:on|off) |open |toggle )?(wi-?fi|bluetooth|internet|nfc|hotspot|airplane mode|mobile data)(?: settings)?$').firstMatch(p)) != null) {
      final w = m!.group(1)!.replaceAll('-', '');
      final panel = switch (w) { 'airplane mode' => 'airplane', 'mobile data' => 'internet', _ => w };
      return OvaLocalIntent('open_quick_panel', {'panel': panel});
    }
    if (!kIsWeb && Platform.isAndroid && RegExp(r"^(phone status|device status|how'?s my phone|storage|how much storage( do i have)?|what'?s playing)$").hasMatch(p)) {
      return const OvaLocalIntent('device_overview', {});
    }
    if (RegExp(r"^(read (the|my) screen|what'?s on (the|my) screen)$").hasMatch(p)) {
      return const OvaLocalIntent('read_screen', {});
    }

    // Hardware
    if ((m = RegExp(r'^(?:turn\s+)?(?:the\s+)?(?:flashlight|torch|flash)\s+(on|off)$|^turn\s+(on|off)\s+(?:the\s+)?(?:flashlight|torch|flash)$').firstMatch(p)) != null) {
      final v = m!.group(1) ?? m.group(2);
      return OvaLocalIntent('flashlight', {'on': v == 'on'});
    }
    if ((m = RegExp(r'^(?:set\s+)?(?:the\s+)?volume\s+(?:to\s+)?(\d{1,3})\s*%?$').firstMatch(p)) != null) {
      return OvaLocalIntent('set_volume', {'percent': int.parse(m!.group(1)!)});
    }
    if (RegExp(r'^(mute|silence)( the phone| volume)?$').hasMatch(p)) {
      return const OvaLocalIntent('set_volume', {'percent': 0});
    }
    if ((m = RegExp(r'^(?:set\s+)?(?:the\s+)?brightness\s+(?:to\s+)?(\d{1,3})\s*%?$').firstMatch(p)) != null) {
      return OvaLocalIntent('set_brightness', {'percent': int.parse(m!.group(1)!)});
    }
    if ((m = RegExp(r'^(?:fly(?:\s+me)?\s+to|take me live to|zoom to)\s+(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('fly_to_place', {'destination': _orig(raw, m!.group(1)!)});
    }
    if (RegExp(r'^(?:show\s+)?(?:my\s+)?(?:map|location|places?)\s+history$').hasMatch(p)) {
      return const OvaLocalIntent('map_history', {});
    }
    if ((m = RegExp(r'^share (?:my )?live location(?:\s+for\s+(\d+)\s*(min|mins|minutes|h|hr|hour|hours))?$').firstMatch(p)) != null) {
      final rawNum = int.tryParse(m!.group(1) ?? '');
      final unit = m.group(2) ?? 'minutes';
      final mins = rawNum == null ? 60 : (unit.startsWith('h') ? rawNum * 60 : rawNum);
      return OvaLocalIntent('share_live_location', {'duration_minutes': mins});
    }
    if (RegExp(r'^(where am i|my location|share my location|what is my location)$').hasMatch(p)) {
      return const OvaLocalIntent('get_location', {'rotoscope': true});
    }
    if ((m = RegExp(r'^(start\s+navigation|start\s+directions|navigate|directions|get directions|route|guide me|how do i get|how to get)\s+(?:me\s+)?(?:to|for)\s+(.+)$').firstMatch(p)) != null) {
      final isStart = m!.group(1)!.startsWith('start');
      return OvaLocalIntent('navigate_to', {
        'destination': _orig(raw, m.group(2)!),
        'mode': 'driving',
        'start_navigation': isStart,
        'rotoscope': true,
      });
    }
    if ((m = RegExp(r'^(walk|drive|cycle|bike|ride)\s+(?:me\s+)?to\s+(.+)$').firstMatch(p)) != null) {
      final v = m!.group(1)!;
      return OvaLocalIntent('navigate_to', {
        'destination': _orig(raw, m.group(2)!),
        'mode': v == 'walk' ? 'walking' : (v == 'drive' ? 'driving' : 'cycling'),
        'start_navigation': true,
        'rotoscope': true,
      });
    }
    if (RegExp(r"^(what'?s|what is|show( me)?|anything)\s+(near me|nearby|around( me| here)?)$").hasMatch(p)) {
      return const OvaLocalIntent('find_nearby', {'what': ''});
    }
    if ((m = RegExp(r'^(?:find|show|search|any|where is|where are)?\s*(?:me\s+)?(?:the\s+|a\s+|an\s+|some\s+)?(?:nearest|closest)?\s*(.+?)\s+(?:near me|nearby|around( me| here)?|close by)$').firstMatch(p)) != null ||
        (m = RegExp(r'^(?:find\s+|show\s+|where is\s+)?(?:the\s+)?(?:nearest|closest)\s+(.+)$').firstMatch(p)) != null) {
      final what = m!.group(1)!.trim();
      if (what.isNotEmpty) return OvaLocalIntent('find_nearby', {'what': _orig(raw, what)});
    }
    if ((m = RegExp(r'^find\s+(.+?)\s+within\s+(\d+)\s*(km|m)$').firstMatch(p)) != null) {
      final n = int.parse(m!.group(2)!);
      return OvaLocalIntent('find_nearby', {'what': _orig(raw, m.group(1)!), 'radius_m': m.group(3) == 'km' ? n * 1000 : n});
    }
    if (RegExp(r'^(how is|how.?s|check)( my)? (signal|network|reception|connection)|^(signal|network) (strength|check)$').hasMatch(p)) {
      return const OvaLocalIntent('check_signal', {});
    }
    if (RegExp(r'^(what (was|have) i (been )?(doing|working on)|what am i working on|where did i leave off|my recent activity|recent activity)$').hasMatch(p)) {
      return const OvaLocalIntent('recent_activity', {});
    }
    if (RegExp(r'^(list|show)?\s*(my )?(upcoming )?reminders$').hasMatch(p)) {
      return const OvaLocalIntent('list_reminders', {});
    }
    if ((m = RegExp(r'^(?:cancel|delete|remove)\s+(?:the\s+|my\s+)?reminder\s+(?:to\s+|about\s+)?(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('cancel_reminder', {'query': _orig(raw, m!.group(1)!)});
    }
    if (RegExp(r'^(battery|battery level|how much battery( do i have)?)$').hasMatch(p)) {
      return const OvaLocalIntent('device_status', {});
    }
    if (RegExp(r'^(take|snap) (a )?(photo|picture|selfie|pic)$').hasMatch(p)) {
      return const OvaLocalIntent('take_photo', {});
    }

    // Time
    if ((m = RegExp(r'^(?:set\s+)?(?:an\s+)?alarm\s+(?:for\s+|at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(?:\s+(.+))?$').firstMatch(p)) != null ||
        (m = RegExp(r'^wake me (?:up )?at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?()$').firstMatch(p)) != null) {
      var h = int.parse(m!.group(1)!);
      final min = int.tryParse(m.group(2) ?? '') ?? 0;
      final ap = m.group(3);
      if (ap == 'pm' && h < 12) h += 12;
      if (ap == 'am' && h == 12) h = 0;
      if (h > 23 || min > 59) return null;
      return OvaLocalIntent('set_alarm', {'hour': h, 'minute': min, 'label': m.group(4) ?? ''});
    }
    if ((m = RegExp(r'^(?:set\s+|start\s+)?(?:a\s+)?(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hour|hours)\s+timer$|^(?:set\s+|start\s+)?(?:a\s+)?timer\s+(?:for\s+)?(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hour|hours)$').firstMatch(p)) != null) {
      final n = int.parse(m!.group(1) ?? m.group(3)!);
      final u = m.group(2) ?? m.group(4)!;
      return OvaLocalIntent('set_timer', {'seconds': n * _unit(u), 'label': ''});
    }
    if ((m = RegExp(r'^remind me (?:to\s+)?(.+?)\s+in\s+(\d+)\s*(s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hour|hours)$').firstMatch(p)) != null) {
      final at = DateTime.now().add(Duration(seconds: int.parse(m!.group(2)!) * _unit(m.group(3)!)));
      return OvaLocalIntent('set_reminder', {'text': _orig(raw, m.group(1)!), 'at': at.toIso8601String()});
    }

    if ((m = RegExp(r'^remind me (?:to\s+)?(.+?)\s+(tomorrow\s+)?(?:at|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?(\s+tomorrow)?$').firstMatch(p)) != null) {
      var h = int.parse(m!.group(3)!);
      final min = int.tryParse(m.group(4) ?? '') ?? 0;
      final ap = m.group(5);
      if (ap == 'pm' && h < 12) h += 12;
      if (ap == 'am' && h == 12) h = 0;
      if (h > 23 || min > 59) return null;
      final now = DateTime.now();
      var at = DateTime(now.year, now.month, now.day, h, min);
      if (m.group(2) != null || m.group(6) != null) {
        at = at.add(const Duration(days: 1));
      } else if (!at.isAfter(now)) {
        at = at.add(const Duration(days: 1));
      }
      return OvaLocalIntent('set_reminder', {'text': _orig(raw, m.group(1)!), 'at': at.toIso8601String()});
    }

    // Clipboard / share
    if ((m = RegExp(r'^copy\s+(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('copy_text', {'text': _orig(raw, m!.group(1)!)});
    }
    if (RegExp(r"^(paste|read (my )?clipboard|what'?s (on|in) (my )?clipboard)$").hasMatch(p)) {
      return const OvaLocalIntent('read_clipboard', {});
    }
    if ((m = RegExp(r'^share\s+(.+)$').firstMatch(p)) != null) {
      return OvaLocalIntent('share_text', {'text': _orig(raw, m!.group(1)!)});
    }

    // Android screen control
    if (!kIsWeb && Platform.isAndroid &&
        RegExp(r'^((go )?back|(go )?home|recent apps|recents|scroll (up|down)|take a screenshot|screenshot|lock the phone|lock screen|open quick settings|(open|show) notifications)$').hasMatch(p)) {
      return OvaLocalIntent('device_control', {'command': p});
    }

    // Open …
    if ((m = RegExp(r'^(?:open|launch|go to|show|take me to)\s+(?:the\s+|my\s+)?(.+?)(?:\s+app)?$').firstMatch(p)) != null) {
      final target = m!.group(1)!.trim();
      final screen = _screenAliases[target];
      if (screen != null && ovaScreens.containsKey(screen)) return OvaLocalIntent('open_screen', {'screen': screen});
      if (target == 'settings' || target == 'phone settings') return const OvaLocalIntent('open_settings', {});
      if (RegExp(r'^[\w-]+(\.[\w-]+)+(/\S*)?$').hasMatch(target) || target.startsWith('http')) {
        return OvaLocalIntent('open_url', {'url': _orig(raw, target)});
      }
      if (!target.contains(' ') || target.split(' ').length <= 2) return OvaLocalIntent('open_app', {'app': target});
    }
    return null;
  }

  static int _unit(String u) {
    if (u.startsWith('h')) return 3600;
    if (u.startsWith('m')) return 60;
    return 1;
  }

  /// Returns [lowered] with its original casing from [raw] when possible.
  static String _orig(String raw, String lowered) {
    final i = raw.toLowerCase().indexOf(lowered);
    return i < 0 ? lowered : raw.substring(i, i + lowered.length);
  }
}
