//
//  RubikMetalSolver.mm
//  RubikSolver - Solver Facade
//

#import "RubikMetalSolver.h"
#import "RubikCoreMLModel.h"

@implementation RubikMetalSolver {
    RubikSolverEngine* _engine;
    RubikNeuralSolver* _neuralSolver;
    BOOL _shouldCancel;
}

+ (NSString*)defaultCacheDir {
    NSArray<NSString*>* paths =
        NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                            NSUserDomainMask, YES);
    NSString* base = paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    return [base stringByAppendingPathComponent:@"RubikSolver/ckociemba-cache"];
}

- (instancetype)init {
    return [self initWithCacheDir:[RubikMetalSolver defaultCacheDir]];
}

- (instancetype)initWithCacheDir:(NSString*)cacheDir {
    self = [super init];
    if (self) {
        _shouldCancel = NO;
        _engine = new RubikSolverEngine(cacheDir.length > 0 ? cacheDir.UTF8String : "");
        _neuralSolver = [[RubikNeuralSolver alloc] initWithModel:[RubikCoreMLModel sharedInstance]];
    }
    return self;
}

- (RubikNeuralSolver *)neuralSolver {
    return _neuralSolver;
}

- (void)dealloc {
    if (_engine) {
        _engine->cancel();
        delete _engine;
        _engine = nullptr;
    }
}

- (void)cancelSolve {
    _shouldCancel = YES;
    if (_engine) {
        _engine->cancel();
    }
    [_neuralSolver cancel];
}

- (RubikSolveResult)solveCubeTyped:(const RubikCube&)cube
                           options:(const RubikSolverOptions&)options {
    _shouldCancel = NO;
    if (!_engine) {
        RubikSolveResult result;
        result.status = RubikSolveStatus::InternalError;
        result.message = "The solver engine is not initialized.";
        return result;
    }

    if (options.kind == RubikSolverKind::Exact) {
        return _engine->solveExact(cube, options);
    }

    RubikSolveResult neuralResult = [_neuralSolver solveCube:cube options:options];
    if (neuralResult.status == RubikSolveStatus::Success ||
        neuralResult.status == RubikSolveStatus::AlreadySolved ||
        neuralResult.status == RubikSolveStatus::InvalidState ||
        neuralResult.status == RubikSolveStatus::Cancelled) {
        return neuralResult;
    }

    if (options.kind != RubikSolverKind::Exact && options.hybridFallsBackToExact) {
        RubikSolverOptions exactOptions = options;
        exactOptions.kind = RubikSolverKind::Exact;
        RubikSolveResult exactResult = _engine->solveExact(cube, exactOptions);
        if (exactResult.status == RubikSolveStatus::Success ||
            exactResult.status == RubikSolveStatus::AlreadySolved) {
            exactResult.usedFallback = true;
            exactResult.timeMs += neuralResult.timeMs;
            exactResult.nodesExpanded += neuralResult.nodesExpanded;
            exactResult.message = "Model-guided search did not finish; solved with the exact fallback.";
            return exactResult;
        }
        exactResult.usedFallback = true;
        exactResult.message = neuralResult.message + " Exact fallback also failed: " + exactResult.message;
        return exactResult;
    }

    return neuralResult;
}

- (std::vector<int>)solveCube:(const RubikCube&)cube executionTimeMs:(double*)outTimeMs {
    return [self solveCube:cube hintSolution:{} executionTimeMs:outTimeMs];
}

- (std::vector<int>)solveCube:(const RubikCube&)cube
                 hintSolution:(const std::vector<int>&)hint
              executionTimeMs:(double*)outTimeMs {
    (void)hint;
    RubikSolverOptions options;
    RubikSolveResult result = [self solveCubeTyped:cube options:options];

    if (outTimeMs) {
        *outTimeMs = result.timeMs;
    }

    switch (result.status) {
        case RubikSolveStatus::Success:
            return result.moves;
        case RubikSolveStatus::AlreadySolved:
            NSLog(@"[RubikMetalSolver] Cube is already solved.");
            return {};
        case RubikSolveStatus::Cancelled:
            NSLog(@"[RubikMetalSolver] Solve cancelled.");
            return {};
        default:
            NSLog(@"[RubikMetalSolver] Solve failed (%s): %s",
                  RubikSolveStatusName(result.status), result.message.c_str());
            return {};
    }
}

- (std::vector<std::string>)solveCubeWithTrace:(const RubikCube&)cube executionTimeMs:(double*)outTimeMs {
    std::vector<std::string> trace;
    double t = 0.0;
    std::vector<int> solution = [self solveCube:cube executionTimeMs:&t];
    if (solution.empty()) {
        if (outTimeMs) *outTimeMs = t;
        return trace;
    }

    RubikCube cur = cube;
    trace.push_back(std::string("Start: ") + cur.toFaceletString());
    for (int move : solution) {
        cur.applyMove(move);
        trace.push_back(RubikCube::moveToString(move) + ": " + cur.toFaceletString());
    }
    if (outTimeMs) *outTimeMs = t;
    return trace;
}

+ (std::vector<int>)simplifyMoves:(const std::vector<int>&)moves {
    return RubikCube::simplifyMoves(moves);
}

@end
