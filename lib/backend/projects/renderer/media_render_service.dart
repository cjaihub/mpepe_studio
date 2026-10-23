import 'dart:async';
import 'package:flutter/foundation.dart';
import '../editor/timeline_time.dart';
import 'render_models.dart';
import 'render_context.dart';
import 'render_graph.dart';
import 'media_decoder.dart';
import 'render_cache_manager.dart';
import 'proxy_service.dart';

class MediaRenderService {
  final MediaDecoder decoder;
  final RenderCacheManager cacheManager;
  final ProxyService proxyService;
  
  MediaRenderService({
    MediaDecoder? decoder,
    RenderCacheManager? cacheManager,
    ProxyService? proxyService,
  }) : decoder = decoder ?? RealMediaDecoder(),
       cacheManager = cacheManager ?? RenderCacheManager(),
       proxyService = proxyService ?? ProxyService();

  Future<RenderResult> render(dynamic project, RenderRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    // 0. Cache Check
    final cacheKey = request.cacheKey;
    if (request.target == RenderTarget.livePreview || request.target == RenderTarget.thumbnail) {
      final cachedResult = cacheManager.get(cacheKey);
      if (cachedResult != null) {
        return cachedResult;
      }
    }

    // 1. Resolve sequence
    final sequence = project.sequences.firstWhere(
      (s) => s.id == request.sequenceId,
      orElse: () => project.sequences.first,
    );

    // 2. Resolve Active Clips at the requested sequenceTime
    final activeClips = <ClipRenderContext>[];
    
    // Iterate bottom-up if tracks are rendered bottom-to-top, or process in normal order 
    // and rely on Compositing logic. We'll iterate normally.
    for (var track in sequence.tracks) {
      if (track.isHidden) continue;
      
      for (var clip in track.clips) {
        if (request.sequenceTime.toSeconds >= clip.startTime &&
            request.sequenceTime.toSeconds < (clip.startTime + clip.duration)) {
          
          final sourceTimeSeconds = clip.sourceStart + (request.sequenceTime.toSeconds - clip.startTime);
          
          activeClips.add(ClipRenderContext(
            clip: clip,
            track: track,
            sourceTime: TimelineTime.fromSeconds(sourceTimeSeconds, sequence.settings.frameRate),
          ));
        }
      }
    }

    // 3. Create Context (Minimal Deterministic State)
    final context = RenderContext(
      request: request,
      timelineTime: request.sequenceTime,
      activeClips: activeClips,
    );

    // 4. Build the Global Render Graph
    final List<RenderNode> globalNodes = [];
    
    // For each active clip, build a nested ClipPipelineNode
    // This allows multi-track compositing. Bottom tracks first (index 0 is bottom-most in standard NLEs, though it depends on your specific track sorting).
    for (var activeClip in activeClips) {
      final clipNodes = <RenderNode>[];
      final clip = activeClip.clip;

      // Decode phase
      clipNodes.add(DecodeNode(activeClip, useProxy: request.useProxy && request.quality.index <= PreviewQuality.balanced.index));
      clipNodes.add(InputTransformNode());
      clipNodes.add(SpatialTransformNode(clip.transform));

      // Color & LUT
      clipNodes.add(PrimaryColorNode(clip.color));
      
      if (clip.secondaryColorStates.isNotEmpty) {
        clipNodes.add(SecondaryColorNode(clip.secondaryColorStates));
      }
      
      if (clip.color.lutStack.isNotEmpty) {
        for (var lut in clip.color.lutStack) {
          clipNodes.add(LutNode(lutId: lut.id, intensity: lut.intensity));
        }
      }

      // Effects
      if (!request.bypassEffects && clip.effects.isNotEmpty) {
        clipNodes.add(EffectStackNode(clip.effects));
      }

      // Add the clip pipeline to the global graph
      globalNodes.add(ClipPipelineNode(activeClip, RenderGraph(clipNodes)));
    }

    // Final Output transform
    globalNodes.add(OutputTransformNode());

    final graph = RenderGraph(globalNodes);

    try {
      final frame = await graph.execute(context);
      stopwatch.stop();
      
      final result = RenderResult(
        frame: frame,
        diagnostics: context.diagnostics.values.toList(),
        isSuccess: true,
        renderTime: stopwatch.elapsed,
      );

      // Cache the result for live preview or thumbnails
      if (request.target == RenderTarget.livePreview || request.target == RenderTarget.thumbnail) {
        cacheManager.put(cacheKey, result);
      }

      return result;
    } catch (e, st) {
      stopwatch.stop();
      debugPrint('Render failed: $e\\n$st');
      return RenderResult(
        isSuccess: false,
        diagnostics: [RenderDiagnostic('RENDER_EXCEPTION', e.toString())],
        renderTime: stopwatch.elapsed,
      );
    }
  }

  void cancelRequest(RenderRequest request) {
    // Abort rendering job
  }
}
