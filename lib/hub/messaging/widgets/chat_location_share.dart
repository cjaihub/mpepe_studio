import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../../../shared/location/geo_services.dart';
import '../../../shared/location/oneova_map_view.dart';
import '../../../shared/theme/app_theme.dart';

/// What the user picked in the share-location sheet.
class LocationShareChoice {
  final LatLng point;
  final double accuracy;
  final String? address;

  /// Null for a one-off pin; otherwise how long live sharing lasts.
  final Duration? live;

  const LocationShareChoice({required this.point, required this.accuracy, this.address, this.live});

  /// The `location` map stored on the chat message.
  Map<String, dynamic> toMessageLocation() {
    final now = DateTime.now();
    return {
      'lat': point.latitude,
      'lng': point.longitude,
      'accuracy': accuracy,
      'address': ?address,
      'live': live != null,
      if (live != null) ...{
        'active': true,
        'expiresAt': Timestamp.fromDate(now.add(live!)),
        'durationMin': live!.inMinutes,
      },
      'updatedAt': Timestamp.fromDate(now),
    };
  }

  String get mapsUrl => 'https://www.google.com/maps/search/?api=1&query=${point.latitude},${point.longitude}';
}

/// Location data stored on a chat message (`mediaType: 'location'`).
class ChatLocation {
  final LatLng point;
  final double? accuracy;
  final String? address;
  final bool live;
  final bool active;
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  const ChatLocation({
    required this.point,
    this.accuracy,
    this.address,
    this.live = false,
    this.active = false,
    this.expiresAt,
    this.updatedAt,
  });

  static ChatLocation? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final lat = (m['lat'] as num?)?.toDouble();
    final lng = (m['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return ChatLocation(
      point: LatLng(lat, lng),
      accuracy: (m['accuracy'] as num?)?.toDouble(),
      address: m['address'] as String?,
      live: m['live'] == true,
      active: m['active'] == true,
      expiresAt: (m['expiresAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Live and not yet stopped or expired.
  bool get isLiveNow => live && active && (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
}

/// Keeps live-location messages up to date while this phone shares them.
///
/// Each share writes the newest position into its message document, so
/// everyone in the chat sees the pin move in real time. A share stops when
/// the user stops it, when it expires, or when the app is closed (the
/// message then shows the last known position until it expires).
class LiveLocationSharer {
  LiveLocationSharer._();
  static final LiveLocationSharer instance = LiveLocationSharer._();

  final Map<String, _LiveShare> _shares = {};
  final ValueNotifier<int> changes = ValueNotifier(0);

  static String _key(String chatId, String messageId) => '$chatId/$messageId';

  bool isSharing(String chatId, String messageId) => _shares.containsKey(_key(chatId, messageId));
  bool get anyActive => _shares.isNotEmpty;

  DocumentReference<Map<String, dynamic>> _doc(String chatId, String messageId) =>
      FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').doc(messageId);

  void start(String chatId, String messageId, Duration duration) {
    final key = _key(chatId, messageId);
    if (_shares.containsKey(key)) return;
    final until = DateTime.now().add(duration);
    DateTime lastWrite = DateTime.fromMillisecondsSinceEpoch(0);
    LatLng? lastPoint;

    // One background stream is enough for every share on this phone.
    final sub = GeoServices.instance
        .track(distanceFilterM: 10, background: true, notificationText: 'Live location is on until ${_hm(until)}')
        .listen((p) {
      final pt = LatLng(p.latitude, p.longitude);
      final now = DateTime.now();
      // Throttle: at most every 8 s unless the user moved more than 30 m.
      final moved = lastPoint == null ? 1e9 : GeoServices.instance.distanceM(lastPoint!, pt);
      if (now.difference(lastWrite) < const Duration(seconds: 8) && moved < 30) return;
      lastWrite = now;
      lastPoint = pt;
      _doc(chatId, messageId).update({
        'location.lat': p.latitude,
        'location.lng': p.longitude,
        'location.accuracy': p.accuracy,
        'location.updatedAt': Timestamp.fromDate(now),
      }).catchError((Object e) => debugPrint('[LiveLocation] update failed: $e'));
    }, onError: (Object e) => debugPrint('[LiveLocation] stream error: $e'));

    final timer = Timer(duration, () => stop(chatId, messageId, expired: true));
    _shares[key] = _LiveShare(sub, timer);
    changes.value++;
  }

  Future<void> stop(String chatId, String messageId, {bool expired = false}) async {
    final s = _shares.remove(_key(chatId, messageId));
    s?.sub.cancel();
    s?.timer.cancel();
    changes.value++;
    try {
      await _doc(chatId, messageId).update({
        'location.active': false,
        'location.endedAt': Timestamp.now(),
        if (!expired) 'location.stoppedEarly': true,
      });
    } catch (e) {
      debugPrint('[LiveLocation] stop failed: $e');
    }
  }

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _LiveShare {
  final StreamSubscription<Position> sub;
  final Timer timer;
  _LiveShare(this.sub, this.timer);
}

/// Bottom sheet: send the current position as a pin, or share live for
/// 15 min / 1 h / 8 h. Returns null when cancelled.
Future<LocationShareChoice?> showShareLocationSheet(BuildContext context) async {
  final problem = await GeoServices.instance.ensureReady();
  if (problem != null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(problem),
        backgroundColor: AppColors.brandPink,
        action: SnackBarAction(label: 'Settings', textColor: Colors.white, onPressed: Geolocator.openAppSettings),
      ));
    }
    return null;
  }
  if (!context.mounted) return null;
  return showModalBottomSheet<LocationShareChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
    builder: (_) => const _ShareLocationSheet(),
  );
}

class _ShareLocationSheet extends StatefulWidget {
  const _ShareLocationSheet();

  @override
  State<_ShareLocationSheet> createState() => _ShareLocationSheetState();
}

class _ShareLocationSheetState extends State<_ShareLocationSheet> {
  LatLng? _me;
  double _accuracy = 0;
  String? _address;
  String? _error;
  StreamSubscription<Position>? _sub;
  bool _addressLoading = false;

  @override
  void initState() {
    super.initState();
    _first();
    _sub = GeoServices.instance.track(distanceFilterM: 3).listen((p) {
      if (!mounted) return;
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _accuracy = p.accuracy;
      });
    }, onError: (_) {});
  }

