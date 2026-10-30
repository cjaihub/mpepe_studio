import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/theme/app_theme.dart';
import '../settings/live_advanced_settings_sheet.dart';
import '../widgets/oneova_live_creation_wizard.dart'
    show OneovaLiveCreationConfig;

typedef ConfigChanged = void Function(OneovaLiveCreationConfig next);

/// Pop-up sheets opened from the Go LIVE screen's icon rail. Each sheet edits
/// one slice of [OneovaLiveCreationConfig] and reports changes immediately.
class GoLiveSheets {
  GoLiveSheets._();

  static const categories = <(String, IconData)>[
    ('Entertainment', Icons.movie_outlined),
    ('Music', Icons.music_note_outlined),
    ('Gaming', Icons.sports_esports_outlined),
    ('Tech', Icons.code_outlined),
    ('Biz', Icons.business_center_outlined),
    ('Education', Icons.school_outlined),
    ('Lifestyle', Icons.spa_outlined),
    ('Sports', Icons.sports_soccer_outlined),
    ('Talk', Icons.forum_outlined),
  ];

  static IconData categoryIcon(String name) => categories
      .firstWhere((c) => c.$1 == name, orElse: () => categories.first)
      .$2;

  static const scenes = <(String, String, IconData, List<Color>)>[
    ('Executive Suite', 'Corporate · clean boardroom glow',
        Icons.business_center_outlined, [AppColors.brandBlack, AppColors.brandBlue]),
    ('Cyber-Cinema 7.1', 'Cinematic blue halo',
        Icons.movie_filter_outlined, [AppColors.brandBlue, AppColors.brandBlack]),
    ('Neon Stadium', 'Electric blue & pink arena',
        Icons.stadium_outlined, [AppColors.brandBlue, AppColors.brandPink]),
    ('Acoustic Loft', 'Warm, intimate lounge',
        Icons.queue_music_outlined, [AppColors.brandPink, AppColors.brandBlack]),
    ('Cosmic Hologram', 'Deep space nebula',
        Icons.auto_awesome_outlined, [AppColors.brandBlack, AppColors.brandPink]),
  ];

  // ── Generic shell ────────────────────────────────────────────────────────

