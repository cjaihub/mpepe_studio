import '../../../backend/live/models/live_models.dart';
import 'live_studio_geometry.dart';

/// Someone who is (or can be) on the studio stage.
class StageMember {
  final String uid;
  final String displayName;
  final String avatarUrl;
  final bool isHost;
  final String roleLabel;
  final bool isMuted;
  final bool isCameraOn;
  final DateTime joinedAt;

  const StageMember({
    required this.uid,
    required this.displayName,
    required this.avatarUrl,
    required this.isHost,
    required this.roleLabel,
    required this.isMuted,
    required this.isCameraOn,
    required this.joinedAt,
  });
}

/// Result of mapping the live roster onto the studio walls.
class StudioRoster {
  final StageMember? center;

  /// slotId → member (only filled slots).
  final Map<String, StageMember> wall;

  /// Stage members with no free wall slot; shown in the Participants tab.
  final List<StageMember> overflow;

  /// Every publisher (center + wall + overflow).
  final List<StageMember> publishers;

  const StudioRoster({
    required this.center,
    required this.wall,
    required this.overflow,
    required this.publishers,
  });

  Set<String> get publisherIds => publishers.map((m) => m.uid).toSet();

  Map<String, String> get assignment =>
      wall.map((slotId, m) => MapEntry(slotId, m.uid));

  static const empty = StudioRoster(
      center: null, wall: {}, overflow: [], publishers: []);
}

/// Whether a participant is currently allowed on stage: co-hosts, or guests
/// whose join request was approved and not since dropped.
bool isOnStage(LiveParticipant p, Map<String, LiveGuestRequest> requestsByUser) {
  if (p.hasRequestedToJoin) return false;
  if (p.isCoHost || p.role == LiveGuestRole.coHost) return true;
  return requestsByUser[p.userId]?.status == LiveGuestRequestStatus.approved;
}

String _roleLabel(LiveParticipant p) {
  switch (p.role) {
    case LiveGuestRole.coHost:
      return 'Co-host';
    case LiveGuestRole.moderator:
      return 'Moderator';
    case LiveGuestRole.speaker:
      return 'Speaker';
    case LiveGuestRole.viewer:
      return 'Guest';
  }
}

/// Builds the studio roster.
///
/// * [stageFocusUserId] — who the host put on the center stage (falls back to
///   the host when that person is no longer on stage).
/// * [isPortraitVideo] — optional hint (from the incoming video's aspect
///   ratio) so phone guests prefer the tall glass panels.
/// * [previous] — last slot assignment, so guests don't jump between walls
///   when the roster changes.
StudioRoster buildStudioRoster({
  required LiveStream stream,
  required List<LiveParticipant> participants,
  required List<LiveGuestRequest> requests,
  required String? stageFocusUserId,
  required List<WallSlot> slots,
  bool? Function(String uid)? isPortraitVideo,
  Map<String, String> previous = const {},
}) {
  final requestsByUser = {for (final r in requests) r.userId: r};
  final hostDoc = participants.where((p) => p.userId == stream.hostId).firstOrNull;

  final host = StageMember(
    uid: stream.hostId,
    displayName: stream.hostDisplayName,
    avatarUrl: stream.hostAvatarUrl,
    isHost: true,
    roleLabel: 'Host',
    isMuted: hostDoc?.isMuted ?? false,
    isCameraOn: hostDoc?.isCameraOn ?? true,
    joinedAt: stream.createdAt,
  );

  final guests = participants
      .where((p) => p.userId != stream.hostId && isOnStage(p, requestsByUser))
      .map((p) => StageMember(
            uid: p.userId,
            displayName: p.displayName,
            avatarUrl: p.avatarUrl,
            isHost: false,
            roleLabel: _roleLabel(p),
            isMuted: p.isMuted,
            isCameraOn: p.isCameraOn,
            joinedAt: p.joinedAt,
          ))
      .toList()
    ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

  final publishers = [host, ...guests];
  final center = publishers.firstWhere(
    (m) => m.uid == stageFocusUserId,
    orElse: () => host,
  );
  final waiting = publishers.where((m) => m.uid != center.uid).toList();

  final wall = <String, StageMember>{};
  final freeSlots = slots.map((s) => s.id).toSet();

  // 1. Sticky: keep members in the slot they had.
  for (final m in waiting.toList()) {
    final prevSlot = previous.entries
        .where((e) => e.value == m.uid && freeSlots.contains(e.key))
        .map((e) => e.key)
        .firstOrNull;
    if (prevSlot != null) {
      wall[prevSlot] = m;
      freeSlots.remove(prevSlot);
      waiting.remove(m);
    }
  }

  // 2. Fill remaining slots in config order, preferring portrait panels for
  //    portrait video.
  final overflow = <StageMember>[];
  for (final m in waiting) {
    final wantsPortrait = isPortraitVideo?.call(m.uid) ?? false;
    final ordered = slots.where((s) => freeSlots.contains(s.id)).toList()
      ..sort((a, b) {
        final pa = a.portrait == wantsPortrait ? 0 : 1;
        final pb = b.portrait == wantsPortrait ? 0 : 1;
        // List.sort is not stable: tie-break on config order.
        return pa != pb ? pa - pb : slots.indexOf(a) - slots.indexOf(b);
      });
    if (ordered.isEmpty) {
      overflow.add(m);
      continue;
    }
    final slot = ordered.first;
    wall[slot.id] = m;
    freeSlots.remove(slot.id);
  }

  return StudioRoster(
    center: center,
    wall: wall,
    overflow: overflow,
    publishers: publishers,
  );
}
