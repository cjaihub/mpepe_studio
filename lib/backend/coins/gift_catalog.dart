import 'package:flutter/material.dart';

import '../../shared/theme/app_theme.dart';

/// One gift. Prices are only shown here; the server (GIFT_CATALOG in
/// functions/src/liveStudio/gift_logic.ts) decides what is charged.
class GiftType {
  final String id;
  final String label;
  final IconData icon;
  final int coins;
  final List<Color> colors;

  const GiftType(this.id, this.label, this.icon, this.coins, this.colors);

  /// 0 small · 1 medium · 2 big · 3 legendary: drives the animation size.
  int get tier => coins >= 1000 ? 3 : coins >= 100 ? 2 : coins >= 15 ? 1 : 0;
}

const _bp = [AppColors.brandBlue, AppColors.brandPink];
const _pink = [AppColors.brandPink, AppColors.brandPink];
const _blue = [AppColors.brandBlue, AppColors.brandBlue];

const giftCatalog = <GiftType>[
  GiftType('rose', 'Rose', Icons.local_florist_rounded, 1, _pink),
  GiftType('thumbs', 'Thumbs up', Icons.thumb_up_alt_rounded, 1, _blue),
  GiftType('spark', 'Spark', Icons.auto_awesome_rounded, 2, _bp),
  GiftType('coffee', 'Coffee', Icons.local_cafe_rounded, 3, _blue),
  GiftType('heart', 'Heart', Icons.favorite_rounded, 5, _pink),
  GiftType('icecream', 'Ice cream', Icons.icecream_rounded, 7, _pink),
  GiftType('star', 'Star', Icons.star_rounded, 10, _bp),
  GiftType('fire', 'Fire', Icons.local_fire_department_rounded, 15, _pink),
  GiftType('balloon', 'Balloons', Icons.celebration_rounded, 20, _bp),
  GiftType('music', 'Mic drop', Icons.mic_external_on_rounded, 30, _blue),
  GiftType('crown', 'Crown', Icons.workspace_premium_rounded, 50, _bp),
  GiftType('rocket', 'Rocket', Icons.rocket_launch_rounded, 100, _bp),
  GiftType('trophy', 'Trophy', Icons.emoji_events_rounded, 199, _bp),
  GiftType('diamond', 'Diamond', Icons.diamond_rounded, 500, _bp),
  GiftType('car', 'Sports car', Icons.directions_car_filled_rounded, 1000, _bp),
  GiftType('castle', 'Castle', Icons.castle_rounded, 2500, _bp),
  GiftType('galaxy', 'Galaxy', Icons.blur_on_rounded, 5000, _bp),
];

GiftType giftById(String? id) => giftCatalog.firstWhere((g) => g.id == id, orElse: () => giftCatalog.first);
