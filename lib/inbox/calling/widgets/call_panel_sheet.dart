import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/models/call_participant.dart';
import '../../../backend/calling/providers/active_call_controller.dart';
import '../../../backend/calling/providers/call_media_service.dart';
import '../../../backend/calling/providers/call_room_controller.dart';
import '../../../backend/calling/providers/webrtc_connection_manager.dart';
import '../../../backend/social/models/audio_track.dart';
import '../../../backend/social/repositories/audio_track_repository.dart';
import '../../../shared/theme/app_theme.dart';
import 'call_invite_sheet.dart';
import 'call_widgets.dart';

/// Sections of the call panel.
enum CallPanelTab { me, effects, sounds, music, people, layout }

/// Each participant's own control panel: their mic/camera/audio, camera
/// filters, the sound pad, shared music, who is in the call, and how the
/// call is laid out on this phone.
Future<void> showCallPanel(BuildContext context, {CallPanelTab initial = CallPanelTab.me}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => _CallPanel(initial: initial),
  );
}

class _CallPanel extends ConsumerWidget {
  final CallPanelTab initial;
  const _CallPanel({required this.initial});

  static const _tabs = [
    (CallPanelTab.me, 'Me', Icons.person_rounded),
    (CallPanelTab.effects, 'Effects', Icons.auto_awesome_rounded),
    (CallPanelTab.sounds, 'Sounds', Icons.surround_sound_rounded),
    (CallPanelTab.music, 'Music', Icons.library_music_rounded),
    (CallPanelTab.people, 'People', Icons.groups_rounded),
    (CallPanelTab.layout, 'Layout', Icons.dashboard_customize_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Close the panel when the call is over.
    ref.listen<ActiveCallState>(activeCallControllerProvider, (_, next) {
      if (!next.isBusy && Navigator.of(context).canPop()) Navigator.of(context).pop();
    });
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.62,
        child: DefaultTabController(
          length: _tabs.length,
          initialIndex: _tabs.indexWhere((t) => t.$1 == initial),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelColor: AppColors.brandBlue,
                unselectedLabelColor: context.textSecondary,
                indicatorColor: AppColors.brandBlue,
                dividerColor: context.border,
                labelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
                unselectedLabelStyle: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w500),
                tabs: [
                  for (final t in _tabs) Tab(height: 52, icon: Icon(t.$3, size: 18), text: t.$2),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _MeSection(),
                    _EffectsSection(),
                    _SoundsSection(),
                    _MusicSection(),
                    _PeopleSection(),
                    _LayoutSection(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
      child: Text(
        text,
        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: context.textSecondary),
      ),
    );

/// Square tile used by the effects and sound grids.
class _PadTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _PadTile({required this.icon, required this.label, this.selected = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandBlue : context.surfaceMid,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: selected ? AppColors.brandWhite : AppColors.brandBlue),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.brandWhite : context.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Me ─────────────────────────

class _MeSection extends ConsumerWidget {
  const _MeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(callMediaServiceProvider);
    final controller = ref.read(activeCallControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle(context, 'Microphone and camera'),
        Wrap(
          spacing: 18,
          runSpacing: 14,
          children: [
            CallControlButton(
              icon: media.isAudioMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
              label: media.isAudioMuted ? 'Unmute' : 'Mute',
              active: media.isAudioMuted,
              onTap: controller.toggleMute,
            ),
            CallControlButton(
              icon: media.isVideoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
              label: media.isVideoOn ? 'Camera on' : 'Camera off',
              active: media.isVideoOn,
              onTap: controller.toggleCamera,
            ),
            if (media.isVideoOn)
              CallControlButton(
                icon: Icons.flip_camera_ios_rounded,
                label: media.isFrontCamera ? 'Front' : 'Back',
                onTap: controller.switchCamera,
              ),
          ],
        ),
        _sectionTitle(context, 'Audio output'),
        for (final o in media.outputs)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: Icon(audioRouteIcon(o.route), color: AppColors.brandBlue, size: 20),
            title: Text(
              o.route == AudioRoute.bluetooth && o.label.isNotEmpty ? o.label : audioRouteLabel(o.route),
              style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary),
            ),
            trailing: media.audioRoute == o.route
                ? const Icon(Icons.check_rounded, color: AppColors.brandBlue, size: 18)
                : null,
            onTap: () {
              HapticFeedback.selectionClick();
              controller.selectAudioRoute(o.route, deviceId: o.deviceId);
            },
          ),
      ],
    );
  }
}

// ───────────────────────── Effects ─────────────────────────

class _EffectsSection extends ConsumerWidget {
  const _EffectsSection();

