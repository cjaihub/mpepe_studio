import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/theme/app_theme.dart';
import '../data/currencies.dart';
import '../data/model3d_repository.dart' show PublishedModel;
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/customization_editor.dart';
import '../widgets/product_3d_viewer.dart';
import '../widgets/texture_picker.dart';
import '../widgets/stage_style.dart';

/// `/shops/product/edit?id=` — create or edit a product for the 3D shop:
/// photos, a 3D model from the private library, price in any world currency,
/// stock and options. New products start in the page-by-page creator
/// (`/shops/product/new`); this is the full editor.
class ProductEditorScreen extends ConsumerStatefulWidget {
  const ProductEditorScreen({super.key, this.productId});
  final String? productId;

  @override
  ConsumerState<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends ConsumerState<ProductEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _compare = TextEditingController();
  final _stock = TextEditingController();
  final _category = TextEditingController();

  late final String _id;
  late final bool _isNew;
  bool _loaded = false;
  bool _saving = false;
  String _currency = deviceCurrency();
  String? _modelHd;
  String? _modelAr;
  List<String> _modelAnimations = [];
  bool _active = true;
  List<String> _images = [];
  String? _model;
  List<ProductVariant> _variants = [];
  List<String> _modelVariants = [];
  List<ProductOption> _custom = [];
  List<ProductTexture> _textures = [];
  List<String> _materials = [];
  double? _uploadProgress;
  String? _uploadLabel;

  Shop3DRepository get _repo => ref.read(shop3dRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _isNew = widget.productId == null;
    _id = widget.productId ?? _repo.newProductId();
    if (_isNew) {
      _loaded = true;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final p = await _repo.watchProduct(_id).first;
      if (!mounted) return;
      if (p == null || p.ownerId != _repo.uid) {
        _toast('You can only edit your own products.');
        context.pop();
        return;
      }
      setState(() {
        _name.text = p.name;
        _desc.text = p.description;
        _price.text = _num(p.price);
        _compare.text = p.compareAtPrice == null ? '' : _num(p.compareAtPrice!);
        _stock.text = p.variants.isNotEmpty || p.stock == null ? '' : '${p.stock}';
        _category.text = p.category;
        _currency = p.currency.length == 3 ? p.currency : 'usd';
        _modelHd = p.model3dHdUrl;
        _modelAr = p.model3dArUrl;
        _modelAnimations = p.modelAnimations;
        _active = p.active;
        _images = p.gallery;
        _model = p.model3dUrl;
        _variants = [...p.variants];
        _custom = [...p.customization];
        _textures = [...p.textures];
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        _toast("Couldn't load this product.");
        context.pop();
      }
    }
  }

  static String _num(num n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();

  @override
  void dispose() {
    for (final c in [_name, _desc, _price, _compare, _stock, _category]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  bool get _uploading => _uploadProgress != null;

  Future<void> _addImages() async {
    if (_images.length >= 8) return _toast('Up to 8 photos per product.');
    final picked = await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2000, limit: 8 - _images.length);
    if (picked.isEmpty) return;
    for (var i = 0; i < picked.length; i++) {
      final f = File(picked[i].path);
      if (await f.length() > 10 * 1024 * 1024) {
        _toast('A photo is over 10 MB and was skipped.');
        continue;
      }
      setState(() {
        _uploadLabel = 'Uploading photo ${i + 1} of ${picked.length}';
        _uploadProgress = 0;
      });
      try {
        final url = await _repo.uploadProductFile(_id, f, onProgress: (v) {
          if (mounted) setState(() => _uploadProgress = v);
        });
        if (mounted) setState(() => _images = [..._images, url]);
      } catch (_) {
        if (mounted) _toast("A photo didn't upload. Check your connection.");
      }
    }
    if (mounted) setState(() => _uploadProgress = null);
  }

  /// Opens the private model library; the chosen model is copied onto this
  /// product by the model service (optimized phone, tablet and AR files).
  Future<void> _pickModel() async {
    final published = await context.push<PublishedModel>('/shops/models?pick=$_id');
    if (published == null || !mounted) return;
    setState(() {
      _model = published.url;
      _modelHd = published.hdUrl;
      _modelAr = published.arUrl;
      _modelAnimations = published.animations;
    });
  }

  Future<void> _editVariant([int? index]) async {
    final result = await showModalBottomSheet<ProductVariant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _VariantSheet(initial: index == null ? null : _variants[index], modelVariants: _modelVariants),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _variants = [..._variants, result];
      } else {
        _variants = [..._variants]..[index] = result;
      }
    });
  }

