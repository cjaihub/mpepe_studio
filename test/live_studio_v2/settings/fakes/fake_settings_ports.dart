import 'dart:async';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:oneova/backend/live_studio/contracts/studio_contracts.dart';
import 'package:oneova/backend/live_studio/contracts/studio_ports.dart';
import 'package:oneova/backend/live_studio/settings/settings_rules.dart';
import 'package:oneova/backend/live_studio/settings/studio_catalog.dart';
import 'package:oneova/backend/live_studio/settings/studio_settings_controller.dart';

/// Records lsSetSettings calls and answers like the server would.
class FakeSettingsCallPort implements StudioCallPort {
  FakeSettingsCallPort([this.server = const StudioSettings()]);

  StudioSettings server;
  final List<({String name, Map<String, dynamic> args})> calls = [];
  bool fail = false;

  List<Map<String, Object?>> get partials =>
      [for (final c in calls) Map<String, Object?>.from(c.args['partial'] as Map)];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> args) async {
    calls.add((name: name, args: args));
    await Future<void>.value();
    if (fail) throw StateError('server rejected');
    server = applySettingsPatch(server, Map<String, Object?>.from(args['partial'] as Map));
    return {'settings': server.toJson(), 'changed': <String>[]};
  }
}

class FakeCatalog implements StudioCatalogPort {
  const FakeCatalog(this.entries);
  final List<StudioCatalogEntry> entries;
  @override
  Future<List<StudioCatalogEntry>> load() async => entries;
}

StudioState stateWith(StudioSettings s, {String streamId = 's1', int seq = 1}) => StudioState(
      streamId: streamId,
      hostId: 'host',
      seq: seq,
      settings: s,
      stage: const StageLayout(centerUid: 'host'),
    );

/// Overrides wiring the settings controller to fakes.
List<Override> settingsOverrides({
  required FakeSettingsCallPort port,
  required Stream<StudioState> states,
  List<StudioCatalogEntry> catalog = const [
    StudioCatalogEntry(id: 'broadcast_curved_wall', label: 'Broadcast studio — curved wall'),
  ],
}) =>
    [
      studioCallPortProvider.overrideWithValue(port),
      studioSettingsStateSourceProvider.overrideWith((ref, streamId) => states),
      studioCatalogPortProvider.overrideWithValue(FakeCatalog(catalog)),
    ];

StreamController<StudioState> stateController() => StreamController<StudioState>.broadcast();
