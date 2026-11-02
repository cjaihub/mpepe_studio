// LIVE STUDIO v2 — GIF picker for live comments (GIPHY via lsGifSearch).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../backend/gif/oneova_gif_engine.dart';
import '../../../../backend/live_studio/fun/studio_fun.dart';
import '../theme/live_studio_tokens.dart';

Future<StudioGif?> showGifPicker(BuildContext context) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<StudioGif>(
    context: context,
    isScrollControlled: true,
    backgroundColor: LiveStudioAccent.clear,
    barrierColor: LiveStudioTokens.dimTint(0.3),
    builder: (_) => const _GifPicker(),
  );
}

class _GifPicker extends ConsumerStatefulWidget {
  const _GifPicker();

  @override
  ConsumerState<_GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends ConsumerState<_GifPicker> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<StudioGif> _gifs = const [];
  bool _loading = true;
  bool _enabled = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_search(''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });

    List<StudioGif> foundGifs = const [];

    try {
      final r = await ref.read(studioGifApiProvider).search(q.trim());
      if (r.gifs.isNotEmpty) {
        foundGifs = r.gifs;
      }
    } catch (_) {}

    // Resilient fallback to Open-Source GIF Engine
    if (foundGifs.isEmpty) {
      try {
        final openGifs = await ref.read(oneovaGifEngineProvider).search(q.trim());
        if (openGifs.isNotEmpty) {
          foundGifs = openGifs.map((g) => g.toStudioGif()).toList();
        }
      } catch (_) {}
    }

    if (!mounted || seq != _seq) return;
    setState(() {
      _enabled = true;
      _gifs = foundGifs;
      _loading = false;
      if (foundGifs.isEmpty) {
        _error = 'No GIFs found for "$q". Try another search!';
      } else {
        _error = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Container(
      height: h * 0.62,
      padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
      decoration: const BoxDecoration(
        color: LiveStudioWorld.popHeader,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        Container(width: 38, height: 4, decoration: BoxDecoration(color: LiveStudioWorld.textDim, borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 10),
        TextField(
          controller: _q,
          autofocus: false,
          style: LiveStudioType.s(14, FontWeight.w600, LiveStudioWorld.textHigh),
          textInputAction: TextInputAction.search,
          onChanged: (v) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), () => _search(v));
          },
          decoration: InputDecoration(
            hintText: 'Search GIFs',
            hintStyle: LiveStudioType.s(14, FontWeight.w500, LiveStudioWorld.textDim),
            prefixIcon: const Icon(Icons.search_rounded, color: LiveStudioWorld.textMedium),
            isDense: true,
            filled: true,
            fillColor: LiveStudioWorld.surface2,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(999), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: LiveStudioAccent.pink))
                : !_enabled || _error != null || _gifs.isEmpty
                    ? Center(
                        child: Text(
                          !_enabled ? 'GIFs are coming soon.' : (_error ?? 'No GIFs found.'),
                          style: LiveStudioType.s(13, FontWeight.w600, LiveStudioWorld.textMedium),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                        itemCount: _gifs.length,
                        itemBuilder: (_, i) {
                          final g = _gifs[i];
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop(g);
                            },
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: ColoredBox(
                                color: LiveStudioWorld.surface2,
                                child: Image.network(g.url, fit: BoxFit.cover, gaplessPlayback: true),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Powered by GIPHY', style: LiveStudioType.s(10, FontWeight.w600, LiveStudioWorld.textDim)),
      ]),
    );
  }
}
