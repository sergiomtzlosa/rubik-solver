//
//  RubikSolverEngineTests.mm
//  RubikSolverTests
//

#import <XCTest/XCTest.h>

#include "RubikCube.h"
#include "RubikOrientation.h"
#include "RubikSolveResult.h"
#include "RubikSolverEngine.h"
#include "RubikValidation.h"

#include <atomic>
#include <cstring>
#include <filesystem>
#include <random>
#include <thread>
#include <unistd.h>
#include <utility>
#include <vector>

static void CopyFacelets(const RubikCube& cube, uint8_t out[54]) {
    for (int i = 0; i < 54; ++i) {
        out[i] = cube.getFacelet(i);
    }
}

static RubikCube DeterministicScramble(std::mt19937& rng, int length) {
    RubikCube cube;
    std::uniform_int_distribution<int> faceDist(0, 5);
    std::uniform_int_distribution<int> suffixDist(0, 2);

    int lastFace = -1;
    for (int i = 0; i < length; ++i) {
        int face = faceDist(rng);
        while (face == lastFace) {
            face = faceDist(rng);
        }
        cube.applyMove(face * 3 + suffixDist(rng));
        lastFace = face;
    }
    return cube;
}

static NSString* TestCacheDir(NSString* suffix) {
    return [NSString stringWithFormat:@"/private/tmp/rubik-tests-%@-%d",
            suffix, (int)getpid()];
}

@interface RubikSolverEngineTests : XCTestCase
@end

@implementation RubikSolverEngineTests

#pragma mark - Validation

- (void)testValidSolvedCube {
    RubikCube cube;
    RubikValidationResult validation = RubikValidateCube(cube);
    XCTAssertTrue(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::Valid);
    XCTAssertFalse(validation.message.empty());
}

- (void)testColorCountIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    facelets[0] = 1; // U face now has eight U stickers and ten R stickers.

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::ColorCount);
}

- (void)testDuplicateCentersAreRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    facelets[4] = 1;  // U center becomes R
    facelets[13] = 0; // R center becomes U

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::CenterColor);
}

- (void)testDuplicateEdgeIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    // Copy the UF edge's F sticker onto the UR edge, then rebalance the color
    // counts on a corner sticker so this fixture exercises edge existence
    // rather than the color-count check.
    facelets[10] = facelets[19]; // R2 -> F
    facelets[26] = 1;            // F9 -> R

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::EdgeExistence);
}

- (void)testFlippedEdgeIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    std::swap(facelets[7], facelets[19]); // UF edge stickers

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::EdgeFlip);
}

- (void)testDuplicateCornerIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    // Copy UFR (U9, R1, F3) onto URB (U3, B1, R3), then rebalance the color
    // counts on another corner sticker.
    facelets[2] = facelets[8];
    facelets[45] = facelets[9];
    facelets[11] = facelets[20];
    facelets[24] = 5; // F7 -> B

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::CornerExistence);
}

- (void)testTwistedCornerIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    // Rotate the three stickers of UFR (U9, R1, F3).
    uint8_t a = facelets[8];
    facelets[8] = facelets[9];
    facelets[9] = facelets[20];
    facelets[20] = a;

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::CornerTwist);
}

- (void)testParityErrorIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    // Swap the complete UF and UR edge pieces.
    std::swap(facelets[5], facelets[7]);
    std::swap(facelets[10], facelets[19]);

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::Parity);
}

- (void)testOutOfRangeFaceletIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    facelets[0] = 6;

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::Unknown);
}

#pragma mark - Exact solver

- (void)testAlreadySolvedIsNotAFailure {
    RubikCube cube;
    RubikSolverEngine engine(TestCacheDir(@"already-solved").UTF8String);
    RubikSolverOptions options;
    options.timeoutSeconds = 20;

    RubikSolveResult result = engine.solveExact(cube, options);
    XCTAssertEqual(result.status, RubikSolveStatus::AlreadySolved);
    XCTAssertTrue(result.alreadySolved);
    XCTAssertTrue(result.moves.empty());
    XCTAssertTrue(result.verified);
}

- (void)testInvalidStateReturnsInvalidNotAlreadySolved {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    std::swap(facelets[7], facelets[19]); // single flipped edge

    RubikSolverEngine engine(TestCacheDir(@"invalid").UTF8String);
    RubikSolveResult result = engine.solveExact(RubikCube(facelets), RubikSolverOptions());

    XCTAssertEqual(result.status, RubikSolveStatus::InvalidState);
    XCTAssertEqual(result.validation.code, RubikValidationCode::EdgeFlip);
    XCTAssertFalse(result.alreadySolved);
    XCTAssertFalse(result.verified);
    XCTAssertTrue(result.moves.empty());
}

- (void)testOneHundredScramblesAreSolvedAndReplayed {
    RubikSolverEngine engine(TestCacheDir(@"hundred").UTF8String);
    RubikSolverOptions options;
    options.timeoutSeconds = 30;
    options.verify = true;
    options.simplify = true;

    std::mt19937 rng(20261110u);
    for (int i = 0; i < 100; ++i) {
        RubikCube cube = DeterministicScramble(rng, 20 + (i % 10));
        XCTAssertFalse(cube.isSolved());

        RubikSolveResult result = engine.solveExact(cube, options);
        XCTAssertEqual(result.status, RubikSolveStatus::Success,
                       @"Scramble %d failed: %s", i, result.message.c_str());
        XCTAssertTrue(result.verified, @"Scramble %d was not verified", i);

        RubikCube replay = cube;
        replay.applyMoves(result.moves);
        XCTAssertTrue(replay.isSolved(), @"Scramble %d replay did not solve", i);
    }
}

