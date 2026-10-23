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

/// Lists the user's recent chat partners and rings the chosen one into the
/// current call.
Future<void> showCallInviteSheet(BuildContext context, WidgetRef ref) async {
  HapticFeedback.lightImpact();
  final me = FirebaseAuth.instance.currentUser?.uid;
  if (me == null) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => Consumer(builder: (ctx, ref, _) {
      final chats = ref.watch(userChatsProvider(me)).value ?? const [];
      final inCall = ref.watch(activeCallControllerProvider).participants.keys.toSet();
      final ids = <String>{
        for (final c in chats)
          if (c.participants.length == 2) ...c.participants.where((p) => p != me && !inCall.contains(p)),
      }.take(25).toList();
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('Add people',
                style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
            const SizedBox(height: 6),
            if (ids.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No recent chats to add.',
                    style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary)),
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
                              style: GoogleFonts.inter(fontSize: 13, color: ctx.textPrimary)),
                          trailing: const Icon(Icons.add_call, color: AppColors.brandBlue, size: 20),
                          onTap: () async {
                            Navigator.of(ctx).pop();
                            try {
                              await ref.read(activeCallControllerProvider.notifier).invite([id]);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(content: Text('$e')));
                              }
                            }
                          },
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }),
  );
}
