//
//  RubikScanSession.mm
//  RubikSolver - Any-Order Six-Face Scan Session
//

#import "RubikScanSession.h"
#import "RubikOrientation.h"

#include <algorithm>
#include <array>
#include <cstring>

static NSString* const RubikScanErrorDomain = @"RubikScanSession";

namespace {

RubikColorReading classifyWithBalance(const RubikColorReading& reading,
                                      const RubikWhiteBalance& balance,
                                      const std::array<RubikLabColor, NUM_COLORS>& prototypes,
                                      bool calibrated) {
    float r = reading.r;
    float g = reading.g;
    float b = reading.b;
    if (balance.valid) {
        r = std::min(1.0f, reading.rawR * balance.scaleR);
        g = std::min(1.0f, reading.rawG * balance.scaleG);
        b = std::min(1.0f, reading.rawB * balance.scaleB);
    }
    RubikColorReading result = RubikColorMath::analyze(r, g, b, prototypes, calibrated);
    result.rawR = reading.rawR;
    result.rawG = reading.rawG;
    result.rawB = reading.rawB;
    return result;
}

void rotateBlock(uint8_t* values, int turns) {
    turns = ((turns % 4) + 4) % 4;
    for (int turn = 0; turn < turns; ++turn) {
        uint8_t source[9];
        for (int i = 0; i < 9; ++i) source[i] = values[i];
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 3; ++col) {
                values[col * 3 + (2 - row)] = source[row * 3 + col];
            }
        }
    }
}

void rotateFloatBlock(float* values, int turns) {
    turns = ((turns % 4) + 4) % 4;
    for (int turn = 0; turn < turns; ++turn) {
        float source[9];
        for (int i = 0; i < 9; ++i) source[i] = values[i];
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 3; ++col) {
                values[col * 3 + (2 - row)] = source[row * 3 + col];
            }
        }
    }
}

void rotateBoolBlock(bool* values, int turns) {
    turns = ((turns % 4) + 4) % 4;
    for (int turn = 0; turn < turns; ++turn) {
        bool source[9];
        for (int i = 0; i < 9; ++i) source[i] = values[i];
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 3; ++col) {
                values[col * 3 + (2 - row)] = source[row * 3 + col];
            }
        }
    }
}

NSString* colorLabel(uint8_t color) {
    switch (color) {
        case COLOR_WHITE: return @"white";
        case COLOR_RED: return @"red";
        case COLOR_GREEN: return @"green";
        case COLOR_YELLOW: return @"yellow";
        case COLOR_ORANGE: return @"orange";
        case COLOR_BLUE: return @"blue";
        default: return @"unknown";
    }
}

NSError* scanError(NSString* message) {
    return [NSError errorWithDomain:RubikScanErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

} // namespace

@implementation RubikScanSession {
    RubikScannedFace _faces[6];
    NSUInteger _faceCount;
    int _slots[6];
    uint8_t _facelets[54];
    uint8_t _rawFacelets[54];
    float _confidences[54];
    bool _reliable[54];
    int _rotations[6];
    BOOL _hasCalibration;
    BOOL _orientationRecovered;
    BOOL _manualEdits;
    RubikValidationResult _validation;
    NSString* _statusMessage;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self reset];
    }
    return self;
}

#pragma mark - Accessors

- (NSUInteger)capturedFaceCount { return _faceCount; }
- (BOOL)hasAllFaces { return _faceCount == 6; }
- (BOOL)hasCalibration { return _hasCalibration; }
- (BOOL)orientationRecovered { return _orientationRecovered; }
- (BOOL)manualEdits { return _manualEdits; }
- (BOOL)valid { return _validation.valid; }
- (const uint8_t*)facelets { return _facelets; }
- (const uint8_t*)rawFacelets { return _rawFacelets; }
- (const float*)confidences { return _confidences; }
- (const bool*)reliableFlags { return _reliable; }
- (RubikValidationResult)validation { return _validation; }
- (NSString*)statusMessage { return _statusMessage ?: @""; }

- (void)reset {
    _faceCount = 0;
    _hasCalibration = NO;
    _orientationRecovered = NO;
    _manualEdits = NO;
    std::memset(_faces, 0, sizeof(_faces));
    std::memset(_facelets, 0xFF, sizeof(_facelets));
    std::memset(_rawFacelets, 0xFF, sizeof(_rawFacelets));
    std::memset(_confidences, 0, sizeof(_confidences));
    std::memset(_reliable, 0, sizeof(_reliable));
    std::memset(_rotations, 0, sizeof(_rotations));
    for (int i = 0; i < 6; ++i) _slots[i] = -1;
    _validation = RubikValidationResult{};
    _statusMessage = @"Capture the first face.";
}

