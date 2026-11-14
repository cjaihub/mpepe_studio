import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/money/money_widgets.dart';
import '../id_guide.dart';
import '../identity_service.dart';
import '../identity_vault.dart';
import '../widgets/oneova_verified_badge.dart';
import 'id_share_sheet.dart';

/// Oneova ID hub (`/id`): your level, your verified identity and business,
/// sharing, and your data — in one place.
class OneovaIdScreen extends ConsumerStatefulWidget {
  const OneovaIdScreen({super.key, this.openShare = false});
  final bool openShare;

  @override
  ConsumerState<OneovaIdScreen> createState() => _OneovaIdScreenState();
}

class _OneovaIdScreenState extends ConsumerState<OneovaIdScreen> {
  /// One ID, one person: the verified owner can let up to 3 of their own other
  /// accounts verify with the same ID.
  Future<void> _linkAccount() async {
    final ctrl = TextEditingController();
    final handle = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Link another account'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Each ID belongs to one person. To verify another account you own (up to 3) with your ID, enter its @username.'),
          const SizedBox(height: 10),
          TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(isDense: true, prefixText: '@', hintText: 'username')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, ctrl.text.trim()), child: const Text('Link')),
        ],
      ),
    );
    ctrl.dispose();
    if (handle == null || handle.isEmpty || !mounted) return;
    try {
      await FirebaseFunctions.instance.httpsCallable('kycLinkAccount').call({'username': handle});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('@$handle can now verify with your ID.')));
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Couldn’t link that account.')));
    }
  }

  bool? _saved;
  bool _saving = false;
  final _vault = IdentityVault();
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _vault.has(_uid, 'person').then((v) => mounted ? setState(() => _saved = v) : null);
    if (widget.openShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(identityProvider).verified) IdShareSheet.show(context);
      });
    }
  }

  Future<void> _saveToPhone() async {
    setState(() => _saving = true);
    try {
      final c = await ref.read(identityServiceProvider).fetchCredential();
      await _vault.save(_uid, 'person', c.token);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _saved = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(identityError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showCard() async {
    final token = await _vault.read(_uid, 'person');
    if (token == null || !mounted) return;
    final claims = credentialClaims(token);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _IdCard(claims: claims),
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(identityProvider);
    final biz = ref.watch(businessIdentityProvider).value ?? const BusinessIdentity({});
    final invites = ref.watch(ownerInvitesProvider).value ?? const [];
    final shares = ref.watch(activeSharesProvider).value ?? const [];
    return MoneyScaffold(
      title: 'Oneova ID',
      actions: const [Padding(padding: EdgeInsets.only(right: 8), child: IdGuideButton(guideContext: IdGuideContext(screen: 'hub')))],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
        children: [
          _LevelHeader(level: id.shownLevel, business: biz),
          const SizedBox(height: 18),
          for (final inv in invites) _ownerInvite(inv),
          const SectionTitle('Your identity'),
          _personCard(id),
          const SizedBox(height: 18),
          const SectionTitle('Your business'),
          _businessCard(biz),
          if (shares.isNotEmpty) ...[
            const SizedBox(height: 18),
            const SectionTitle('Active shares'),
            ...shares.map(_shareRow),
          ],
          const SizedBox(height: 18),
          MoneyCard(
            onTap: () => context.push('/id/devices'),
            child: _row(Icons.phonelink_lock_rounded, 'Payment phones', 'Phones that can approve payments with your fingerprint or face'),
          ),
          const SizedBox(height: 10),
          MoneyCard(
            onTap: _linkAccount,
            child: _row(Icons.link_rounded, 'Linked accounts', 'Let your other Oneova account verify with your ID'),
          ),
          const SizedBox(height: 10),
          MoneyCard(
            onTap: () => context.push('/id/data'),
            child: _row(Icons.shield_outlined, 'Privacy & my data', 'What’s stored, who saw it, delete anytime'),
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String title, String sub, {Widget? trailing}) => Row(children: [
        Icon(icon, color: AppColors.brandBlue),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.3)),
          ]),
        ),
        trailing ?? Icon(Icons.chevron_right_rounded, color: context.textMuted),
      ]);

  Widget _personCard(IdentityState id) {
    final k = id.kyc;
    final (title, sub, cta) = switch (k.status) {
      'verified' => ('ID verified', 'Verified${k.verifiedName != null ? ' as ${k.verifiedName}' : ''}${k.country != null ? ' · ${k.country}' : ''}', null),
      'review' => ('In review', 'In review · usually within a day. We’ll notify you.', null),
      'rejected' => ('Needs another try', k.lastError ?? 'We couldn’t confirm your ID. Try again with clear photos.', 'Try again'),
      'collecting' => ('Almost there', 'Finish adding your photos.', 'Continue'),
      _ => ('Verify once, use everywhere', 'A photo of your ID and a selfie. Takes about 2 minutes.', 'Verify my identity'),
    };
    return MoneyCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _row(id.verified ? Icons.verified_rounded : Icons.badge_outlined, title, sub,
            trailing: id.verified ? const OneovaVerifiedBadge(size: 22) : const SizedBox.shrink()),
        if (cta != null) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.push('/wallet/verify'),
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(44)),
            child: Text(cta),
          ),
        ],
        if (id.verified) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => IdShareSheet.show(context),
                style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue),
                icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _saving ? null : (_saved == true ? _showCard : _saveToPhone),
                icon: Icon(_saved == true ? Icons.lock_rounded : Icons.download_rounded, size: 18),
                label: Text(_saved == true ? 'My ID card' : (_saving ? 'Saving…' : 'Save to phone')),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  Widget _businessCard(BusinessIdentity b) {
    final (title, sub) = switch (b.status) {
      'verified' => (b.level >= 2 ? 'Verified Business' : 'Registered business', '${b.legalName} · ${b.country}'),
      'review' => ('In review', '${b.legalName} · usually within 2 working days.'),
      'rejected' => ('Needs another try', b.rejectReason ?? 'Check the documents and try again.'),
      'expired' => ('Renew verification', b.rejectReason ?? 'Upload fresh documents to keep the badge.'),
      'collecting' => ('In progress', 'Finish your business check.'),
      _ => ('Get the Verified Business badge', 'For shops, brands and organisations — shows on your profile and store.'),
    };
    return MoneyCard(
      onTap: () => context.push('/id/business'),
      child: _row(Icons.storefront_rounded, title, sub,
          trailing: b.verified ? OneovaVerifiedBadge(kind: VerifiedKind.business, level: b.level, size: 22) : null),
    );
  }

  Widget _ownerInvite(Map<String, dynamic> inv) {
    final svc = ref.read(identityServiceProvider);
    Future<void> answer(bool yes) async {
      try {
        await svc.respondOwner('${inv['bizUid']}', yes);
        HapticFeedback.mediumImpact();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(identityError(e))));
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: MoneyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row(Icons.group_add_outlined, 'Are you an owner of ${inv['legalName']}?',
              'They listed you with ${inv['share']}% in their business check. Confirm only if it’s true.',
              trailing: const SizedBox.shrink()),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => answer(false), child: const Text('Not me'))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => answer(true),
                style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue),
                child: const Text('Confirm'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _shareRow(Map<String, dynamic> s) {
    final fields = (s['fields'] as List? ?? const []).join(', ');
    final views = (s['views'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MoneyCard(
        child: _row(Icons.qr_code_rounded, fields.isEmpty ? 'Verified only' : fields,
            'Checked $views ${views == 1 ? 'time' : 'times'}',
            trailing: TextButton(
              onPressed: () => ref.read(identityServiceProvider).stopShare('${s['id']}'),
              child: const Text('Stop', style: TextStyle(color: AppColors.brandPink)),
            )),
      ),
    );
  }
}

/// Level ladder at the top of the hub.
class _LevelHeader extends StatelessWidget {
  const _LevelHeader({required this.level, required this.business});
  final int level;
  final BusinessIdentity business;

  @override
  Widget build(BuildContext context) {
    const steps = ['Account', 'Contact verified', 'ID verified'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: AppColors.premiumGradient, borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(steps[level.clamp(0, 2)],
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            if (business.verified)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(AppRadius.full)),
                child: Text(business.level >= 2 ? 'Verified Business' : 'Registered business',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
          ]),
          const SizedBox(height: 14),
          Row(
            children: List.generate(3, (i) {
              final on = i <= level;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                  decoration: BoxDecoration(
                    color: on ? Colors.white : Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ).animate(delay: (120 * i).ms).scaleX(begin: on ? 0 : 1, alignment: Alignment.centerLeft, duration: 400.ms),
              );
            }),
          ),
          const SizedBox(height: 10),
          Text(
            level >= 2
                ? 'Verified once. Share proof with a QR code — only what you choose.'
                : 'Verify once and reuse it anywhere Oneova ID is accepted.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13, height: 1.35),
          ),
        ]),
      ),
    );
  }
}

/// The credential saved on this phone, opened with biometrics.
class _IdCard extends StatelessWidget {
  const _IdCard({required this.claims});
  final Map<String, Object?> claims;

  @override
  Widget build(BuildContext context) {
    String v(String k) => '${claims[k] ?? '—'}';
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.brandBlue, Color(0xFF0A2E66)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('ONEOVA ID', style: TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w800)),
            const Spacer(),
            Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.brandPink, shape: BoxShape.circle)),
          ]),
          const SizedBox(height: 18),
          Text(v('name'), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('@${v('handle')}', style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 16),
          Wrap(spacing: 22, runSpacing: 10, children: [
            _f('Country', v('country')),
            _f('Document', v('document').replaceAll('_', ' ')),
            _f('Verified since', v('since')),
            _f('Level', v('level')),
          ]),
          const SizedBox(height: 14),
          Text('Signed by Oneova · stored encrypted on this phone',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11)),
        ]),
      ),
    );
  }

  Widget _f(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
        Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ]);
}
