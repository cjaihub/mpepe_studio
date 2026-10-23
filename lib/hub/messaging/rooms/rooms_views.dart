import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/messaging_repository.dart';
import '../../../shared/theme/app_theme.dart';

/// Live list of open rooms (`vip: false`) or VIP private rooms (`vip: true`),
/// backed by `chats` docs with category `room` / `vip_room`.
class RoomsListView extends ConsumerWidget {
  final bool vip;
  const RoomsListView({super.key, required this.vip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final repo = ref.watch(messagingRepositoryProvider);

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: repo.watchRooms(vip: vip),
      builder: (context, snap) {
        final header = _RoomsHeader(vip: vip);
        if (snap.hasError) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            header,
            const SizedBox(height: 24),
            Center(child: Text('Could not load rooms', style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 13))),
          ]);
        }
        if (!snap.hasData) {
          return ListView(padding: const EdgeInsets.all(16), children: [
            header,
            const SizedBox(height: 32),
            const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue))),
          ]);
        }
        final rooms = snap.data!;
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: rooms.length + 1,
          separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 12 : 8),
          itemBuilder: (context, index) {
            if (index == 0) {
              return rooms.isEmpty ? Column(children: [header, const SizedBox(height: 28), _EmptyRooms(vip: vip)]) : header;
            }
            final doc = rooms[index - 1];
            return _RoomTile(chatId: doc.id, data: doc.data(), uid: uid, vip: vip)
                .animate()
                .fadeIn(duration: 250.ms, delay: (index * 30).ms)
                .slideY(begin: 0.05, end: 0);
          },
        );
      },
    );
  }
}

class _RoomsHeader extends ConsumerWidget {
  final bool vip;
  const _RoomsHeader({required this.vip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                vip ? 'VIP private rooms' : 'Rooms',
                style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 15, letterSpacing: -0.2),
              ),
              const SizedBox(height: 2),
              Text(
                vip ? 'Members-only spaces. The host approves who joins.' : 'Open group spaces anyone can join.',
                style: GoogleFonts.inter(color: context.textSecondary, fontSize: 11.5),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 34,
          child: ElevatedButton.icon(
            onPressed: () => showCreateRoomSheet(context, ref, vip: vip),
            style: ElevatedButton.styleFrom(
              backgroundColor: vip ? AppColors.brandPink : AppColors.brandBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text('Create', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12.5)),
          ),
        ),
      ],
    );
  }
}

class _EmptyRooms extends StatelessWidget {
  final bool vip;
  const _EmptyRooms({required this.vip});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(vip ? Icons.lock_outline_rounded : Icons.forum_outlined, color: context.textMuted, size: 32),
        const SizedBox(height: 8),
        Text(
          vip ? 'No VIP rooms yet' : 'No rooms yet',
          style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'Create the first one and invite your community.',
          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5),
        ),
      ],
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _RoomTile extends ConsumerStatefulWidget {
  final String chatId;
  final Map<String, dynamic> data;
  final String? uid;
  final bool vip;

  const _RoomTile({required this.chatId, required this.data, required this.uid, required this.vip});

  @override
  ConsumerState<_RoomTile> createState() => _RoomTileState();
}

class _RoomTileState extends ConsumerState<_RoomTile> {
  bool _busy = false;

  String get _title => (widget.data['title'] as String?)?.trim().isNotEmpty == true ? widget.data['title'] as String : 'Untitled room';
  List<String> get _members => List<String>.from(widget.data['participants'] ?? const []);
  String? get _ownerId => widget.data['ownerId'] as String?;
  bool get _isMember => widget.uid != null && _members.contains(widget.uid);

  void _open() {
    HapticFeedback.lightImpact();
    context.push('/hub/messages/${widget.chatId}');
  }

