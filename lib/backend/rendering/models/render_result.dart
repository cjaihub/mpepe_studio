import 'render_frame.dart';
import 'render_diagnostic.dart';

class RenderResult {
  final RenderFrame? frame;
  final bool success;
  final List<RenderDiagnostic> diagnostics;
  final Duration processTime;

  const RenderResult({
    this.frame,
    required this.success,
    this.diagnostics = const [],
    this.processTime = Duration.zero,
  });
  
  bool get hasErrors => diagnostics.any((d) => 
    d.severity == RenderDiagnosticSeverity.error || 
    d.severity == RenderDiagnosticSeverity.fatal
  );
}
