import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/theme/app_theme.dart';
import '../data/shop3d_repository.dart';
import '../models/shop_models.dart';

final textureLibraryProvider = FutureProvider.autoDispose<List<ShopTexture>>(
  (ref) => ref.watch(shop3dRepositoryProvider).textureLibrary(),
);

final myTexturesProvider = StreamProvider.autoDispose<List<ShopTexture>>(
  (ref) => ref.watch(shop3dRepositoryProvider).watchMyTextures(),
);

/// Picks a texture: the hosted library, the seller's own set, a new colorway
/// rendered on the server, or a photo.
Future<ShopTexture?> showTexturePicker(BuildContext context) {
  return showModalBottomSheet<ShopTexture>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: context.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (_) => const _TexturePicker(),
  );
}

class _TexturePicker extends StatelessWidget {
  const _TexturePicker();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.82,
      child: DefaultTabController(
        length: 3,
        child: Column(children: [
          const SizedBox(height: 10),
          Text('Textures', style: AppTypography.title2(context.textPrimary)),
          TabBar(
            indicatorColor: AppColors.brandBlue,
            labelColor: AppColors.brandBlue,
            unselectedLabelColor: context.textSecondary,
            tabs: const [Tab(text: 'Library'), Tab(text: 'Mine'), Tab(text: 'Create')],
          ),
          const Expanded(child: TabBarView(children: [_LibraryTab(), _MineTab(), _CreateTab()])),
        ]),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.items, this.onLongPress});
  final List<ShopTexture> items;
  final ValueChanged<ShopTexture>? onLongPress;

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final t = items[i];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.pop(context, t);
            },
            onLongPress: onLongPress == null ? null : () => onLongPress!(t),
            child: Column(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.network(t.url, fit: BoxFit.cover, width: double.infinity, cacheWidth: 240,
                      errorBuilder: (_, _, _) => ColoredBox(color: context.surfaceMid)),
                ),
              ),
              const SizedBox(height: 4),
              Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.caption(context.textPrimary)),
            ]),
          );
        },
      );
}

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(textureLibraryProvider).when(
          loading: () => Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppColors.brandBlue),
              const SizedBox(height: 12),
              Text('Preparing the texture library…', style: AppTypography.small(context.textSecondary)),
            ]),
          ),
          error: (e, _) => Center(
            child: TextButton(onPressed: () => ref.invalidate(textureLibraryProvider), child: const Text('Couldn’t load textures. Try again')),
          ),
          data: (list) => _Grid(items: list),
        );
  }
}

class _MineTab extends ConsumerWidget {
  const _MineTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myTexturesProvider).value ?? const <ShopTexture>[];
    if (mine.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text('Textures you create or upload show up here. Long-press one to delete it.',
              textAlign: TextAlign.center, style: AppTypography.body(context.textSecondary)),
        ),
      );
    }
    return _Grid(
      items: mine,
      onLongPress: (t) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text('Delete ${t.name}?'),
            content: const Text('Products already using it keep their look.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
            ],
          ),
        );
        if (ok == true) await ref.read(shop3dRepositoryProvider).deleteMyTexture(t.id);
      },
    );
  }
}

class _CreateTab extends ConsumerStatefulWidget {
  const _CreateTab();

  @override
  ConsumerState<_CreateTab> createState() => _CreateTabState();
}

class _CreateTabState extends ConsumerState<_CreateTab> {
  static const _kinds = <(String, String, IconData)>[
    ('wood', 'Wood', Icons.forest_rounded),
    ('marble', 'Marble', Icons.landscape_rounded),
    ('carbon', 'Carbon fibre', Icons.grid_4x4_rounded),
    ('denim', 'Denim', Icons.checkroom_rounded),
    ('leather', 'Leather', Icons.work_outline_rounded),
    ('brushed_metal', 'Metal', Icons.hardware_rounded),
    ('glitter', 'Glitter', Icons.auto_awesome_rounded),
    ('knit', 'Knit', Icons.texture_rounded),
    ('terrazzo', 'Terrazzo', Icons.bubble_chart_rounded),
    ('camo', 'Camo', Icons.park_rounded),
    ('concrete', 'Concrete', Icons.foundation_rounded),
    ('velvet', 'Velvet', Icons.blur_on_rounded),
  ];
  static const _palette = [
    0xFF111111, 0xFF3B2A1A, 0xFF8C5A33, 0xFFD2A66E, 0xFFF4F2EE, 0xFF9E9E9E,
    0xFF0C4FA8, 0xFF7FB2FF, 0xFFFF2D87, 0xFFB23A7A, 0xFFE53935, 0xFF43A047,
    0xFF2E3A23, 0xFFFDD835, 0xFFC0A060, 0xFF3D0F2E,
  ];

  String _kind = 'leather';
  int _a = 0xFF3B2A1A;
  int _b = 0xFF8C5A33;
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String _hex(int c) => '#${(c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final t = await ref.read(shop3dRepositoryProvider).createTexture(kind: _kind, colors: [_hex(_a), _hex(_b)], name: _name.text.trim().isEmpty ? null : _name.text.trim());
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t create the texture: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _photo() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 2048, imageQuality: 90);
    if (x == null) return;
    setState(() => _busy = true);
    try {
      final t = await ref.read(shop3dRepositoryProvider).uploadTexturePhoto(File(x.path), _name.text);
      if (mounted) Navigator.pop(context, t);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t upload the photo: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _swatches(int selected, ValueChanged<int> onPick) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in _palette)
          GestureDetector(
            onTap: () => setState(() => onPick(c)),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: selected == c ? AppColors.brandPink : Colors.black26, width: selected == c ? 3 : 1),
              ),
            ),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
      Text('Material', style: AppTypography.callout(context.textPrimary)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final (id, label, icon) in _kinds)
          ChoiceChip(
            avatar: Icon(icon, size: 16),
            label: Text(label),
            selected: _kind == id,
            onSelected: (_) => setState(() => _kind = id),
          ),
      ]),
      const SizedBox(height: 14),
      Text('Main color', style: AppTypography.callout(context.textPrimary)),
      const SizedBox(height: 8),
      _swatches(_a, (c) => _a = c),
      const SizedBox(height: 14),
      Text('Second color', style: AppTypography.callout(context.textPrimary)),
      const SizedBox(height: 8),
      _swatches(_b, (c) => _b = c),
      const SizedBox(height: 14),
      TextField(controller: _name, maxLength: 40, decoration: const InputDecoration(labelText: 'Name (optional)')),
      const SizedBox(height: 8),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(48)),
        onPressed: _busy ? null : _create,
        icon: _busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_fix_high_rounded),
        label: const Text('Create texture'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
        onPressed: _busy ? null : _photo,
        icon: const Icon(Icons.photo_outlined),
        label: const Text('Use a photo of your material'),
      ),
    ]);
  }
}
