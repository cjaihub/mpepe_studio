import 'dart:math' as math;

import '../../social/models/content.dart';

/// Real engagement signals for one piece of content. Every field comes from
/// a Firestore counter; nothing is estimated or invented.
class ViralSignals {
  final int views;
  final int likes;
  final int comments;
  final int shares;
  final int saves;
  final int completions;
  final int follows;
  final int watchTimeMs;
  final Duration? videoDuration;
  final double ageHours;

  const ViralSignals({
    this.views = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
    this.completions = 0,
    this.follows = 0,
    this.watchTimeMs = 0,
    this.videoDuration,
    required this.ageHours,
  });

  factory ViralSignals.fromContent(Content c, {DateTime? now}) {
    final age = (now ?? DateTime.now()).difference(c.createdAt).inSeconds / 3600.0;
    return ViralSignals(
      views: c.viewCount,
      likes: c.likeCount,
      comments: c.commentCount,
      shares: c.shareCount + c.repostCount,
      saves: c.saveCount,
      completions: c.completionCount,
      follows: c.followerConversions,
      watchTimeMs: c.watchTimeMs,
      videoDuration: c.mediaMetadata.duration,
      ageHours: math.max(0.0, age),
    );
  }
}

/// Every factor that went into a score, so "why am I seeing this" can be
/// answered from the numbers.
class ViralScoreBreakdown {
  final double engagementPoints;
  final double watchPoints;
  final double velocityPerHour;
  final double qualityMultiplier;
  final double freshnessBonus;
  final double timeDecay;
  final double score;
  final List<String> reasons;

  const ViralScoreBreakdown({
    required this.engagementPoints,
    required this.watchPoints,
    required this.velocityPerHour,
    required this.qualityMultiplier,
    required this.freshnessBonus,
    required this.timeDecay,
    required this.score,
    required this.reasons,
  });
}

/// Viral-velocity score: how fast real engagement is arriving per hour since
/// posting, adjusted for how well it converts viewers, faded with age, and
/// with a head start for brand-new posts so they get a first audience.
///
/// score = (ln(1 + points/hour) × quality + freshness) × decay
///
/// - points = 1·like + 3·comment + 5·share + 4·save + 8·follow
///            + 2·completion + 1·(watch time / video length)
/// - quality = per-view points rate vs the prior (Bayesian-smoothed, so a
///   post with 2 views can't look perfect), clamped to 0.5–2.0
/// - freshness = up to [freshnessMax] for posts under [freshnessWindowHours]
/// - decay = 0.5^(age / [halfLifeHours])
class ViralVelocityScorer {
  static const double likeWeight = 1;
  static const double commentWeight = 3;
  static const double shareWeight = 5;
  static const double saveWeight = 4;
  static const double followWeight = 8;
  static const double completionWeight = 2;
  static const double watchWeight = 1;

  static const double halfLifeHours = 36;
  static const double freshnessWindowHours = 6;
  static const double freshnessMax = 1.5;

  // Prior: 1 point per 20 views is "average".
  static const double _priorPoints = 1;
  static const double _priorViews = 20;
  static const double _priorRate = _priorPoints / _priorViews;

  const ViralVelocityScorer();

  ViralScoreBreakdown score(ViralSignals s) {
    final engagement = s.likes * likeWeight +
        s.comments * commentWeight +
        s.shares * shareWeight +
        s.saves * saveWeight +
        s.follows * followWeight;

    // Watch time in "full plays", capped so a stuck player can't farm it.
    final durMs = s.videoDuration?.inMilliseconds ?? 0;
    final fullPlays = durMs > 0 ? s.watchTimeMs / durMs : 0.0;
    final cappedPlays = math.min(fullPlays, 3.0 * math.max(s.views, 1));
    final watch = s.completions * completionWeight + cappedPlays * watchWeight;

    final points = engagement + watch;
    final velocity = points / math.max(1.0, s.ageHours);

    final rate = (points + _priorPoints) / (s.views + _priorViews);
    final quality = (rate / _priorRate).clamp(0.5, 2.0).toDouble();

    final freshness = s.ageHours < freshnessWindowHours
        ? freshnessMax * (1 - s.ageHours / freshnessWindowHours)
        : 0.0;
    final decay = math.pow(0.5, s.ageHours / halfLifeHours).toDouble();

    final total = (math.log(1 + velocity) * quality + freshness) * decay;

    final reasons = <String>[];
    if (velocity >= 1) reasons.add('${velocity.toStringAsFixed(1)} engagement points per hour');
    if (s.follows > 0) reasons.add('${s.follows} follow${s.follows == 1 ? '' : 's'} gained from this post');
    if (s.shares > 0) reasons.add('shared ${s.shares} time${s.shares == 1 ? '' : 's'}');
    if (quality >= 1.5) reasons.add('strong engagement per view');
    if (quality <= 0.6) reasons.add('low engagement per view');
    if (freshness > 0) reasons.add('new post boost');
    if (s.ageHours >= halfLifeHours) reasons.add('older post, fading');

    return ViralScoreBreakdown(
      engagementPoints: engagement,
      watchPoints: watch,
      velocityPerHour: velocity,
      qualityMultiplier: quality,
      freshnessBonus: freshness,
      timeDecay: decay,
      score: total,
      reasons: reasons,
    );
  }

  double scoreContent(Content c, {DateTime? now}) => score(ViralSignals.fromContent(c, now: now)).score;
}
