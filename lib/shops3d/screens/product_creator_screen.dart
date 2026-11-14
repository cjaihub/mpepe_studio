import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../shared/theme/app_theme.dart';
import '../data/currencies.dart';
import '../data/model3d_repository.dart';
import '../data/product_photo.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';
import '../widgets/agent_activity.dart';
import '../widgets/product_3d_viewer.dart';
import '../widgets/stage_style.dart';
import 'model_library_screen.dart';

/// `/shops/product/new` — add a product page by page with Ova doing the work.
///
///   1 Photos   take or pick photos; backgrounds are removed on the phone
///   2 Details  Ova reads the photos and writes name, description, category
///   3 Price    currency from the phone's region, a price band to tap
///   4 3D       build from photos, pick from the private library, or upload
///   5 Review   publish, or keep as a draft
///
/// The bar at the bottom says what Ova is doing right now and can be
/// minimized. The 3D model keeps building after the seller leaves; the
/// product is saved as a draft and the model lands on it when ready.
class ProductCreatorScreen extends ConsumerStatefulWidget {
  const ProductCreatorScreen({super.key});

  @override
  ConsumerState<ProductCreatorScreen> createState() => _ProductCreatorScreenState();
}

typedef _Band = ({num low, num typical, num high, String basis, int samples});

class _ProductCreatorScreenState extends ConsumerState<ProductCreatorScreen> {
  final _pages = PageController();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _category = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController();

  late final String _id = _repo.newProductId();
  int _page = 0;
  bool _clean = true;
  final List<String> _images = [];
  File? _firstPhoto;
  String _currency = deviceCurrency();
  List<ProductVariant> _variants = [];
  List<({String name, String hex})> _colors = [];
  _Band? _band;
  String _photoTip = '';
  bool _aiFilled = false;

  // 3D
  String? _modelId;
  PublishedModel? _published;
  bool _attaching = false;

  // Ova activity
  AgentState _agent = AgentState.idle;
  String _now = '';
  double? _progress;
  final List<String> _log = [];
  (String, VoidCallback)? _agentAction;
  bool _saving = false;

  Shop3DRepository get _repo => ref.read(shop3dRepositoryProvider);
  Model3DRepository get _models => ref.read(model3dRepositoryProvider);

  static const _titles = ['Photos', 'Details', 'Price', '3D model', 'Review'];

