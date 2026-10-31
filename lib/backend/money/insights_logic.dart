import 'package:intl/intl.dart';

import 'money_models.dart';

/// Plain-language reading of a creator's numbers. Pure functions, so the
/// wording is tested in test/money/insights_logic_test.dart.

String compact(num n) => NumberFormat.compact().format(n);

String watchTime(int ms) {
  final m = ms ~/ 60000;
  if (m < 1) return '${(ms / 1000).round()}s';
  if (m < 60) return '${m}m';
  final h = m ~/ 60;
  return m % 60 == 0 ? '${h}h' : '${h}h ${m % 60}m';
}

String money(double amount, String currency) {
  final f = NumberFormat.simpleCurrency(name: currency, decimalDigits: amount >= 1000 || amount == amount.roundToDouble() ? 0 : 2);
  return f.format(amount);
}

/// Change between two periods as a whole percent, or null when there is no base.
int? percentChange(num now, num before) {
  if (before <= 0) return null;
  return (((now - before) / before) * 100).round();
}

class PeriodTotals {
  final int views, plays, watchMs, completes, likes, comments, shares, followsNet, gifts;
  const PeriodTotals({
    this.views = 0,
    this.plays = 0,
    this.watchMs = 0,
    this.completes = 0,
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.followsNet = 0,
    this.gifts = 0,
  });

  factory PeriodTotals.of(Iterable<DayStat> days) {
    var v = 0, p = 0, w = 0, c = 0, l = 0, cm = 0, s = 0, f = 0, g = 0;
    for (final d in days) {
      v += d.views;
      p += d.plays;
      w += d.watchMs;
      c += d.completes;
      l += d.likes;
      cm += d.comments;
      s += d.shares;
      f += d.netFollows;
      g += d.giftDiamonds;
    }
    return PeriodTotals(views: v, plays: p, watchMs: w, completes: c, likes: l, comments: cm, shares: s, followsNet: f, gifts: g);
  }

  int get engagements => likes + comments + shares;
}

/// The headline above the charts ("You're growing!").
({String title, String body}) headline(PeriodTotals now, PeriodTotals before, int days) {
  final views = percentChange(now.views, before.views);
  if (now.views == 0 && now.engagements == 0) {
    return (title: 'Your story starts here', body: 'Post a clip and your first views will show up here within minutes.');
  }
  if (views != null && views >= 10) {
    return (title: "You're growing! 🚀", body: 'Views are up $views% compared with the $days days before. Keep the streak going.');
  }
  if (now.followsNet > 0) {
    return (title: '${compact(now.followsNet)} new ${now.followsNet == 1 ? 'follower' : 'followers'}', body: 'People like what you make. Reply to comments to keep them close.');
  }
  if (views != null && views <= -10) {
    return (title: 'A quieter stretch', body: 'Views are down ${-views}%. Posting a new clip is the fastest way to bounce back.');
  }
  return (title: 'Steady and strong', body: '${compact(now.views)} views in $days days. Small daily posts add up fast.');
}

/// Clips by length bucket, for the "short clips get 2x views" tip.
String bucketOf(int durationMs) => durationMs < 20000 ? 'under 20s' : durationMs <= 60000 ? '20–60s' : 'over a minute';

String _partOfDay(int hour) => hour < 6 ? 'at night' : hour < 12 ? 'in the morning' : hour < 18 ? 'in the afternoon' : 'in the evening';

double _avg(Iterable<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a + b) / xs.length;

/// Compares groups of clips and returns a tip when one group clearly wins.
String? _bestGroupTip(Map<String, List<ClipStat>> groups, String Function(String key, String times) say) {
  final eligible = groups.entries.where((e) => e.value.length >= 2).toList();
  if (eligible.length < 2) return null;
  eligible.sort((a, b) => _avg(b.value.map((c) => c.views)).compareTo(_avg(a.value.map((c) => c.views))));
  final best = _avg(eligible.first.value.map((c) => c.views));
  final rest = _avg(eligible.skip(1).expand((e) => e.value).map((c) => c.views));
  if (best < 20 || rest <= 0 || best / rest < 1.5) return null;
  return say(eligible.first.key, (best / rest).toStringAsFixed(1).replaceAll('.0', ''));
}

