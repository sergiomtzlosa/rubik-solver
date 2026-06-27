//
//  RubikMetalSolver.h
//  RubikSolver - Solver Facade
//
//  Historically this class wrapped the Core ML model and ckociemba directly.
//  It is now a thin Objective-C++ facade over RubikSolverEngine so that the
//  app, the CLI, and the tests all share the same validated solve path.
//

#ifndef RubikMetalSolver_h
#define RubikMetalSolver_h

#import <Foundation/Foundation.h>
#include "RubikCube.h"
#include "RubikSolveResult.h"
#include "RubikSolverEngine.h"
#include "RubikNeuralSolver.h"
#include <string>
#include <vector>

@interface RubikMetalSolver : NSObject

/// Initialize with the default cache directory
/// (~/Library/Application Support/RubikSolver/ckociemba-cache).
- (instancetype)init;

/// Initialize with an explicit pruning-table cache directory (tests, CLI).
- (instancetype)initWithCacheDir:(NSString*)cacheDir;

/// Full typed solve. Prefer this API in new code.
- (RubikSolveResult)solveCubeTyped:(const RubikCube&)cube
                          options:(const RubikSolverOptions&)options;

/// Solve using the exact two-phase engine with default options.
/// Returns an empty array when the cube is already solved, invalid, or the
/// solve fails/cancels. Use solveCubeTyped:options: to inspect why.
- (std::vector<int>)solveCube:(const RubikCube&)cube executionTimeMs:(double*)outTimeMs;

/// Solve and return a textual trace of each move and the cube state after it
- (std::vector<std::string>)solveCubeWithTrace:(const RubikCube&)cube executionTimeMs:(double*)outTimeMs;

/// Solve with optional reference hint moves (kept for API compatibility;
/// the exact solver ignores hints).
- (std::vector<int>)solveCube:(const RubikCube&)cube
                 hintSolution:(const std::vector<int>&)hint
              executionTimeMs:(double*)outTimeMs;

/// Cancel the current solve operation.
- (void)cancelSolve;

/// Neural (Core ML GPU) solver, exposed for diagnostics and tests.
@property (nonatomic, readonly) RubikNeuralSolver *neuralSolver;

/// Combine consecutive moves on the same face.
+ (std::vector<int>)simplifyMoves:(const std::vector<int>&)moves;

@end

#endif /* RubikMetalSolver_h */
