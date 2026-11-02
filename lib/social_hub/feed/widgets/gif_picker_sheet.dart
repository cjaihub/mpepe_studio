import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../backend/giphy_service.dart';
import '../../../feed/widgets/oneova_gif_picker_sheet.dart';

/// Legacy adapter for Social Hub GIF picker, backed by [OneovaGifPickerSheet]
/// and `lsGifSearch`.
class GifPickerSheet extends ConsumerWidget {
  const GifPickerSheet({super.key});

  static Future<GiphyGif?> show(BuildContext context) async {
    final g = await OneovaGifPickerSheet.show(context);
    if (g == null) return null;
    return GiphyGif(id: g.id, previewUrl: g.url, fullUrl: g.url);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const OneovaGifPickerSheet();
  }
}