  Future<void> _join() async {
    final uid = widget.uid;
    if (uid == null) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await ref.read(messagingRepositoryProvider).joinRoom(widget.chatId, uid);
      if (mounted) context.push('/hub/messages/${widget.chatId}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not join: $e'), backgroundColor: AppColors.brandPink));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestAccess() async {
    final uid = widget.uid;
    final owner = _ownerId;
    if (uid == null || owner == null) return;
    HapticFeedback.lightImpact();
    setState(() => _busy = true);
    try {
      await ref.read(messagingRepositoryProvider).requestRoomAccess(
            chatId: widget.chatId,
            userId: uid,
            ownerId: owner,
            roomTitle: _title,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent. The host will be notified.'), backgroundColor: AppColors.brandBlue),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not send request: $e'), backgroundColor: AppColors.brandPink));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final description = (widget.data['description'] as String?) ?? '';
    final tags = List<String>.from(widget.data['tags'] ?? const []);
    final accessNote = widget.data['accessNote'] as String?;
    final accent = widget.vip ? AppColors.brandPink : AppColors.brandBlue;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: _isMember ? _open : null,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(widget.vip ? Icons.lock_rounded : Icons.forum_rounded, color: accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 14, letterSpacing: -0.2)),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, height: 1.35)),
                    ],
                    if (widget.vip && accessNote != null && accessNote.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(accessNote, style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${_members.length} member${_members.length == 1 ? '' : 's'}',
                            style: GoogleFonts.inter(color: context.textMuted, fontSize: 11, fontWeight: FontWeight.w500)),
                        for (final tag in tags.take(3))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.surfaceMid,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                              border: Border.all(color: context.border, width: 1.0),
                            ),
                            child: Text(tag, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 9.5, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildAction(accent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(Color accent) {
    if (_busy) {
      return const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue));
    }
    if (_isMember) return _pill('Open', accent, filled: false, onTap: _open);
    if (!widget.vip) return _pill('Join', accent, filled: true, onTap: _join);

    final uid = widget.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<bool>(
      stream: ref.read(messagingRepositoryProvider).watchHasRequestedAccess(widget.chatId, uid),
      builder: (context, snap) {
        final requested = snap.data ?? false;
        return requested
            ? _pill('Requested', context.textMuted, filled: false, onTap: null)
            : _pill('Request', accent, filled: true, onTap: _requestAccess);
      },
    );
  }

  Widget _pill(String label, Color color, {required bool filled, required VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: color, width: 1.0),
        ),
        child: Text(label, style: GoogleFonts.inter(color: filled ? Colors.white : color, fontWeight: FontWeight.w700, fontSize: 11.5)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create sheets
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showCreateRoomSheet(BuildContext context, WidgetRef ref, {required bool vip}) {
  HapticFeedback.lightImpact();
  return _showFormSheet(
    context,
    title: vip ? 'New VIP room' : 'New room',
    subtitle: vip
        ? 'Only people you approve can join. Requests arrive in your notifications.'
        : 'Anyone on Oneova can find and join this room.',
    actionLabel: 'Create room',
    accent: vip ? AppColors.brandPink : AppColors.brandBlue,
    fields: [
      const _FieldSpec('title', 'Room name', maxLength: 48, required: true),
      const _FieldSpec('description', 'What is it about?', maxLength: 140, maxLines: 2),
      const _FieldSpec('tags', 'Tags (comma separated)', maxLength: 60),
      if (vip) const _FieldSpec('accessNote', 'Access terms shown to members (optional)', maxLength: 60),
    ],
    onSubmit: (values) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in to create a room.');
      return ref.read(messagingRepositoryProvider).createRoom(
            ownerId: uid,
            title: values['title']!,
            description: values['description'] ?? '',
            tags: (values['tags'] ?? '').split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).take(5).toList(),
            isVip: vip,
            accessNote: values['accessNote'],
          );
    },
  );
}

Future<void> showCreateBroadcastSheet(BuildContext context, WidgetRef ref) {
  HapticFeedback.lightImpact();
  return _showFormSheet(
    context,
    title: 'New broadcast channel',
    subtitle: 'Your current followers are added. Only you can post; they get your updates.',
    actionLabel: 'Create channel',
    accent: AppColors.brandBlue,
    fields: const [
      _FieldSpec('title', 'Channel name', maxLength: 48, required: true),
      _FieldSpec('description', 'Description (optional)', maxLength: 140, maxLines: 2),
    ],
    onSubmit: (values) async {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Sign in to create a channel.');
      return ref.read(messagingRepositoryProvider).createBroadcastChannel(
            ownerId: uid,
            title: values['title']!,
            description: values['description'] ?? '',
          );
    },
  );
}

class _FieldSpec {
  final String key;
  final String hint;
  final int maxLength;
  final int maxLines;
  final bool required;
  const _FieldSpec(this.key, this.hint, {this.maxLength = 60, this.maxLines = 1, this.required = false});
}

Future<void> _showFormSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String actionLabel,
  required Color accent,
  required List<_FieldSpec> fields,
  required Future<String> Function(Map<String, String?> values) onSubmit,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => _FormSheet(
      title: title,
      subtitle: subtitle,
      actionLabel: actionLabel,
      accent: accent,
      fields: fields,
      onSubmit: onSubmit,
      onCreated: (chatId) {
        Navigator.of(sheetCtx).pop();
        context.push('/hub/messages/$chatId');
      },
    ),
  );
}

