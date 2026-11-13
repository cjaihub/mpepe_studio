import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/theme/app_theme.dart';
import '../models/shop_models.dart';
import 'stage_style.dart';

/// Buyer selection: optionId → choiceId (choice) or the typed text.
typedef CustomSelection = Map<String, String>;

/// Extra price of a selection (display only; checkout re-prices it).
num customizationExtra(ShopProduct p, CustomSelection sel) {
  num extra = 0;
  for (final o in p.customization) {
    final v = sel[o.id];
    if (v == null || v.isEmpty) continue;
    if (o.type == ProductOptionType.text) {
      extra += o.priceDelta;
    } else {
      for (final c in o.choices) {
        if (c.id == v) extra += c.priceDelta;
      }
    }
  }
  return extra;
}

/// The 3D material look the selection asks for (last option wins), or null.
String? customizationLook(ShopProduct p, CustomSelection sel) {
  String? look;
  for (final o in p.customization) {
    if (o.type != ProductOptionType.choice) continue;
    for (final c in o.choices) {
      if (c.id == sel[o.id] && (c.modelVariant ?? '').isNotEmpty) look = c.modelVariant;
    }
  }
  return look;
}

/// Product textures with the buyer's texture choices on top.
List<ProductTexture> customizationTextures(ShopProduct p, CustomSelection sel) {
  final out = [...p.textures];
  for (final o in p.customization) {
    if (o.type != ProductOptionType.choice) continue;
    for (final c in o.choices) {
      final t = c.texture;
      if (c.id == sel[o.id] && t != null) {
        out.removeWhere((x) => x.material == t.material || t.material.isEmpty);
        out.add(t);
      }
    }
  }
  return out;
}

/// First required option the buyer hasn't filled, or null.
ProductOption? missingRequired(ShopProduct p, CustomSelection sel) {
  for (final o in p.customization) {
    if (o.required && (sel[o.id] ?? '').trim().isEmpty) return o;
  }
  return null;
}

/// URL-safe form for the checkout route.
String encodeCustomization(CustomSelection sel) =>
    sel.isEmpty ? '' : base64Url.encode(utf8.encode(jsonEncode(sel)));

CustomSelection decodeCustomization(String? raw) {
  if (raw == null || raw.isEmpty) return {};
  try {
    final m = jsonDecode(utf8.decode(base64Url.decode(raw)));
    return m is Map ? {for (final e in m.entries) '${e.key}': '${e.value}'} : {};
  } catch (_) {
    return {};
  }
}

class CustomizationPicker extends StatelessWidget {
  const CustomizationPicker({super.key, required this.product, required this.selection, required this.style, required this.onChanged});
  final ShopProduct product;
  final CustomSelection selection;
  final StageStyle style;
  final ValueChanged<CustomSelection> onChanged;

  void _set(String id, String? value) {
    final next = {...selection};
    if (value == null || value.isEmpty) {
      next.remove(id);
    } else {
      next[id] = value;
    }
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final p = product;
    if (p.customization.isEmpty) return const SizedBox.shrink();
    final extra = customizationExtra(p, selection);
    return GlassPanel(
      style: style,
      strong: true,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Icon(Icons.tune_rounded, size: 16, color: style.accent),
          const SizedBox(width: 6),
          Text('Make it yours', style: AppTypography.callout(style.fg)),
          const Spacer(),
          if (extra > 0) Text('+$extra', style: AppTypography.small(style.accent).copyWith(fontWeight: FontWeight.w800)),
        ]),
        for (final o in p.customization) ...[
          const SizedBox(height: 8),
          Text('${o.label}${o.required ? ' *' : ''}', style: AppTypography.caption(style.fgSecondary)),
          const SizedBox(height: 4),
          if (o.type == ProductOptionType.text)
            _TextOption(option: o, value: selection[o.id] ?? '', style: style, onChanged: (v) => _set(o.id, v))
          else
            SizedBox(
              height: 36,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in o.choices)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _set(o.id, selection[o.id] == c.id && !o.required ? null : c.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: selection[o.id] == c.id ? style.accent.withValues(alpha: 0.18) : style.glass,
                          borderRadius: BorderRadius.circular(AppRadius.full),
                          border: Border.all(color: selection[o.id] == c.id ? style.accent : style.hairline, width: selection[o.id] == c.id ? 1.6 : 1),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          if (c.texture != null) ...[
                            ClipOval(child: Image.network(c.texture!.texture.url, width: 16, height: 16, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox(width: 16))),
                            const SizedBox(width: 6),
                          ] else if (c.color != null) ...[
                            Container(width: 14, height: 14, decoration: BoxDecoration(color: c.color, shape: BoxShape.circle, border: Border.all(color: style.hairline))),
                            const SizedBox(width: 6),
                          ],
                          Text(c.label, style: AppTypography.small(style.fg)),
                          if (c.priceDelta > 0) Text('  +${c.priceDelta}', style: AppTypography.caption(style.fgMuted)),
                          if ((c.modelVariant ?? '').isNotEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.view_in_ar_rounded, size: 12, color: style.accent),
                          ],
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _TextOption extends StatefulWidget {
  const _TextOption({required this.option, required this.value, required this.style, required this.onChanged});
  final ProductOption option;
  final String value;
  final StageStyle style;
  final ValueChanged<String> onChanged;

  @override
  State<_TextOption> createState() => _TextOptionState();
}

class _TextOptionState extends State<_TextOption> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _c,
        maxLength: widget.option.maxLength,
        onChanged: widget.onChanged,
        style: AppTypography.small(widget.style.fg),
        decoration: InputDecoration(
          isDense: true,
          counterText: '',
          hintText: 'Type up to ${widget.option.maxLength} characters'
              '${widget.option.priceDelta > 0 ? ' (+${widget.option.priceDelta})' : ''}',
          hintStyle: AppTypography.small(widget.style.fgMuted),
          filled: true,
          fillColor: widget.style.glass,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide(color: widget.style.hairline)),
        ),
      );
}
