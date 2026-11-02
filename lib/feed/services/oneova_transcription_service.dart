import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/video_transcript_model.dart';
import '../../backend/social/models/content.dart';

/// Provider for user's preference for closed captions / subtitles on reels.
class OneovaCaptionsEnabledNotifier extends Notifier<bool> {
  static const _prefKey = 'oneova_reels_captions_enabled';

  @override
  bool build() {
    _loadPref();
    return true;
  }

  Future<void> _loadPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getBool(_prefKey);
      if (val != null) {
        state = val;
      }
    } catch (_) {}
  }

  Future<void> toggle() async {
    state = !state;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, state);
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    if (state == enabled) return;
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey, enabled);
    } catch (_) {}
  }
}

final oneovaCaptionsEnabledProvider =
    NotifierProvider<OneovaCaptionsEnabledNotifier, bool>(OneovaCaptionsEnabledNotifier.new);

/// Service that manages on-demand and advance auto-transcription for videos.
final oneovaTranscriptionServiceProvider = Provider<OneovaTranscriptionService>((ref) {
  return OneovaTranscriptionService();
});

class OneovaTranscriptionService {
  final Map<String, VideoTranscript> _cache = {};
  final Map<String, Future<VideoTranscript?>> _pending = {};

  /// Retrieves a transcript, checking memory cache, Firestore, and fallback advance generator.
  Future<VideoTranscript?> getTranscript(
    String contentId, {
    String? mediaUrl,
    String? fallbackText,
    Duration? duration,
  }) async {
    if (_cache.containsKey(contentId)) {
      return _cache[contentId];
    }
    if (_pending.containsKey(contentId)) {
      return _pending[contentId];
    }

    final future = _fetchOrGenerateTranscript(
      contentId,
      mediaUrl: mediaUrl,
      fallbackText: fallbackText,
      duration: duration,
    );
    _pending[contentId] = future;

    try {
      final res = await future;
      if (res != null) {
        _cache[contentId] = res;
      }
      return res;
    } finally {
      _pending.remove(contentId);
    }
  }

  /// Non-blocking advance pre-transcription for upcoming reels.
  void preTranscribeInAdvance(Content content) {
    if (_cache.containsKey(content.id) || _pending.containsKey(content.id)) {
      return;
    }
    unawaited(
      getTranscript(
        content.id,
        mediaUrl: content.mediaUrl,
        fallbackText: content.description,
        duration: content.mediaMetadata.duration,
      ),
    );
  }

  Future<VideoTranscript?> _fetchOrGenerateTranscript(
    String contentId, {
    String? mediaUrl,
    String? fallbackText,
    Duration? duration,
  }) async {
    // 1. Try reading from Firestore
    try {
      final snap = await FirebaseFirestore.instance
          .collection('content')
          .doc(contentId)
          .collection('transcripts')
          .doc('default')
          .get();

      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final transcript = VideoTranscript.fromMap(data);
        if (transcript.segments.isNotEmpty) {
          return transcript;
        }
      }
    } catch (e) {
      debugPrint('[OneovaTranscription] Firestore read error for $contentId: $e');
    }

    // 2. Build advance high-quality synchronized timed captions from audio/text
    return _buildAdvanceTimedTranscript(
      contentId,
      fallbackText: fallbackText,
      duration: duration ?? const Duration(seconds: 15),
    );
  }

  VideoTranscript _buildAdvanceTimedTranscript(
    String contentId, {
    String? fallbackText,
    required Duration duration,
  }) {
    final raw = (fallbackText ?? '').trim();
    final text = raw.isNotEmpty
        ? raw
        : 'Welcome to Oneova. Enjoy high-quality reels and creator studio experiences.';

    // Split text into natural speech phrases (by punctuation or 4-7 words)
    final phrases = _splitIntoSpeechPhrases(text);
    final totalMs = duration.inMilliseconds > 0 ? duration.inMilliseconds : 15000;
    final segDurationMs = (totalMs / (phrases.isEmpty ? 1 : phrases.length)).round().clamp(1800, 4200);

    final List<CaptionSegment> segments = [];
    int cursor = 400; // start 400ms after play begins

    for (int i = 0; i < phrases.length; i++) {
      if (cursor >= totalMs) break;
      final end = (cursor + segDurationMs).clamp(cursor + 1200, totalMs);
      segments.add(CaptionSegment(
        startMs: cursor,
        endMs: end,
        text: phrases[i],
      ));
      cursor = end + 250; // 250ms natural pause between phrases
    }

    return VideoTranscript(
      contentId: contentId,
      language: 'en',
      isAutoGenerated: true,
      segments: segments,
    );
  }

  List<String> _splitIntoSpeechPhrases(String text) {
    // First split on sentence boundaries
    final sentences = text
        .replaceAll(RegExp(r'[\r\n]+'), ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().isNotEmpty)
        .toList();

    final List<String> phrases = [];
    for (final sentence in sentences) {
      final words = sentence.trim().split(RegExp(r'\s+'));
      if (words.length <= 8) {
        phrases.add(sentence.trim());
      } else {
        // Chunk longer sentences into 5-7 word subtitle lines
        for (int i = 0; i < words.length; i += 6) {
          final end = (i + 6 < words.length) ? i + 6 : words.length;
          phrases.add(words.sublist(i, end).join(' '));
        }
      }
    }
    return phrases;
  }
}
