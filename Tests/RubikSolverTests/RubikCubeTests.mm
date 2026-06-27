//
//  RubikCubeTests.mm
//  RubikSolverTests
//

#import <XCTest/XCTest.h>

#include "RubikCube.h"

#include <random>
#include <string>
#include <vector>

@interface RubikCubeTests : XCTestCase
@end

@implementation RubikCubeTests

- (void)testEachMoveRepeatedFourTimesIsIdentity {
    for (int move = 0; move < NUM_MOVES; ++move) {
        RubikCube cube;
        for (int i = 0; i < 4; ++i) {
            cube.applyMove(move);
        }
        XCTAssertTrue(cube.isSolved(), @"Move %s did not return to solved after four turns",
                      RubikCube::moveToString(move).c_str());
    }
}

- (void)testEachMoveAndItsInverseCancel {
    for (int move = 0; move < NUM_MOVES; ++move) {
        RubikCube cube;
        cube.applyMove(move);
        cube.applyMove(RubikCube::invertMove(move));
        XCTAssertTrue(cube.isSolved(), @"Move %s and its inverse did not cancel",
                      RubikCube::moveToString(move).c_str());
    }
}

- (void)testInverseIsAnInvolution {
    for (int move = 0; move < NUM_MOVES; ++move) {
        XCTAssertEqual(RubikCube::invertMove(RubikCube::invertMove(move)), move);
    }
}

- (void)testFaceletStringRoundTrip {
    RubikCube cube;
    cube.applyAlgorithm("R U R' U' F2 L D' B2 R' U2 F' L2 D2");

    const std::string facelets = cube.toFaceletString();
    XCTAssertEqual(facelets.size(), 54u);

    RubikCube decoded(facelets);
    for (int i = 0; i < 54; ++i) {
        XCTAssertEqual(decoded.getFacelet(i), cube.getFacelet(i));
    }
    XCTAssertTrue(decoded.isSolved() == false);
}

- (void)testDeterministicScrambleAndReplay {
    RubikCube cube;
    cube.applyAlgorithm("R U2 F' L D B2 R' U F2 D' L2");
    RubikCube scrambleState = cube;

    std::vector<int> inverse;
    for (int move : RubikCube::stringToMoves("R U2 F' L D B2 R' U F2 D' L2")) {
        inverse.insert(inverse.begin(), RubikCube::invertMove(move));
    }
    cube.applyMoves(inverse);
    XCTAssertTrue(cube.isSolved());
    XCTAssertFalse(scrambleState.isSolved());
}

- (void)testMoveParserAcceptsWhitespaceAndSuffixes {
    std::vector<int> moves = RubikCube::stringToMoves("  R   U'  F2\tD\nL2 B  ");
    XCTAssertEqual(moves.size(), 6u);
    XCTAssertEqual(moves[0], MOVE_R);
    XCTAssertEqual(moves[1], MOVE_U_PRIME);
    XCTAssertEqual(moves[2], MOVE_F2);
    XCTAssertEqual(moves[3], MOVE_D);
    XCTAssertEqual(moves[4], MOVE_L2);
    XCTAssertEqual(moves[5], MOVE_B);
}

- (void)testSimplifyCollapsesSameFaceMoves {
    std::vector<int> raw = {MOVE_U, MOVE_U, MOVE_R, MOVE_R_PRIME, MOVE_F, MOVE_F2};
    std::vector<int> simple = RubikCube::simplifyMoves(raw);
    XCTAssertEqual(simple.size(), 2u);
    XCTAssertEqual(simple[0], MOVE_U2);
    XCTAssertEqual(simple[1], MOVE_F_PRIME);
}

- (void)testScrambleProducesNonSolvedCube {
    RubikCube cube;
    std::vector<int> scramble = cube.scramble(25);
    XCTAssertEqual(scramble.size(), 25u);
    XCTAssertFalse(cube.isSolved());

    RubikCube replay = cube;
    for (auto it = scramble.rbegin(); it != scramble.rend(); ++it) {
        replay.applyMove(RubikCube::invertMove(*it));
    }
    XCTAssertTrue(replay.isSolved());
}

- (void)testEveryColorAppearsNineTimesAfterScramble {
    RubikCube cube;
    cube.scramble(30);

    int counts[NUM_COLORS] = {0};
    for (int i = 0; i < 54; ++i) {
        counts[cube.getFacelet(i)]++;
    }
    for (int color = 0; color < NUM_COLORS; ++color) {
        XCTAssertEqual(counts[color], 9);
    }
}

@end
