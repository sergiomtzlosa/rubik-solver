//
//  RubikCoreSmokeTests.mm
//  RubikSolverTests
//

#import <XCTest/XCTest.h>

#include "RubikCube.h"
#include "RubikOrientation.h"
#include "RubikSolverEngine.h"
#include "RubikValidation.h"

@interface RubikCoreSmokeTests : XCTestCase
@end

@implementation RubikCoreSmokeTests

- (void)testSolvedCubeValidatesAndReportsAlreadySolved {
    RubikCube cube;
    XCTAssertTrue(cube.isSolved());

    RubikValidationResult validation = RubikValidateCube(cube);
    XCTAssertTrue(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::Valid);

    RubikSolverEngine engine("/private/tmp/rubik-tests-cache");
    RubikSolverOptions options;
    options.timeoutSeconds = 20;
    RubikSolveResult result = engine.solveExact(cube, options);
    XCTAssertEqual(result.status, RubikSolveStatus::AlreadySolved);
    XCTAssertTrue(result.moves.empty());
}

- (void)testRandomScramblesAreSolvedAndVerified {
    RubikSolverEngine engine("/private/tmp/rubik-tests-cache");
    RubikSolverOptions options;
    options.timeoutSeconds = 30;

    RubikCube cube;
    std::vector<int> scramble = cube.scramble(20);
    XCTAssertFalse(cube.isSolved());

    RubikSolveResult result = engine.solveExact(cube, options);
    XCTAssertEqual(result.status, RubikSolveStatus::Success);
    XCTAssertTrue(result.verified);

    RubikCube replay = cube;
    replay.applyMoves(result.moves);
    XCTAssertTrue(replay.isSolved());
}

- (void)testTwistedCornerIsRejected {
    RubikCube cube;
    uint8_t facelets[54];
    for (int i = 0; i < 54; ++i) facelets[i] = cube.getFacelet(i);
    uint8_t a = facelets[8], b = facelets[9], c = facelets[20];
    facelets[8] = b;
    facelets[9] = c;
    facelets[20] = a;

    RubikValidationResult validation = RubikValidateFacelets(facelets);
    XCTAssertFalse(validation.valid);
    XCTAssertEqual(validation.code, RubikValidationCode::CornerTwist);
}

- (void)testOrientationRecoveryUndoesFaceRotation {
    RubikCube scrambled;
    scrambled.applyAlgorithm("R U R' U' F2 L D' B2 R' U2");

    uint8_t rotated[54];
    for (int i = 0; i < 54; ++i) rotated[i] = scrambled.getFacelet(i);
    RubikRotateFaceClockwise(rotated, 0, 1);

    RubikOrientationResult result = RubikRecoverOrientation(rotated);
    XCTAssertTrue(result.success);
    for (int i = 0; i < 54; ++i) {
        XCTAssertEqual(result.facelets[i], scrambled.getFacelet(i));
    }
}

- (void)testSimplifyMoves {
    std::vector<int> raw = {MOVE_U, MOVE_U, MOVE_R, MOVE_R_PRIME, MOVE_F, MOVE_F2};
    std::vector<int> simple = RubikCube::simplifyMoves(raw);
    XCTAssertEqual(simple.size(), 2u);
    XCTAssertEqual(simple[0], MOVE_U2);
    XCTAssertEqual(simple[1], MOVE_F_PRIME);
}

@end
