import '../models/pro_project_models.dart';
import 'render_models.dart';
import '../editor/timeline_time.dart';

class ClipRenderContext {
  final Clip clip;
  final Track track;
  final TimelineTime sourceTime;

  ClipRenderContext({
    required this.clip,
    required this.track,
    required this.sourceTime,
  });
}

class RenderContext {
  final RenderRequest request;
  final TimelineTime timelineTime;
  final List<ClipRenderContext> activeClips;
  final RenderFrame? initialFrame;
  final Map<String, RenderDiagnostic> diagnostics = {};

  RenderContext({
    required this.request,
    required this.timelineTime,
    required this.activeClips,
    this.initialFrame,
  });

  void addDiagnostic(RenderDiagnostic diagnostic) {
    diagnostics[diagnostic.code] = diagnostic;
  }
}