  static const Map<String, IconData> _icons = {
    'original': Icons.block_rounded,
    'vivid': Icons.palette_rounded,
    'warm': Icons.wb_sunny_rounded,
    'cool': Icons.ac_unit_rounded,
    'cinematic': Icons.movie_filter_rounded,
    'portrait': Icons.face_retouching_natural_rounded,
    'golden': Icons.wb_twilight_rounded,
    'mono': Icons.filter_b_and_w_rounded,
    'film': Icons.camera_roll_rounded,
    'neon': Icons.nightlife_rounded,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = ref.watch(callMediaServiceProvider);
    final room = ref.watch(callRoomControllerProvider);
    final looks = ref.watch(callLooksControllerProvider);
    final roomCtl = ref.read(callRoomControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle(context, 'Camera filters · everyone in the call sees them'),
        if (!media.isVideoOn)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam_off_rounded, color: AppColors.brandBlue, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Turn your camera on to use filters.',
                      style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary)),
                ),
                TextButton(
                  onPressed: ref.read(activeCallControllerProvider.notifier).toggleCamera,
                  child: Text('Camera on',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
              ],
            ),
          ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (final f in kCallFilters)
              _PadTile(
                icon: _icons[f.id] ?? Icons.auto_awesome_rounded,
                label: f.label,
                selected: room.filterId == f.id,
                onTap: () => roomCtl.setFilter(f.id),
              ),
          ],
        ),
        if (looks.lastError != null && room.filterId != 'original')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Filters are not supported on this phone.',
                style: GoogleFonts.inter(fontSize: 11.5, color: AppColors.brandPink)),
          ),
      ],
    );
  }
}

// ───────────────────────── Sounds ─────────────────────────

class _SoundsSection extends ConsumerWidget {
  const _SoundsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomCtl = ref.read(callRoomControllerProvider.notifier);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle(context, 'Tap to play for everyone'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.15,
          children: [
            for (final s in CallSound.values)
              _PadTile(
                icon: s.icon,
                label: s.label,
                onTap: () async {
                  final sent = await roomCtl.sendSound(s);
                  if (!sent) HapticFeedback.heavyImpact();
                },
              ),
          ],
        ),
      ],
    );
  }
}

// ───────────────────────── Music ─────────────────────────

class _MusicSection extends ConsumerWidget {
  const _MusicSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(callRoomControllerProvider);
    final roomCtl = ref.read(callRoomControllerProvider.notifier);
    final music = room.music;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (music != null) ...[
          _sectionTitle(context, 'Playing for everyone'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceMid,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _Cover(url: music.coverUrl, size: 48),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(music.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                          Text(
                            [if (music.artist.isNotEmpty) music.artist, if (music.byName.isNotEmpty) 'by ${music.byName}']
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: music.playing ? 'Pause for everyone' : 'Play for everyone',
                      icon: Icon(music.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                          color: AppColors.brandBlue, size: 36),
                      onPressed: roomCtl.togglePlay,
                    ),
                    IconButton(
                      tooltip: 'Stop music',
                      icon: const Icon(Icons.stop_circle_rounded, color: AppColors.brandPink, size: 30),
                      onPressed: roomCtl.stopMusic,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Icon(Icons.volume_down_rounded, size: 18, color: context.textSecondary),
                    Expanded(
                      child: Slider(
                        value: room.musicVolume,
                        min: 0,
                        max: 100,
                        activeColor: AppColors.brandBlue,
                        onChanged: roomCtl.setMusicVolume,
                      ),
                    ),
                    Icon(Icons.volume_up_rounded, size: 18, color: context.textSecondary),
                  ],
                ),
              ],
            ),
          ),
        ],
        _sectionTitle(context, 'Pick a song · everyone hears it'),
        StreamBuilder<List<AudioTrack>>(
          stream: ref.read(audioTrackRepositoryProvider).watchAvailableTracks(limit: 40),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
              );
            }
            final tracks = (snap.data ?? const <AudioTrack>[]).where((t) => t.contentUrl.isNotEmpty).toList();
            if (tracks.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No music available yet.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary)),
              );
            }
            return Column(
              children: [
                for (final t in tracks)
                  ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: _Cover(url: t.coverImageUrl, size: 40),
                    title: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
                    subtitle: Text(t.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
                    trailing: music?.url == t.contentUrl
                        ? const Icon(Icons.graphic_eq_rounded, color: AppColors.brandPink)
                        : const Icon(Icons.play_arrow_rounded, color: AppColors.brandBlue),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      roomCtl.playTrack(t);
                    },
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  final String? url;
  final double size;
  const _Cover({this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.brandBlue,
      child: Icon(Icons.music_note_rounded, color: AppColors.brandWhite, size: size * 0.5),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: url == null || url!.isEmpty
          ? fallback
          : CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => fallback,
              errorWidget: (_, _, _) => fallback,
            ),
    );
  }
}

