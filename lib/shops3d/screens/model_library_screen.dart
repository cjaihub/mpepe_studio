import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/theme/app_theme.dart';
import '../data/model3d_repository.dart';
import '../data/product_photo.dart';
import '../models/shop_models.dart';
import '../widgets/product_3d_viewer.dart';
import '../widgets/stage_style.dart';

/// `/shops/models` — the seller's private 3D model library.
///
/// Upload a 3D file or build one from photos; every model is optimized for
/// phones, tablets and AR on Oneova's servers and stays private until it is
/// put on a product. With [pickForProductId] the screen is a picker: choosing
/// a ready model puts it on that product and returns its [PublishedModel].
class ModelLibraryScreen extends ConsumerStatefulWidget {
  const ModelLibraryScreen({super.key, this.pickForProductId});
  final String? pickForProductId;

  @override
  ConsumerState<ModelLibraryScreen> createState() => _ModelLibraryScreenState();
}

class _ModelLibraryScreenState extends ConsumerState<ModelLibraryScreen> {
  double? _upload;
  String _uploadLabel = '';
  bool _attaching = false;

  Model3DRepository get _repo => ref.read(model3dRepositoryProvider);

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _uploadFile() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null) return;
    setState(() {
      _upload = 0;
      _uploadLabel = 'Uploading your 3D file';
    });
    try {
      await _repo.addFile(File(path), productId: widget.pickForProductId, onProgress: (v) {
        if (mounted) setState(() => _upload = v);
      });
      _toast('Uploaded. Optimizing it now; you can leave this screen.');
    } on StateError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("The file didn't upload. Check your connection.");
    } finally {
      if (mounted) setState(() => _upload = null);
    }
  }

  Future<void> _fromPhotos() async {
    final photos = await showModelPhotoSheet(context);
    if (photos == null || photos.isEmpty || !mounted) return;
    setState(() {
      _upload = 0;
      _uploadLabel = 'Sending your photos';
    });
    try {
      final r = await _repo.generateFromPhotos(photos, name: 'Product model', productId: widget.pickForProductId, onProgress: (v) {
        if (mounted) setState(() => _upload = v);
      });
      _toast(r.started
          ? 'Building your 3D model. We’ll notify you when it’s ready.'
          : 'Photos saved. Link a 3D provider below to build the model.');
    } on StateError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast("The photos didn't upload. Check your connection.");
    } finally {
      if (mounted) setState(() => _upload = null);
    }
  }

  Future<void> _use(Model3DAsset m) async {
    final productId = widget.pickForProductId;
    if (productId == null || _attaching) return;
    setState(() => _attaching = true);
    try {
      final published = await _repo.attach(m.id, productId);
      if (mounted) context.pop(published);
    } on StateError catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _attaching = false);
    }
  }

  Future<void> _delete(Model3DAsset m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this model?'),
        content: Text('“${m.name}” and its files are removed from your library. Products already using it keep their copy.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: AppColors.brandPink))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.delete(m.id);
    } on StateError catch (e) {
      _toast(e.message);
    }
  }

  void _open(Model3DAsset m) {
    HapticFeedback.lightImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheet) => _ModelSheet(
        modelId: m.id,
        picking: widget.pickForProductId != null,
        onUse: () {
          Navigator.pop(sheet);
          _use(m);
        },
        onDelete: () {
          Navigator.pop(sheet);
          _delete(m);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(modelLibraryProvider);
    final providers = ref.watch(modelProvidersProvider).value ?? const [];
    final picking = widget.pickForProductId != null;
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.textPrimary),
          onPressed: () => context.canPop() ? context.pop() : context.go('/business'),
        ),
        title: Text(picking ? 'Choose a 3D model' : 'My 3D models', style: AppTypography.pageTitle(context.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Row(children: [
            Icon(Icons.lock_outline_rounded, size: 13, color: context.textMuted),
            const SizedBox(width: 5),
            Expanded(
              child: Text('Private to you. A model is shown to buyers only on products you put it on.',
                  style: AppTypography.caption(context.textSecondary)),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _Action(icon: Icons.photo_camera_outlined, label: 'From photos', hint: 'Ova builds the 3D', onTap: _upload == null ? _fromPhotos : null)),
            const SizedBox(width: 8),
            Expanded(child: _Action(icon: Icons.upload_file_rounded, label: 'Upload a file', hint: 'GLB · GLTF · OBJ · STL', onTap: _upload == null ? _uploadFile : null)),
          ]),
          if (_upload != null) ...[
            const SizedBox(height: 10),
            Text(_uploadLabel, style: AppTypography.small(context.textPrimary)),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: _upload! > 0 ? _upload : null, minHeight: 3, color: AppColors.brandBlue, backgroundColor: context.surfaceMid),
          ],
          const SizedBox(height: 12),
          _ProviderTile(links: providers),
          const SizedBox(height: 16),
          models.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2)),
            ),
            error: (_, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text("Couldn't load your models. Check your connection.", textAlign: TextAlign.center, style: AppTypography.body(context.textSecondary)),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 36),
                    child: Column(children: [
                      Icon(Icons.view_in_ar_rounded, size: 32, color: context.textMuted),
                      const SizedBox(height: 8),
                      Text('No models yet', style: AppTypography.title3(context.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Take four photos of a product or upload a 3D file to start.',
                          textAlign: TextAlign.center, style: AppTypography.body(context.textSecondary)),
                    ]),
                  )
                : Column(children: [for (final m in list) _ModelRow(model: m, onTap: () => _open(m))]),
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.hint, this.onTap});
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: AppDecorations.card(context),
        child: Row(children: [
          Icon(icon, size: 20, color: onTap == null ? context.textMuted : AppColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppTypography.callout(context.textPrimary)),
              Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textSecondary)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.model, required this.onTap});
  final Model3DAsset model;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final m = model;
    final failed = m.status == ModelStatus.failed;
    final line = switch (m.status) {
      ModelStatus.ready => [
          if (m.mobileTriangles > 0) '${_k(m.mobileTriangles)} triangles',
          if (m.mobileBytes > 0) '${formatBytes(m.mobileBytes)} on phones',
          if (m.animations.isNotEmpty) '${m.animations.length} animations',
        ].join(' · '),
      _ => m.stage,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: AppDecorations.card(context),
          child: Row(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 48,
                height: 48,
                child: (m.thumbUrl ?? '').startsWith('https://')
                    ? Image.network(m.thumbUrl!, fit: BoxFit.cover, cacheWidth: 150, errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid))
                    : ColoredBox(
                        color: context.surfaceMid,
                        child: Icon(Icons.view_in_ar_rounded, size: 20, color: m.ready ? AppColors.brandBlue : context.textMuted),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.sectionTitle(context.textPrimary)),
                const SizedBox(height: 2),
                Text(line.isEmpty ? 'Ready' : line,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption(failed ? AppColors.brandPink : context.textSecondary)),
                if (m.status.working) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(value: m.progress > 0 ? m.progress : null, minHeight: 2, color: AppColors.brandBlue, backgroundColor: context.surfaceMid),
                ],
              ]),
            ),
            const SizedBox(width: 6),
            if (m.ready)
              const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.brandBlue)
            else if (m.status == ModelStatus.needsEngine)
              Icon(Icons.link_rounded, size: 16, color: context.textMuted)
            else if (failed)
              const Icon(Icons.error_outline_rounded, size: 16, color: AppColors.brandPink),
          ]),
        ),
      ),
    );
  }

  static String _k(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';
}

