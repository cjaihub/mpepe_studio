enum RenderDiagnosticSeverity {
  info,
  warning,
  error,
  fatal,
}

enum RenderFailureType {
  missingSource,
  missingProxy,
  unsupportedCodec,
  missingLUT,
  missingMask,
  rendererUnsupported,
  insufficientMemory,
  invalidEffect,
  corruptFrame,
  exportEncoderFailure,
  unknown,
}

class RenderDiagnostic {
  final RenderDiagnosticSeverity severity;
  final RenderFailureType type;
  final String message;
  final StackTrace? stackTrace;

  const RenderDiagnostic({
    required this.severity,
    required this.type,
    required this.message,
    this.stackTrace,
  });

  @override
  String toString() => 'RenderDiagnostic($severity, $type): $message';
}
