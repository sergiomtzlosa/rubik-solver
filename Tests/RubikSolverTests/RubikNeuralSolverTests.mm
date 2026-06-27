//
//  RubikNeuralSolverTests.mm
//  RubikSolverTests
//

#import <XCTest/XCTest.h>

#import "RubikCoreMLModel.h"
#import "RubikMetalSolver.h"
#import "RubikNeuralSolver.h"

#include "RubikCube.h"

@interface RubikNeuralSolverTests : XCTestCase
@end

@implementation RubikNeuralSolverTests

- (void)testModelLoadsAndReportsVerifiedGPUPlacement {
    RubikCoreMLModel *model = [RubikCoreMLModel sharedInstance];
    XCTAssertNotNil(model);
    XCTAssertNotNil(model.model, @"DeepCubeA.mlmodelc must load from the app bundle");

    XCTestExpectation *expectation = [self expectationWithDescription:@"compute plan"];
    [model verifyGPUUsageWithCompletion:^(BOOL usingGPU, NSString *details) {
        NSLog(@"[RubikNeuralSolverTests] GPU verification: %d %@", usingGPU, details);
        XCTAssertTrue(usingGPU, @"Core ML should prefer the GPU: %@", details);
        XCTAssertTrue(model.isAcceleratedOnGPU);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
}

- (void)testTrueBatchMatchesSingleInference {
    RubikCoreMLModel *model = [RubikCoreMLModel sharedInstance];
    XCTAssertNotNil(model.model);

    RubikCube solved;
    RubikCube shallow;
    shallow.applyAlgorithm("R U F'");
    RubikCube deep;
    deep.applyAlgorithm("R U R' U' F2 L D' B2 R' U2");

    const uint8_t *states[] = { solved.getFacelets(), shallow.getFacelets(), deep.getFacelets() };

    NSError *error = nil;
    NSArray<RubikMLPrediction *> *batch = [model predictBatchForFaceletsList:
        std::vector<const uint8_t *>(states, states + 3) error:&error];
    XCTAssertNotNil(batch, @"%@", error);
    XCTAssertEqual(batch.count, 3u);

    for (NSUInteger i = 0; i < 3; ++i) {
        RubikMLPrediction *single = [model predictForFacelets:states[i] error:&error];
        XCTAssertNotNil(single, @"%@", error);
        XCTAssertEqualWithAccuracy(single.costToGo, batch[i].costToGo, 0.05);
        XCTAssertEqual(single.policyLogits.count, 18u);
        for (NSUInteger k = 0; k < 18; ++k) {
            XCTAssertEqualWithAccuracy(single.policyLogits[k].floatValue,
                                       batch[i].policyLogits[k].floatValue, 0.05);
        }
    }
}

- (void)testNeuralSolvesTenMoveScrambleWithoutFallback {
    RubikCube cube;
    cube.applyAlgorithm("R U R' U' F2 L D' B2 R' U2");

    RubikSolverOptions options;
    options.kind = RubikSolverKind::Neural;
    options.neuralBeamWidth = 512;
    options.neuralMaxDepth = 20;
    options.neuralTimeBudgetSeconds = 8.0f;

    RubikMetalSolver *solver = [[RubikMetalSolver alloc] initWithCacheDir:@"/private/tmp/rubik-tests-cache"];
    RubikSolveResult result = [solver solveCubeTyped:cube options:options];

    XCTAssertEqual(result.status, RubikSolveStatus::Success, @"%@", [NSString stringWithUTF8String:result.message.c_str()]);
    XCTAssertTrue(result.verified);
    XCTAssertEqual(result.engineUsed, RubikSolverKind::Neural);
    XCTAssertFalse(result.usedFallback, @"a 10-move scramble should be solved by the model itself");
    XCTAssertFalse(result.moves.empty());

    RubikCube replay = cube;
    replay.applyMoves(result.moves);
    XCTAssertTrue(replay.isSolved());
}

- (void)testHybridFallsBackToExact {
    RubikCube cube;
    cube.applyAlgorithm("R U R' U' F2 L D' B2 R' U2");

    RubikSolverOptions options;
    options.kind = RubikSolverKind::Hybrid;
    options.timeoutSeconds = 20;
    options.neuralBeamWidth = 64;
    options.neuralMaxDepth = 8;
    options.neuralTimeBudgetSeconds = 0.2f;

    RubikMetalSolver *solver = [[RubikMetalSolver alloc] initWithCacheDir:@"/private/tmp/rubik-tests-cache"];
    RubikSolveResult result = [solver solveCubeTyped:cube options:options];

    XCTAssertEqual(result.status, RubikSolveStatus::Success, @"%@", [NSString stringWithUTF8String:result.message.c_str()]);
    XCTAssertTrue(result.verified);
    XCTAssertTrue(result.usedFallback);
    XCTAssertEqual(result.engineUsed, RubikSolverKind::Exact);
}

- (void)testNeuralFallsBackToExactWhenModelSearchCannotFinish {
    RubikCube cube;
    cube.applyAlgorithm("R U R' U' F2 L D' B2 R' U2");

    RubikSolverOptions options;
    options.kind = RubikSolverKind::Neural;
    options.timeoutSeconds = 20;
    options.neuralBeamWidth = 2;
    options.neuralMaxDepth = 4;
    options.neuralTimeBudgetSeconds = 0.2f;
    options.hybridFallsBackToExact = true;

    RubikMetalSolver *solver = [[RubikMetalSolver alloc] initWithCacheDir:@"/private/tmp/rubik-tests-cache"];
    RubikSolveResult result = [solver solveCubeTyped:cube options:options];

    XCTAssertEqual(result.status, RubikSolveStatus::Success, @"%@", [NSString stringWithUTF8String:result.message.c_str()]);
    XCTAssertTrue(result.verified);
    XCTAssertTrue(result.usedFallback);
    XCTAssertEqual(result.engineUsed, RubikSolverKind::Exact);
    XCTAssertTrue([NSString stringWithUTF8String:result.message.c_str()].length > 0);
}

@end