/// One model: live 3D preview, what the optimizer did, and its actions.
class _ModelSheet extends ConsumerWidget {
  const _ModelSheet({required this.modelId, required this.picking, required this.onUse, required this.onDelete});
  final String modelId;
  final bool picking;
  final VoidCallback onUse;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(model3dProvider(modelId)).value;
    if (m == null) return const SizedBox(height: 120);
    final style = StageStyle.of(context, const StageConfig());
    final saved = m.sourceBytes > 0 && m.mobileBytes > 0 ? (100 - m.mobileBytes * 100 / m.sourceBytes).round() : 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(m.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.title3(context.textPrimary)),
          const SizedBox(height: 10),
          if (m.ready)
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: SizedBox(
                height: 240,
                child: Stack(fit: StackFit.expand, children: [
                  StageBackdropLayer(style: style),
                  Product3DViewer(
                    product: ShopProduct(id: m.id, ownerId: '', name: m.name, imageUrl: m.thumbUrl ?? '', model3dUrl: m.mobileUrl, model3dHdUrl: m.hdUrl),
                    style: style,
                    interactive: true,
                  ),
                ]),
              ),
            )
          else ...[
            Text(m.stage, style: AppTypography.body(m.status == ModelStatus.failed ? AppColors.brandPink : context.textSecondary)),
            if (m.status.working) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(value: m.progress > 0 ? m.progress : null, minHeight: 3, color: AppColors.brandBlue, backgroundColor: context.surfaceMid),
            ],
            const SizedBox(height: 8),
            for (final s in m.steps.reversed.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('· ${s.text}', style: AppTypography.caption(context.textSecondary)),
              ),
          ],
          if (m.ready) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              if (m.triangles > 0) _Chip('${m.triangles} → ${m.mobileTriangles} triangles'),
              if (saved > 0) _Chip('$saved% lighter on phones'),
              _Chip('Phone · tablet · AR files'),
              if (m.materials.isNotEmpty) _Chip('${m.materials.length} materials'),
              if (m.animations.isNotEmpty) _Chip('${m.animations.length} animations'),
            ]),
          ],
          const SizedBox(height: 12),
          Row(children: [
            if (m.status == ModelStatus.needsEngine || (m.status == ModelStatus.failed && m.kind == 'generate'))
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size(0, 40)),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    Navigator.pop(context);
                    try {
                      await ref.read(model3dRepositoryProvider).resume(m.id);
                    } on StateError catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  },
                  child: Text(m.status == ModelStatus.failed ? 'Try again' : 'Build now'),
                ),
              ),
            if (m.ready && picking)
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size(0, 40)),
                  onPressed: onUse,
                  child: const Text('Use on this product'),
                ),
              ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: context.textSecondary, side: BorderSide(color: context.border), minimumSize: const Size(0, 40)),
              onPressed: m.status.working ? null : onDelete,
              child: const Text('Delete'),
            ),
          ]),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: context.surfaceMid, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Text(label, style: AppTypography.caption(context.textSecondary)),
      );
}

