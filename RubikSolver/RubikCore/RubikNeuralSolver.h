//
//  RubikNeuralSolver.h
//  RubikSolver - Core ML GPU Beam Search
//

#ifndef RubikNeuralSolver_h
#define RubikNeuralSolver_h

#import <Foundation/Foundation.h>
#include "RubikCube.h"
#include "RubikSolveResult.h"

@class RubikCoreMLModel;

@interface RubikNeuralSolver : NSObject

- (instancetype)init;
- (instancetype)initWithModel:(RubikCoreMLModel *)model;

/// Run a GPU-batched beam search guided by the DeepCubeA value/policy heads.
/// Every returned solution is replayed and verified.
- (RubikSolveResult)solveCube:(const RubikCube &)cube
                     options:(const RubikSolverOptions &)options;

- (void)cancel;

@property (nonatomic, readonly) NSUInteger lastEvaluatedStates;
@property (nonatomic, readonly) BOOL modelAvailable;

@end

#endif /* RubikNeuralSolver_h */