/// Simple, specific tips from the creator's own clips.
List<String> creatorTips(List<ClipStat> clips, {DateTime? now}) {
  final tips = <String>[];
  final timed = clips.where((c) => c.durationMs != null).toList();
  final byLength = <String, List<ClipStat>>{};
  for (final c in timed) {
    byLength.putIfAbsent(bucketOf(c.durationMs!), () => []).add(c);
  }
  final t1 = _bestGroupTip(byLength, (k, x) => 'Your clips $k get ${x}x more views. Make more of them.');
  if (t1 != null) tips.add(t1);

  final byTime = <String, List<ClipStat>>{};
  for (final c in clips) {
    byTime.putIfAbsent(_partOfDay(c.createdAt.toLocal().hour), () => []).add(c);
  }
  final t2 = _bestGroupTip(byTime, (k, x) => 'Clips you post $k get ${x}x more views. Try posting then.');
  if (t2 != null) tips.add(t2);

  final played = clips.where((c) => c.plays >= 10).toList();
  if (played.length >= 2) {
    final rate = played.map((c) => c.completionRate!).reduce((a, b) => a + b) / played.length;
    if (rate < 0.3) {
      tips.add('Most people swipe away before the end. Show the best moment in the first 2 seconds.');
    } else if (rate >= 0.6) {
      tips.add('${(rate * 100).round()}% of viewers watch to the end. Your stories hold attention, so you can go a little longer.');
    }
  }

  final shared = clips.where((c) => c.shares > 0).toList()..sort((a, b) => b.shares.compareTo(a.shares));
  if (shared.isNotEmpty && shared.first.shares >= 3) {
    final name = shared.first.caption.trim().isEmpty ? 'One of your clips' : '“${_short(shared.first.caption)}”';
    tips.add('$name was shared ${shared.first.shares} times. People share what makes them feel something. Make another like it.');
  }

  final today = now ?? DateTime.now();
  final recent = clips.where((c) => today.difference(c.createdAt).inDays < 14).length;
  if (clips.isNotEmpty && recent < 3) {
    tips.add(recent == 0
        ? 'You haven’t posted in 2 weeks. A new clip puts you back in people’s feeds.'
        : 'You posted $recent ${recent == 1 ? 'time' : 'times'} in 2 weeks. Posting 3 times a week keeps you in more feeds.');
  }
  return tips;
}

String _short(String s) {
  final t = s.replaceAll('\n', ' ').trim();
  return t.length <= 28 ? t : '${t.substring(0, 27)}…';
}

/// Tips for one clip, compared with the creator's other clips.
List<String> clipTips(ClipStat clip, List<ClipStat> all) {
  final others = all.where((c) => c.id != clip.id).toList();
  final tips = <String>[];
  if (others.length >= 2) {
    final avgViews = _avg(others.map((c) => c.views));
    if (avgViews > 0) {
      final x = clip.views / avgViews;
      if (x >= 1.5) {
        tips.add('This clip has ${x.toStringAsFixed(1)}x your usual views. Something here works: the topic, the sound or the first second.');
      } else if (x <= 0.5 && DateTime.now().difference(clip.createdAt).inDays >= 2) {
        tips.add('This clip has fewer views than your usual. Try a stronger first line on screen.');
      }
    }
  }
  final rate = clip.completionRate;
  if (rate != null && clip.plays >= 10) {
    if (rate >= 0.6) {
      tips.add('${(rate * 100).round()}% of people watch it to the end. Great pacing!');
    } else if (rate < 0.3) {
      tips.add('Only ${(rate * 100).round()}% watch to the end. Cutting slow parts can lift this.');
    }
  }
  if (clip.views >= 50 && clip.engagementRate >= 0.1) {
    tips.add('${(clip.engagementRate * 100).round()}% of viewers liked, commented or shared. That is a strong reaction.');
  }
  if (clip.views >= 50 && clip.comments == 0) {
    tips.add('No comments yet. Ending with a question invites people to talk.');
  }
  final d = clip.durationMs;
  if (d != null && d > 60000 && rate != null && rate < 0.4) {
    tips.add('Long clips lose people. A 20–40s cut of this could travel further.');
  }
  if (tips.isEmpty) tips.add('Keep sharing it. Clips often pick up views for days after posting.');
  return tips;
}

/// Next round number to cheer for ("1,000 followers").
int nextMilestone(int value) {
  const steps = [10, 50, 100, 250, 500, 1000, 2500, 5000, 10000, 25000, 50000, 100000, 250000, 500000, 1000000];
  return steps.firstWhere((s) => s > value, orElse: () => ((value ~/ 1000000) + 1) * 1000000);
}

/// Encouraging line for the wallet, from what was earned.
String earningsCheer(CreatorWallet w) {
  final usd = w.lifetimeUsd;
  if (usd <= 0) return 'Go live or post clips. Every gift you receive lands here as Diamonds.';
  if (!w.canWithdraw) {
    final left = minWithdrawUsd - w.availableUsd;
    return w.pendingDiamonds > 0
        ? 'You’re growing! ${money(w.pendingUsd, 'USD')} is on the way, and ${money(left, 'USD')} more unlocks your first withdrawal.'
        : 'Only ${money(left, 'USD')} more to unlock your first withdrawal. You’ve got this!';
  }
  return 'Amazing! You can withdraw ${money(w.availableUsd, 'USD')} today. Your fans are backing you.';
}
