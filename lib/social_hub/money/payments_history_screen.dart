import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../backend/pay/oneova_pay_service.dart';
import '../../shared/theme/app_theme.dart';

/// Every Oneova Pay payment you made (orders and top-ups), newest first.
/// `/wallet/payments`
class PaymentsHistoryScreen extends StatelessWidget {
  const PaymentsHistoryScreen({super.key});

  static (String, Color, IconData) _status(String s) => switch (s) {
        'succeeded' => ('Paid', AppColors.brandBlue, Icons.check_circle_rounded),
        'created' || 'pending_payer' => ('Waiting for approval', const Color(0xFFF5A524), Icons.hourglass_top_rounded),
        'refunded' => ('Refunded', AppColors.brandPink, Icons.undo_rounded),
        'review' => ('Being checked', const Color(0xFFF5A524), Icons.manage_search_rounded),
        'expired' => ('Timed out', Colors.grey, Icons.timer_off_rounded),
        'cancelled' => ('Cancelled', Colors.grey, Icons.block_rounded),
        _ => ('Didn’t go through', AppColors.brandPink, Icons.error_outline_rounded),
      };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '-';
    final stream = FirebaseFirestore.instance
        .collection('pay_intents')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots();
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/wallet'),
        ),
        title: Text('Payments', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: context.textPrimary)),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Couldn’t load your payments.', style: TextStyle(color: context.textSecondary)));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.brandBlue));
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.receipt_long_rounded, size: 44, color: context.textMuted),
                  const SizedBox(height: 10),
                  Text('No payments yet', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Your purchases and top-ups will show here.',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
                ]),
              ),
            );
          }
          final fmt = DateFormat('d MMM, HH:mm');
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: docs.length,
            separatorBuilder: (_, _) => Divider(height: 1, indent: 64, color: context.border),
            itemBuilder: (context, i) {
              final d = docs[i].data();
              final p = PayIntent.fromMap(docs[i].id, d);
              final (label, color, icon) = _status(p.status);
              final at = (d['createdAt'] as Timestamp?)?.toDate();
              final order = d['purpose'] == 'order';
              return ListTile(
                onTap: order && d['refId'] is String ? () => context.push('/biz/orders/${d['refId']}') : null,
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.14),
                  child: Icon(order ? Icons.shopping_bag_rounded : Icons.add_card_rounded, color: color, size: 20),
                ),
                title: Text(order ? 'Order payment' : 'Added to balance',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: context.textPrimary)),
                subtitle: Row(children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      [label, if (p.methodLabel.isNotEmpty) p.methodLabel, if (at != null) fmt.format(at), if (p.sandbox) 'Test'].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                    ),
                  ),
                ]),
                trailing: Text(formatMinor(p.amountMinor, p.currency),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: context.textPrimary)),
              );
            },
          );
        },
      ),
    );
  }
}
