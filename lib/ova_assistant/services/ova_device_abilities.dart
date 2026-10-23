import 'dart:io';

import 'package:add_2_calendar/add_2_calendar.dart' as cal;
import 'package:android_intent_plus/android_intent.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' show FlutterContacts, ContactProperty, ContactFilter;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:volume_controller/volume_controller.dart';

import '../core/ova_tool_result.dart';
import 'ova_native_service.dart';
import 'ova_permissions.dart';

/// Real phone abilities used by Ova. Each method asks for the permission it
/// needs, explains why, and returns an [OvaToolResult] the sheet can render.
///
/// Platform notes (shown to the user on the cards):
/// - Calls / SMS / email always open the system dialer or composer. Nothing
///   is ever sent or dialled silently, on Android or iOS.
/// - Alarms and timers use the Clock app on Android. iOS has no public API,
///   so Ova schedules a local notification instead.
/// - Volume works on both; brightness changes the screen while Oneova is open.
class OvaDeviceAbilities {
  final OvaNativeService _native;
  OvaDeviceAbilities(this._native);

  bool get _android => !kIsWeb && Platform.isAndroid;
  bool get _ios => !kIsWeb && Platform.isIOS;

  // ── Calls, SMS, email ──────────────────────────────────────────────────

  Future<OvaToolResult> dial(String number) async {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+*#]'), '');
    if (cleaned.isEmpty) return OvaToolResult.fail('That does not look like a phone number.');
    final ok = await _launch(Uri(scheme: 'tel', path: cleaned));
    return ok
        ? OvaToolResult(ok: true, summary: 'Opened the dialer for $cleaned.', icon: Icons.call_rounded)
        : OvaToolResult.fail('This device cannot place calls.');
  }

  Future<OvaToolResult> composeSms(String number, String body) async {
    final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
    // iOS uses `&body=`, Android accepts `?body=`.
    final uri = Uri.parse('sms:$cleaned${_ios ? '&' : '?'}body=${Uri.encodeComponent(body)}');
    final ok = await _launch(uri);
    return ok
        ? OvaToolResult(
            ok: true,
            summary: 'Opened Messages with your text to $cleaned. Tap send to deliver it.',
            icon: Icons.sms_rounded)
        : OvaToolResult.fail('No SMS app is available on this device.');
  }

  Future<OvaToolResult> composeEmail(String to, String subject, String body) async {
    final uri = Uri(
      scheme: 'mailto',
      path: to,
      query: 'subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}',
    );
    final ok = await _launch(uri);
    return ok
        ? OvaToolResult(ok: true, summary: 'Opened your mail app with the draft to $to.', icon: Icons.email_rounded)
        : OvaToolResult.fail('No mail app is set up on this device.');
  }

  Future<OvaToolResult> whatsapp(String number, String text) async {
    final cleaned = number.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$cleaned?text=${Uri.encodeComponent(text)}');
    final ok = await _launch(uri);
    return ok
        ? OvaToolResult(ok: true, summary: 'Opened WhatsApp with your message. Tap send there.', icon: Icons.chat_rounded)
        : OvaToolResult.fail('Could not open WhatsApp.');
  }

  // ── Contacts ───────────────────────────────────────────────────────────