/// The seller's own 3D provider account: link, or unlink (with confirmation).
class _ProviderTile extends ConsumerWidget {
  const _ProviderTile({required this.links});
  final List<ModelProviderLink> links;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = links.isEmpty ? null : links.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: AppDecorations.card(context),
      child: Row(children: [
        Icon(Icons.hub_outlined, size: 20, color: link == null ? context.textMuted : AppColors.brandBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(link == null ? '3D provider' : '${link.label} linked', style: AppTypography.callout(context.textPrimary)),
            Text(
              link == null
                  ? 'Link your own account to build models from photos with your credits.'
                  : 'Key ending ${link.keyEnd} · used for your photo → 3D builds',
              style: AppTypography.caption(context.textSecondary),
            ),
          ]),
        ),
        TextButton(
          onPressed: () => link == null ? _link(context, ref) : _unlink(context, ref, link),
          child: Text(link == null ? 'Link' : 'Unlink'),
        ),
      ]),
    );
  }

  Future<void> _unlink(BuildContext context, WidgetRef ref, ModelProviderLink link) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Unlink ${link.label}?'),
        content: const Text('Models being built with this account will stop. Your finished models stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Unlink', style: TextStyle(color: AppColors.brandPink))),
        ],
      ),
    );
    if (ok == true) await ref.read(model3dRepositoryProvider).unlinkProvider(link.engine);
  }

  Future<void> _link(BuildContext context, WidgetRef ref) {
    final key = TextEditingController();
    var busy = false;
    String? error;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, set) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Link your Meshy account', style: AppTypography.title3(sheet.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Paste an API key from your Meshy account. Oneova checks it, encrypts it and keeps it on the server; it is never shown again or sent to another phone.',
              style: AppTypography.caption(sheet.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: key,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                isDense: true,
                labelText: 'API key',
                errorText: error,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size(0, 40)),
              onPressed: busy
                  ? null
                  : () async {
                      set(() {
                        busy = true;
                        error = null;
                      });
                      try {
                        await ref.read(model3dRepositoryProvider).linkProvider('meshy', key.text);
                        if (sheet.mounted) Navigator.pop(sheet);
                      } on StateError catch (e) {
                        set(() {
                          busy = false;
                          error = e.message;
                        });
                      }
                    },
              child: busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Check and link'),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Guided photos for photo → 3D ──────────────────────────────────────────