- (void)testCancellationStopsTheSolver {
    RubikSolverEngine engine(TestCacheDir(@"cancel").UTF8String);
    RubikSolverOptions options;
    options.timeoutSeconds = 30;

    // Warm the pruning tables so cancellation lands in the search loop rather
    // than during one-time table generation.
    std::mt19937 warmup(7u);
    XCTAssertEqual(engine.solveExact(DeterministicScramble(warmup, 20), options).status,
                   RubikSolveStatus::Success);

    std::mt19937 rng(99u);
    RubikCube cube = DeterministicScramble(rng, 40);

    std::atomic<bool> stop{false};
    std::thread canceller([&]() {
        while (!stop.load()) {
            engine.cancel();
            std::this_thread::yield();
        }
    });

    RubikSolveResult result = engine.solveExact(cube, options);
    stop.store(true);
    canceller.join();

    XCTAssertEqual(result.status, RubikSolveStatus::Cancelled);
    XCTAssertFalse(result.verified);
    XCTAssertTrue(result.moves.empty());
}

- (void)testConcurrentSolveReturnsBusy {
    RubikSolverEngine engine(TestCacheDir(@"busy").UTF8String);
    RubikSolverOptions options;
    options.timeoutSeconds = 30;

    std::mt19937 rng(4242u);
    RubikCube cube = DeterministicScramble(rng, 40);

    for (int attempt = 0; attempt < 20; ++attempt) {
        std::atomic<bool> finished{false};
        std::thread worker([&]() {
            engine.solveExact(cube, options);
            finished.store(true);
        });

        while (!engine.isSolving() && !finished.load()) {
            std::this_thread::yield();
        }

        if (engine.isSolving()) {
            RubikSolveResult busy = engine.solveExact(cube, options);
            XCTAssertEqual(busy.status, RubikSolveStatus::Busy);
            worker.join();
            return;
        }

        worker.join();
    }

    XCTFail(@"Could not observe a running solve to exercise the Busy path");
}

- (void)testSecondSolverInstanceReusesTheSameCache {
    NSString* cacheDir = TestCacheDir(@"cache");
    std::filesystem::create_directories(cacheDir.UTF8String);

    std::mt19937 rng(123u);
    RubikCube cube = DeterministicScramble(rng, 20);

    RubikSolverOptions options;
    options.timeoutSeconds = 30;

    RubikSolveResult first;
    {
        RubikSolverEngine engine(cacheDir.UTF8String);
        first = engine.solveExact(cube, options);
    }
    XCTAssertEqual(first.status, RubikSolveStatus::Success);

    RubikSolverEngine second(cacheDir.UTF8String);
    RubikSolveResult again = second.solveExact(cube, options);
    XCTAssertEqual(again.status, RubikSolveStatus::Success);
    XCTAssertTrue(again.verified);
    XCTAssertTrue(std::filesystem::exists(cacheDir.UTF8String));
}

#pragma mark - Orientation

- (void)testOrientationRecoversEveryRotatedFace {
    RubikCube scrambled;
    scrambled.applyAlgorithm("R U R' U' F2 L D' B2 R' U2 F' L2");

    for (int face = 0; face < 6; ++face) {
        uint8_t rotated[54];
        CopyFacelets(scrambled, rotated);
        RubikRotateFaceClockwise(rotated, face, 1 + face % 3);

        RubikOrientationResult result = RubikRecoverOrientation(rotated);
        XCTAssertTrue(result.success, @"Face %d: %s", face, result.message.c_str());
        for (int i = 0; i < 54; ++i) {
            XCTAssertEqual(result.facelets[i], scrambled.getFacelet(i),
                           @"Face %d mismatch at %d", face, i);
        }
    }
}

- (void)testSolvedCubeIsNotAmbiguous {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);

    RubikOrientationResult result = RubikRecoverOrientation(facelets);
    XCTAssertTrue(result.success);
    XCTAssertFalse(result.ambiguous);
    XCTAssertEqual(result.validCandidates, 4096);
    for (int i = 0; i < 54; ++i) {
        XCTAssertEqual(result.facelets[i], cube.getFacelet(i));
    }
}

- (void)testOrientationRejectsBadColorCounts {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    facelets[0] = 1;

    RubikOrientationResult result = RubikRecoverOrientation(facelets);
    XCTAssertFalse(result.success);
    XCTAssertTrue(result.ambiguous == false);
}

- (void)testOrientationRejectsDuplicateCenters {
    RubikCube cube;
    uint8_t facelets[54];
    CopyFacelets(cube, facelets);
    facelets[4] = 1;
    facelets[13] = 0;

    RubikOrientationResult result = RubikRecoverOrientation(facelets);
    XCTAssertFalse(result.success);
}

@end
