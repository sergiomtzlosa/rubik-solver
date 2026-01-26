//
//  RubikColorClassifier.h
//  RubikSolver - Real-Time Rubik Facelet Color Recognition
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreVideo/CoreVideo.h>
#include "RubikTypes.h"
#include "RubikColorMath.h"
#include <vector>

/// One classified sticker. `colorIndex` is 255 when the sample was rejected
/// as background or was too ambiguous to classify safely.
struct SampledPatch {
    uint8_t colorIndex = 255;
    float r = 0, g = 0, b = 0;
    float h = 0, s = 0, v = 0;
    float labL = 0, labA = 0, labB = 0;
    float confidence = 0;
    bool reliable = false;
    bool background = false;
};

@interface RubikColorClassifier : NSObject

/// Classifies the 3x3 grid from a camera frame. `roi` is normalized to the
/// pixel buffer with a top-left origin (row 0 is the top of the image).
- (std::vector<SampledPatch>)classifyGridFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                              normalizedROI:(CGRect)roi;

/// Full colour readings (Lab, confidence, white balance) for a camera frame.
- (std::vector<RubikColorReading>)readingsFromPixelBuffer:(CVPixelBufferRef)pixelBuffer
                                             normalizedROI:(CGRect)roi;

- (std::vector<SampledPatch>)classifyGridFromImage:(NSImage*)image
                                     normalizedROI:(CGRect)roi;

- (std::vector<SampledPatch>)classifyGridFromCGImage:(CGImageRef)cgImage
                                       normalizedROI:(CGRect)roi;

/// Re-classify a set of readings with centre-calibrated prototypes.
- (std::vector<SampledPatch>)classifyReadings:(const std::vector<RubikColorReading>&)readings
                              withPrototypes:(const std::array<RubikLabColor, NUM_COLORS>&)prototypes
                        calibratedPrototypes:(BOOL)calibrated;

+ (NSColor*)nsColorForIndex:(uint8_t)colorIndex;
+ (NSString*)colorNameForIndex:(uint8_t)colorIndex;

@end