  Future<void> _save() async {
    if (_uploading || _saving) return;
    if (!_form.currentState!.validate()) return;
    if (_images.isEmpty) return _toast('Add at least one photo.');
    final price = num.parse(_price.text.trim());
    final compare = _compare.text.trim().isEmpty ? null : num.parse(_compare.text.trim());
    final stock = _variants.isNotEmpty || _stock.text.trim().isEmpty ? null : int.parse(_stock.text.trim());
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      await _repo.saveProduct(
        productId: _id,
        isNew: _isNew,
        name: _name.text,
        description: _desc.text,
        price: price,
        compareAtPrice: compare != null && compare > price ? compare : null,
        currency: _currency,
        stock: stock,
        category: _category.text,
        imageUrls: _images,
        model3dUrl: _model,
        model3dHdUrl: _modelHd,
        model3dArUrl: _modelAr,
        modelAnimations: _modelAnimations,
        variants: _variants,
        customization: _custom,
        textures: _textures,
        active: _active,
        sortOrder: _isNew ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : null,
      );
      if (!mounted) return;
      _toast(_isNew ? 'Product added' : 'Product updated');
      context.pop();
    } catch (_) {
      if (mounted) _toast("Couldn't save. Check the fields and your connection.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this product?'),
        content: const Text('It will disappear from your shop and live stages. Orders already placed are kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete', style: TextStyle(color: AppColors.brandPink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteProduct(_id);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) _toast("Couldn't delete right now.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        backgroundColor: context.bg,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 50,
        leading: IconButton(icon: Icon(Icons.close_rounded, color: context.textPrimary), onPressed: () => context.pop()),
        title: Text(_isNew ? 'New product' : 'Edit product', style: AppTypography.pageTitle(context.textPrimary)),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete',
              icon: Icon(Icons.delete_outline_rounded, color: context.textSecondary),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              onPressed: (!_loaded || _saving || _uploading) ? null : _save,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator(color: AppColors.brandBlue, strokeWidth: 2))
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  if (_uploading) _progress(),
                  _section('Photos', 'The first photo is the cover and the 3D poster.', _photos()),
                  _section('3D model', 'Buyers rotate, zoom and place it in their room. Build one from photos or upload a file in your private library.', _modelBlock()),
                  _section('Details', null, _details()),
                  _section('Price & stock', 'Buyers pay the price shown here; Oneova checks it again at checkout.', _pricing()),
                  _section('Options', 'Colours or sizes. Each can have its own stock and 3D look.', _options()),
                  if (_model != null)
                    _section(
                      'Materials & textures',
                      'Put a texture from the Oneova library, your own colorway or a photo on the whole model or one part.',
                      _texturesBlock(),
                    ),
                  _section(
                    'Buyer customization',
                    'Let buyers change colors, materials or add a name. Extra prices are added at checkout.',
                    CustomizationEditor(
                      options: _custom,
                      modelVariants: _modelVariants,
                      currency: _currency,
                      onChanged: (v) => setState(() => _custom = v),
                    ),
                  ),
                  _section(
                    'Visibility',
                    null,
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: _active,
                      activeTrackColor: AppColors.brandBlue,
                      title: Text('Show in my shop', style: AppTypography.callout(context.textPrimary)),
                      subtitle: Text(_active ? 'Buyers can see and buy it' : 'Hidden draft',
                          style: AppTypography.caption(context.textSecondary)),
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _addTexture() async {
    String material = '';
    if (_materials.length > 1) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: context.surface,
        builder: (sheet) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(title: const Text('Whole model'), onTap: () => Navigator.pop(sheet, '')),
            for (final m in _materials) ListTile(title: Text(m), onTap: () => Navigator.pop(sheet, m)),
          ]),
        ),
      );
      if (picked == null || !mounted) return;
      material = picked;
    }
    final t = await showTexturePicker(context);
    if (t == null || !mounted) return;
    setState(() => _textures = [..._textures.where((x) => x.material != material), ProductTexture(material: material, texture: t)]);
  }

  Widget _texturesBlock() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final t in _textures)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Image.network(t.texture.url, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 40)),
            ),
            title: Text(t.texture.name, style: AppTypography.callout(context.textPrimary)),
            subtitle: Text(t.material.isEmpty ? 'Whole model' : t.material, style: AppTypography.caption(context.textSecondary)),
            trailing: IconButton(
              tooltip: 'Remove',
              icon: Icon(Icons.close_rounded, color: context.textMuted),
              onPressed: () => setState(() => _textures = [..._textures]..remove(t)),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(onPressed: _addTexture, icon: const Icon(Icons.texture_rounded, size: 18), label: const Text('Add texture')),
        ),
      ]);

  Widget _progress() => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: AppDecorations.card(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_uploadLabel ?? 'Uploading', style: AppTypography.small(context.textPrimary)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: (_uploadProgress ?? 0) > 0 ? _uploadProgress : null,
                color: AppColors.brandBlue,
                backgroundColor: context.surfaceMid,
                minHeight: 3,
              ),
            ],
          ),
        ),
      );

  Widget _section(String title, String? hint, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: AppDecorations.groupedSection(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.sectionTitle(context.textPrimary)),
              if (hint != null) ...[
                const SizedBox(height: 2),
                Text(hint, style: AppTypography.caption(context.textSecondary)),
              ],
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      );

  Widget _photos() {
    return SizedBox(
      height: 84,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _images.length + 1,
        onReorderItem: (a, b) {
          if (a >= _images.length) return;
          setState(() {
            final list = [..._images];
            final item = list.removeAt(a);
            list.insert(b.clamp(0, list.length), item);
            _images = list;
          });
        },
        itemBuilder: (context, i) {
          if (i == _images.length) {
            return Padding(
              key: const ValueKey('add'),
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                onTap: _uploading ? null : _addImages,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: context.border),
                    color: context.surfaceMid,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_photo_alternate_outlined, color: AppColors.brandBlue),
                      const SizedBox(height: 4),
                      Text('Add', style: AppTypography.caption(context.textSecondary)),
                    ],
                  ),
                ),
              ),
            );
          }
          return ReorderableDelayedDragStartListener(
            key: ValueKey(_images[i]),
            index: i,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.network(_images[i], width: 84, height: 84, fit: BoxFit.cover, cacheWidth: 250),
                  ),
                  if (i == 0)
                    const Positioned(left: 4, bottom: 4, child: StagePill(label: 'COVER', color: AppColors.brandBlue)),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => setState(() => _images = [..._images]..removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: context.surface, shape: BoxShape.circle),
                        child: Icon(Icons.close_rounded, size: 13, color: context.textPrimary),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _modelBlock() {
    if (_model == null) {
      return OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brandBlue,
          side: BorderSide(color: context.border),
          minimumSize: const Size(double.infinity, 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
        onPressed: _uploading ? null : _pickModel,
        icon: const Icon(Icons.view_in_ar_rounded, size: 18),
        label: const Text('Add a 3D model'),
      );
    }
    final style = StageStyle.of(context, const StageConfig());
    final preview = ShopProduct(id: _id, ownerId: _repo.uid ?? '', name: _name.text, imageUrl: _images.isEmpty ? '' : _images.first, model3dUrl: _model, model3dHdUrl: _modelHd);
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 220,
            child: Stack(
              fit: StackFit.expand,
              children: [
                StageBackdropLayer(style: style),
                Product3DViewer(
                  product: preview,
                  style: style,
                  interactive: true,
                  textures: _textures,
                  onMaterialsFound: (m) {
                    if (mounted && m.join() != _materials.join()) setState(() => _materials = m);
                  },
                  onVariantsFound: (v) {
                    if (mounted && v.join() != _modelVariants.join()) setState(() => _modelVariants = v);
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                _modelVariants.isEmpty ? 'Model ready' : 'Model ready · ${_modelVariants.length} material looks found',
                style: AppTypography.caption(context.textSecondary),
              ),
            ),
            TextButton(onPressed: _uploading ? null : _pickModel, child: const Text('Replace')),
            TextButton(
              onPressed: () => setState(() {
                _model = null;
                _modelHd = null;
                _modelAr = null;
                _modelAnimations = [];
                _modelVariants = [];
              }),
              child: Text('Remove', style: TextStyle(color: context.textSecondary)),
            ),
          ],
        ),
      ],
    );
  }

  InputDecoration _dec(String label, {String? hint, String? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.brandBlue),
        ),
      );

  Widget _details() => Column(
        children: [
          TextFormField(
            controller: _name,
            maxLength: 120,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec('Name'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Give it a name' : null,
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _desc,
            maxLength: 4000,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec('Description', hint: 'Materials, size, what makes it special'),
          ),
          const SizedBox(height: 4),
          TextFormField(
            controller: _category,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Category', hint: 'e.g. Sneakers'),
          ),
        ],
      );

  Widget _pricing() {
    String? money(String? v, {bool required = false}) {
      final t = (v ?? '').trim();
      if (t.isEmpty) return required ? 'Required' : null;
      final n = num.tryParse(t);
      if (n == null || n < 0) return 'Enter a number';
      if (required && n <= 0) return 'Must be above 0';
      if (n > 10000000) return 'Too high';
      return null;
    }

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () async {
                final c = await showCurrencyPicker(context, ref, selected: _currency);
                if (c != null && mounted) setState(() => _currency = c);
              },
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: context.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(_currency.toUpperCase(), style: AppTypography.callout(context.textPrimary)),
                  Icon(Icons.expand_more_rounded, size: 18, color: context.textMuted),
                ]),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _dec('Price'),
                validator: (v) => money(v, required: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: _compare,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _dec('Was (optional)', hint: 'Shows a discount when higher than the price'),
          validator: (v) => money(v),
        ),
        if (_variants.isEmpty) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _stock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _dec('Stock (optional)', hint: 'Leave empty if you don’t track stock'),
          ),
        ],
      ],
    );
  }

  Widget _options() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _variants.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: CircleAvatar(
              radius: 12,
              backgroundColor: _variants[i].swatch ?? context.surfaceMid,
              child: _variants[i].swatch == null ? Icon(Icons.label_outline, size: 13, color: context.textSecondary) : null,
            ),
            title: Text(_variants[i].name, style: AppTypography.callout(context.textPrimary)),
            subtitle: Text(
              [
                _variants[i].stock == null ? 'Stock not tracked' : '${_variants[i].stock} in stock',
                if ((_variants[i].modelVariant ?? '').isNotEmpty) '3D look: ${_variants[i].modelVariant}',
              ].join(' · '),
              style: AppTypography.caption(context.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: Icon(Icons.edit_outlined, size: 18, color: context.textSecondary), onPressed: () => _editVariant(i)),
                IconButton(
                  icon: Icon(Icons.remove_circle_outline, size: 18, color: context.textSecondary),
                  onPressed: () => setState(() => _variants = [..._variants]..removeAt(i)),
                ),
              ],
            ),
          ),
        if (_variants.length < 24)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _editVariant(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add option'),
            ),
          ),
      ],
    );
  }
}

