import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/theme/app_theme.dart';
import '../../social_hub/money/money_widgets.dart';
import '../id_guide.dart';
import '../id_photo_check.dart';
import '../identity_service.dart';
import '../widgets/oneova_verified_badge.dart';
import 'id_share_sheet.dart';

/// Verified Business (`/id/business`). The checklist comes from the server for
/// the chosen country, so each country asks for what it usually needs.
class BusinessVerifyScreen extends ConsumerStatefulWidget {
  const BusinessVerifyScreen({super.key});

  @override
  ConsumerState<BusinessVerifyScreen> createState() => _BusinessVerifyScreenState();
}

class _Owner {
  final username = TextEditingController();
  final share = TextEditingController(text: '25');
}

class _BusinessVerifyScreenState extends ConsumerState<BusinessVerifyScreen> {
  static const _types = {
    'sole_trader': 'Sole trader',
    'company': 'Company',
    'partnership': 'Partnership',
    'nonprofit': 'Non-profit',
    'public_body': 'Public body',
  };
  static const _countries = {
    'KE': 'Kenya', 'UG': 'Uganda', 'TZ': 'Tanzania', 'RW': 'Rwanda', 'ET': 'Ethiopia', 'NG': 'Nigeria', 'GH': 'Ghana',
    'ZA': 'South Africa', 'EG': 'Egypt', 'MA': 'Morocco', 'SN': 'Senegal', 'CI': 'Côte d’Ivoire', 'CM': 'Cameroon',
    'US': 'United States', 'CA': 'Canada', 'MX': 'Mexico', 'BR': 'Brazil', 'GB': 'United Kingdom', 'IE': 'Ireland',
    'FR': 'France', 'DE': 'Germany', 'ES': 'Spain', 'IT': 'Italy', 'NL': 'Netherlands', 'SE': 'Sweden', 'PL': 'Poland',
    'TR': 'Türkiye', 'AE': 'United Arab Emirates', 'SA': 'Saudi Arabia', 'QA': 'Qatar', 'IN': 'India', 'PK': 'Pakistan',
    'BD': 'Bangladesh', 'CN': 'China', 'JP': 'Japan', 'KR': 'South Korea', 'ID': 'Indonesia', 'PH': 'Philippines',
    'VN': 'Vietnam', 'MY': 'Malaysia', 'SG': 'Singapore', 'AU': 'Australia', 'NZ': 'New Zealand',
  };

  String _country = '';
  String _type = 'company';
  bool _busy = false;
  String? _sessionId;
  String? _path;
  KybRequirements? _req;
  final _uploaded = <String, String>{}; // doc key → file name
  final _uploading = <String>{};
  final _photoFacts = <String, Object?>{};
  final _legalName = TextEditingController();
  final _regNo = TextEditingController();
  final _taxId = TextEditingController();
  final _address = TextEditingController();
  final _owners = <_Owner>[];
  bool _consent = false;
  bool _restart = false;

  @override
  void initState() {
    super.initState();
    final cc = WidgetsBinding.instance.platformDispatcher.locale.countryCode?.toUpperCase();
    _country = _countries.containsKey(cc) ? cc! : 'KE';
  }

  @override
  void dispose() {
    for (final c in [_legalName, _regNo, _taxId, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final r = await ref.read(identityServiceProvider).startBusiness(_country, _type);
      setState(() {
        _sessionId = r.sessionId;
        _path = r.path;
        _req = r.requirements;
        _restart = false;
      });
    } catch (e) {
      _toast(identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String m) => mounted ? ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))) : null;

