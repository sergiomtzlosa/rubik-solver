//
//  RubikScanSession.h
//  RubikSolver - Any-Order Six-Face Scan Session
//
//  Captures six faces in any order, identifies each face by its centre
//  sticker, reclassifies every sticker against centre-calibrated CIELAB
//  prototypes, recovers face rotations, and validates the final cube.
//

#import <Foundation/Foundation.h>

#include "RubikColorMath.h"
#include "RubikValidation.h"

#include <array>
#include <vector>

struct RubikScannedFace {
    std::array<RubikColorReading, 9> readings;
    uint8_t centerColor = 255;
    bool captured = false;
};

@interface RubikScanSession : NSObject

@property (nonatomic, readonly) NSUInteger capturedFaceCount;
@property (nonatomic, readonly) BOOL hasAllFaces;
@property (nonatomic, readonly) BOOL hasCalibration;
@property (nonatomic, readonly) BOOL orientationRecovered;
@property (nonatomic, readonly) BOOL manualEdits;
@property (nonatomic, readonly) BOOL valid;

/// Final 54 facelets in U, R, F, D, L, B order (orientation-corrected when
/// recovery succeeded, otherwise the raw captured layout).
@property (nonatomic, readonly) const uint8_t* facelets;

/// The captured layout before rotation recovery, useful for review UI.
@property (nonatomic, readonly) const uint8_t* rawFacelets;

/// Confidence and reliability for each of the 54 final facelets.
@property (nonatomic, readonly) const float* confidences;
@property (nonatomic, readonly) const bool* reliableFlags;

@property (nonatomic, readonly) RubikValidationResult validation;
@property (nonatomic, readonly) NSString* statusMessage;

- (BOOL)addFaceFromReadings:(const std::vector<RubikColorReading>&)readings
                       error:(NSError**)error;
- (void)removeLastFace;
- (void)reset;

/// Correct one sticker in the final facelet array. Centre indices are ignored.
- (void)setFacelet:(uint8_t)color atIndex:(NSInteger)index;

/// Rotate one final face by a quarter turn. Handy when automatic orientation
/// recovery could not produce a valid state.
- (void)rotateFace:(NSInteger)face clockwise:(BOOL)clockwise;

- (uint8_t)centerColorForCapturedFace:(NSInteger)capturedIndex;
- (NSInteger)slotForCapturedFace:(NSInteger)capturedIndex;
- (NSInteger)rotationForFace:(NSInteger)face;
- (NSArray<NSNumber*>*)faceletValues;
- (RubikCube)cube;

@end