class _VariantSheet extends StatefulWidget {
  const _VariantSheet({required this.initial, required this.modelVariants});
  final ProductVariant? initial;
  final List<String> modelVariants;

  @override
  State<_VariantSheet> createState() => _VariantSheetState();
}

class _VariantSheetState extends State<_VariantSheet> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _stock = TextEditingController(text: widget.initial?.stock?.toString() ?? '');
  late String? _color = widget.initial?.colorHex;
  late String? _look = widget.initial?.modelVariant;

  // Neutral product colours plus the two brand colours.
  static const _palette = [
    '#111111', '#FFFFFF', '#9CA3AF', '#0C4FA8', '#FF2D87', '#1E3A8A', '#B91C1C',
    '#15803D', '#CA8A04', '#7C3AED', '#92400E', '#F5F5DC',
  ];

  @override
  void dispose() {
    _name.dispose();
    _stock.dispose();
    super.dispose();
  }

  String _newId(String name) {
    final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
    final r = Random.secure().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${slug.isEmpty ? 'opt' : slug.substring(0, min(slug.length, 20))}-$r';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
          const SizedBox(height: 12),
          Text(widget.initial == null ? 'New option' : 'Edit option', style: AppTypography.title3(context.textPrimary)),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            maxLength: 60,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name (e.g. Royal Blue, 42)', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
          ),
          TextField(
            controller: _stock,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: 'Stock (optional)', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm))),
          ),
          const SizedBox(height: 12),
          Text('Swatch', style: AppTypography.small(context.textSecondary)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('None'),
                selected: _color == null,
                onSelected: (_) => setState(() => _color = null),
                visualDensity: VisualDensity.compact,
              ),
              for (final hex in _palette)
                GestureDetector(
                  onTap: () => setState(() => _color = hex),
                  child: Container(
                    width: 28,
                    height: 28,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == hex ? AppColors.brandBlue : context.border, width: _color == hex ? 2 : 1),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: ProductVariant(id: '', name: '', colorHex: hex).swatch,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (widget.modelVariants.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('3D look', style: AppTypography.small(context.textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(label: const Text('Default'), selected: _look == null, onSelected: (_) => setState(() => _look = null)),
                for (final m in widget.modelVariants)
                  ChoiceChip(label: Text(m), selected: _look == m, onSelected: (_) => setState(() => _look = m)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
              onPressed: () {
                final name = _name.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  context,
                  ProductVariant(
                    id: widget.initial?.id ?? _newId(name),
                    name: name,
                    colorHex: _color,
                    stock: int.tryParse(_stock.text.trim()),
                    modelVariant: _look,
                  ),
                );
              },
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
