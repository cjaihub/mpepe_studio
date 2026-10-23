// LIVE STUDIO v2 — table content metrics (workstream #5).
//
// Values from the prototype (reference/html/landscape/Main.dc.html and
// phone/Phone.dc.html, table section): landscape 288×162, phone 240×135.
// Inside a larger box (pop-out / full screen) everything scales with width.

import 'package:flutter/material.dart';

import '../../../../backend/live_studio/contracts/studio_contracts.dart';

@immutable
class TableMetrics {
  const TableMetrics._(this.phone, this.scale);

  /// [width] is the content width (inside the frame border).
  factory TableMetrics.forWidth(double width, {required bool phone}) {
    final base = phone ? phoneWidth : landscapeWidth;
    final s = width.isFinite && width > 0 ? (width / base).clamp(1.0, 3.0) : 1.0;
    return TableMetrics._(phone, s);
  }

  static const double landscapeWidth = 288, landscapeHeight = 162;
  static const double phoneWidth = 240, phoneHeight = 135;

  final bool phone;
  final double scale;

  double _v(double land, double ph) => (phone ? ph : land) * scale;

  // Header row (tag + LIVE): left/top inset, right inset clears the expand button.
  double get headerInset => _v(10, 8);
  double get headerRight => _v(44, 40);
  double get tagFont => _v(10, 9);
  double get tagLine => _v(14, 13);
  EdgeInsets get tagPadding =>
      EdgeInsets.symmetric(horizontal: _v(8, 7), vertical: _v(3, 2));
  double get tagRadius => 4 * scale;
  double get liveDot => _v(6, 5);
  double get liveGap => 5 * scale;

  // Bottom bar.
  EdgeInsets get bottomPadding => phone
      ? EdgeInsets.fromLTRB(10 * scale, 18 * scale, 8 * scale, 8 * scale)
      : EdgeInsets.fromLTRB(12 * scale, 22 * scale, 10 * scale, 10 * scale);
  double get bottomGap => _v(10, 8);
  double get titleFont => _v(14, 13);
  double get titleLine => _v(18, 16);
  double get subFont => _v(12, 11);
  double get subLine => _v(16, 14);

  // CTA.
  double get ctaHeight => 36 * scale;
  double get ctaPadH => _v(14, 12);
  double get ctaFont => 12 * scale;
  double get ctaLine => 16 * scale;
  double get ctaRadius => 8 * scale;

  // Goods cube.
  double get cubeTop => _v(34, 26);
  double get cubeSize => _v(64, 56);
  double get cubeRadius => _v(14, 12);
  double get cubeIcon => _v(32, 28);

  // Movie play disc + letterbox.
  double get playTop => _v(48, 40);
  double get playSize => _v(48, 40);
  double get playIcon => _v(18, 16);
  double get letterbox => _v(14, 12);

  // Screen illustration window.
  EdgeInsets get screenWindow => phone
      ? EdgeInsets.fromLTRB(18 * scale, 14 * scale, 18 * scale, 30 * scale)
      : EdgeInsets.fromLTRB(22 * scale, 32 * scale, 22 * scale, 40 * scale);
  double get windowBar => _v(14, 12);
  double get windowDot => _v(6, 5);

  double get emptyIcon => _v(26, 22);
}

/// Prototype copy per mode.
class TableModeCopy {
  TableModeCopy._();

  static String label(TableMode m) => switch (m) {
        TableMode.goods => 'Goods',
        TableMode.screen => 'Screen',
        TableMode.match => 'Match',
        TableMode.movie => 'Movie',
      };

  static String tag(TableMode m) => switch (m) {
        TableMode.goods => 'PRESENTER’S GOODS',
        TableMode.screen => 'SCREEN SHARE',
        TableMode.match => 'LIVE MATCH',
        TableMode.movie => 'WATCH PARTY',
      };

  static String defaultSub(TableMode m) => switch (m) {
        TableMode.goods => '',
        TableMode.screen => 'Shared to the table',
        TableMode.match => 'Football · watch together',
        TableMode.movie => 'Streaming live to the room',
      };

  static IconData icon(TableMode m) => switch (m) {
        TableMode.goods => Icons.inventory_2,
        TableMode.screen => Icons.desktop_windows,
        TableMode.match => Icons.sports_soccer,
        TableMode.movie => Icons.movie,
      };

  static const String viewItem = 'View item';
  static const String join = 'Join';
  static const String watching = 'Watching';
  static const String waitingScreen = 'Waiting for screen share';
  static const String noLicensed = 'No licensed content available';
  static const String viewerNothing = 'Nothing playing yet';
  static const String viewerNothingSub = 'The host will put something on soon';
  static const String unavailable = 'This content is no longer available';
  static const String noGoods = 'Nothing on the table yet';
  static const String noGoodsHost = 'Add products to your shop to show them here';
  static const String hostScreen = 'Host’s screen';
}
