import 'render_models.dart';

class MediaMetadata {
  final int width;
  final int height;
  final double frameRate;
  final double durationSeconds;
  final String codec;
  final int bitDepth;
  final String colorSpace;
  final bool hasAudio;
  final int orientation;
  final bool isHDR;
  final bool isUnknown;

  const MediaMetadata({
    this.width = 0,
    this.height = 0,
    this.frameRate = 0.0,
    this.durationSeconds = 0.0,
    this.codec = 'unknown',
    this.bitDepth = 8,
    this.colorSpace = 'sRGB',
    this.hasAudio = false,
    this.orientation = 0,
    this.isHDR = false,
    this.isUnknown = false,
  });

  static const unknown = MediaMetadata(isUnknown: true);
}

class FrameRequest {
  final String mediaId;
  final String path;
  final double sourceTime;
  final PreviewQuality quality;
  final bool useProxy;

  const FrameRequest({
    required this.mediaId,
    required this.path,
    required this.sourceTime,
    this.quality = PreviewQuality.balanced,
    this.useProxy = false,
  });
}

abstract class MediaDecoder {
  Future<MediaMetadata> extractMetadata(String path);
  Future<RenderFrame?> decodeFrame(FrameRequest request);
  Future<void> preload(String path);
  Future<void> release(String path);
}

// SUPPORTED MODEL RENDERER PENDING
class RealMediaDecoder implements MediaDecoder {
  @override
  Future<MediaMetadata> extractMetadata(String path) async {
    // SUPPORTED MODEL RENDERER PENDING
    // In a real implementation, this would call FFprobe or MediaMetadataRetriever
    return MediaMetadata.unknown;
  }

  @override
  Future<RenderFrame?> decodeFrame(FrameRequest request) async {
    // SUPPORTED MODEL RENDERER PENDING
    // In a real implementation, this would decode the precise frame via ffmpeg/videotoolbox/mediacodec
    return null;
  }

  @override
  Future<void> preload(String path) async {
    // Warm up decoder
  }

  @override
  Future<void> release(String path) async {
    // Release native resources
  }
}
