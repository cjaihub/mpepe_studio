import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/theme/app_theme.dart';
import '../services/platform_docs_cms_service.dart';

/// Real-Time Admin Studio for editing Oneova's Advanced Feature Documentation,
/// Community Guidelines, Legal Policies, and African/Global Regulations.
/// Every save updates Firestore `platform_cms_docs` immediately, syncing the
/// Oneova mobile app and the live React website (`oneova.app`) in real time.
class AdminDocsCmsScreen extends ConsumerStatefulWidget {
  final String? initialDocId;

  const AdminDocsCmsScreen({super.key, this.initialDocId});

  @override
  ConsumerState<AdminDocsCmsScreen> createState() => _AdminDocsCmsScreenState();
}

class _AdminDocsCmsScreenState extends ConsumerState<AdminDocsCmsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _filter = 'all'; // all | feature | policy | regulation | drafts
  String _query = '';
  bool _isSeeding = false;
  bool _openedInitial = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSeedMissing() async {
    setState(() => _isSeeding = true);
    try {
      final count = await ref.read(platformDocsCmsServiceProvider).seedMissingDefaultsToCloud();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'All baseline docs are already live in Firestore.'
                : 'Synced $count baseline document(s) to live cloud (App + Website).',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sync failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSeeding = false);
    }
  }

  void _openEditor(PlatformCmsDoc? existing) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AdminDocEditorPage(existingDoc: existing),
      ),
    );
  }

  Future<void> _confirmDeleteOrReset(PlatformCmsDoc doc) async {
    final isBuiltIn = OneovaPlatformDocsCatalog.defaults.any((d) => d.id == doc.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: ctx.border, width: 1.0),
        ),
        title: Text(
          isBuiltIn ? 'Reset Live Edits to Baseline?' : 'Delete Custom Document?',
          style: GoogleFonts.inter(
            fontSize: 15.5,
            fontWeight: FontWeight.w700,
            color: ctx.textPrimary,
          ),
        ),
        content: Text(
          isBuiltIn
              ? 'This removes custom cloud overrides for "${doc.title}" and restores the verified baseline text on both the App and Website.'
              : 'This permanently deletes "${doc.title}" from the live App and Website catalog.',
          style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: ctx.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.inter(color: ctx.textSecondary, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPink,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              isBuiltIn ? 'Reset Override' : 'Delete Permanently',
              style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(platformDocsCmsServiceProvider).deleteCloudDoc(doc.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isBuiltIn ? 'Restored baseline for "${doc.title}".' : 'Deleted "${doc.title}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAdminAsync = ref.watch(isPlatformDocsAdminProvider);
    final docsAsync = ref.watch(adminAllPlatformDocsProvider);
    final isAdmin = isAdminAsync.value ?? false;

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/legal');
            }
          },
        ),
        title: Text(
          'Live Docs & Rules CMS',
          style: GoogleFonts.inter(
            fontSize: 17.0,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            color: context.textPrimary,
          ),
        ),
        actions: [
          if (isAdmin)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    onPressed: () => _openEditor(null),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: Text(
                      'New Doc',
                      style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                    ),
                  ),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.border),
        ),
      ),
      body: isAdminAsync.isLoading
          ? const Center(child: CircularProgressIndicator())
          : !isAdmin
              ? _buildAccessRestricted(context)
              : docsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Unable to load CMS stream: $err',
                        style: GoogleFonts.inter(fontSize: 12.5, color: context.textSecondary),
                      ),
                    ),
                  ),
                  data: (allDocs) {
                    if (!_openedInitial && widget.initialDocId != null) {
                      _openedInitial = true;
                      final target = allDocs.where((d) => d.id == widget.initialDocId).firstOrNull;
                      if (target != null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _openEditor(target);
                        });
                      }
                    }

                    final filtered = allDocs.where((d) {
                      if (_filter == 'feature' && d.docType != 'feature') return false;
                      if (_filter == 'policy' && d.docType != 'policy') return false;
                      if (_filter == 'regulation' && d.docType != 'regulation') return false;
                      if (_filter == 'drafts' && d.isPublished) return false;

                      final q = _query.trim().toLowerCase();
                      if (q.isEmpty) return true;
                      return d.title.toLowerCase().contains(q) ||
                          d.category.toLowerCase().contains(q) ||
                          d.inShort.toLowerCase().contains(q) ||
                          d.badge.toLowerCase().contains(q);
                    }).toList();

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 36),
                      children: [
                        _buildSyncBanner(context, allDocs),
                        const SizedBox(height: 10),
                        _buildSearchBar(context),
                        const SizedBox(height: 10),
                        _buildFilterRow(context, allDocs),
                        const SizedBox(height: 12),
                        for (final doc in filtered) ...[
                          _buildDocTile(context, doc),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
    );
  }

  Widget _buildAccessRestricted(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings_rounded, size: 40, color: AppColors.brandPink),
              const SizedBox(height: 10),
              Text(
                'Administrator Access Required',
                style: GoogleFonts.inter(
                  fontSize: 15.0,
                  fontWeight: FontWeight.w700,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Only verified Oneova accounts with role "admin", "owner", or "founder" may edit live platform documentation, rules, and legal policies.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  height: 1.4,
                  color: context.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38,
                child: ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text('Back to Rules & Docs', style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncBanner(BuildContext context, List<PlatformCmsDoc> allDocs) {
    final liveCount = allDocs.where((d) => d.isLiveFromCloud).length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.brandBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: const Icon(Icons.sync_rounded, size: 18, color: AppColors.brandBlue),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Real-Time App ↔ React Website Sync',
                  style: GoogleFonts.inter(
                    fontSize: 13.0,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                Text(
                  '$liveCount / ${allDocs.length} docs materialized in cloud · Edits publish live with revision history.',
                  style: GoogleFonts.inter(
                    fontSize: 11.0,
                    color: context.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: OutlinedButton(
              onPressed: _isSeeding ? null : _handleSeedMissing,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.brandBlue.withValues(alpha: 0.5), width: 1.0),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              child: Text(
                _isSeeding ? 'Syncing...' : 'Sync Cloud',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brandBlue,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.border, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 17, color: context.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'Filter features, rules, policies, or regulations...',
                hintStyle: GoogleFonts.inter(fontSize: 12.0, color: context.textMuted),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
              child: Icon(Icons.close_rounded, size: 16, color: context.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(BuildContext context, List<PlatformCmsDoc> docs) {
    final chips = <(String, String)>[
      ('all', 'All (${docs.length})'),
      ('feature', 'Features (${docs.where((d) => d.docType == 'feature').length})'),
      ('policy', 'Policies (${docs.where((d) => d.docType == 'policy').length})'),
      ('regulation', 'Regulations (${docs.where((d) => d.docType == 'regulation').length})'),
      ('drafts', 'Drafts (${docs.where((d) => !d.isPublished).length})'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in chips)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () => setState(() => _filter = item.$1),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _filter == item.$1 ? AppColors.brandBlue : context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(
                      color: _filter == item.$1 ? AppColors.brandBlue : context.border,
                      width: 1.0,
                    ),
                  ),
                  child: Text(
                    item.$2,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _filter == item.$1 ? Colors.white : context.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDocTile(BuildContext context, PlatformCmsDoc doc) {
    final accent = doc.isAccentBadge ? AppColors.brandPink : AppColors.brandBlue;
    return Container(
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _openEditor(doc),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _microPill(doc.docType.toUpperCase(), AppColors.brandBlue),
                        _microPill(doc.badge, accent),
                        _microPill(doc.version, context.textSecondary),
                        if (!doc.isPublished) _microPill('DRAFT', AppColors.brandPink),
                        if (doc.isLiveFromCloud) _microPill('CLOUD LIVE', AppColors.brandBlue),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      doc.title,
                      style: GoogleFonts.inter(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      doc.inShort,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        height: 1.35,
                        color: context.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${doc.category} · ${doc.sections.length} section(s) · ID: ${doc.id}',
                      style: GoogleFonts.inter(fontSize: 10.5, color: context.textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_note_rounded, size: 20, color: AppColors.brandBlue),
                    tooltip: 'Edit Live',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openEditor(doc),
                  ),
                  if (doc.isLiveFromCloud)
                    IconButton(
                      icon: Icon(Icons.restore_rounded, size: 18, color: context.textMuted),
                      tooltip: 'Reset / Delete',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmDeleteOrReset(doc),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _microPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9.0,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: color,
        ),
      ),
    );
  }
}

/// Full-featured Editor + Live Preview + Revision History Rollback screen.
class _AdminDocEditorPage extends ConsumerStatefulWidget {
  final PlatformCmsDoc? existingDoc;

  const _AdminDocEditorPage({this.existingDoc});

  @override
  ConsumerState<_AdminDocEditorPage> createState() => _AdminDocEditorPageState();
}

class _AdminDocEditorPageState extends ConsumerState<_AdminDocEditorPage> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _titleCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _badgeCtrl;
  late final TextEditingController _versionCtrl;
  late final TextEditingController _effectiveDateCtrl;
  late final TextEditingController _readTimeCtrl;
  late final TextEditingController _orderCtrl;
  late final TextEditingController _inShortCtrl;
  late final TextEditingController _changeNoteCtrl;

  late String _docType;
  late String _policyTab;
  late bool _isAccentBadge;
  late bool _isPublished;
  late List<_EditableSectionControllers> _sectionCtrls;

  bool _previewMode = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final d = widget.existingDoc;
    _idCtrl = TextEditingController(text: d?.id ?? '');
    _titleCtrl = TextEditingController(text: d?.title ?? '');
    _categoryCtrl = TextEditingController(text: d?.category ?? 'Live & Broadcasting');
    _badgeCtrl = TextEditingController(text: d?.badge ?? 'OFFICIAL');
    _versionCtrl = TextEditingController(text: d?.version ?? 'v1.0');
    _effectiveDateCtrl = TextEditingController(text: d?.effectiveDate ?? 'October 25, 2026');
    _readTimeCtrl = TextEditingController(text: d?.readTime ?? '4 min read');
    _orderCtrl = TextEditingController(text: '${d?.order ?? 20}');
    _inShortCtrl = TextEditingController(text: d?.inShort ?? '');
    _changeNoteCtrl = TextEditingController();

    _docType = d?.docType ?? 'feature';
    _policyTab = d?.policyTab ?? '';
    _isAccentBadge = d?.isAccentBadge ?? false;
    _isPublished = d?.isPublished ?? true;

    final initialSections = (d?.sections.isNotEmpty == true)
        ? d!.sections
        : const [PlatformDocSection(heading: '1. Overview', bullets: ['Key capability or rule'])];

    _sectionCtrls = initialSections.map(_EditableSectionControllers.fromSection).toList();
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    _badgeCtrl.dispose();
    _versionCtrl.dispose();
    _effectiveDateCtrl.dispose();
    _readTimeCtrl.dispose();
    _orderCtrl.dispose();
    _inShortCtrl.dispose();
    _changeNoteCtrl.dispose();
    for (final s in _sectionCtrls) {
      s.dispose();
    }
    super.dispose();
  }

  void _bumpMinorVersion() {
    final cur = _versionCtrl.text.trim();
    final match = RegExp(r'^v?(\d+)\.(\d+)$').firstMatch(cur);
    if (match != null) {
      final major = int.parse(match.group(1)!);
      final minor = int.parse(match.group(2)!) + 1;
      setState(() => _versionCtrl.text = 'v$major.$minor');
    } else {
      setState(() => _versionCtrl.text = 'v1.1');
    }
  }

  PlatformCmsDoc _assembleDoc() {
    final rawId = widget.existingDoc?.id ??
        _idCtrl.text
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9\-_]'), '-')
            .replaceAll(RegExp(r'-+'), '-');

    return PlatformCmsDoc(
      id: rawId,
      docType: _docType,
      category: _categoryCtrl.text.trim().isEmpty ? 'General' : _categoryCtrl.text.trim(),
      policyTab: _policyTab,
      title: _titleCtrl.text.trim(),
      badge: _badgeCtrl.text.trim().isEmpty ? 'OFFICIAL' : _badgeCtrl.text.trim(),
      isAccentBadge: _isAccentBadge,
      inShort: _inShortCtrl.text.trim(),
      readTime: _readTimeCtrl.text.trim().isEmpty ? '4 min read' : _readTimeCtrl.text.trim(),
      version: _versionCtrl.text.trim().isEmpty ? 'v1.0' : _versionCtrl.text.trim(),
      effectiveDate: _effectiveDateCtrl.text.trim(),
      order: int.tryParse(_orderCtrl.text.trim()) ?? 20,
      isPublished: _isPublished,
      sections: _sectionCtrls.map((c) => c.toSection()).toList(),
      htmlOverride: widget.existingDoc?.htmlOverride ?? '',
    );
  }

  Future<void> _saveLive() async {
    final assembled = _assembleDoc();
    if (assembled.id.isEmpty || assembled.title.isEmpty || assembled.inShort.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document ID, Title, and "In Short" summary are required.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(platformDocsCmsServiceProvider).saveDoc(
            assembled,
            changeNote: _changeNoteCtrl.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Published "${assembled.title}" (${assembled.version}) live to App & Website!'),
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openRevisionHistorySheet(String docId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (sheetCtx) {
        return Consumer(
          builder: (ctx, sheetRef, _) {
            final stream = sheetRef.watch(platformDocsCmsServiceProvider).watchRevisions(docId);
            return StreamBuilder<List<PlatformDocRevision>>(
              stream: stream,
              builder: (context, snap) {
                final revs = snap.data ?? const <PlatformDocRevision>[];
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Immutable Revision Audit History',
                        style: GoogleFonts.inter(
                          fontSize: 15.0,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Select any prior revision to restore it live across App & Website.',
                        style: GoogleFonts.inter(fontSize: 11.5, color: context.textMuted),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: revs.isEmpty
                            ? Center(
                                child: Text(
                                  'No cloud revisions recorded yet for this document.',
                                  style: GoogleFonts.inter(fontSize: 12.5, color: context.textMuted),
                                ),
                              )
                            : ListView.separated(
                                itemCount: revs.length,
                                separatorBuilder: (_, _) => Divider(height: 1, color: context.border),
                                itemBuilder: (_, idx) {
                                  final r = revs[idx];
                                  final dateStr = r.createdAt != null
                                      ? '${r.createdAt!.year}-${r.createdAt!.month.toString().padLeft(2, '0')}-${r.createdAt!.day.toString().padLeft(2, '0')} ${r.createdAt!.hour.toString().padLeft(2, '0')}:${r.createdAt!.minute.toString().padLeft(2, '0')}'
                                      : 'Just now';
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    title: Text(
                                      '${r.version} · ${r.changeNote.isEmpty ? "Update" : r.changeNote}',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimary,
                                      ),
                                    ),
                                    subtitle: Text(
                                      'By ${r.actorName} · $dateStr',
                                      style: GoogleFonts.inter(fontSize: 11.0, color: context.textMuted),
                                    ),
                                    trailing: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(color: context.border),
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (dCtx) => AlertDialog(
                                            backgroundColor: dCtx.surface,
                                            title: Text(
                                              'Restore ${r.version}?',
                                              style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: dCtx.textPrimary),
                                            ),
                                            content: Text(
                                              'This publishes the ${r.version} snapshot live to both the Oneova App and React Website.',
                                              style: GoogleFonts.inter(fontSize: 12.5, color: dCtx.textSecondary),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.of(dCtx).pop(false),
                                                child: const Text('Cancel'),
                                              ),
                                              ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: AppColors.brandBlue,
                                                  foregroundColor: Colors.white,
                                                ),
                                                onPressed: () => Navigator.of(dCtx).pop(true),
                                                child: const Text('Restore Live'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await sheetRef.read(platformDocsCmsServiceProvider).rollbackToRevision(docId, r);
                                          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                                          if (mounted) Navigator.of(this.context).pop();
                                        }
                                      },
                                      child: Text(
                                        'Restore',
                                        style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existingDoc == null;
    final previewDoc = _assembleDoc();

    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, size: 20, color: context.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isNew ? 'Create Live Document' : 'Edit Live Document',
          style: GoogleFonts.inter(
            fontSize: 16.5,
            fontWeight: FontWeight.w700,
            color: context.textPrimary,
          ),
        ),
        actions: [
          if (!isNew)
            IconButton(
              icon: Icon(Icons.history_rounded, size: 20, color: context.textSecondary),
              tooltip: 'Revision History',
              onPressed: () => _openRevisionHistorySheet(widget.existingDoc!.id),
            ),
          TextButton(
            onPressed: () => setState(() => _previewMode = !_previewMode),
            child: Text(
              _previewMode ? 'Edit' : 'Preview',
              style: GoogleFonts.inter(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandBlue,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(
              child: SizedBox(
                height: 34,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveLive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text(
                    _saving ? 'Saving...' : 'Publish Live',
                    style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.border),
        ),
      ),
      body: _previewMode ? _buildLivePreview(context, previewDoc) : _buildEditorForm(context, isNew),
    );
  }

  Widget _buildEditorForm(BuildContext context, bool isNew) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
      children: [
        if (isNew) ...[
          _labeledField(context, 'Unique Document Slug ID (e.g. feature-audio-studio)', _idCtrl),
          const SizedBox(height: 10),
        ],
        _labeledField(context, 'Document Title', _titleCtrl),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dropdownField(
                context,
                label: 'Document Track',
                value: _docType,
                items: const [
                  DropdownMenuItem(value: 'feature', child: Text('Platform Feature Doc')),
                  DropdownMenuItem(value: 'policy', child: Text('User Rule / Policy')),
                  DropdownMenuItem(value: 'regulation', child: Text('Legal / Regulation')),
                ],
                onChanged: (v) => setState(() => _docType = v ?? 'feature'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dropdownField(
                context,
                label: 'Policy Tab Mapping',
                value: _policyTab,
                items: const [
                  DropdownMenuItem(value: '', child: Text('None (Feature Doc)')),
                  DropdownMenuItem(value: 'guidelines', child: Text('Community Guidelines')),
                  DropdownMenuItem(value: 'terms', child: Text('Terms of Service')),
                  DropdownMenuItem(value: 'privacy', child: Text('Privacy Policy')),
                  DropdownMenuItem(value: 'safety', child: Text('Child & Teen Safety')),
                  DropdownMenuItem(value: 'biz', child: Text('Biz & Monetization')),
                  DropdownMenuItem(value: 'deletion', child: Text('Data Deletion')),
                  DropdownMenuItem(value: 'law_enforcement', child: Text('Law Enforcement')),
                  DropdownMenuItem(value: 'africa', child: Text('Africa & Global Law')),
                ],
                onChanged: (v) => setState(() => _policyTab = v ?? ''),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _labeledField(context, 'Category Name', _categoryCtrl)),
            const SizedBox(width: 10),
            Expanded(child: _labeledField(context, 'Badge Tag (e.g. 4K LIVE)', _badgeCtrl)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _labeledField(context, 'Version', _versionCtrl)),
            const SizedBox(width: 6),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                height: 38,
                child: OutlinedButton(
                  onPressed: _bumpMinorVersion,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.border),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                  ),
                  child: Text('+0.1', style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _labeledField(context, 'Effective Date', _effectiveDateCtrl)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _labeledField(context, 'Read Time', _readTimeCtrl)),
            const SizedBox(width: 10),
            Expanded(child: _labeledField(context, 'Sort Order (1–99)', _orderCtrl)),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Switch.adaptive(
                      value: _isPublished,
                      activeThumbColor: AppColors.brandBlue,
                      onChanged: (v) => setState(() => _isPublished = v),
                    ),
                    Text(
                      _isPublished ? 'Published Live' : 'Draft Only',
                      style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Switch.adaptive(
                      value: _isAccentBadge,
                      activeThumbColor: AppColors.brandPink,
                      onChanged: (v) => setState(() => _isAccentBadge = v),
                    ),
                    Text(
                      'Pink Accent Badge',
                      style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _labeledField(
          context,
          'Executive Summary ("In Short" — shown at top of App & Website)',
          _inShortCtrl,
          maxLines: 3,
        ),
        const SizedBox(height: 10),
        _labeledField(
          context,
          'Revision Change Note (Audit Trail)',
          _changeNoteCtrl,
          hint: 'e.g. Added Tanzania PDPC registration update',
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'STRUCTURED SECTIONS (${_sectionCtrls.length})',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: AppColors.brandBlue,
              ),
            ),
            SizedBox(
              height: 32,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _sectionCtrls.add(
                      _EditableSectionControllers.fromSection(
                        PlatformDocSection(
                          heading: '${_sectionCtrls.length + 1}. New Section',
                          bullets: const ['Add point here'],
                        ),
                      ),
                    );
                  });
                },
                icon: const Icon(Icons.add_rounded, size: 15, color: AppColors.brandBlue),
                label: Text(
                  'Add Section',
                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.brandBlue),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _sectionCtrls.length; i++) ...[
          _buildSectionEditorCard(context, i),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSectionEditorCard(BuildContext context, int index) {
    final s = _sectionCtrls[index];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'SECTION ${index + 1}',
                style: GoogleFonts.inter(
                  fontSize: 10.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppColors.brandPink,
                ),
              ),
              const Spacer(),
              if (index > 0)
                IconButton(
                  icon: Icon(Icons.arrow_upward_rounded, size: 16, color: context.textSecondary),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      final item = _sectionCtrls.removeAt(index);
                      _sectionCtrls.insert(index - 1, item);
                    });
                  },
                ),
              if (index < _sectionCtrls.length - 1)
                IconButton(
                  icon: Icon(Icons.arrow_downward_rounded, size: 16, color: context.textSecondary),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    setState(() {
                      final item = _sectionCtrls.removeAt(index);
                      _sectionCtrls.insert(index + 1, item);
                    });
                  },
                ),
              if (_sectionCtrls.length > 1)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 17, color: AppColors.brandPink),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: ctx.surface,
                        title: Text('Remove Section ${index + 1}?', style: GoogleFonts.inter(fontSize: 14.5, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                        content: Text('Are you sure you want to remove this section from the document?', style: GoogleFonts.inter(fontSize: 12.5, color: ctx.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brandPink, foregroundColor: Colors.white),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      setState(() {
                        final removed = _sectionCtrls.removeAt(index);
                        removed.dispose();
                      });
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          _labeledField(context, 'Section Heading', s.headingCtrl),
          const SizedBox(height: 8),
          _labeledField(context, 'Intro Paragraph (Optional)', s.summaryCtrl, maxLines: 2),
          const SizedBox(height: 8),
          _labeledField(context, 'Highlighted Callout Note (Optional)', s.calloutCtrl, maxLines: 2),
          const SizedBox(height: 8),
          _labeledField(
            context,
            'Bullet Points (One bullet per line)',
            s.bulletsCtrl,
            maxLines: 5,
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreview(BuildContext context, PlatformCmsDoc doc) {
    final accent = doc.isAccentBadge ? AppColors.brandPink : AppColors.brandBlue;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.xs),
                    ),
                    child: Text(
                      doc.badge,
                      style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: accent),
                    ),
                  ),
                  Text(
                    '${doc.version} · ${doc.effectiveDate} · ${doc.readTime}',
                    style: GoogleFonts.inter(fontSize: 11.0, color: context.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                doc.title,
                style: GoogleFonts.inter(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.surfaceMid,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border, width: 1.0),
                ),
                child: Text(
                  'In short: ${doc.inShort}',
                  style: GoogleFonts.inter(fontSize: 12.5, height: 1.38, color: context.textPrimary),
                ),
              ),
              const SizedBox(height: 14),
              for (final sec in doc.sections) ...[
                Text(
                  sec.heading,
                  style: GoogleFonts.inter(
                    fontSize: 14.0,
                    fontWeight: FontWeight.w700,
                    color: context.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                if (sec.summary.isNotEmpty) ...[
                  Text(
                    sec.summary,
                    style: GoogleFonts.inter(fontSize: 12.5, height: 1.4, color: context.textSecondary),
                  ),
                  const SizedBox(height: 6),
                ],
                if (sec.callout.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(9),
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brandPink.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppColors.brandPink.withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      sec.callout,
                      style: GoogleFonts.inter(fontSize: 12.0, fontWeight: FontWeight.w600, color: context.textPrimary),
                    ),
                  ),
                ],
                for (final b in sec.bullets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Icon(Icons.circle, size: 5, color: AppColors.brandBlue),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b,
                            style: GoogleFonts.inter(fontSize: 12.5, height: 1.38, color: context.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _labeledField(
    BuildContext context,
    String label,
    TextEditingController ctrl, {
    int maxLines = 1,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: GoogleFonts.inter(fontSize: 12.0, color: context.textMuted),
            filled: true,
            fillColor: context.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: BorderSide(color: context.border, width: 1.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              borderSide: const BorderSide(color: AppColors.brandBlue, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dropdownField(
    BuildContext context, {
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 11.0,
            fontWeight: FontWeight.w600,
            color: context.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: context.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: context.border, width: 1.0),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              items: items,
              onChanged: onChanged,
              isExpanded: true,
              isDense: true,
              dropdownColor: context.surface,
              style: GoogleFonts.inter(fontSize: 12.5, color: context.textPrimary),
            ),
          ),
        ),
      ],
    );
  }
}

class _EditableSectionControllers {
  final TextEditingController headingCtrl;
  final TextEditingController summaryCtrl;
  final TextEditingController calloutCtrl;
  final TextEditingController bulletsCtrl;

  _EditableSectionControllers({
    required this.headingCtrl,
    required this.summaryCtrl,
    required this.calloutCtrl,
    required this.bulletsCtrl,
  });

  factory _EditableSectionControllers.fromSection(PlatformDocSection s) {
    return _EditableSectionControllers(
      headingCtrl: TextEditingController(text: s.heading),
      summaryCtrl: TextEditingController(text: s.summary),
      calloutCtrl: TextEditingController(text: s.callout),
      bulletsCtrl: TextEditingController(text: s.bullets.join('\n')),
    );
  }

  PlatformDocSection toSection() {
    return PlatformDocSection(
      heading: headingCtrl.text.trim(),
      summary: summaryCtrl.text.trim(),
      callout: calloutCtrl.text.trim(),
      bullets: bulletsCtrl.text
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList(),
    );
  }

  void dispose() {
    headingCtrl.dispose();
    summaryCtrl.dispose();
    calloutCtrl.dispose();
    bulletsCtrl.dispose();
  }
}
