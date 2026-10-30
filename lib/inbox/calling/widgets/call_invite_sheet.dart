import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../backend/calling/providers/active_call_controller.dart';
import '../../../backend/calling/providers/call_signaling_service.dart';
import '../../../backend/messaging_repository.dart';
import '../../../shared/theme/app_theme.dart';
import 'call_widgets.dart';

/// Rings more people into the current call (a 1:1 call becomes a group
/// call). Shows recent chat partners and searches everyone by username.
Future<void> showCallInviteSheet(BuildContext context, WidgetRef ref) async {
  HapticFeedback.lightImpact();
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => _InviteBody(me: me, messenger: messenger),
  );
}

class _InviteBody extends ConsumerStatefulWidget {
  final String me;
  final ScaffoldMessengerState? messenger;
  const _InviteBody({required this.me, this.messenger});

  @override
  ConsumerState<_InviteBody> createState() => _InviteBodyState();
}

class _InviteBodyState extends ConsumerState<_InviteBody> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<String>? _results;
  bool _searching = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onQuery(String text) {
    _debounce?.cancel();
    final q = text.trim().toLowerCase().replaceAll('@', '');
    if (q.isEmpty) {
      setState(() => _results = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThan: '$q')
          .limit(15)
          .get();
      if (!mounted || _query.text.trim().toLowerCase().replaceAll('@', '') != q) return;
      setState(() => _results = snap.docs.map((d) => d.id).where((id) => id != widget.me).toList());
    } catch (e) {
      debugPrint('[CallInvite] search failed: $e');
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _invite(String id) async {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    try {
      await ref.read(activeCallControllerProvider.notifier).invite([id]);
    } catch (e) {
      widget.messenger?.showSnackBar(SnackBar(
        content: Text(e is StateError ? e.message : 'Could not add them to the call.',
            style: GoogleFonts.inter(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.brandBlue,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final chats = ref.watch(userChatsProvider(widget.me)).value ?? const [];
    final inCall = ref.watch(activeCallControllerProvider).participants.keys.toSet();
    final recent = <String>{
      for (final c in chats)
        if (c.participants.length == 2) ...c.participants.where((p) => p != widget.me),
    }.where((id) => !inCall.contains(id)).take(25).toList();
    final ids = (_results ?? recent).where((id) => !inCall.contains(id)).toList();
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: context.border, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              Text('Add people',
                  style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: _query,
                  onChanged: _onQuery,
                  style: GoogleFonts.inter(fontSize: 13.5, color: context.textPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search by username',
                    hintStyle: GoogleFonts.inter(fontSize: 13.5, color: context.textSecondary),
                    prefixIcon: Icon(Icons.search_rounded, color: context.textSecondary, size: 20),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.brandBlue),
                            ),
                          )
                        : null,
                    filled: true,
                    fillColor: context.surfaceMid,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _results == null ? 'Recent chats' : 'Results',
                    style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: context.textSecondary),
                  ),
                ),
              ),
              if (ids.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    _results == null ? 'No recent chats to add. Search above.' : 'No one found.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
                  ),
                ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final id in ids)
                      FutureBuilder<CallTarget>(
                        future: ref.read(callSignalingServiceProvider).resolveUser(id),
                        builder: (ctx, snap) {
                          final t = snap.data;
                          return ListTile(
                            dense: true,
                            leading: CallAvatar(url: t?.avatar, name: t?.name ?? '', size: 34),
                            title: Text(t?.name ?? '…',
                                style: GoogleFonts.inter(fontSize: 13, color: context.textPrimary)),
                            trailing: const Icon(Icons.add_call, color: AppColors.brandBlue, size: 20),
                            onTap: () => _invite(id),
                          );
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