  Future<void> _pick(Map<String, dynamic> doc) async {
    final key = '${doc['key']}';
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(ctx, 'camera')),
          ListTile(leading: const Icon(Icons.picture_as_pdf_outlined), title: const Text('Choose a PDF or image'), onTap: () => Navigator.pop(ctx, 'file')),
        ]),
      ),
    );
    if (source == null || _path == null) return;
    File? file;
    if (source == 'camera') {
      final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 88, maxWidth: 2200);
      if (x != null) file = File(x.path);
    } else {
      final r = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
      final p = r.isNotEmpty ? r.first.path : null;
      if (p != null) file = File(p);
    }
    if (file == null || !mounted) return;
    final lower = file.path.toLowerCase();
    final ext = lower.endsWith('.pdf') ? 'pdf' : lower.endsWith('.png') ? 'png' : 'jpg';
    if (await file.length() > 15 * 1024 * 1024) return _toast('That file is over 15 MB.');
    if (ext != 'pdf') {
      final check = await IdPhotoCheck.check(file);
      _photoFacts.addAll(check.asGuideFacts(key));
      if (!mounted || !await IdPhotoCheck.review(context, check)) return;
    }
    setState(() => _uploading.add(key));
    try {
      final mime = ext == 'pdf' ? 'application/pdf' : ext == 'png' ? 'image/png' : 'image/jpeg';
      await FirebaseStorage.instance.ref('$_path/$key.$ext').putFile(file, SettableMetadata(contentType: mime));
      HapticFeedback.selectionClick();
      setState(() => _uploaded[key] = '$key.$ext');
    } catch (e) {
      _toast('Upload failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _uploading.remove(key));
    }
  }

  bool get _ready {
    final r = _req;
    if (r == null || !_consent) return false;
    final docsOk = r.documents.every((d) => d['required'] != true || _uploaded.containsKey(d['key']));
    return docsOk &&
        _legalName.text.trim().length >= 2 &&
        _address.text.trim().length >= 5 &&
        KybRequirements.fieldOk(r.registrationNumber, _regNo.text.trim()) &&
        KybRequirements.fieldOk(r.taxId, _taxId.text.trim());
  }

  Future<void> _submit() async {
    if (!_ready || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(identityServiceProvider).submitBusiness({
        'sessionId': _sessionId,
        'legalName': _legalName.text.trim(),
        'registrationNumber': _regNo.text.trim(),
        'taxId': _taxId.text.trim(),
        'address': _address.text.trim(),
        'owners': _owners
            .where((o) => o.username.text.trim().isNotEmpty)
            .map((o) => {'username': o.username.text.trim(), 'share': int.tryParse(o.share.text) ?? 0})
            .toList(),
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      _toast(identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(identityProvider);
    final b = ref.watch(businessIdentityProvider).value ?? const BusinessIdentity({});
    final guide = IdGuideContext(screen: 'business', extra: {
      'country': _country,
      'business_type': _type,
      'documents_uploaded': _uploaded.keys.toList(),
      'documents_missing': _req?.documents.where((d) => d['required'] == true && !_uploaded.containsKey(d['key'])).map((d) => d['label']).toList(),
      ..._photoFacts,
    });
    final showForm = _restart || b.status == 'none' || b.status == 'collecting';
    return MoneyScaffold(
      title: 'Verified Business',
      actions: [Padding(padding: const EdgeInsets.only(right: 8), child: IdGuideButton(guideContext: guide))],
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 40),
        children: [
          if (!id.verified) _needPersonal(),
          if (!showForm) _status(b) else ...[
            _intro(),
            if (_req == null) _choose() else ..._form(_req!),
          ],
        ],
      ),
    );
  }

  Widget _needPersonal() => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: MoneyCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('First, verify yourself', style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimary)),
            const SizedBox(height: 4),
            Text('A business is verified through its owner. It takes about 2 minutes.', style: TextStyle(fontSize: 12, color: context.textSecondary)),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => context.push('/wallet/verify'),
              style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue),
              child: const Text('Verify my identity'),
            ),
          ]),
        ),
      );

  Widget _intro() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Text(
          'Get the Verified Business badge on your profile and store. We’ll show exactly what your country usually needs.',
          style: TextStyle(fontSize: 13, height: 1.4, color: context.textSecondary),
        ),
      );

  Widget _choose() => MoneyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DropdownButtonFormField<String>(
            initialValue: _country,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Country of registration'),
            items: (_countries.entries.toList()..sort((a, b) => a.value.compareTo(b.value)))
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _country = v ?? _country),
          ),
          const SizedBox(height: 14),
          Text('Business type', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: _types.entries
                .map((t) => ChoiceChip(
                      label: Text(t.value),
                      selected: _type == t.key,
                      selectedColor: AppColors.brandBlue.withValues(alpha: 0.22),
                    checkmarkColor: AppColors.brandBlue,
                    labelStyle: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _type = t.key),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _start,
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(46)),
            child: Text(_busy ? 'Loading…' : 'See what’s needed'),
          ),
        ]),
      );

  InputDecoration _dec(Map<String, dynamic> f, TextEditingController c) {
    final v = c.text.trim();
    final bad = v.isNotEmpty && !KybRequirements.fieldOk(f, v);
    return InputDecoration(
      labelText: '${f['label']}${f['required'] == true ? '' : ' (optional)'}',
      helperText: '${f['hint']}',
      errorText: bad ? 'That doesn’t look right — check the format.' : null,
    );
  }

  List<Widget> _form(KybRequirements r) => [
        MoneyCard(
          child: Row(children: [
            const Icon(Icons.account_balance_outlined, color: AppColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${_countries[_country] ?? _country} · ${_types[_type]}\nUsually checked against ${r.registry}.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: context.textSecondary)),
            ),
            TextButton(onPressed: () => setState(() => _req = null), child: const Text('Change')),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Business details'),
        MoneyCard(
          child: Column(children: [
            TextField(controller: _legalName, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Registered business name')),
            TextField(controller: _regNo, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.characters, decoration: _dec(r.registrationNumber, _regNo)),
            TextField(controller: _taxId, onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.characters, decoration: _dec(r.taxId, _taxId)),
            TextField(controller: _address, onChanged: (_) => setState(() {}), maxLines: 2, decoration: const InputDecoration(labelText: 'Registered address')),
          ]),
        ),
        const SizedBox(height: 16),
        const SectionTitle('Documents'),
        ...r.documents.map(_docTile),
        const SizedBox(height: 16),
        SectionTitle('Owners with ${r.ownershipThreshold}% or more'),
        MoneyCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add each owner’s Oneova username (including you). Each one confirms and verifies their own identity — you never upload someone else’s ID.',
                style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary)),
            ..._owners.map((o) => Row(children: [
                  Expanded(flex: 3, child: TextField(controller: o.username, decoration: const InputDecoration(labelText: '@username'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: o.share, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '%'))),
                  IconButton(onPressed: () => setState(() => _owners.remove(o)), icon: const Icon(Icons.close_rounded)),
                ])),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(onPressed: () => setState(() => _owners.add(_Owner())), icon: const Icon(Icons.add_rounded), label: const Text('Add owner')),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        CheckboxListTile(
          value: _consent,
          activeColor: AppColors.brandBlue,
          onChanged: (v) => setState(() => _consent = v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(
            'I’m allowed to act for this business. I agree that Oneova’s review team checks these documents (with an AI pre-check that never decides) and deletes them 30 days after the decision.',
            style: TextStyle(fontSize: 12, height: 1.35, color: context.textSecondary),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: _ready && !_busy ? _submit : null,
            style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue, minimumSize: const Size.fromHeight(50)),
            child: Text(_busy ? 'Sending…' : 'Send for review'),
          ),
        ),
      ];

  Widget _docTile(Map<String, dynamic> d) {
    final key = '${d['key']}';
    final done = _uploaded.containsKey(key);
    final busy = _uploading.contains(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MoneyCard(
        onTap: busy ? null : () => _pick(d),
        child: Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.upload_file_rounded, color: done ? AppColors.brandBlue : context.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${d['label']}${d['required'] == true ? '' : ' (optional)'}', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimary)),
              Text('${d['hint']}', style: TextStyle(fontSize: 12, color: context.textSecondary)),
            ]),
          ),
          if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) else Text(done ? 'Replace' : 'Add', style: const TextStyle(color: AppColors.brandBlue, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _status(BusinessIdentity b) {
    final owners = ref.watch(businessOwnersProvider).value ?? const [];
    final (title, body) = switch (b.status) {
      'verified' => (b.level >= 2 ? 'Verified Business' : 'Registered business', 'The badge shows on your profile and your store. Renew by ${b.expiresAt != null ? MaterialLocalizations.of(context).formatMediumDate(b.expiresAt!) : 'next year'}.'),
      'review' => ('Being checked', 'Our team is reviewing your documents — usually within 2 working days.'),
      'expired' => ('Renewal needed', b.rejectReason ?? 'Upload fresh documents to keep the badge.'),
      _ => ('Needs another try', b.rejectReason ?? 'Check the documents and try again.'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MoneyCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (b.verified) OneovaVerifiedBadge(kind: VerifiedKind.business, level: b.level, size: 34) else const Icon(Icons.hourglass_top_rounded, color: AppColors.brandBlue, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: context.textPrimary)),
                Text('${b.legalName} · ${b.country}', style: TextStyle(fontSize: 12, color: context.textSecondary)),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Text(body, style: TextStyle(fontSize: 13, height: 1.4, color: context.textSecondary)),
          if (b.registrationNumber.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Registration ${b.registrationNumber}${b.taxIdLast4.isNotEmpty ? ' · Tax ID •••• ${b.taxIdLast4}' : ''}',
                style: TextStyle(fontSize: 12, color: context.textMuted)),
          ],
          const SizedBox(height: 12),
          if (b.verified)
            FilledButton.icon(
              onPressed: () => IdShareSheet.show(context, kind: 'business'),
              style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue),
              icon: const Icon(Icons.qr_code_2_rounded, size: 18),
              label: const Text('Share proof of business'),
            ),
          if (b.status == 'rejected' || b.status == 'expired')
            FilledButton(
              onPressed: () => setState(() => _restart = true),
              style: FilledButton.styleFrom(foregroundColor: Colors.white, backgroundColor: AppColors.brandBlue),
              child: const Text('Start again'),
            ),
        ]),
      ),
      if (owners.isNotEmpty) ...[
        const SizedBox(height: 16),
        const SectionTitle('Owners'),
        ...owners.map((o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MoneyCard(
                child: Row(children: [
                  Expanded(child: Text('@${o['username']} · ${o['share']}%', style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.w600))),
                  Text(
                    o['status'] != 'confirmed' ? (o['status'] == 'declined' ? 'Declined' : 'Waiting') : (o['idVerified'] == true ? 'Verified' : 'Needs ID check'),
                    style: TextStyle(fontSize: 12, color: o['idVerified'] == true ? AppColors.brandBlue : AppColors.brandPink, fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            )),
      ],
    ]);
  }
}
