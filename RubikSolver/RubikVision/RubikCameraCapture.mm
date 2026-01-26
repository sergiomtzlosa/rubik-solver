//
//  RubikCameraCapture.mm
//  RubikSolver - AVFoundation Camera Capture Session
//

#import "RubikCameraCapture.h"

NSString* const RubikCameraErrorDomain = @"RubikCamera";

static NSError* RubikCameraError(RubikCameraErrorCode code, NSString* message) {
    return [NSError errorWithDomain:RubikCameraErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface RubikCameraCapture () <AVCaptureVideoDataOutputSampleBufferDelegate>
@end

@implementation RubikCameraCapture {
    AVCaptureSession* _session;
    AVCaptureDevice* _device;
    AVCaptureDeviceInput* _input;
    AVCaptureVideoDataOutput* _videoOutput;
    AVCaptureVideoPreviewLayer* _previewLayer;
    dispatch_queue_t _cameraQueue;
    dispatch_queue_t _sessionQueue;
    BOOL _configured;
    BOOL _starting;
    id _runtimeErrorObserver;
    id _interruptionObserver;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cameraQueue = dispatch_queue_create("com.rubik.camera.frames", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.rubik.camera.session", DISPATCH_QUEUE_SERIAL);
        _session = [[AVCaptureSession alloc] init];
        if ([_session canSetSessionPreset:AVCaptureSessionPreset1280x720]) {
            _session.sessionPreset = AVCaptureSessionPreset1280x720;
        } else {
            _session.sessionPreset = AVCaptureSessionPresetHigh;
        }
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
        _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [self observeRuntimeErrors];
    }
    return self;
}

- (void)dealloc {
    NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
    if (_runtimeErrorObserver) [center removeObserver:_runtimeErrorObserver];
    if (_interruptionObserver) [center removeObserver:_interruptionObserver];
    if (_session.isRunning) [_session stopRunning];
}

- (BOOL)isRunning {
    return _session.isRunning;
}

- (AVCaptureVideoPreviewLayer*)previewLayer {
    return _previewLayer;
}

- (NSString*)deviceName {
    return _device.localizedName;
}

- (BOOL)hasDevice {
    return _device != nil;
}

#pragma mark - Authorization

+ (AVAuthorizationStatus)authorizationStatus {
    return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
}

+ (void)requestAuthorization:(void (^)(BOOL))completion {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(granted);
        });
    }];
}

#pragma mark - Session setup

- (void)observeRuntimeErrors {
    __weak __typeof__(self) weakSelf = self;
    _runtimeErrorObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVCaptureSessionRuntimeErrorNotification
                    object:_session
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
        NSError* error = note.userInfo[AVCaptureSessionErrorKey];
        [weakSelf deliverError:error ?: RubikCameraError(RubikCameraErrorRuntime,
                                                         @"The camera stopped unexpectedly.")];
    }];
    _interruptionObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVCaptureSessionWasInterruptedNotification
                    object:_session
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification* note) {
        if ([weakSelf.delegate respondsToSelector:@selector(cameraCaptureDidChangeRunning:)]) {
            [weakSelf.delegate cameraCaptureDidChangeRunning:NO];
        }
    }];
}

- (AVCaptureDevice*)discoverDevice {
    AVCaptureDeviceDiscoverySession* discovery = [AVCaptureDeviceDiscoverySession
        discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera,
                                          AVCaptureDeviceTypeExternal,
                                          AVCaptureDeviceTypeContinuityCamera]
                              mediaType:AVMediaTypeVideo
                               position:AVCaptureDevicePositionUnspecified];
    AVCaptureDevice* device = discovery.devices.firstObject;
    if (!device) {
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    return device;
}

