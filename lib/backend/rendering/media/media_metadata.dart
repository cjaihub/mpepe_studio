class MediaMetadata {
  final int width;
  final int height;
  final double fps;
  final Duration duration;
  final String? codec;
  final int? bitDepth;
  final bool hasAudio;
  final int orientation;
  final bool isHdr;
  final bool hasAlpha;

  const MediaMetadata({
    required this.width,
    required this.height,
    required this.fps,
    required this.duration,
    this.codec,
    this.bitDepth,
    this.hasAudio = false,
    this.orientation = 0,
    this.isHdr = false,
    this.hasAlpha = false,
  });

  factory MediaMetadata.unknown() {
    return const MediaMetadata(
      width: 0,
      height: 0,
      fps: 0,
      duration: Duration.zero,
    );
  }
}
