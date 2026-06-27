//
//  RubikCameraCapture.h
//  RubikSolver - AVFoundation Camera Capture Session
//

#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol RubikCameraCaptureDelegate <NSObject>
@optional
/// Called on the camera queue. The pixel buffer is only valid for the
/// duration of the call.
- (void)cameraCaptureDidOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer;
/// Called on the main queue.
- (void)cameraCaptureDidFailWithError:(NSError*)error;
/// Called on the main queue after the session starts or stops.
- (void)cameraCaptureDidChangeRunning:(BOOL)running;
@end

extern NSString* const RubikCameraErrorDomain;

typedef NS_ENUM(NSInteger, RubikCameraErrorCode) {
    RubikCameraErrorPermissionDenied = -1001,
    RubikCameraErrorNoDevice = -1002,
    RubikCameraErrorConfiguration = -1003,
    RubikCameraErrorRuntime = -1004,
};

@interface RubikCameraCapture : NSObject

@property (nonatomic, weak, nullable) id<RubikCameraCaptureDelegate> delegate;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly, nullable) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, readonly, nullable) NSString* deviceName;
@property (nonatomic, readonly) BOOL hasDevice;

- (instancetype)init;

/// Request permission if needed, configure the session, and start it on a
/// background queue. The completion is called on the main queue.
- (void)startCameraCaptureWithCompletion:(void (^ _Nullable)(BOOL started, NSError* _Nullable error))completion;

/// Legacy fire-and-forget start. Prefer the completion API.
- (BOOL)startCameraCapture;

- (void)stopCameraCapture;

+ (AVAuthorizationStatus)authorizationStatus;
+ (void)requestAuthorization:(void (^)(BOOL granted))completion;

@end

NS_ASSUME_NONNULL_END
