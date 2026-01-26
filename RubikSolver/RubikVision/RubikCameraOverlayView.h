//
//  RubikCameraOverlayView.h
//  RubikSolver - Camera Viewfinder HUD & 6-Face Scanner
//

#import <AppKit/AppKit.h>
#import "RubikCameraCapture.h"
#import "RubikColorClassifier.h"

#if __has_include("../RubikCore/RubikCube.h")
#include "../RubikCore/RubikCube.h"
#else
#include "RubikCube.h"
#endif

@class RubikScanSession;

@protocol RubikCameraOverlayDelegate <NSObject>
- (void)cameraOverlayDidFinishAllFaces:(const RubikCube&)cube;
- (void)cameraOverlayDidCancel;
@end

@interface RubikCameraOverlayView : NSView <RubikCameraCaptureDelegate>

@property (nonatomic, weak) id<RubikCameraOverlayDelegate> delegate;
@property (nonatomic, readonly) RubikCameraCapture* cameraCapture;
@property (nonatomic, readonly) RubikScanSession* scanSession;
@property (nonatomic, readonly) NSUInteger currentFaceIndex;
@property (nonatomic, readonly) BOOL reviewVisible;

- (instancetype)initWithFrame:(NSRect)frameRect;
- (void)startScanning;
- (void)stopScanning;
- (void)resetScan;
- (void)captureCurrentFace;

/// Test hook: inject a face reading without a live camera.
- (BOOL)addSyntheticFaceReadings:(const std::vector<RubikColorReading>&)readings;

@end