  Future<void> _first() async {
    try {
      final p = await GeoServices.instance.current();
      if (!mounted) return;
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _accuracy = p.accuracy;
        _addressLoading = true;
      });
      final a = await GeoServices.instance.reverse(_me!);
      if (mounted) {
        setState(() {
          _address = a;
          _addressLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not find your location: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _pick(Duration? live) {
    final me = _me;
    if (me == null) return;
    HapticFeedback.mediumImpact();
    Navigator.pop(context, LocationShareChoice(point: me, accuracy: _accuracy, address: _address, live: live));
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text('Share location', style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 10),
            if (_error != null)
              Text(_error!, style: GoogleFonts.inter(fontSize: 12.5, color: AppColors.brandPink))
            else if (me == null)
              Container(
                height: 180,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: const CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue),
              )
            else
              OneovaMapView(me: me, height: 180),
            const SizedBox(height: 12),
            _option(
              context,
              icon: Icons.my_location_rounded,
              color: AppColors.brandBlue,
              title: 'Send your current location',
              subtitle: me == null
                  ? 'Finding you…'
                  : '${_addressLoading ? 'Looking up address…' : (_address ?? '${me.latitude.toStringAsFixed(5)}, ${me.longitude.toStringAsFixed(5)}')} · ±${_accuracy.round()} m',
              onTap: me == null ? null : () => _pick(null),
            ),
            const SizedBox(height: 8),
            Text('SHARE LIVE LOCATION',
                style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: context.textMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                for (final d in const [(Duration(minutes: 15), '15 min'), (Duration(hours: 1), '1 hour'), (Duration(hours: 8), '8 hours')])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: OutlinedButton.icon(
                        onPressed: me == null ? null : () => _pick(d.$1),
                        icon: const Icon(Icons.share_location_rounded, size: 16, color: AppColors.brandPink),
                        label: Text(d.$2, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: context.textPrimary)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          side: BorderSide(color: context.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Live location updates in this chat as you move, until you stop it or it ends. It keeps running in the background with a notification.',
              style: GoogleFonts.inter(fontSize: 11, height: 1.35, color: context.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _option(BuildContext context,
      {required IconData icon, required Color color, required String title, required String subtitle, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.border),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Icon(icon, size: 18, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(fontSize: 11, color: context.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.send_rounded, size: 18, color: onTap == null ? context.textMuted : AppColors.brandBlue),
          ],
        ),
      ),
    );
  }
}

/// Map bubble for a `location` message. Live shares move in real time
/// because the message document itself is updated.
class ChatLocationBubble extends StatefulWidget {
  final String chatId;
  final String messageId;
  final Map<String, dynamic>? location;
  final bool isMe;
  final String senderName;

  const ChatLocationBubble({
    super.key,
    required this.chatId,
    required this.messageId,
    required this.location,
    required this.isMe,
    this.senderName = '',
  });

  @override
  State<ChatLocationBubble> createState() => _ChatLocationBubbleState();
}

class _ChatLocationBubbleState extends State<ChatLocationBubble> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Refresh the "ends in" / "updated" labels.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    // The app was restarted during a live share: pick it back up so the pin
    // keeps moving until it expires.
    final loc = ChatLocation.fromMap(widget.location);
    if (widget.isMe && loc != null && loc.isLiveNow && !LiveLocationSharer.instance.isSharing(widget.chatId, widget.messageId)) {
      LiveLocationSharer.instance.start(widget.chatId, widget.messageId, loc.expiresAt!.difference(DateTime.now()));
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    return '${d.inHours} h ago';
  }

  String _left(DateTime t) {
    final d = t.difference(DateTime.now());
    if (d.inMinutes < 60) return '${d.inMinutes.clamp(1, 59)} min';
    return '${d.inHours} h ${d.inMinutes % 60} min';
  }

  @override
  Widget build(BuildContext context) {
    final loc = ChatLocation.fromMap(widget.location);
    if (loc == null) {
      return Text('Location unavailable', style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary));
    }
    final liveNow = loc.isLiveNow;
    final fg = widget.isMe ? Colors.white : context.textPrimary;
    final sub = widget.isMe ? Colors.white70 : context.textSecondary;
    final String title;
    final String subtitle;
    if (loc.live) {
      title = liveNow ? 'Live location' : 'Live location ended';
      subtitle = liveNow
          ? 'Ends in ${_left(loc.expiresAt!)}${loc.updatedAt != null ? ' · updated ${_ago(loc.updatedAt!)}' : ''}'
          : (loc.updatedAt != null ? 'Last seen ${_ago(loc.updatedAt!)}' : 'No longer sharing');
    } else {
      title = 'Location';
      subtitle = loc.address ?? '${loc.point.latitude.toStringAsFixed(5)}, ${loc.point.longitude.toStringAsFixed(5)}';
    }
    final label = widget.isMe ? 'You' : widget.senderName;

    return SizedBox(
      width: 240,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openViewer(context),
            child: AbsorbPointer(
              child: OneovaMapView(
                me: widget.isMe ? loc.point : null,
                others: widget.isMe ? const {} : {label: loc.point},
                interactive: false,
                height: 130,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(loc.live ? Icons.share_location_rounded : Icons.location_on_rounded,
                  size: 15, color: liveNow ? AppColors.brandPink : (widget.isMe ? Colors.white : AppColors.brandBlue)),
              const SizedBox(width: 5),
              Expanded(
                child: Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
              ),
              if (liveNow)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.brandPink, borderRadius: BorderRadius.circular(4)),
                  child: Text('LIVE', style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.white)),
                ),
            ],
          ),
          Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 11, color: sub)),
          if (widget.isMe && liveNow) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  LiveLocationSharer.instance.stop(widget.chatId, widget.messageId);
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: Text('Stop sharing', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openViewer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg))),
      builder: (_) => _LocationViewer(
        chatId: widget.chatId,
        messageId: widget.messageId,
        isMe: widget.isMe,
        senderName: widget.senderName,
      ),
    );
  }
}