#pragma mark - Capture

- (BOOL)addFaceFromReadings:(const std::vector<RubikColorReading>&)readings
                       error:(NSError**)error {
    if (readings.size() != 9) {
        if (error) *error = scanError(@"A face must contain exactly nine sticker readings.");
        return NO;
    }
    if (_faceCount >= 6) {
        if (error) *error = scanError(@"All six faces have already been captured.");
        return NO;
    }

    const RubikColorReading& centre = readings[4];
    if (centre.colorIndex >= NUM_COLORS || centre.background) {
        if (error) {
            *error = scanError(@"The centre sticker could not be identified. Fill the grid with one face and try again.");
        }
        return NO;
    }
    for (NSUInteger i = 0; i < _faceCount; ++i) {
        if (_faces[i].centerColor == centre.colorIndex) {
            if (error) {
                *error = scanError([NSString stringWithFormat:
                    @"The %@ centre has already been captured. Scan a different face.",
                    colorLabel(centre.colorIndex)]);
            }
            return NO;
        }
    }

    RubikScannedFace& face = _faces[_faceCount];
    face.captured = true;
    face.centerColor = centre.colorIndex;
    for (int i = 0; i < 9; ++i) face.readings[i] = readings[i];
    _slots[_faceCount] = centre.colorIndex;
    ++_faceCount;

    _manualEdits = NO;
    [self analyze];
    return YES;
}

- (void)removeLastFace {
    if (_faceCount == 0) return;
    --_faceCount;
    std::memset(&_faces[_faceCount], 0, sizeof(RubikScannedFace));
    _slots[_faceCount] = -1;
    _manualEdits = NO;
    [self analyze];
}

- (void)analyze {
    _orientationRecovered = NO;
    _hasCalibration = NO;
    std::memset(_rotations, 0, sizeof(_rotations));
    _validation = RubikValidationResult{};

    if (_faceCount < 6) {
        _statusMessage = _faceCount == 0
            ? @"Capture the first face."
            : [NSString stringWithFormat:
                @"Captured %lu/6 faces. Scan the next face.", (unsigned long)_faceCount];
        return;
    }

    // 1. Find the white centre. It is the best available white reference.
    RubikWhiteBalance balance;
    for (NSUInteger i = 0; i < 6; ++i) {
        if (_faces[i].centerColor == COLOR_WHITE) {
            const RubikColorReading& centre = _faces[i].readings[4];
            balance = RubikWhiteBalance::fromWhiteReference(centre.rawR, centre.rawG, centre.rawB);
            break;
        }
    }

    // 2. Build colour prototypes from the six centres.
    std::array<RubikColorReading, NUM_COLORS> centers;
    std::array<bool, NUM_COLORS> used{};
    std::array<RubikLabColor, NUM_COLORS> prototypes = RubikColorMath::defaultPrototypes();
    bool centersUsable = true;
    int slotMap[6] = {-1, -1, -1, -1, -1, -1};

    for (NSUInteger i = 0; i < 6; ++i) {
        RubikColorReading balanced = classifyWithBalance(
            _faces[i].readings[4], balance, RubikColorMath::defaultPrototypes(), false);
        if (balanced.colorIndex >= NUM_COLORS || used[balanced.colorIndex]) {
            centersUsable = false;
            break;
        }
        used[balanced.colorIndex] = true;
        centers[balanced.colorIndex] = balanced;
        prototypes[balanced.colorIndex] = balanced.lab;
        slotMap[i] = balanced.colorIndex;
    }

    if (!centersUsable) {
        // Fall back to the centres recorded at capture time, so the review UI
        // still has a complete net to correct manually.
        for (NSUInteger i = 0; i < 6; ++i) slotMap[i] = _slots[i];
        _statusMessage = @"Centre colours are ambiguous under this lighting. Review every sticker before solving.";
    } else {
        _hasCalibration = true;
    }

    // 3. Reclassify every sticker against the calibrated prototypes.
    uint8_t raw[54];
    float confidence[54];
    bool reliable[54];
    std::memset(raw, 0xFF, sizeof(raw));
    std::memset(confidence, 0, sizeof(confidence));
    std::memset(reliable, 0, sizeof(reliable));

    for (NSUInteger i = 0; i < 6; ++i) {
        const int slot = slotMap[i];
        if (slot < 0 || slot >= 6) continue;
        for (int j = 0; j < 9; ++j) {
            RubikColorReading reading = classifyWithBalance(
                _faces[i].readings[j], balance, prototypes, centersUsable);
            const int index = slot * 9 + j;
            raw[index] = reading.colorIndex < NUM_COLORS ? reading.colorIndex : 255;
            confidence[index] = reading.confidence;
            reliable[index] = reading.reliable;
        }
    }

    // Keep the centre stickers pinned to their identified colour: a centre is
    // ground truth for the face, even if one live sample was noisy.
    for (NSUInteger i = 0; i < 6; ++i) {
        if (slotMap[i] >= 0 && slotMap[i] < 6) {
            raw[slotMap[i] * 9 + 4] = static_cast<uint8_t>(slotMap[i]);
            confidence[slotMap[i] * 9 + 4] = 1.0f;
            reliable[slotMap[i] * 9 + 4] = true;
        }
    }

    std::memcpy(_rawFacelets, raw, sizeof(raw));

    // 4. Recover independent per-face rotations.
    RubikOrientationResult oriented = RubikRecoverOrientation(raw);
    if (oriented.success) {
        std::memcpy(_facelets, oriented.facelets, sizeof(_facelets));
        std::memcpy(_confidences, confidence, sizeof(confidence));
        std::memcpy(_reliable, reliable, sizeof(reliable));
        for (int face = 0; face < 6; ++face) {
            _rotations[face] = oriented.rotations[face];
        }
        for (int face = 0; face < 6; ++face) {
            rotateFloatBlock(_confidences + face * 9, oriented.rotations[face]);
            rotateBoolBlock(_reliable + face * 9, oriented.rotations[face]);
        }
        _orientationRecovered = YES;
        _validation = RubikValidateFacelets(_facelets);
        _statusMessage = oriented.ambiguous
            ? @"Scan complete. More than one orientation fits; review the net before solving."
            : @"Scan complete. Review the net, then solve.";
    } else {
        std::memcpy(_facelets, raw, sizeof(_facelets));
        std::memcpy(_confidences, confidence, sizeof(confidence));
        std::memcpy(_reliable, reliable, sizeof(reliable));
        _validation = RubikValidateFacelets(_facelets);
        _statusMessage = @"Automatic orientation failed. Correct the highlighted stickers or rotate faces manually.";
    }
}

