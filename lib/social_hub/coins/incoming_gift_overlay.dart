import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../backend/coins/gift_catalog.dart';
import '../../shared/theme/app_theme.dart';

class _Drop {
  final String fromName;
  final String fromAvatar;
  final GiftType gift;
  final int qty;
  final int received;
  final String message;
  const _Drop(this.fromName, this.fromAvatar, this.gift, this.qty, this.received, this.message);
}

/// Plays a gift the moment it lands for the signed-in person, anywhere in
/// the app: the gift bursts in the middle of the screen (bigger gifts, bigger
/// show) and the sender's message rises as a big live comment. Listens to
/// `users/{uid}/gift_inbox`, written by `sendUserGift`.
class IncomingGiftOverlay extends StatefulWidget {
  const IncomingGiftOverlay({super.key, required this.child});
  final Widget child;

  @override
  State<IncomingGiftOverlay> createState() => _IncomingGiftOverlayState();
}

class _IncomingGiftOverlayState extends State<IncomingGiftOverlay> with SingleTickerProviderStateMixin {
  StreamSubscription<User?>? _auth;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _inbox;
  final List<_Drop> _queue = [];
  _Drop? _current;
  late final AnimationController _anim = AnimationController(vsync: this);
  DateTime _since = DateTime.now();

  @override
  void initState() {
    super.initState();
    _auth = FirebaseAuth.instance.authStateChanges().listen(_listen);
  }

  void _listen(User? user) {
    _inbox?.cancel();
    _inbox = null;
    if (user == null || user.isAnonymous) return;
    // Only gifts that land from now on are played; older ones are in notifications.
    _since = DateTime.now().subtract(const Duration(seconds: 5));
    _inbox = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('gift_inbox')
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .listen((snap) {
      for (final c in snap.docChanges) {
        if (c.type != DocumentChangeType.added) continue;
        final d = c.doc.data();
        if (d == null) continue;
        final at = (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
        if (at.isBefore(_since)) continue;
        _queue.add(_Drop(
          (d['fromName'] as String?) ?? 'Someone',
          (d['fromAvatar'] as String?) ?? '',
          giftById(d['giftId'] as String?),
          (d['qty'] as num?)?.toInt() ?? 1,
          (d['received'] as num?)?.toInt() ?? 0,
          (d['message'] as String?) ?? '',
        ));
      }
      _next();
    }, onError: (_) {});
  }

  void _next() {
    if (_current != null || _queue.isEmpty || !mounted) return;
    final d = _queue.removeAt(0);
    setState(() => _current = d);
    HapticFeedback.heavyImpact();
    _anim.duration = Duration(milliseconds: 3200 + d.gift.tier * 900);
    _anim.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() => _current = null);
      _next();
    });
  }

  @override
  void dispose() {
    _auth?.cancel();
    _inbox?.cancel();
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = _current;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        widget.child,
        if (d != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _anim.animateTo(1, duration: const Duration(milliseconds: 250)),
              child: AnimatedBuilder(
                animation: _anim,
                builder: (context, _) => _GiftShow(drop: d, t: _anim.value),
              ),
            ),
          ),
      ],
    );
  }
}

class _GiftShow extends StatelessWidget {
  const _GiftShow({required this.drop, required this.t});
  final _Drop drop;
  final double t;

  @override
  Widget build(BuildContext context) {
    final g = drop.gift;
    // Fade in over the first 10%, out over the last 12%.
    final fade = t < 0.1 ? t / 0.1 : (t > 0.88 ? (1 - t) / 0.12 : 1.0);
    final pop = Curves.elasticOut.transform((t / 0.35).clamp(0.0, 1.0));
    final size = 90.0 + g.tier * 40;
    final size2 = MediaQuery.sizeOf(context);
    final rnd = math.Random(g.id.hashCode);
    final particles = 8 + g.tier * 10;

    return Material(
      type: MaterialType.transparency,
      child: Opacity(
        opacity: fade.clamp(0.0, 1.0),
        child: Stack(
          children: [
            // Dim the app a little so the gift reads clearly.
            Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.25 + 0.1 * g.tier))),
            // Rising sparkles of the same gift.
            for (var i = 0; i < particles; i++)
              Builder(builder: (_) {
                final x = rnd.nextDouble();
                final delay = rnd.nextDouble() * 0.4;
                final p = ((t - delay) / 0.6).clamp(0.0, 1.0);
                return Positioned(
                  left: x * size2.width,
                  top: size2.height * (0.85 - 0.75 * p),
                  child: Opacity(
                    opacity: p == 0 ? 0 : (1 - p),
                    child: Transform.rotate(
                      angle: (x - 0.5) * math.pi * p,
                      child: Icon(g.icon, size: 14 + rnd.nextDouble() * 16, color: g.colors[i % g.colors.length]),
                    ),
                  ),
                );
              }),
            // The gift itself.
            Align(
              alignment: const Alignment(0, -0.2),
              child: Transform.scale(
                scale: 0.2 + 0.8 * pop,
                child: Container(
                  width: size + 40,
                  height: size + 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [g.colors.last.withValues(alpha: 0.45), Colors.transparent]),
                  ),
                  child: Center(
                    child: ShaderMask(
                      shaderCallback: (r) => LinearGradient(colors: g.colors).createShader(r),
                      child: Icon(g.icon, size: size, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            // Big live comment.
            Align(
              alignment: const Alignment(0, 0.55),
              child: Transform.translate(
                offset: Offset(0, 40 * (1 - Curves.easeOutCubic.transform((t / 0.25).clamp(0.0, 1.0)))),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    boxShadow: [BoxShadow(color: AppColors.brandPink.withValues(alpha: 0.35), blurRadius: 24)],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.white24,
                        backgroundImage: drop.fromAvatar.startsWith('http') ? NetworkImage(drop.fromAvatar) : null,
                        child: drop.fromAvatar.startsWith('http') ? null : const Icon(Icons.person_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${drop.fromName} sent you ${drop.qty > 1 ? '${drop.qty} × ' : ''}${g.label}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            if (drop.message.isNotEmpty)
                              Text(
                                drop.message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white, height: 1.25),
                              ),
                            Text('+${drop.received} coins', style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
