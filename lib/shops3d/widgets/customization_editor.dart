import 'dart:math';

import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';
import '../models/shop_models.dart';
import 'texture_picker.dart';

/// Seller side of 3D customization: options buyers can change (each choice
/// can switch a material look in the 3D model and add to the price) and
/// short texts such as an engraving.
class CustomizationEditor extends StatelessWidget {
  const CustomizationEditor({super.key, required this.options, required this.modelVariants, required this.currency, required this.onChanged});

  final List<ProductOption> options;
  final List<String> modelVariants;
  final String currency;
  final ValueChanged<List<ProductOption>> onChanged;

  static String _id() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(999)}';

  Future<void> _edit(BuildContext context, [int? index]) async {
    final result = await showModalBottomSheet<ProductOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (_) => _OptionSheet(initial: index == null ? null : options[index], modelVariants: modelVariants, currency: currency),
    );
    if (result == null) return;
    final next = [...options];
    if (index == null) {
      next.add(result);
    } else {
      next[index] = result;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < options.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(options[i].type == ProductOptionType.text ? Icons.text_fields_rounded : Icons.palette_outlined,
              color: AppColors.brandBlue),
          title: Text('${options[i].label}${options[i].required ? ' · required' : ''}', style: AppTypography.callout(context.textPrimary)),
          subtitle: Text(
            options[i].type == ProductOptionType.text
                ? 'Up to ${options[i].maxLength} characters${options[i].priceDelta > 0 ? ' · +${options[i].priceDelta}' : ''}'
                : options[i].choices.map((c) => '${c.label}${c.priceDelta > 0 ? ' +${c.priceDelta}' : ''}').join(', '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(context.textSecondary),
          ),
          trailing: IconButton(
            tooltip: 'Remove',
            icon: Icon(Icons.close_rounded, color: context.textMuted),
            onPressed: () => onChanged([...options]..removeAt(i)),
          ),
          onTap: () => _edit(context, i),
        ),
      if (options.length < 12)
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add customization'),
          ),
        ]),
    ]);
  }

  /// A new empty option of [type] (used by the sheet).
  static ProductOption blank(ProductOptionType type) =>
      ProductOption(id: _id(), label: type == ProductOptionType.text ? 'Engraving' : 'Color', type: type);
}

class _OptionSheet extends StatefulWidget {
  const _OptionSheet({required this.initial, required this.modelVariants, required this.currency});
  final ProductOption? initial;
  final List<String> modelVariants;
  final String currency;

  @override
  State<_OptionSheet> createState() => _OptionSheetState();
}

class _OptionSheetState extends State<_OptionSheet> {
  late ProductOption _o = widget.initial ?? CustomizationEditor.blank(ProductOptionType.choice);
  late final _label = TextEditingController(text: _o.label);
  late final _textPrice = TextEditingController(text: _o.priceDelta > 0 ? '${_o.priceDelta}' : '');
  late double _maxLen = _o.maxLength.toDouble();

  @override
  void dispose() {
    _label.dispose();
    _textPrice.dispose();
    super.dispose();
  }