// ───────────────────────── People ─────────────────────────

class _PeopleSection extends ConsumerWidget {
  const _PeopleSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(activeCallControllerProvider);
    final mesh = ref.watch(webrtcConnectionManagerProvider);
    final room = ref.watch(callRoomControllerProvider);
    final me = FirebaseAuth.instance.currentUser?.uid;
    final people = s.participants.values
        .where((p) =>
            p.status == ParticipantStatus.joined ||
            p.status == ParticipantStatus.ringing ||
            p.userId == me)
        .toList()
      ..sort((a, b) => a.userId == me ? -1 : (b.userId == me ? 1 : a.name.compareTo(b.name)));
    final canInvite = s.isBusy && s.phase != CallPhase.outgoing;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle(context, '${people.length} in this call'),
        for (final p in people)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: CallAvatar(url: p.avatar, name: p.name, size: 36),
            title: Text(
              p.userId == me ? '${p.name} (you)' : p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary),
            ),
            subtitle: Text(
              _status(p, p.userId == me ? null : mesh.peers[p.userId]),
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.isAudioMuted) const Icon(Icons.mic_off_rounded, size: 18, color: AppColors.brandPink),
                if (p.isVideoMuted) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.videocam_off_rounded, size: 18, color: context.textSecondary),
                ],
                if (p.userId != me && p.status == ParticipantStatus.joined)
                  IconButton(
                    tooltip: room.pinnedUid == p.userId ? 'Unpin' : 'Pin to the big screen',
                    icon: Icon(
                      room.pinnedUid == p.userId ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                      size: 18,
                      color: AppColors.brandBlue,
                    ),
                    onPressed: () {
                      final roomCtl = ref.read(callRoomControllerProvider.notifier);
                      roomCtl.pin(p.userId);
                      if (room.pinnedUid != p.userId) roomCtl.setLayout(CallLayout.spotlight);
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        if (canInvite)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brandBlue,
              foregroundColor: AppColors.brandWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
            ),
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text('Add people', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700)),
            onPressed: () => showCallInviteSheet(context, ref),
          ),
        const SizedBox(height: 12),
      ],
    );
  }

  static String _status(CallParticipant p, PeerState? peer) {
    if (p.status == ParticipantStatus.ringing) return p.deliveredAt != null ? 'Ringing…' : 'Calling…';
    if (peer == null) return 'In the call';
    if (peer.link == PeerLinkState.reconnecting) return 'Reconnecting…';
    if (!peer.isConnected) return 'Connecting…';
    return switch (peer.quality) {
      CallQuality.poor => 'Weak connection',
      CallQuality.fair => 'Fair connection',
      _ => peer.frameEncrypted ? 'Connected · end-to-end encrypted' : 'Connected',
    };
  }
}

// ───────────────────────── Layout ─────────────────────────

class _LayoutSection extends ConsumerWidget {
  const _LayoutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(callRoomControllerProvider);
    final roomCtl = ref.read(callRoomControllerProvider.notifier);
    final isGroup = ref.watch(activeCallControllerProvider.select((s) => s.call?.isGroup ?? false));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        _sectionTitle(context, 'Only on your phone'),
        if (isGroup)
          Row(
            children: [
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: _PadTile(
                    icon: Icons.grid_view_rounded,
                    label: 'Grid',
                    selected: room.layout == CallLayout.grid,
                    onTap: () => roomCtl.setLayout(CallLayout.grid),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1.6,
                  child: _PadTile(
                    icon: Icons.featured_video_rounded,
                    label: 'Spotlight',
                    selected: room.layout == CallLayout.spotlight,
                    onTap: () => roomCtl.setLayout(CallLayout.spotlight),
                  ),
                ),
              ),
            ],
          ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          activeThumbColor: AppColors.brandBlue,
          title: Text('Hide my video preview', style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
          subtitle: Text('Others still see you',
              style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
          value: room.hideSelfView,
          onChanged: roomCtl.setHideSelfView,
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          activeThumbColor: AppColors.brandBlue,
          title: Text('Mirror my preview', style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
          subtitle: Text('Front camera only', style: GoogleFonts.inter(fontSize: 11.5, color: context.textSecondary)),
          value: room.mirrorSelfView,
          onChanged: roomCtl.setMirrorSelfView,
        ),
      ],
    );
  }
}