/// Must be called on `_sessionQueue`.
- (NSError*)configureSessionIfNeeded {
    if (_configured) return nil;

    _device = [self discoverDevice];
    if (!_device) {
        return RubikCameraError(RubikCameraErrorNoDevice,
                                @"No camera was found. Connect a webcam and try again.");
    }

    NSError* inputError = nil;
    _input = [AVCaptureDeviceInput deviceInputWithDevice:_device error:&inputError];
    if (!_input) {
        return inputError ?: RubikCameraError(RubikCameraErrorConfiguration,
                                              @"The camera could not be opened.");
    }

    [_session beginConfiguration];
    if ([_session canAddInput:_input]) {
        [_session addInput:_input];
    } else {
        [_session commitConfiguration];
        return RubikCameraError(RubikCameraErrorConfiguration,
                                @"The camera input could not be added.");
    }

    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    _videoOutput.videoSettings = @{
        (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    [_videoOutput setSampleBufferDelegate:self queue:_cameraQueue];

    if ([_session canAddOutput:_videoOutput]) {
        [_session addOutput:_videoOutput];
    } else {
        [_session commitConfiguration];
        return RubikCameraError(RubikCameraErrorConfiguration,
                                @"The camera video output could not be added.");
    }
    [_session commitConfiguration];

    _configured = YES;
    return nil;
}

#pragma mark - Start / stop

- (void)startCameraCaptureWithCompletion:(void (^ _Nullable)(BOOL, NSError* _Nullable))completion {
    void (^finish)(BOOL, NSError*) = ^(BOOL started, NSError* error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(started, error);
        });
    };

    const AVAuthorizationStatus status = [RubikCameraCapture authorizationStatus];
    if ([NSProcessInfo.processInfo.environment[@"RUBIK_DISABLE_CAMERA"] isEqualToString:@"1"]) {
        finish(NO, RubikCameraError(RubikCameraErrorNoDevice,
            @"Camera capture is disabled for this UI test."));
        return;
    }
    if (status == AVAuthorizationStatusDenied ||
        status == AVAuthorizationStatusRestricted) {
        finish(NO, RubikCameraError(RubikCameraErrorPermissionDenied,
            @"Camera access is denied. Enable it in System Settings > Privacy & Security > Camera."));
        return;
    }

    if (status == AVAuthorizationStatusNotDetermined) {
        __weak __typeof__(self) weakSelf = self;
        [RubikCameraCapture requestAuthorization:^(BOOL granted) {
            if (!granted) {
                finish(NO, RubikCameraError(RubikCameraErrorPermissionDenied,
                    @"Camera access was not granted."));
                return;
            }
            [weakSelf startCameraCaptureWithCompletion:completion];
        }];
        return;
    }

    dispatch_async(_sessionQueue, ^{
        if (self->_session.isRunning) {
            self->_starting = NO;
            finish(YES, nil);
            return;
        }
        if (self->_starting) {
            // A start is already in flight; report the eventual state instead
            // of racing two startRunning calls.
            finish(self->_session.isRunning, nil);
            return;
        }
        self->_starting = YES;

        NSError* configError = [self configureSessionIfNeeded];
        if (configError) {
            self->_starting = NO;
            finish(NO, configError);
            return;
        }

        [self->_session startRunning];
        self->_starting = NO;
        const BOOL running = self->_session.isRunning;
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(cameraCaptureDidChangeRunning:)]) {
                [self.delegate cameraCaptureDidChangeRunning:running];
            }
            if (!running) {
                [self deliverError:RubikCameraError(RubikCameraErrorRuntime,
                                                    @"The camera session did not start.")];
            }
        });
        finish(running, running ? nil : RubikCameraError(RubikCameraErrorRuntime,
                                                          @"The camera session did not start."));
    });
}

- (BOOL)startCameraCapture {
    [self startCameraCaptureWithCompletion:nil];
    return self.isRunning;
}

- (void)stopCameraCapture {
    dispatch_async(_sessionQueue, ^{
        if (self->_session.isRunning) {
            [self->_session stopRunning];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(cameraCaptureDidChangeRunning:)]) {
                [self.delegate cameraCaptureDidChangeRunning:NO];
            }
        });
    });
}

- (void)deliverError:(NSError*)error {
    if ([self.delegate respondsToSelector:@selector(cameraCaptureDidFailWithError:)]) {
        [self.delegate cameraCaptureDidFailWithError:error];
    }
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput*)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection*)connection {
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer && [self.delegate respondsToSelector:@selector(cameraCaptureDidOutputPixelBuffer:)]) {
        [self.delegate cameraCaptureDidOutputPixelBuffer:imageBuffer];
    }
}

@end
