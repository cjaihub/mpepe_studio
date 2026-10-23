import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../shared/location/geo_services.dart';

/// How risky a tool is. Anything that sends, calls, deletes or posts is
/// [OvaRisk.confirm] and only runs after the user taps Confirm on a card.
enum OvaRisk { safe, confirm }

/// A tappable follow-up shown under a result card.
class OvaResultAction {
  final String label;
  final IconData icon;

  /// go_router path to push, e.g. `/profile/abc`.
  final String? route;

  /// A prompt to run through the assistant (e.g. "call +2547…").
  final String? prompt;

  /// An http(s)/tel/sms/geo URL to open outside the app.
  final String? url;

  const OvaResultAction({
    required this.label,
    required this.icon,
    this.route,
    this.prompt,
    this.url,
  });
}

/// One row inside a result card (search hit, contact, etc.).
class OvaResultItem {
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final IconData icon;
  final OvaResultAction? onTap;

  const OvaResultItem({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.icon = Icons.chevron_right_rounded,
    this.onTap,
  });
}

/// A live map shown inside a result card (where am I, nearby, navigate).
class OvaMapSpec {
  /// The user's position when the tool ran; the card then tracks it live.
  final LatLng me;
  final List<GeoPlace> places;
  final GeoRoute? route;
  final GeoPlace? destination;

  /// driving, walking or cycling (for the Navigate button).
  final String mode;

  /// Signal when the tool ran.
  final GeoSignal? signal;

  const OvaMapSpec({
    required this.me,
    this.places = const [],
    this.route,
    this.destination,
    this.mode = 'driving',
    this.signal,
  });
}

/// What a tool returns. [summary] is fed back to the model; the rest is UI.
class OvaToolResult {
  final bool ok;
  final String summary;

  /// Short card heading; defaults to the first line of [summary].
  final String? title;
  final IconData icon;
  final List<OvaResultItem> items;
  final List<OvaResultAction> actions;
  final String? imagePath;

  /// True when the ability does not exist on this platform (shown in grey).
  final bool unsupported;

  /// A route to push once the sheet closes (navigation tools).
  final String? navigateTo;

  /// A live map card under the result (location tools).
  final OvaMapSpec? map;

  const OvaToolResult({
    required this.ok,
    required this.summary,
    this.title,
    this.icon = Icons.check_circle_rounded,
    this.items = const [],
    this.actions = const [],
    this.imagePath,
    this.unsupported = false,
    this.navigateTo,
    this.map,
  });

  factory OvaToolResult.fail(String summary, {IconData icon = Icons.error_outline_rounded}) =>
      OvaToolResult(ok: false, summary: summary, icon: icon);

  factory OvaToolResult.unsupported(String summary) => OvaToolResult(
        ok: false,
        summary: summary,
        icon: Icons.block_rounded,
        unsupported: true,
      );
}

/// A tool call that is waiting for the user's Cancel / Confirm.
class OvaPendingAction {
  final String toolName;
  final Map<String, dynamic> args;
  final String title;
  final String detail;
  final IconData icon;

  /// Extra platform note shown on the card (e.g. iOS opens the composer).
  final String? note;

  /// Which service acts: oneova, phone, gmail, youtube, facebook, whatsapp, screen.
  final String service;

  /// Who or what it goes to (shown as a compact "To" line).
  final String? target;

  /// Public or hard-to-undo actions need press-and-hold instead of a tap.
  final bool hold;

  /// The verb on the confirm button ("Send", "Post", "Tap"…).
  final String confirmLabel;

  const OvaPendingAction({
    required this.toolName,
    required this.args,
    required this.title,
    required this.detail,
    required this.icon,
    this.note,
    this.service = 'oneova',
    this.target,
    this.hold = false,
    this.confirmLabel = 'Confirm',
  });
}