#pragma mark - Correction

- (void)setFacelet:(uint8_t)color atIndex:(NSInteger)index {
    if (index < 0 || index >= 54 || color >= NUM_COLORS) return;
    static const NSInteger centreIndices[6] = {4, 13, 22, 31, 40, 49};
    for (NSInteger centre : centreIndices) {
        if (index == centre) return;
    }
    _facelets[index] = color;
    _confidences[index] = 1.0f;
    _reliable[index] = true;
    _manualEdits = YES;
    _validation = RubikValidateFacelets(_facelets);
    _statusMessage = _validation.valid
        ? @"Review complete. The cube is ready to solve."
        : [NSString stringWithFormat:@"Cube is not solvable yet: %s",
                                     _validation.message.c_str()];
}

- (void)rotateFace:(NSInteger)face clockwise:(BOOL)clockwise {
    if (face < 0 || face >= 6) return;
    rotateBlock(_facelets + face * 9, clockwise ? 1 : 3);
    rotateFloatBlock(_confidences + face * 9, clockwise ? 1 : 3);
    rotateBoolBlock(_reliable + face * 9, clockwise ? 1 : 3);
    _manualEdits = YES;
    _validation = RubikValidateFacelets(_facelets);
    _statusMessage = _validation.valid
        ? @"Face rotated. The cube is ready to solve."
        : [NSString stringWithFormat:@"Cube is not solvable yet: %s",
                                     _validation.message.c_str()];
}

#pragma mark - Queries

- (uint8_t)centerColorForCapturedFace:(NSInteger)capturedIndex {
    if (capturedIndex < 0 || capturedIndex >= static_cast<NSInteger>(_faceCount)) return 255;
    return _faces[capturedIndex].centerColor;
}

- (NSInteger)slotForCapturedFace:(NSInteger)capturedIndex {
    if (capturedIndex < 0 || capturedIndex >= static_cast<NSInteger>(_faceCount)) return -1;
    return _slots[capturedIndex];
}

- (NSInteger)rotationForFace:(NSInteger)face {
    if (face < 0 || face >= 6) return 0;
    return _rotations[face];
}

- (NSArray<NSNumber*>*)faceletValues {
    NSMutableArray<NSNumber*>* values = [NSMutableArray arrayWithCapacity:54];
    for (int i = 0; i < 54; ++i) {
        [values addObject:@(_facelets[i])];
    }
    return values;
}

- (RubikCube)cube {
    if (_validation.valid) {
        return RubikCube(_facelets);
    }
    return RubikCube();
}

@end