  @override
  void dispose() {
    _pages.dispose();
    for (final c in [_name, _desc, _category, _price, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toast(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void _say(String now, {AgentState state = AgentState.working, double? progress, (String, VoidCallback)? action}) {
    if (!mounted) return;
    setState(() {
      _agent = state;
      _now = now;
      _progress = progress;
      _agentAction = action;
      if (_log.isEmpty || _log.last != now) _log.add(now);
    });
  }

  // ── Photos ────────────────────────────────────────────────────────────

  Future<void> _addPhotos(ImageSource source) async {
    if (_images.length >= 8) return _toast('Up to 8 photos per product.');
    final picker = ImagePicker();
    final picked = source == ImageSource.camera
        ? [await picker.pickImage(source: ImageSource.camera, imageQuality: 92, maxWidth: 2600)].whereType<XFile>().toList()
        : await picker.pickMultiImage(imageQuality: 92, maxWidth: 2600, limit: 8 - _images.length);
    if (picked.isEmpty) return;
    final wasEmpty = _images.isEmpty;
    for (var i = 0; i < picked.length; i++) {
      final label = picked.length > 1 ? ' ${i + 1} of ${picked.length}' : '';
      _say(_clean ? 'Removing the background$label' : 'Preparing photo$label');
      final prepared = await ProductPhoto.prepare(File(picked[i].path), removeBackground: _clean);
      if (_clean && !prepared.cleaned) _say('Kept photo$label as taken (no clear subject found)');
      _say('Uploading photo$label', progress: 0);
      try {
        final url = await _repo.uploadProductFile(_id, prepared.file, onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        });
        if (!mounted) return;
        setState(() => _images.add(url));
        _firstPhoto ??= prepared.file;
      } catch (_) {
        _say("A photo didn't upload. Check your connection.", state: AgentState.failed);
        return;
      }
    }
    if (wasEmpty || !_aiFilled) {
      unawaited(_draftListing());
    } else {
      _say('Photos added', state: AgentState.done);
    }
  }

  // ── Ova writes the listing ────────────────────────────────────────────

  Future<void> _draftListing() async {
    if (_images.isEmpty) return;
    _say('Ova is looking at your photos');
    try {
      final r = await FirebaseFunctions.instance
          .httpsCallable('shopListingDraft', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
          .call(<String, dynamic>{
        'imageUrls': _images.take(4).toList(),
        'currency': _currency.toUpperCase(),
        'country': deviceCountry(),
        if (_name.text.trim().isNotEmpty) 'hint': _name.text.trim(),
      });
      if (!mounted) return;
      final d = Map<String, dynamic>.from(r.data as Map);
      _say('Writing the name and description');
      final price = d['price'];
      setState(() {
        // Never overwrite what the seller already typed.
        if (_name.text.trim().isEmpty) _name.text = '${d['name'] ?? ''}';
        if (_desc.text.trim().isEmpty) _desc.text = '${d['description'] ?? ''}';
        if (_category.text.trim().isEmpty) _category.text = '${d['category'] ?? ''}';
        _colors = [
          for (final c in (d['colors'] as List? ?? const []))
            if (c is Map) (name: '${c['name']}', hex: '${c['hex']}'),
        ];
        _photoTip = '${d['photoTip'] ?? ''}';
        _band = price is Map
            ? (
                low: price['low'] as num,
                typical: price['typical'] as num,
                high: price['high'] as num,
                basis: '${price['basis']}',
                samples: (price['samples'] as num?)?.toInt() ?? 0,
              )
            : null;
        _aiFilled = true;
      });
      _say(_band == null ? 'Listing drafted. Check it and set your price.' : 'Listing drafted with a price suggestion', state: AgentState.done);
    } on FirebaseFunctionsException catch (e) {
      _say(e.message ?? 'Ova couldn’t read these photos.', state: AgentState.failed, action: ('Try again', _draftListing));
    } catch (_) {
      _say('Ova couldn’t be reached. Fill it in by hand or try again.', state: AgentState.failed, action: ('Try again', _draftListing));
    }
  }

  // ── 3D ────────────────────────────────────────────────────────────────

  Future<void> _buildFromPhotos() async {
    final photos = await showModelPhotoSheet(context, front: _firstPhoto);
    if (photos == null || photos.isEmpty) return;
    _say('Sending ${photos.length} photo${photos.length == 1 ? '' : 's'} to build the 3D model', progress: 0);
    try {
      final r = await _models.generateFromPhotos(
        photos,
        name: _name.text.trim().isEmpty ? 'Product model' : _name.text.trim(),
        productId: _id,
        onProgress: (v) {
          if (mounted) setState(() => _progress = v);
        },
      );
      if (!mounted) return;
      setState(() => _modelId = r.id);
      if (!r.started) {
        _say('Photos saved. The 3D builder is switching on; build it later from My 3D models.',
            state: AgentState.failed, action: ('My 3D models', () => context.push('/shops/models')));
      }
    } on StateError catch (e) {
      _say(e.message, state: AgentState.failed);
    } catch (_) {
      _say("The photos didn't upload. Check your connection.", state: AgentState.failed);
    }
  }

  Future<void> _uploadModel() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    final path = picked?.path;
    if (path == null) return;
    _say('Uploading your 3D file', progress: 0);
    try {
      final id = await _models.addFile(File(path), name: _name.text.trim().isEmpty ? null : _name.text.trim(), productId: _id, onProgress: (v) {
        if (mounted) setState(() => _progress = v);
      });
      if (mounted) setState(() => _modelId = id);
    } on StateError catch (e) {
      _say(e.message, state: AgentState.failed);
    } catch (_) {
      _say("The file didn't upload. Check your connection.", state: AgentState.failed);
    }
  }

  Future<void> _fromLibrary() async {
    final published = await context.push<PublishedModel>('/shops/models?pick=$_id');
    if (published == null || !mounted) return;
    setState(() {
      _published = published;
      _modelId = null;
    });
    _say('3D model added from your library', state: AgentState.done);
  }

  /// Follows the model being prepared and collects its files when ready.
  void _followModel(Model3DAsset? m) {
    if (m == null || _published != null) return;
    if (m.status.working && (_now != m.stage || _progress != m.progress)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _say(m.stage, progress: m.progress > 0 ? m.progress : null));
    } else if (m.status == ModelStatus.failed && _agent != AgentState.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _say(m.error ?? m.stage, state: AgentState.failed));
    } else if (m.ready && !_attaching) {
      _attaching = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _say('Putting the model on your product');
        try {
          final p = await _models.attach(m.id, _id);
          if (!mounted) return;
          setState(() => _published = p);
          _say(m.stage.isEmpty ? '3D model ready' : '3D model ready · ${m.stage.replaceFirst('Ready · ', '')}', state: AgentState.done);
        } on StateError catch (e) {
          _say(e.message, state: AgentState.failed);
        } finally {
          _attaching = false;
        }
      });
    }
  }

  // ── Save ──────────────────────────────────────────────────────────────

  String? _blocker() {
    if (_images.isEmpty) return 'Add at least one photo.';
    if (_name.text.trim().length < 2) return 'Give the product a name.';
    final p = num.tryParse(_price.text.trim());
    if (p == null || p <= 0) return 'Set a price above 0.';
    return null;
  }

  Future<void> _save({required bool publish}) async {
    if (_saving) return;
    if (publish) {
      final b = _blocker();
      if (b != null) return _toast(b);
    } else if (_images.isEmpty) {
      return context.pop();
    }
    setState(() => _saving = true);
    HapticFeedback.lightImpact();
    try {
      final hasStockPerOption = _variants.isNotEmpty;
      await _repo.saveProduct(
        productId: _id,
        isNew: true,
        name: _name.text.trim().isEmpty ? 'Untitled product' : _name.text,
        description: _desc.text,
        price: num.tryParse(_price.text.trim()) ?? 0,
        compareAtPrice: null,
        currency: _currency,
        stock: hasStockPerOption || _stock.text.trim().isEmpty ? null : int.tryParse(_stock.text.trim()),
        category: _category.text,
        imageUrls: _images,
        model3dUrl: _published?.url,
        model3dHdUrl: _published?.hdUrl,
        model3dArUrl: _published?.arUrl,
        modelAnimations: _published?.animations ?? const [],
        variants: _variants,
        active: publish,
        sortOrder: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      if (!mounted) return;
      final building = _modelId != null && _published == null;
      _toast(publish
          ? (building ? 'Product published. The 3D model is added when it’s ready.' : 'Product published')
          : (building ? 'Saved as a draft. We’ll notify you when the 3D model is ready.' : 'Saved as a draft'));
      context.pop();
    } catch (_) {
      _toast("Couldn't save. Check your connection.");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _close() async {
    if (_images.isEmpty) return context.pop();
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave this product?'),
        content: const Text('Save it as a draft to finish later, or discard it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Keep editing')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Discard', style: TextStyle(color: AppColors.brandPink))),
          TextButton(onPressed: () => Navigator.pop(c, 'draft'), child: const Text('Save draft')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'draft') await _save(publish: false);
    if (choice == 'discard' && mounted) context.pop();
  }

  void _go(int page) {
    FocusScope.of(context).unfocus();
    HapticFeedback.selectionClick();
    _pages.animateToPage(page, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_modelId != null) _followModel(ref.watch(model3dProvider(_modelId!)).value);
    final last = _page == _titles.length - 1;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: context.bg,
        appBar: AppBar(
          backgroundColor: context.bg,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 50,
          leading: IconButton(icon: Icon(Icons.close_rounded, color: context.textPrimary), onPressed: _close),
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('New product', style: AppTypography.pageTitle(context.textPrimary)),
            Text('Step ${_page + 1} of ${_titles.length} · ${_titles[_page]}', style: AppTypography.caption(context.textSecondary)),
          ]),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (var i = 0; i < _titles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= _page ? AppColors.brandBlue : context.surfaceMid,
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [_photosPage(), _detailsPage(), _pricePage(), _modelPage(), _reviewPage()],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: AgentActivityBar(state: _agent, now: _now, progress: _progress, log: _log, action: _agentAction),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(children: [
                if (_page > 0)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.textPrimary,
                      side: BorderSide(color: context.border),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    onPressed: () => _go(_page - 1),
                    child: const Text('Back'),
                  ),
                if (_page > 0) const SizedBox(width: 8),
                if (last)
                  TextButton(onPressed: _saving ? null : () => _save(publish: false), child: const Text('Save draft')),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brandBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(120, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                  ),
                  onPressed: _saving || (_page == 0 && _images.isEmpty) ? null : () => last ? _save(publish: true) : _go(_page + 1),
                  child: _saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(last ? 'Publish' : (_page == 3 && _modelId == null && _published == null ? 'Skip for now' : 'Next')),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _page0(String title, String hint, List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          Text(title, style: AppTypography.title2(context.textPrimary)),
          const SizedBox(height: 2),
          Text(hint, style: AppTypography.body(context.textSecondary)),
          const SizedBox(height: 14),
          ...children,
        ],
      );

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffix,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide(color: context.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: const BorderSide(color: AppColors.brandBlue)),
      );

  Widget _bigButton(IconData icon, String label, String hint, VoidCallback? onTap, {bool primary = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
            decoration: BoxDecoration(
              color: context.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: primary ? AppColors.brandBlue : context.border),
            ),
            child: Row(children: [
              Icon(icon, size: 20, color: onTap == null ? context.textMuted : AppColors.brandBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: AppTypography.callout(context.textPrimary)),
                  Text(hint, style: AppTypography.caption(context.textSecondary)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: context.textMuted),
            ]),
          ),
        ),
      );

  Widget _photosPage() => _page0('Show the product', 'One clear photo is enough. Ova fills in the rest.', [
        if (_images.isNotEmpty) ...[
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _images.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(_images[i], width: 92, height: 92, fit: BoxFit.cover, cacheWidth: 280),
                ),
                if (i == 0) const Positioned(left: 4, bottom: 4, child: StagePill(label: 'COVER', color: AppColors.brandBlue)),
                Positioned(
                  right: 2,
                  top: 2,
                  child: GestureDetector(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(color: context.surface, shape: BoxShape.circle),
                      child: Icon(Icons.close_rounded, size: 13, color: context.textPrimary),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _bigButton(Icons.photo_camera_outlined, 'Take a photo', 'Plain surface, even light', () => _addPhotos(ImageSource.camera), primary: _images.isEmpty),
        _bigButton(Icons.photo_library_outlined, 'Choose from gallery', 'Up to 8 photos', () => _addPhotos(ImageSource.gallery)),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: _clean,
          activeTrackColor: AppColors.brandBlue,
          title: Text('Remove the background', style: AppTypography.callout(context.textPrimary)),
          subtitle: Text('Done on your phone; the product is placed on clean white.', style: AppTypography.caption(context.textSecondary)),
          onChanged: (v) => setState(() => _clean = v),
        ),
      ]);

  Widget _detailsPage() => _page0(
        'Details',
        _aiFilled ? 'Ova wrote these from your photos. Change anything.' : 'Ova fills these from your photos; you can also type them.',
        [
          TextField(controller: _name, maxLength: 120, textCapitalization: TextCapitalization.sentences, decoration: _dec('Name')),
          TextField(
            controller: _desc,
            maxLength: 4000,
            minLines: 3,
            maxLines: 7,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec('Description', hint: 'Materials, size, what makes it special'),
          ),
          TextField(controller: _category, maxLength: 40, textCapitalization: TextCapitalization.words, decoration: _dec('Category', hint: 'e.g. Sneakers')),
          if (_colors.isNotEmpty) ...[
            Text('Colours Ova sees · tap to offer as an option', style: AppTypography.caption(context.textSecondary)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in _colors)
                FilterChip(
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(backgroundColor: ProductVariant(id: '', name: '', colorHex: c.hex).swatch, radius: 8),
                  label: Text(c.name),
                  selected: _variants.any((v) => v.name == c.name),
                  onSelected: (on) => setState(() {
                    _variants = on
                        ? [..._variants, ProductVariant(id: 'c-${c.hex.replaceAll('#', '').toLowerCase()}', name: c.name, colorHex: c.hex)]
                        : _variants.where((v) => v.name != c.name).toList();
                  }),
                ),
            ]),
          ],
          if (_photoTip.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_outline_rounded, size: 14, color: AppColors.brandPink),
              const SizedBox(width: 6),
              Expanded(child: Text(_photoTip, style: AppTypography.caption(context.textSecondary))),
            ]),
          ],
          if (_images.isNotEmpty && _agent != AgentState.working)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _name.clear();
                    _desc.clear();
                    _category.clear();
                  });
                  _draftListing();
                },
                icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                label: const Text('Write it again'),
              ),
            ),
        ],
      );

  Widget _pricePage() {
    final rates = ref.watch(fxRatesProvider).value ?? FxRates.empty;
    final fmt = NumberFormat.decimalPattern();
    final band = _band;
    final typed = num.tryParse(_price.text.trim());
    final usd = typed == null || _currency == 'usd' ? null : rates.convert(typed, _currency, 'usd');
    return _page0('Price', 'Your currency comes from your region. Buyers elsewhere see it converted at today’s rate.', [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () async {
            final c = await showCurrencyPicker(context, ref, selected: _currency);
            if (c == null || c == _currency || !mounted) return;
            setState(() {
              _currency = c;
              _band = null; // the band was in the old currency
            });
            if (_images.isNotEmpty) unawaited(_draftListing());
          },
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: context.border)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_currency.toUpperCase(), style: AppTypography.callout(context.textPrimary)),
              Icon(Icons.expand_more_rounded, size: 18, color: context.textMuted),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onChanged: (_) => setState(() {}),
            decoration: _dec('Price'),
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 10),
        child: Text(
          '${currencyName(_currency)}${usd == null ? '' : ' · ≈ USD ${usd.toStringAsFixed(2)} today'}',
          style: AppTypography.caption(context.textSecondary),
        ),
      ),
      if (band != null) ...[
        Text(
          band.basis == 'oneova'
              ? 'What ${band.samples} similar products sell for on Oneova'
              : 'Ova’s market estimate for your region · check it against your costs',
          style: AppTypography.caption(context.textSecondary),
        ),
        const SizedBox(height: 6),
        Row(children: [
          for (final (label, value) in [('Low', band.low), ('Typical', band.typical), ('High', band.high)]) ...[
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _price.text = value == value.roundToDouble() ? value.toInt().toString() : value.toString());
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: num.tryParse(_price.text) == value ? AppColors.brandBlue.withValues(alpha: 0.12) : context.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    border: Border.all(color: num.tryParse(_price.text) == value ? AppColors.brandBlue : context.border),
                  ),
                  child: Column(children: [
                    Text(label, style: AppTypography.caption(context.textSecondary)),
                    Text(fmt.format(value), style: AppTypography.callout(context.textPrimary)),
                  ]),
                ),
              ),
            ),
            if (label != 'High') const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 14),
      ],
      if (_variants.isEmpty)
        TextField(
          controller: _stock,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _dec('Stock (optional)', hint: 'Leave empty if you don’t track stock'),
        )
      else
        Text('Stock per colour is set in the product editor after saving.', style: AppTypography.caption(context.textSecondary)),
    ]);
  }

  Widget _modelPage() {
    final m = _modelId == null ? null : ref.watch(model3dProvider(_modelId!)).value;
    final style = StageStyle.of(context, const StageConfig());
    final busy = m != null && m.status.working;
    return _page0('3D model', 'Buyers can turn it, zoom in and place it in their room. Every model is optimized for phones and tablets on Oneova’s servers.', [
      if (_published != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 240,
            child: Stack(fit: StackFit.expand, children: [
              StageBackdropLayer(style: style),
              Product3DViewer(
                product: ShopProduct(
                  id: _id,
                  ownerId: '',
                  name: _name.text,
                  imageUrl: _images.isEmpty ? '' : _images.first,
                  model3dUrl: _published!.url,
                  model3dHdUrl: _published!.hdUrl,
                ),
                style: style,
                interactive: true,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: Text('Model ready on this product', style: AppTypography.caption(context.textSecondary))),
          TextButton(
            onPressed: () => setState(() {
              _published = null;
              _modelId = null;
            }),
            child: const Text('Remove'),
          ),
        ]),
      ] else if (m != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: AppDecorations.card(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m.stage.isEmpty ? 'Preparing your model' : m.stage,
                style: AppTypography.callout(m.status == ModelStatus.failed ? AppColors.brandPink : context.textPrimary)),
            if (busy) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: m.progress > 0 ? m.progress : null, minHeight: 3, color: AppColors.brandBlue, backgroundColor: context.surfaceMid),
              const SizedBox(height: 8),
              Text('This keeps going if you move on or close the app. You’ll get a notification when it’s ready.',
                  style: AppTypography.caption(context.textSecondary)),
            ],
            if (!busy)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(onPressed: () => setState(() => _modelId = null), child: const Text('Choose another way')),
              ),
          ]),
        ),
      ] else ...[
        _bigButton(Icons.auto_awesome_rounded, 'Build it from photos', 'Ova asks for up to four sides and keeps the real texture', _buildFromPhotos, primary: true),
        _bigButton(Icons.collections_bookmark_outlined, 'Pick from my models', 'Your private library', _fromLibrary),
        _bigButton(Icons.upload_file_rounded, 'Upload a 3D file', 'GLB, GLTF, OBJ or STL up to 100 MB', _uploadModel),
      ],
    ]);
  }

  Widget _reviewPage() {
    final blocker = _blocker();
    final price = num.tryParse(_price.text.trim());
    Widget row(String k, String v, int page) => InkWell(
          onTap: () => _go(page),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 84, child: Text(k, style: AppTypography.caption(context.textSecondary))),
              Expanded(child: Text(v, maxLines: 3, overflow: TextOverflow.ellipsis, style: AppTypography.small(context.textPrimary))),
              Icon(Icons.edit_outlined, size: 14, color: context.textMuted),
            ]),
          ),
        );
    return _page0('Review', blocker ?? 'Looks good. Publish it, or keep it as a draft.', [
      if (_images.isNotEmpty)
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: AspectRatio(aspectRatio: 16 / 10, child: Image.network(_images.first, fit: BoxFit.cover, cacheWidth: 900)),
        ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: AppDecorations.groupedSection(context),
        child: Column(children: [
          row('Photos', '${_images.length}', 0),
          row('Name', _name.text.trim().isEmpty ? 'Missing' : _name.text.trim(), 1),
          row('Category', _category.text.trim().isEmpty ? 'None' : _category.text.trim(), 1),
          if (_variants.isNotEmpty) row('Options', _variants.map((v) => v.name).join(', '), 1),
          row('Price', price == null || price <= 0 ? 'Missing' : '${_currency.toUpperCase()} ${NumberFormat.decimalPattern().format(price)}', 2),
          row(
            '3D model',
            _published != null ? 'Ready' : (_modelId != null ? 'Being prepared; added automatically' : 'None'),
            3,
          ),
        ]),
      ),
    ]);
  }
}