const _angles = [
  ('Front', Icons.crop_portrait_rounded),
  ('Right side', Icons.rotate_right_rounded),
  ('Back', Icons.flip_camera_android_outlined),
  ('Left side', Icons.rotate_left_rounded),
];

/// Asks for up to four angles of one product (front is required). Each photo
/// has its background removed on the phone. Returns the cleaned files, front
/// first, or null when cancelled.
Future<List<File>?> showModelPhotoSheet(BuildContext context, {File? front}) {
  return showModalBottomSheet<List<File>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => _PhotoSheet(front: front),
  );
}

class _PhotoSheet extends StatefulWidget {
  const _PhotoSheet({this.front});
  final File? front;

  @override
  State<_PhotoSheet> createState() => _PhotoSheetState();
}

class _PhotoSheetState extends State<_PhotoSheet> {
  late final List<File?> _shots = [widget.front, null, null, null];
  int? _busy;

  Future<void> _take(int i, ImageSource source) async {
    final x = await ImagePicker().pickImage(source: source, imageQuality: 92, maxWidth: 2600);
    if (x == null || !mounted) return;
    setState(() => _busy = i);
    final r = await ProductPhoto.prepare(File(x.path));
    if (!mounted) return;
    setState(() {
      _shots[i] = r.file;
      _busy = null;
    });
  }

  void _pick(int i) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () {
              Navigator.pop(s);
              _take(i, ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () {
              Navigator.pop(s);
              _take(i, ImageSource.gallery);
            },
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _shots.whereType<File>().length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Photos for the 3D model', style: AppTypography.title3(context.textPrimary)),
          const SizedBox(height: 2),
          Text(
            'One photo works. All four sides keep the shape and the real texture of every side. Same distance, even light, plain surface.',
            style: AppTypography.caption(context.textSecondary),
          ),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < 4; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: _busy == null ? () => _pick(i) : null,
                  child: Column(children: [
                    AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          color: context.surfaceMid,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: _shots[i] != null ? AppColors.brandBlue : context.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _busy == i
                            ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.brandBlue)))
                            : _shots[i] != null
                                ? Image.file(_shots[i]!, fit: BoxFit.cover, cacheWidth: 300)
                                : Icon(_angles[i].$2, color: i == 0 ? AppColors.brandBlue : context.textMuted),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_angles[i].$1, style: AppTypography.caption(context.textSecondary)),
                  ]),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size(0, 40)),
            onPressed: _shots[0] == null || _busy != null ? null : () => Navigator.pop(context, _shots.whereType<File>().toList()),
            child: Text(_shots[0] == null ? 'Add the front photo' : 'Build 3D from $count photo${count == 1 ? '' : 's'}'),
          ),
        ]),
      ),
    );
  }
}
