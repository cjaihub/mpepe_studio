import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backend/social/models/content.dart';
import '../../shared/theme/app_theme.dart';

/// An occasional one-question card in the feed about the reel just watched.
/// Answers go to `users/{uid}/feed_feedback` and tune what comes next.
class FeedPulseSlot {
  FeedPulseSlot(this.about) : id = 'pulse_${about.id}';
  final String id;
  final Content about;

  String? get topic => about.hashtags.isEmpty ? null : about.hashtags.first;

  String get question =>
      topic != null ? 'Is this reel mostly about #$topic?' : 'Was this reel the kind you want to see?';

  List<String> get answers => topic != null
      ? const ['Yes, and I want more', 'Yes, but show me less', 'No', 'Not sure']
      : const ['Yes, more like this', 'It was okay', 'No, less like this', 'Not sure'];
}

/// When to ask: once per session after enough reels, at most every 3 days.
class FeedPulsePolicy {
  FeedPulsePolicy._();
  static const _key = 'feed_pulse_last_ms';
  static const int afterReels = 12;
  static bool _askedThisSession = false;

  static Future<bool> shouldAsk(int reelsWatched) async {
    if (_askedThisSession || reelsWatched < afterReels) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_key) ?? 0;
      if (DateTime.now().millisecondsSinceEpoch - last < const Duration(days: 3).inMilliseconds) return false;
      await prefs.setInt(_key, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    _askedThisSession = true;
    return true;
  }
}

class FeedPulseCard extends StatefulWidget {
  const FeedPulseCard({super.key, required this.slot, required this.onDone});
  final FeedPulseSlot slot;
  final VoidCallback onDone;

  @override
  State<FeedPulseCard> createState() => _FeedPulseCardState();
}

class _FeedPulseCardState extends State<FeedPulseCard> {
  int? _picked;
  bool _sent = false;

  Future<void> _submit() async {
    final i = _picked;
    if (i == null || _sent) return;
    HapticFeedback.mediumImpact();
    setState(() => _sent = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final s = widget.slot;
    if (uid != null) {
      final db = FirebaseFirestore.instance;
      // Answers 1 and 3 ("show me less" / "No, less like this") are negative.
      final negative = s.topic != null ? i == 1 : i == 2;
      final positive = i == 0;
      try {
        await db.collection('users').doc(uid).collection('feed_feedback').add({
          'contentId': s.about.id,
          'authorId': s.about.authorId,
          'topic': ?s.topic,
          'question': s.question,
          'answer': s.answers[i],
          'signal': positive ? 1 : (negative ? -1 : 0),
          'createdAt': FieldValue.serverTimestamp(),
        });
        if (negative || positive) {
          await db.collection('users').doc(uid).collection('interactions').doc(s.about.id).set({
            if (negative) 'notInterested': true,
            if (positive) 'interested': true,
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    final thumb = s.about.mediaMetadata.thumbnailUrl ?? s.about.mediaMetadata.posterFrameUrl;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF071A3A), Color(0xFF05070D), Color(0xFF2A0820)],
        ),
      ),
      child: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final thumbH = (box.maxHeight * 0.26).clamp(120.0, 230.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 48),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (thumb != null && thumb.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.network(thumb,
                        height: thumbH,
                        width: thumbH * 0.75,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => SizedBox(height: thumbH)),
                  ),
                const SizedBox(height: 24),
                Text(s.question,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, height: 1.25, letterSpacing: -0.3)),
                const SizedBox(height: 6),
                Text('Your answer only shapes your own feed.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(color: Colors.white60, fontSize: 12.5)),
                const SizedBox(height: 24),
                for (var i = 0; i < s.answers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _Answer(
                      label: s.answers[i],
                      selected: _picked == i,
                      onTap: _sent
                          ? null
                          : () {
                              HapticFeedback.selectionClick();
                              setState(() => _picked = i);
                            },
                    ),
                  ),
                const SizedBox(height: 10),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  opacity: _picked == null ? 0.5 : 1,
                  child: GestureDetector(
                    onTap: _picked == null ? null : _submit,
                    child: Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: _picked == null
                            ? null
                            : const LinearGradient(colors: [AppColors.brandBlue, AppColors.brandPink]),
                        color: _picked == null ? Colors.white12 : null,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(_sent ? 'Thanks!' : 'Submit',
                          style: GoogleFonts.inter(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: _sent ? null : widget.onDone,
                  child: Text('Skip', style: GoogleFonts.inter(color: Colors.white54, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 52,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: selected ? AppColors.brandPink.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? AppColors.brandPink : Colors.white.withValues(alpha: 0.14), width: 1.4),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600)),
        ),
      );
}
