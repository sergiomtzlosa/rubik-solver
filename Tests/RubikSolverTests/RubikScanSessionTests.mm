//
//  RubikScanSessionTests.mm
//  RubikSolverTests - Any-Order Six-Face Scan Session
//

#import <XCTest/XCTest.h>

#import "RubikScanSession.h"

#include "RubikCube.h"
#include "RubikOrientation.h"
#include "RubikTypes.h"

#include <array>
#include <cstring>
#include <vector>

namespace {

constexpr float kIdealRGB[NUM_COLORS][3] = {
    {0.94f, 0.94f, 0.93f}, // white
    {0.78f, 0.12f, 0.16f}, // red
    {0.04f, 0.62f, 0.28f}, // green
    {0.96f, 0.82f, 0.09f}, // yellow
    {0.94f, 0.43f, 0.06f}, // orange
    {0.05f, 0.32f, 0.72f}, // blue
};

RubikColorReading IdealReading(uint8_t color) {
    return RubikColorMath::analyze(kIdealRGB[color][0],
                                   kIdealRGB[color][1],
                                   kIdealRGB[color][2]);
}

std::vector<RubikColorReading> ReadingsForFace(const RubikCube& cube,
                                               int face,
                                               int rotation) {
    uint8_t facelets[54];
    std::memcpy(facelets, cube.getFacelets(), sizeof(facelets));
    RubikRotateFaceClockwise(facelets, face, rotation);

    std::vector<RubikColorReading> readings;
    readings.reserve(9);
    for (int i = 0; i < 9; ++i) {
        readings.push_back(IdealReading(facelets[face * 9 + i]));
    }
    return readings;
}

RubikCube TestScramble() {
    RubikCube cube;
    cube.applyAlgorithm("R U R' U' F2 L D' B2 R' U2 L' B D2 F' R2 U' B'");
    return cube;
}

} // namespace

@interface RubikScanSessionTests : XCTestCase
@end

@implementation RubikScanSessionTests

- (void)testNewSessionStartsEmpty {
    RubikScanSession* session = [[RubikScanSession alloc] init];
    XCTAssertEqual(session.capturedFaceCount, 0u);
    XCTAssertFalse(session.hasAllFaces);
    XCTAssertFalse(session.hasCalibration);
    XCTAssertFalse(session.orientationRecovered);
    XCTAssertFalse(session.manualEdits);
    XCTAssertFalse(session.valid);
    XCTAssertTrue([session.statusMessage containsString:@"Capture the first face"]);
    XCTAssertEqual([session faceletValues].count, 54u);
}

- (void)testPartialScanTracksProgressAndSupportsUndo {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];
    NSError* error = nil;

    XCTAssertTrue([session addFaceFromReadings:ReadingsForFace(cube, FACE_U, 0) error:&error],
                  @"%@", error);
    XCTAssertEqual(session.capturedFaceCount, 1u);
    XCTAssertFalse(session.hasAllFaces);
    XCTAssertTrue([session.statusMessage containsString:@"1/6"]);

    [session removeLastFace];
    XCTAssertEqual(session.capturedFaceCount, 0u);
    XCTAssertTrue([session.statusMessage containsString:@"Capture the first face"]);
}

- (void)testDuplicateCentreIsRejected {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];
    NSError* error = nil;

    XCTAssertTrue([session addFaceFromReadings:ReadingsForFace(cube, FACE_U, 0) error:&error]);
    XCTAssertFalse([session addFaceFromReadings:ReadingsForFace(cube, FACE_U, 0) error:&error]);
    XCTAssertNotNil(error);
    XCTAssertTrue([error.localizedDescription containsString:@"already been captured"]);
    XCTAssertEqual(session.capturedFaceCount, 1u);
}

- (void)testMalformedFaceIsRejected {
    RubikScanSession* session = [[RubikScanSession alloc] init];
    NSError* error = nil;

    std::vector<RubikColorReading> eight(8, IdealReading(COLOR_WHITE));
    XCTAssertFalse([session addFaceFromReadings:eight error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"nine"]);

    std::vector<RubikColorReading> nine(9, IdealReading(COLOR_RED));
    nine[4] = RubikColorMath::analyze(0.001f, 0.001f, 0.001f);
    error = nil;
    XCTAssertFalse([session addFaceFromReadings:nine error:&error]);
    XCTAssertTrue([error.localizedDescription containsString:@"centre"]);
    XCTAssertEqual(session.capturedFaceCount, 0u);
}