  static Future<void> _open(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Widget Function(BuildContext ctx, StateSetter setSheet) body,
  }) {
    HapticFeedback.lightImpact();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.35),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.78),
          child: Container(
            decoration: BoxDecoration(
              color: ctx.surface,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadius.xl)),
              border: Border(top: BorderSide(color: ctx.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ctx.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Row(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: AppColors.brandBlue.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(icon,
                                  color: AppColors.brandBlue, size: 17)
                              .animate()
                              .scale(
                                  begin: const Offset(0.5, 0.5),
                                  duration: 300.ms,
                                  curve: Curves.easeOutBack)
                              .rotate(begin: -0.1, end: 0, duration: 300.ms),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(title,
                              style: GoogleFonts.inter(
                                  color: ctx.textPrimary,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2)),
                        ),
                        IconButton(
                          tooltip: 'Done',
                          onPressed: () => Navigator.of(ctx).pop(),
                          icon: Icon(Icons.check_rounded,
                              color: ctx.textPrimary, size: 20),
                        ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                      child: body(ctx, setSheet)
                          .animate()
                          .fadeIn(duration: 250.ms)
                          .slideY(begin: 0.05, end: 0),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Topic ───────────────────────────────────────────────────────────────

  static Future<void> topic(BuildContext context,
      {required String current, required ValueChanged<String> onPick}) {
    var selected = current;
    return _open(context,
        title: 'Choose a topic',
        icon: Icons.local_offer_outlined,
        body: (ctx, setSheet) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, c) in categories.indexed)
                  _SelectChip(
                    icon: c.$2,
                    label: c.$1,
                    selected: selected == c.$1,
                    onTap: () {
                      setSheet(() => selected = c.$1);
                      onPick(c.$1);
                      Future.delayed(180.ms, () {
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      });
                    },
                  ).animate(delay: (i * 30).ms).fadeIn().scale(
                      begin: const Offset(0.9, 0.9), duration: 200.ms),
              ],
            ));
  }

  // ── Audience ────────────────────────────────────────────────────────────

  static Future<void> audience(BuildContext context,
      {required OneovaLiveCreationConfig config,
      required ConfigChanged onChanged}) {
    var cfg = config;
    void set(StateSetter s, OneovaLiveCreationConfig n) {
      s(() => cfg = n);
      onChanged(n);
    }

    const modes = [
      ('Public', 'Anyone on Oneova can find and watch', Icons.public_rounded),
      ('Followers Only', 'Only people who follow you', Icons.group_rounded),
      ('Private Room', 'Invite link only · not in feeds', Icons.lock_rounded),
    ];
    return _open(context,
        title: 'Who can watch',
        icon: Icons.visibility_outlined,
        body: (ctx, s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final m in modes)
                  _OptionTile(
                    icon: m.$3,
                    title: m.$1,
                    subtitle: m.$2,
                    selected: cfg.audienceMode == m.$1,
                    onTap: () => set(s, cfg.copyWith(audienceMode: m.$1)),
                  ),
                const SizedBox(height: 6),
                _SwitchTile(
                  icon: Icons.group_add_outlined,
                  title: 'Allow requests to join',
                  subtitle: 'Viewers can ask to go live with you',
                  value: cfg.viewerJoinRequests,
                  onChanged: (v) =>
                      set(s, cfg.copyWith(viewerJoinRequests: v)),
                ),
                _SwitchTile(
                  icon: Icons.eighteen_up_rating_outlined,
                  title: 'Mature content (18+)',
                  subtitle: 'Hidden from younger viewers',
                  value: cfg.contentRating.contains('18+'),
                  onChanged: (v) => set(
                      s, cfg.copyWith(contentRating: v ? '18+ Mature' : 'All Ages')),
                ),
              ],
            ));
  }

  // ── Beauty & Looks ────────────────────────────────────────────────────────

  static Future<void> beauty(BuildContext context,
      {required OneovaLiveCreationConfig config,
      required ConfigChanged onChanged}) {
    return showLiveAdvancedSettingsSheet(context);
  }

  // ── Scene / effects ─────────────────────────────────────────────────────

  static Future<void> scene(BuildContext context,
      {required OneovaLiveCreationConfig config,
      required ConfigChanged onChanged}) {
    var cfg = config;
    return _open(context,
        title: cfg.layoutMode == 'studio' ? 'Studio scene' : 'Effects',
        icon: Icons.blur_on_rounded,
        body: (ctx, s) => GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.7,
              children: [
                for (final (i, sc) in scenes.indexed)
                  _SceneCard(
                    title: sc.$1,
                    subtitle: sc.$2,
                    icon: sc.$3,
                    colors: sc.$4,
                    selected: cfg.atmospherePreset == sc.$1,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final n = cfg.copyWith(atmospherePreset: sc.$1);
                      s(() => cfg = n);
                      onChanged(n);
                    },
                  ).animate(delay: (i * 40).ms).fadeIn(duration: 220.ms).slideY(
                      begin: 0.1, end: 0),
              ],
            ));
  }

  // ── Settings ────────────────────────────────────────────────────────────

  static Future<void> settings(BuildContext context,
      {required OneovaLiveCreationConfig config,
      required ConfigChanged onChanged}) {
    var cfg = config;
    void set(StateSetter s, OneovaLiveCreationConfig n) {
      s(() => cfg = n);
      onChanged(n);
    }

    const qualities = ['720p 30fps', '1080p 30fps', '1080p 60fps'];
    return _open(context,
        title: 'LIVE settings',
        icon: Icons.tune_rounded,
        body: (ctx, s) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Video quality'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final q in qualities)
                      _SelectChip(
                        icon: q.startsWith('1080')
                            ? Icons.hd_rounded
                            : Icons.sd_rounded,
                        label: q,
                        selected: cfg.quality == q,
                        onTap: () => set(s, cfg.copyWith(quality: q)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _Label('Comments & safety'),
                _SwitchTile(
                  icon: Icons.shield_outlined,
                  title: 'AI moderation',
                  subtitle: 'Flags harmful comments in real time',
                  value: cfg.isAiModerationEnabled,
                  onChanged: (v) =>
                      set(s, cfg.copyWith(isAiModerationEnabled: v)),
                ),
                _SwitchTile(
                  icon: Icons.filter_alt_outlined,
                  title: 'Filter offensive comments',
                  subtitle: 'Hide toxic words automatically',
                  value: cfg.autoFilterToxicComments,
                  onChanged: (v) =>
                      set(s, cfg.copyWith(autoFilterToxicComments: v)),
                ),
                _SwitchTile(
                  icon: Icons.bolt_outlined,
                  title: 'Auto highlights',
                  subtitle: 'Clip the best moments for your profile',
                  value: cfg.autoHighlightMoments,
                  onChanged: (v) =>
                      set(s, cfg.copyWith(autoHighlightMoments: v)),
                ),
                const SizedBox(height: 14),
                _Label('Sound'),
                _SwitchTile(
                  icon: Icons.music_note_outlined,
                  title: 'Background music',
                  subtitle: 'Play a soft bed under your voice',
                  value: cfg.bgMusicEnabled,
                  onChanged: (v) => set(s, cfg.copyWith(bgMusicEnabled: v)),
                ),
                if (cfg.bgMusicEnabled)
                  _SliderTile(
                    icon: Icons.volume_up_outlined,
                    title: 'Music volume',
                    value: cfg.bgMusicVolume,
                    onChanged: (v) => set(s, cfg.copyWith(bgMusicVolume: v)),
                  ),
              ],
            ));
  }

  // ── Guidelines ──────────────────────────────────────────────────────────

  static Future<void> guidelines(BuildContext context) {
    const rules = [
      (Icons.verified_user_outlined, 'Be yourself',
          'No impersonation or misleading identity.'),
      (Icons.child_care_outlined, 'Keep it safe',
          'No content that endangers minors or anyone else.'),
      (Icons.music_off_outlined, 'Respect rights',
          'Only use music and media you have rights to.'),
      (Icons.handshake_outlined, 'Be kind',
          'No harassment, hate or bullying in your LIVE.'),
    ];
    return _open(context,
        title: 'Community Guidelines',
        icon: Icons.gavel_rounded,
        body: (ctx, s) => Column(
              children: [
                for (final r in rules)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(r.$1, color: AppColors.brandBlue, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.$2,
                                  style: GoogleFonts.inter(
                                      color: ctx.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 2),
                              Text(r.$3,
                                  style: GoogleFonts.inter(
                                      color: ctx.textSecondary,
                                      fontSize: 12.5,
                                      height: 1.35)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET CONTROLS (theme-aware)
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: GoogleFonts.inter(
                color: context.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8)),
      );
}

class _SelectChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SelectChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: 180.ms,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandBlue
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
              color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 15,
                color: selected ? AppColors.brandWhite : context.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.inter(
                    color:
                        selected ? AppColors.brandWhite : context.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: 180.ms,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.brandBlue.withValues(alpha: 0.08)
              : context.surfaceMid,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
              color: selected ? AppColors.brandBlue : context.border),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? AppColors.brandBlue : context.textSecondary,
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.inter(
                          color: context.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.inter(
                          color: context.textSecondary, fontSize: 11.5)),
                ],
              ),
            ),
            AnimatedScale(
              scale: selected ? 1 : 0,
              duration: 200.ms,
              curve: Curves.easeOutBack,
              child: const Icon(Icons.check_circle_rounded,
                  color: AppColors.brandBlue, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: context.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.inter(
                        color: context.textPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: GoogleFonts.inter(
                        color: context.textMuted, fontSize: 11.5)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.brandBlue,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: context.textSecondary, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: Text(title,
                style: GoogleFonts.inter(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: AppColors.brandBlue,
                inactiveTrackColor: context.border,
                thumbColor: AppColors.brandBlue,
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: Slider(value: value.clamp(0, 1), onChanged: onChanged),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text('${(value * 100).round()}',
                textAlign: TextAlign.right,
                style: GoogleFonts.inter(
                    color: context.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _SceneCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final bool selected;
  final VoidCallback onTap;

  const _SceneCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: selected ? AppColors.brandPink : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.brandWhite, size: 18),
                const Spacer(),
                AnimatedScale(
                  scale: selected ? 1 : 0,
                  duration: 200.ms,
                  curve: Curves.easeOutBack,
                  child: const Icon(Icons.check_circle_rounded,
                      color: AppColors.brandWhite, size: 16),
                ),
              ],
            ),
            const Spacer(),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: AppColors.brandWhite,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                    color: AppColors.brandWhite.withValues(alpha: 0.75),
                    fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}
