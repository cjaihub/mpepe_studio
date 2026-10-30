#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

NS_ASSUME_NONNULL_BEGIN

typedef RTCVideoFrame* _Nonnull (^OneovaFrameHandler)(RTCVideoFrame* frame);

/// Installs frame processors on flutter_webrtc local video tracks. Kept in
/// Objective-C++ so Swift never imports flutter_webrtc's C++ headers.
@interface OneovaWebRTCBridge : NSObject

/// Returns a token for removeProcessor, or nil when trackId is not a local
/// camera track with a processing adapter. Call on the main thread.
+ (nullable id)addProcessorToTrack:(NSString*)trackId handler:(OneovaFrameHandler)handler;

/// Once this returns no frame is still inside the handler.
+ (void)removeProcessor:(id)token fromTrack:(NSString*)trackId;

@end

NS_ASSUME_NONNULL_END