class _FormSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final String actionLabel;
  final Color accent;
  final List<_FieldSpec> fields;
  final Future<String> Function(Map<String, String?> values) onSubmit;
  final void Function(String chatId) onCreated;

  const _FormSheet({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.accent,
    required this.fields,
    required this.onSubmit,
    required this.onCreated,
  });

  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields) f.key: TextEditingController()..addListener(() => setState(() {})),
  };
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid => widget.fields.where((f) => f.required).every((f) => _controllers[f.key]!.text.trim().isNotEmpty);

  Future<void> _submit() async {
    if (!_valid || _submitting) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final values = {
        for (final e in _controllers.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim(),
      };
      final chatId = await widget.onSubmit(values);
      if (mounted) widget.onCreated(chatId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: context.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border(top: BorderSide(color: context.border, width: 1.0)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(AppRadius.full)),
                ),
              ),
              const SizedBox(height: 14),
              Text(widget.title, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: -0.3)),
              const SizedBox(height: 4),
              Text(widget.subtitle, style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, height: 1.35)),
              const SizedBox(height: 14),
              for (final f in widget.fields) ...[
                TextField(
                  controller: _controllers[f.key],
                  maxLength: f.maxLength,
                  maxLines: f.maxLines,
                  textCapitalization: TextCapitalization.sentences,
                  style: GoogleFonts.inter(color: context.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: f.hint,
                    hintStyle: GoogleFonts.inter(color: context.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: context.surfaceMid,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: context.border, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      borderSide: BorderSide(color: widget.accent, width: 1.0),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_error != null) ...[
                Text(_error!, style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 11.5)),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: ElevatedButton(
                  onPressed: _valid && !_submitting ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.accent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: context.surfaceMid,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.actionLabel, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
              ),
            ],
          ),
        ),
      ).animate().fadeIn(duration: 200.ms).slideY(begin: 0.05, end: 0),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thread-level helpers (used by ChatDetailScreen)
// ─────────────────────────────────────────────────────────────────────────────

/// Shown instead of the composer to channel members who are not the owner.
class ChannelReadOnlyBar extends StatelessWidget {
  const ChannelReadOnlyBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: context.surface,
          border: Border(top: BorderSide(color: context.border, width: 1.0)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 16, color: context.textMuted),
            const SizedBox(width: 8),
            Text('Only the channel owner can post here', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}

/// Banner for VIP room hosts with pending join requests.
class RoomJoinRequestsBanner extends ConsumerWidget {
  final String chatId;
  final String roomTitle;
  const RoomJoinRequestsBanner({super.key, required this.chatId, required this.roomTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(messagingRepositoryProvider);
    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: repo.watchPendingRoomRequests(chatId),
      builder: (context, snap) {
        final requests = snap.data ?? const [];
        if (requests.isEmpty) return const SizedBox.shrink();
        return GestureDetector(
          onTap: () => _showRequestsSheet(context, ref),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.brandPink.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.4), width: 1.0),
            ),
            child: Row(
              children: [
                const Icon(Icons.person_add_alt_1_rounded, size: 16, color: AppColors.brandPink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${requests.length} pending request${requests.length == 1 ? '' : 's'} to join',
                    style: GoogleFonts.inter(color: context.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Text('Review', style: GoogleFonts.inter(color: AppColors.brandPink, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.1, end: 0),
        );
      },
    );
  }

  void _showRequestsSheet(BuildContext context, WidgetRef ref) {
    HapticFeedback.lightImpact();
    final repo = ref.read(messagingRepositoryProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheetCtx) => SafeArea(
        child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: repo.watchPendingRoomRequests(chatId),
          builder: (context, snap) {
            final requests = snap.data ?? const [];
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Join requests', style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w700, fontSize: 17)),
                  const SizedBox(height: 10),
                  if (requests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('No pending requests', style: GoogleFonts.inter(color: context.textSecondary, fontSize: 12.5)),
                    ),
                  for (final r in requests)
                    _RequestRow(
                      requesterId: r.id,
                      onResolve: (approve) => repo.resolveRoomRequest(
                        chatId: chatId,
                        requesterId: r.id,
                        approve: approve,
                        roomTitle: roomTitle,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RequestRow extends StatelessWidget {
  final String requesterId;
  final Future<void> Function(bool approve) onResolve;
  const _RequestRow({required this.requesterId, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance.collection('users').doc(requesterId).get(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? const {};
        final name = (data['displayName'] as String?) ?? (data['username'] as String?) ?? 'Oneova user';
        final photo = data['profilePhotoUrl'] as String?;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: context.surfaceMid,
                backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
                child: photo == null || photo.isEmpty ? Icon(Icons.person, size: 16, color: context.textMuted) : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => context.push('/profile/$requesterId'),
                  child: Text(name, style: GoogleFonts.inter(color: context.textPrimary, fontWeight: FontWeight.w600, fontSize: 13.5)),
                ),
              ),
              TextButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onResolve(false);
                },
                child: Text('Decline', style: GoogleFonts.inter(color: context.textMuted, fontSize: 12.5)),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 32,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    onResolve(true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text('Approve', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
