//
//  RubikSolveResult.h
//  RubikSolver - Typed Solver Results
//

#ifndef RubikSolveResult_h
#define RubikSolveResult_h

#include "RubikValidation.h"
#include <string>
#include <vector>

enum class RubikSolveStatus {
    AlreadySolved,
    Success,
    InvalidState,
    Timeout,
    Cancelled,
    Busy,
    NoSolution,
    InternalError
};

enum class RubikSolverKind {
    Exact,
    Neural,
    Hybrid
};

struct RubikSolverOptions {
    RubikSolverKind kind = RubikSolverKind::Exact;
    long timeoutSeconds = 10;
    int maxDepth = 24;
    bool simplify = true;
    bool verify = true;
    bool verbose = false;

    // Neural search options
    int neuralBeamWidth = 512;
    int neuralMaxDepth = 30;
    int neuralMaxNodes = 200000;
    float neuralPolicyWeight = 0.25f;
    float neuralTimeBudgetSeconds = 4.0f;

    // Hybrid options
    bool hybridFallsBackToExact = true;
};

struct RubikSolveResult {
    RubikSolveStatus status = RubikSolveStatus::InternalError;
    RubikSolverKind engineUsed = RubikSolverKind::Exact;
    bool usedFallback = false;
    bool verified = false;
    bool alreadySolved = false;
    int nodesExpanded = 0;
    double timeMs = 0.0;
    std::vector<int> moves;
    std::string message;
    RubikValidationResult validation;
};

const char* RubikSolveStatusName(RubikSolveStatus status);
const char* RubikSolverKindName(RubikSolverKind kind);

#endif /* RubikSolveResult_h */
