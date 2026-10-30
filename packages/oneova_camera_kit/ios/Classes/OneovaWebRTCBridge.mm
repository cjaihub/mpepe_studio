#import "OneovaWebRTCBridge.h"

#import <flutter_webrtc/FlutterWebRTCPlugin.h>
#import <flutter_webrtc/LocalVideoTrack.h>

@interface OneovaFrameProcessor : NSObject <ExternalVideoProcessingDelegate>
@property(nonatomic, copy) OneovaFrameHandler handler;
@end

@implementation OneovaFrameProcessor
- (RTCVideoFrame*)onFrame:(RTCVideoFrame*)frame {
  return self.handler(frame);
}
@end

@implementation OneovaWebRTCBridge

+ (LocalVideoTrack*)videoTrack:(NSString*)trackId {
  id<LocalTrack> track = [FlutterWebRTCPlugin sharedSingleton].localTracks[trackId];
  if (![track isKindOfClass:[LocalVideoTrack class]]) return nil;
  LocalVideoTrack* video = (LocalVideoTrack*)track;
  // Only camera tracks own a VideoProcessingAdapter.
  return video.processing != nil ? video : nil;
}

+ (id)addProcessorToTrack:(NSString*)trackId handler:(OneovaFrameHandler)handler {
  LocalVideoTrack* track = [self videoTrack:trackId];
  if (track == nil) return nil;
  OneovaFrameProcessor* processor = [OneovaFrameProcessor new];
  processor.handler = handler;
  [track addProcessing:processor];
  return processor;
}

+ (void)removeProcessor:(id)token fromTrack:(NSString*)trackId {
  // The adapter takes its frame lock here, so an in-flight frame finishes first.
  [[self videoTrack:trackId] removeProcessing:(OneovaFrameProcessor*)token];
}

@end