  Future<OvaToolResult> findContacts(BuildContext? context, String name) async {
    final granted = await OvaPermissions.ensure(
      context,
      Permission.contacts,
      title: 'Allow contacts',
      why: 'Ova reads your contacts only to find the number of the person you name. Nothing is uploaded.',
    );
    if (!granted) return OvaToolResult.fail('Contacts permission was not given, so I could not look up "$name".', icon: Icons.contacts_rounded);
    try {
      final contacts = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone},
        filter: ContactFilter.name(name),
        limit: 6,
      );
      final withPhones = contacts.where((c) => c.phones.isNotEmpty).toList();
      if (withPhones.isEmpty) {
        return OvaToolResult(ok: false, summary: 'No contact with a phone number matches "$name".', icon: Icons.person_search_rounded);
      }
      final items = <OvaResultItem>[];
      final lines = <String>[];
      for (final c in withPhones) {
        for (final p in c.phones.take(2)) {
          final label = c.displayName ?? name;
          lines.add('$label: ${p.number}');
          items.add(OvaResultItem(
            title: label,
            subtitle: p.number,
            icon: Icons.person_rounded,
            onTap: OvaResultAction(label: 'Call', icon: Icons.call_rounded, prompt: 'call ${p.number}'),
          ));
        }
      }
      return OvaToolResult(
        ok: true,
        summary: 'Contacts found:\n${lines.join('\n')}',
        icon: Icons.contacts_rounded,
        items: items,
      );
    } catch (e) {
      return OvaToolResult.fail('Could not read contacts: $e');
    }
  }

  /// Returns the first phone number for a contact name, or null.
  Future<String?> resolveNumber(BuildContext? context, String nameOrNumber) async {
    final digits = nameOrNumber.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.length >= 5) return digits;
    final res = await findContacts(context, nameOrNumber);
    if (!res.ok || res.items.isEmpty) return null;
    return res.items.first.subtitle;
  }

  // ── Apps & links ───────────────────────────────────────────────────────

  static const Map<String, (String android, String ios, String web)> _apps = {
    'whatsapp': ('com.whatsapp', 'whatsapp://', 'https://web.whatsapp.com'),
    'youtube': ('com.google.android.youtube', 'youtube://', 'https://youtube.com'),
    'instagram': ('com.instagram.android', 'instagram://', 'https://instagram.com'),
    'tiktok': ('com.zhiliaoapp.musically', 'tiktok://', 'https://tiktok.com'),
    'facebook': ('com.facebook.katana', 'fb://', 'https://facebook.com'),
    'x': ('com.twitter.android', 'twitter://', 'https://x.com'),
    'twitter': ('com.twitter.android', 'twitter://', 'https://x.com'),
    'telegram': ('org.telegram.messenger', 'tg://', 'https://web.telegram.org'),
    'spotify': ('com.spotify.music', 'spotify://', 'https://open.spotify.com'),
    'gmail': ('com.google.android.gm', 'googlegmail://', 'https://mail.google.com'),
    'maps': ('com.google.android.apps.maps', 'maps://', 'https://maps.google.com'),
    'chrome': ('com.android.chrome', 'googlechrome://', 'https://google.com'),
    'photos': ('com.google.android.apps.photos', 'photos-redirect://', 'https://photos.google.com'),
    'gallery': ('com.google.android.apps.photos', 'photos-redirect://', 'https://photos.google.com'),
  };

  Future<OvaToolResult> openApp(String name) async {
    final key = name.toLowerCase().trim();
    if (key == 'settings') return openSystemSettings();
    final app = _apps[key];
    if (app == null) {
      if (_android && key.contains('.')) {
        final ok = await _native.launchApp(key);
        if (ok) return OvaToolResult(ok: true, summary: 'Opened $name.', icon: Icons.apps_rounded);
      }
      return OvaToolResult.fail('I do not know how to open "$name" yet. Try a link instead.', icon: Icons.apps_rounded);
    }
    if (_android) {
      final ok = await _native.launchApp(app.$1);
      if (ok) return OvaToolResult(ok: true, summary: 'Opened $name.', icon: Icons.apps_rounded);
    } else if (_ios) {
      final ok = await _launch(Uri.parse(app.$2));
      if (ok) return OvaToolResult(ok: true, summary: 'Opened $name.', icon: Icons.apps_rounded);
    }
    final ok = await _launch(Uri.parse(app.$3));
    return ok
        ? OvaToolResult(ok: true, summary: '$name is not installed, so I opened it on the web.', icon: Icons.public_rounded)
        : OvaToolResult.fail('Could not open $name.');
  }

  Future<OvaToolResult> openUrl(String raw) async {
    var url = raw.trim();
    if (!url.contains('://')) url = 'https://$url';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return OvaToolResult.fail('That is not a web link I can open.');
    }
    final ok = await _launch(uri);
    return ok
        ? OvaToolResult(ok: true, summary: 'Opened ${uri.host}.', icon: Icons.open_in_new_rounded)
        : OvaToolResult.fail('Could not open ${uri.host}.');
  }

  Future<OvaToolResult> openSystemSettings() async {
    if (_android && await _native.openSettings('main')) {
      return const OvaToolResult(ok: true, summary: 'Opened Settings.', icon: Icons.settings_rounded);
    }
    final ok = await openAppSettings();
    return ok
        ? const OvaToolResult(ok: true, summary: 'Opened Oneova in Settings (iOS only allows the app page).', icon: Icons.settings_rounded)
        : OvaToolResult.fail('Could not open Settings.');
  }

  // ── Camera & sharing ───────────────────────────────────────────────────

  Future<OvaToolResult> takePhoto(BuildContext? context) async {
    final granted = await OvaPermissions.ensure(
      context,
      Permission.camera,
      title: 'Allow camera',
      why: 'Ova opens the camera so you can take a photo. Photos stay on your phone unless you share them.',
    );
    if (!granted) return OvaToolResult.fail('Camera permission was not given.', icon: Icons.no_photography_rounded);
    try {
      final shot = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88);
      if (shot == null) return OvaToolResult.fail('No photo taken.', icon: Icons.photo_camera_rounded);
      return OvaToolResult(
        ok: true,
        summary: 'Photo taken.',
        icon: Icons.photo_camera_rounded,
        imagePath: shot.path,
      );
    } catch (e) {
      return OvaToolResult.fail('Camera error: $e');
    }
  }

  Future<OvaToolResult> share(String text, {String? filePath}) async {
    try {
      await SharePlus.instance.share(ShareParams(
        text: text.isEmpty ? null : text,
        files: filePath != null ? [XFile(filePath)] : null,
      ));
      return const OvaToolResult(ok: true, summary: 'Opened the share sheet.', icon: Icons.ios_share_rounded);
    } catch (e) {
      return OvaToolResult.fail('Could not open the share sheet: $e');
    }
  }

  Future<OvaToolResult> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    return const OvaToolResult(ok: true, summary: 'Copied to clipboard.', icon: Icons.content_copy_rounded);
  }

  Future<OvaToolResult> readClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return const OvaToolResult(ok: true, summary: 'The clipboard is empty.', icon: Icons.content_paste_rounded);
    return OvaToolResult(ok: true, summary: 'Clipboard: $text', icon: Icons.content_paste_rounded);
  }

  // ── Calendar, alarms, reminders ────────────────────────────────────────

  Future<OvaToolResult> addCalendarEvent({
    required String title,
    required DateTime start,
    DateTime? end,
    String? location,
    String? notes,
  }) async {
    final event = cal.Event(
      title: title,
      startDate: start,
      endDate: end ?? start.add(const Duration(hours: 1)),
      location: location,
      description: notes,
    );
    try {
      final ok = await cal.Add2Calendar.addEvent2Cal(event);
      return ok
          ? OvaToolResult(ok: true, summary: 'Opened your calendar with "$title". Tap save to keep it.', icon: Icons.event_rounded)
          : OvaToolResult.fail('The calendar did not open.');
    } catch (e) {
      return OvaToolResult.fail('Calendar error: $e');
    }
  }

  Future<OvaToolResult> setAlarm(BuildContext? context, int hour, int minute, String label) async {
    if (_android) {
      try {
        await AndroidIntent(
          action: 'android.intent.action.SET_ALARM',
          arguments: <String, dynamic>{
            'android.intent.extra.alarm.HOUR': hour,
            'android.intent.extra.alarm.MINUTES': minute,
            'android.intent.extra.alarm.MESSAGE': label,
            'android.intent.extra.alarm.SKIP_UI': false,
          },
        ).launch();
        return OvaToolResult(ok: true, summary: 'Opened Clock to set an alarm for ${_hm(hour, minute)}.', icon: Icons.alarm_rounded);
      } catch (e) {
        return OvaToolResult.fail('No clock app accepted the alarm: $e');
      }
    }
    // iOS: no public alarm API. Fall back to a reminder notification.
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final res = await scheduleReminder(context, label.isEmpty ? 'Alarm' : label, at);
    if (!res.ok) return res;
    return OvaToolResult(
      ok: true,
      summary: 'iOS does not let apps set Clock alarms, so I scheduled a notification for ${_hm(hour, minute)} instead.',
      icon: Icons.notifications_active_rounded,
    );
  }

  Future<OvaToolResult> setTimer(BuildContext? context, int seconds, String label) async {
    if (_android) {
      try {
        await AndroidIntent(
          action: 'android.intent.action.SET_TIMER',
          arguments: <String, dynamic>{
            'android.intent.extra.alarm.LENGTH': seconds,
            'android.intent.extra.alarm.MESSAGE': label,
            'android.intent.extra.alarm.SKIP_UI': false,
          },
        ).launch();
        return OvaToolResult(ok: true, summary: 'Started a ${_dur(seconds)} timer in Clock.', icon: Icons.timer_rounded);
      } catch (e) {
        return OvaToolResult.fail('No clock app accepted the timer: $e');
      }
    }
    final res = await scheduleReminder(context, label.isEmpty ? 'Timer done' : label, DateTime.now().add(Duration(seconds: seconds)));
    if (!res.ok) return res;
    return OvaToolResult(
      ok: true,
      summary: 'iOS does not let apps start Clock timers, so I will notify you in ${_dur(seconds)}.',
      icon: Icons.timer_rounded,
    );
  }

  static final FlutterLocalNotificationsPlugin _notifs = FlutterLocalNotificationsPlugin();
  static bool _notifsReady = false;

  Future<bool> _ensureNotifications(BuildContext? context) async {
    final granted = await OvaPermissions.ensure(
      context,
      Permission.notification,
      title: 'Allow notifications',
      why: 'Ova needs notifications to remind you at the time you choose.',
    );
    if (!granted) return false;
    if (!_notifsReady) {
      tzdata.initializeTimeZones();
      await _notifs.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      _notifsReady = true;
    }
    return true;
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'ova_reminders',
      'Ova reminders',
      channelDescription: 'Reminders and timers you set with Ova',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

  Future<OvaToolResult> scheduleReminder(BuildContext? context, String text, DateTime at, {int? id}) async {
    if (!at.isAfter(DateTime.now())) return OvaToolResult.fail('That time has already passed.');
    if (!await _ensureNotifications(context)) {
      return OvaToolResult.fail('Notifications are off, so I cannot remind you.', icon: Icons.notifications_off_rounded);
    }
    try {
      await _notifs.zonedSchedule(
        id: id ?? at.millisecondsSinceEpoch ~/ 1000 % 100000000,
        title: 'Ova reminder',
        body: text,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      return OvaToolResult(ok: true, summary: 'Reminder set: "$text" at ${_when(at)}.', icon: Icons.notifications_active_rounded);
    } catch (e) {
      return OvaToolResult.fail('Could not schedule the reminder: $e');
    }
  }

  Future<void> cancelReminder(int id) async {
    try {
      await _notifs.cancel(id: id);
    } catch (e) {
      debugPrint('[OvaDeviceAbilities] cancel reminder failed: $e');
    }
  }

  Future<OvaToolResult> notifyNow(BuildContext? context, String title, String body) async {
    if (!await _ensureNotifications(context)) {
      return OvaToolResult.fail('Notifications are off.', icon: Icons.notifications_off_rounded);
    }
    await _notifs.show(id: DateTime.now().millisecondsSinceEpoch % 100000000, title: title, body: body, notificationDetails: _details);
    return const OvaToolResult(ok: true, summary: 'Notification sent.', icon: Icons.notifications_rounded);
  }

  // ── Hardware ───────────────────────────────────────────────────────────

  /// Last flashlight state Ova set (the plugin cannot read it back).
  static bool torchOn = false;

  Future<OvaToolResult> flashlight(bool on) async {
    try {
      if (!await TorchLight.isTorchAvailable()) {
        return OvaToolResult.unsupported('This device has no flashlight.');
      }
      on ? await TorchLight.enableTorch() : await TorchLight.disableTorch();
      torchOn = on;
      return OvaToolResult(
        ok: true,
        summary: on ? 'Flashlight on.' : 'Flashlight off.',
        icon: on ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
      );
    } catch (e) {
      return OvaToolResult.fail('Flashlight error: $e');
    }
  }

  Future<OvaToolResult> setVolume(int percent) async {
    final v = (percent.clamp(0, 100)) / 100.0;
    try {
      VolumeController.instance.showSystemUI = true;
      await VolumeController.instance.setVolume(v);
      return OvaToolResult(ok: true, summary: 'Media volume set to ${percent.clamp(0, 100)}%.', icon: Icons.volume_up_rounded);
    } catch (e) {
      return OvaToolResult.fail('Could not change the volume: $e');
    }
  }

  Future<OvaToolResult> setBrightness(int percent) async {
    final v = (percent.clamp(5, 100)) / 100.0;
    try {
      await ScreenBrightness.instance.setApplicationScreenBrightness(v);
      return OvaToolResult(
        ok: true,
        summary: 'Brightness set to ${percent.clamp(5, 100)}% while Oneova is open.',
        icon: Icons.brightness_6_rounded,
      );
    } catch (e) {
      return OvaToolResult.fail('Could not change the brightness: $e');
    }
  }

  Future<OvaToolResult> location(BuildContext? context) async {
    final granted = await OvaPermissions.ensure(
      context,
      Permission.locationWhenInUse,
      title: 'Allow location',
      why: 'Ova uses your location once, only when you ask where you are.',
    );
    if (!granted) return OvaToolResult.fail('Location permission was not given.', icon: Icons.location_off_rounded);
    if (!await Geolocator.isLocationServiceEnabled()) {
      return OvaToolResult.fail('Location services are turned off on this phone.', icon: Icons.location_off_rounded);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final lat = pos.latitude.toStringAsFixed(5);
      final lng = pos.longitude.toStringAsFixed(5);
      return OvaToolResult(
        ok: true,
        summary: 'Current location: $lat, $lng (±${pos.accuracy.round()} m).',
        icon: Icons.my_location_rounded,
        actions: [
          OvaResultAction(
            label: 'Open in Maps',
            icon: Icons.map_rounded,
            url: 'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
          ),
          OvaResultAction(label: 'Share', icon: Icons.ios_share_rounded, prompt: 'share my location https://maps.google.com/?q=$lat,$lng'),
        ],
      );
    } catch (e) {
      return OvaToolResult.fail('Could not get your location: $e');
    }
  }

  Future<OvaToolResult> deviceStatus() async {
    final battery = Battery();
    try {
      final level = await battery.batteryLevel;
      final state = await battery.batteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      return OvaToolResult(
        ok: true,
        summary: 'Battery $level%${charging ? ', charging' : ''}.',
        icon: charging ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
      );
    } catch (e) {
      return OvaToolResult.fail('Could not read the battery: $e');
    }
  }

  // ── helpers ────────────────────────────────────────────────────────────

  Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[OvaDeviceAbilities] launch $uri failed: $e');
      return false;
    }
  }

  static String _hm(int h, int m) => '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';

  static String _dur(int s) {
    if (s < 60) return '${s}s';
    if (s < 3600) return '${s ~/ 60} min${s % 60 > 0 ? ' ${s % 60}s' : ''}';
    return '${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
  }

  static String _when(DateTime at) {
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final hm = _hm(at.hour, at.minute);
    return sameDay ? hm : '${at.day}/${at.month} $hm';
  }
}