/// Full map of a shared location. Streams the message so a live pin keeps
/// moving, and shows your own position too.
class _LocationViewer extends StatelessWidget {
  final String chatId;
  final String messageId;
  final bool isMe;
  final String senderName;

  const _LocationViewer({required this.chatId, required this.messageId, required this.isMe, required this.senderName});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final stream = FirebaseFirestore.instance.collection('chats').doc(chatId).collection('messages').doc(messageId).snapshots();
    return SafeArea(
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          final data = snap.data?.data();
          final loc = ChatLocation.fromMap((data?['location'] as Map?)?.cast<String, dynamic>());
          final mine = isMe || (uid != null && data?['senderId'] == uid);
          final label = mine ? 'You' : senderName;
          final whose = mine ? 'Your' : (senderName.isEmpty ? 'Shared' : "$senderName's");
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  loc == null ? 'Location' : (loc.isLiveNow ? '$whose live location' : '$whose location'),
                  style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary),
                ),
                if (loc?.address != null)
                  Text(loc!.address!, style: GoogleFonts.inter(fontSize: 12, color: context.textSecondary)),
                const SizedBox(height: 10),
                if (loc == null)
                  const SizedBox(height: 300, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)))
                else
                  OneovaMapView(
                    others: mine ? const {} : {label: loc.point},
                    me: mine ? loc.point : null,
                    trackUser: !mine,
                    height: MediaQuery.of(context).size.height * 0.5,
                  ),
                const SizedBox(height: 10),
                if (loc != null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => GeoServices.instance.openInMaps(loc.point, label: label.isEmpty ? null : label),
                          icon: const Icon(Icons.map_rounded, size: 16, color: AppColors.brandBlue),
                          label: Text('Open in Maps', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: context.textPrimary)),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(40),
                            side: BorderSide(color: context.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                          ),
                        ),
                      ),
                      if (!mine) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => GeoServices.instance.openNavigation(loc.point),
                            icon: const Icon(Icons.navigation_rounded, size: 16, color: Colors.white),
                            label: Text('Directions', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                              backgroundColor: AppColors.brandBlue,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                            ),
                          ),
                        ),
                      ],
                      if (mine && loc.isLiveNow) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => LiveLocationSharer.instance.stop(chatId, messageId),
                            icon: const Icon(Icons.stop_circle_rounded, size: 16, color: Colors.white),
                            label: Text('Stop sharing', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                              backgroundColor: AppColors.brandPink,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
