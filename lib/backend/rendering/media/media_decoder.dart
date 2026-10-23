import 'dart:async';
import 'media_metadata.dart';
import '../models/render_frame.dart';

/// Abstraction for decoding media (video, photo, etc.)
abstract class MediaDecoder {
  /// Unique identifier for this media file/source
  String get sourceId;
  
  /// Get metadata for this media
  Future<MediaMetadata> getMetadata();

  /// Retrieve a frame at a specific source timestamp
  Future<RenderFrame?> getFrameAtTime(Duration sourceTime);

  /// Retrieve a frame by its exact index
  Future<RenderFrame?> getFrameAtIndex(int frameIndex);

  /// Extract audio waveform data asynchronously
  Future<List<double>> extractAudioWaveform({int samples = 100});

  /// Release resources held by this decoder
  Future<void> dispose();
}
