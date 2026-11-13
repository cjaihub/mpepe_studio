import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/money/money_widgets.dart';
import '../id_guide.dart';
import '../identity_service.dart';
import '../identity_vault.dart';

/// Privacy & my data (`/id/data`): what Oneova ID keeps, the activity log,
/// and deleting it.
class IdDataScreen extends ConsumerWidget {
  const IdDataScreen({super.key});

  static const _labels = {
    'id.submitted': 'You sent your ID for review',
    'id.verified': 'Your identity was verified',
    'id.rejected': 'Your ID check needs another try',
    'id.credential_issued': 'Your Oneova ID was saved to your phone',
    'id.shared': 'You shared your Oneova ID',
    'id.share_stopped': 'You stopped a share',
    'id.deleted': 'You deleted your identity data',
    'id.files_deleted': 'Your ID photos were deleted (30-day rule)',
    'business.started': 'You started a business check',
    'business.submitted': 'You sent business documents',
    'business.verified': 'Your business was verified',
    'business.rejected': 'Your business check needs another try',
    'business.expired': 'Your business verification expired',
    'business.deleted': 'You deleted your business data',
    'business.files_deleted': 'Business documents were deleted (30-day rule)',
    'business.shared': 'You shared your business ID',
    'business.credential_issued': 'Your business ID was saved to your phone',
    'business.owner_confirmed': 'You confirmed a business ownership',
    'business.owner_declined': 'You declined a business ownership',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(identityProvider);
    final biz = ref.watch(businessIdentityProvider).value ?? const BusinessIdentity({});
    final log = ref.watch(identityAuditProvider).value ?? const [];
    return MoneyScaffold(
      title: 'Privacy & my data',
      actions: const [Padding(padding: EdgeInsets.only(right: 8), child: IdGuideButton(guideContext: IdGuideContext(screen: 'my_data')))],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        children: [
          const SectionTitle('What we keep'),
          MoneyCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fact(context, Icons.photo_camera_outlined, 'ID photos and business documents',
                  'Private. Only the review team can open them; every view is logged. Deleted automatically 30 days after the decision.'),
              _fact(context, Icons.person_outline_rounded, 'Your verified details',
                  'Name, country, document type and status. Never your ID number, date of birth or face data.'),
              _fact(context, Icons.lock_outline_rounded, 'Your ID card',
                  'Signed by Oneova and stored encrypted on this phone only. Opening it needs your fingerprint, face or PIN.'),
              _fact(context, Icons.auto_awesome_outlined, 'AI help',
                  'An AI pre-check reads documents to help the reviewer; it never decides. Ova’s chat never sees your photos or numbers.'),
            ]),
          ),
          const SizedBox(height: 18),
          const SectionTitle('Activity'),
          MoneyCard(
            child: log.isEmpty
                ? Text('Nothing yet.', style: TextStyle(color: context.textSecondary))
                : Column(
                    children: log.map((e) {
                      final at = e['at'] is Timestamp ? (e['at'] as Timestamp).toDate() : null;
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_labels[e['type']] ?? '${e['type']}', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                        subtitle: Text(
                          [if ('${e['detail'] ?? ''}'.isNotEmpty) '${e['detail']}', if (at != null) MaterialLocalizations.of(context).formatShortDate(at)].join(' · '),
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 18),
          const SectionTitle('Delete'),
          if (id.kyc.status != 'none')
            MoneyCard(
              onTap: () => _confirmDelete(context, ref, business: false),
              child: _danger(context, 'Delete my identity data', 'Photos, verified details and your ID card. Payouts stop until you verify again.'),
            ),
          if (biz.status != 'none') ...[
            const SizedBox(height: 10),
            MoneyCard(
              onTap: () => _confirmDelete(context, ref, business: true),
              child: _danger(context, 'Delete my business data', 'Documents and details. The Verified Business badge is removed from your profile and store.'),
            ),
          ],
          if (id.kyc.status == 'none' && biz.status == 'none')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text('You have no identity data with Oneova.', style: TextStyle(color: context.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, IconData icon, String title, String body) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: AppColors.brandBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
            ]),
          ),
        ]),
      );

  Widget _danger(BuildContext context, String title, String body) => Row(children: [
        const Icon(Icons.delete_outline_rounded, color: AppColors.brandPink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.brandPink)),
            const SizedBox(height: 2),
            Text(body, style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
          ]),
        ),
      ]);

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, {required bool business}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(business ? 'Delete business data?' : 'Delete identity data?'),
        content: Text(business
            ? 'Your documents and business details are deleted and the Verified Business badge is removed from your profile and store. Shared codes stop working. This can’t be undone.'
            : 'Your ID photos, verified details and ID card are deleted and every shared code stops working. Payouts and withdrawals turn off until you verify again. This can’t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandPink),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final svc = ref.read(identityServiceProvider);
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      if (business) {
        await svc.deleteBusiness();
        await IdentityVault().wipe(uid, 'business');
      } else {
        await svc.deletePersonal();
        await IdentityVault().wipe(uid, 'person');
      }
      messenger.showSnackBar(const SnackBar(content: Text('Deleted.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(identityError(e))));
    }
  }
}