- (void)testAnyOrderRotatedScanRecoversTheCube {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];

    const int order[6] = {FACE_D, FACE_U, FACE_B, FACE_R, FACE_L, FACE_F};
    const int rotations[6] = {1, 0, 3, 2, 1, 0};

    for (int captured = 0; captured < 6; ++captured) {
        const int face = order[captured];
        NSError* error = nil;
        XCTAssertTrue([session addFaceFromReadings:ReadingsForFace(cube, face, rotations[face])
                                            error:&error],
                      @"face %d: %@", face, error);
        XCTAssertEqual([session centerColorForCapturedFace:captured], (uint8_t)face);
        XCTAssertEqual([session slotForCapturedFace:captured], face);
    }

    XCTAssertEqual(session.capturedFaceCount, 6u);
    XCTAssertTrue(session.hasAllFaces);
    XCTAssertTrue(session.hasCalibration);
    XCTAssertTrue(session.orientationRecovered);
    XCTAssertTrue(session.valid, @"%@", session.statusMessage);
    XCTAssertTrue([session.statusMessage containsString:@"Scan complete"]);

    XCTAssertEqual(std::memcmp(session.facelets, cube.getFacelets(), 54), 0);
    RubikCube scanned = [session cube];
    XCTAssertEqualObjects([NSString stringWithUTF8String:scanned.toFaceletString().c_str()],
                          [NSString stringWithUTF8String:cube.toFaceletString().c_str()]);

    for (int face = 0; face < 6; ++face) {
        XCTAssertEqualWithAccuracy(session.confidences[face * 9 + 4], 1.0f, 0.0001f);
        XCTAssertTrue(session.reliableFlags[face * 9 + 4]);
        XCTAssertGreaterThan(session.confidences[face * 9 + 1], 0.0f);
        XCTAssertTrue(session.reliableFlags[face * 9 + 1]);
    }

    // Applying the recovered rotations to the raw capture reproduces the
    // orientation-corrected facelets.
    uint8_t reconstructed[54];
    std::memcpy(reconstructed, session.rawFacelets, sizeof(reconstructed));
    for (int face = 0; face < 6; ++face) {
        RubikRotateFaceClockwise(reconstructed, face, (int)[session rotationForFace:face]);
    }
    XCTAssertEqual(std::memcmp(reconstructed, session.facelets, 54), 0);
}

- (void)testMissingStickerDisablesOrientationRecovery {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];

    for (int face = 0; face < 6; ++face) {
        std::vector<RubikColorReading> readings = ReadingsForFace(cube, face, 0);
        if (face == FACE_F) {
            readings[0] = RubikColorMath::analyze(0.001f, 0.001f, 0.001f);
        }
        NSError* error = nil;
        XCTAssertTrue([session addFaceFromReadings:readings error:&error], @"%@", error);
    }

    XCTAssertTrue(session.hasAllFaces);
    XCTAssertFalse(session.orientationRecovered);
    XCTAssertFalse(session.valid);
    XCTAssertFalse(session.manualEdits);
    XCTAssertTrue([session.statusMessage containsString:@"Automatic orientation failed"],
                  @"%@", session.statusMessage);
}

- (void)testManualCorrectionRestoresValidity {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];

    for (int face = 0; face < 6; ++face) {
        NSError* error = nil;
        XCTAssertTrue([session addFaceFromReadings:ReadingsForFace(cube, face, 0) error:&error],
                      @"%@", error);
    }
    XCTAssertTrue(session.valid);

    const uint8_t original = session.facelets[0];
    const uint8_t replacement = original == COLOR_BLUE ? COLOR_RED : COLOR_BLUE;
    [session setFacelet:replacement atIndex:0];
    XCTAssertTrue(session.manualEdits);
    XCTAssertFalse(session.valid);
    XCTAssertTrue([session.statusMessage containsString:@"not solvable"]);

    [session setFacelet:original atIndex:0];
    XCTAssertTrue(session.valid);
    XCTAssertTrue([session.statusMessage containsString:@"ready to solve"]);

    // Centre stickers are fixed ground truth and cannot be edited.
    const uint8_t centre = session.facelets[4];
    [session setFacelet:COLOR_RED atIndex:4];
    XCTAssertEqual(session.facelets[4], centre);

    // Rotating a face breaks a valid state; rotating it back repairs it.
    [session rotateFace:FACE_U clockwise:YES];
    XCTAssertTrue(session.manualEdits);
    XCTAssertFalse(session.valid);
    [session rotateFace:FACE_U clockwise:NO];
    XCTAssertTrue(session.valid);
}

- (void)testResetClearsEverything {
    RubikCube cube = TestScramble();
    RubikScanSession* session = [[RubikScanSession alloc] init];
    NSError* error = nil;
    XCTAssertTrue([session addFaceFromReadings:ReadingsForFace(cube, FACE_U, 0) error:&error]);
    [session reset];

    XCTAssertEqual(session.capturedFaceCount, 0u);
    XCTAssertFalse(session.hasCalibration);
    XCTAssertFalse(session.orientationRecovered);
    XCTAssertFalse(session.manualEdits);
    XCTAssertFalse(session.valid);
    XCTAssertEqual([session centerColorForCapturedFace:0], 255);
    XCTAssertEqual([session slotForCapturedFace:0], -1);
}

@end