  Future<void> _editChoice([int? i]) async {
    final c = i == null ? null : _o.choices[i];
    final name = TextEditingController(text: c?.label ?? '');
    final price = TextEditingController(text: (c?.priceDelta ?? 0) > 0 ? '${c!.priceDelta}' : '');
    String? look = c?.modelVariant;
    String? hex = c?.colorHex;
    ProductTexture? texture = c?.texture;
    const swatches = ['#111111', '#FFFFFF', '#0C4FA8', '#FF2D87', '#E53935', '#43A047', '#FDD835', '#8D6E63', '#9E9E9E', '#C0A060'];
    final saved = await showDialog<OptionChoice>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => AlertDialog(
          title: Text(c == null ? 'New choice' : 'Edit choice'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Gold sole')),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Extra price (${widget.currency.toUpperCase()})', hintText: '0'),
              ),
              const SizedBox(height: 10),
              const Text('Swatch'),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in swatches)
                  GestureDetector(
                    onTap: () => set(() => hex = hex == s ? null : s),
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: Color(0xFF000000 | int.parse(s.substring(1), radix: 16)),
                        shape: BoxShape.circle,
                        border: Border.all(color: hex == s ? AppColors.brandPink : Colors.black26, width: hex == s ? 3 : 1),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              const Text('Texture on the 3D model'),
              const SizedBox(height: 4),
              Row(children: [
                if (texture != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(texture!.texture.url, width: 32, height: 32, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 32)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(texture!.texture.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: () => set(() => texture = null)),
                ] else
                  TextButton.icon(
                    onPressed: () async {
                      final t = await showTexturePicker(d);
                      if (t != null) set(() => texture = ProductTexture(material: '', texture: t));
                    },
                    icon: const Icon(Icons.texture_rounded, size: 18),
                    label: const Text('Choose texture'),
                  ),
              ]),
              if (widget.modelVariants.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text('3D look'),
                Wrap(spacing: 6, children: [
                  ChoiceChip(label: const Text('Default'), selected: look == null, onSelected: (_) => set(() => look = null)),
                  for (final v in widget.modelVariants) ChoiceChip(label: Text(v), selected: look == v, onSelected: (_) => set(() => look = v)),
                ]),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final n = name.text.trim();
                if (n.isEmpty) return;
                Navigator.pop(
                  d,
                  OptionChoice(
                    id: c?.id ?? CustomizationEditor.blank(ProductOptionType.choice).id,
                    label: n,
                    priceDelta: num.tryParse(price.text.trim()) ?? 0,
                    colorHex: hex,
                    modelVariant: look,
                    texture: texture,
                  ),
                );
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    if (saved == null) return;
    final list = [..._o.choices];
    if (i == null) {
      list.add(saved);
    } else {
      list[i] = saved;
    }
    setState(() => _o = _o.copyWith(choices: list));
  }

  @override
  Widget build(BuildContext context) {
    final text = _o.type == ProductOptionType.text;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.initial == null ? 'New customization' : 'Edit customization', style: AppTypography.title2(context.textPrimary)),
          const SizedBox(height: 12),
          if (widget.initial == null)
            SegmentedButton<ProductOptionType>(
              segments: const [
                ButtonSegment(value: ProductOptionType.choice, icon: Icon(Icons.palette_outlined), label: Text('Choices')),
                ButtonSegment(value: ProductOptionType.text, icon: Icon(Icons.text_fields_rounded), label: Text('Text')),
              ],
              selected: {_o.type},
              onSelectionChanged: (s) => setState(() {
                _o = CustomizationEditor.blank(s.first);
                _label.text = _o.label;
              }),
            ),
          const SizedBox(height: 8),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Name buyers see', hintText: 'Color, Material, Size, Engraving…')),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Buyers must choose'),
            value: _o.required,
            activeTrackColor: AppColors.brandBlue,
            onChanged: (v) => setState(() => _o = _o.copyWith(required: v)),
          ),
          if (text) ...[
            Text('Up to ${_maxLen.round()} characters'),
            Slider(value: _maxLen, min: 4, max: 60, divisions: 56, activeColor: AppColors.brandBlue, onChanged: (v) => setState(() => _maxLen = v)),
            TextField(
              controller: _textPrice,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'Extra price (${widget.currency.toUpperCase()})', hintText: '0'),
            ),
          ] else ...[
            for (var i = 0; i < _o.choices.length; i++)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(radius: 11, backgroundColor: _o.choices[i].color ?? context.surfaceMid),
                title: Text(_o.choices[i].label),
                subtitle: Text([
                  if (_o.choices[i].priceDelta > 0) '+${_o.choices[i].priceDelta}',
                  if ((_o.choices[i].modelVariant ?? '').isNotEmpty) '3D: ${_o.choices[i].modelVariant}',
                ].join(' · ')),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _o = _o.copyWith(choices: [..._o.choices]..removeAt(i))),
                ),
                onTap: () => _editChoice(i),
              ),
            if (_o.choices.length < 24)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(onPressed: _editChoice, icon: const Icon(Icons.add_rounded), label: const Text('Add choice')),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.brandBlue, foregroundColor: Colors.white, minimumSize: const Size.fromHeight(46)),
            onPressed: () {
              final label = _label.text.trim();
              if (label.isEmpty || (!text && _o.choices.isEmpty)) return;
              Navigator.pop(
                context,
                _o.copyWith(
                  label: label,
                  maxLength: _maxLen.round(),
                  priceDelta: text ? (num.tryParse(_textPrice.text.trim()) ?? 0) : 0,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ]),
      ),
    );
  }
}
