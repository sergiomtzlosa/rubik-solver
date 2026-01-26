//
//  RubikNeuralSolver.mm
//  RubikSolver - Core ML GPU Beam Search
//

#import "RubikNeuralSolver.h"
#import "RubikCoreMLModel.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <string>
#include <unordered_set>
#include <vector>

namespace {

struct BeamNode {
    RubikCube cube;
    std::vector<int> path;
    std::array<float, 18> policyLogits{};
    float value = 0.0f;
    int lastMove = -1;
};

struct Candidate {
    BeamNode node;
    float policyLogit = 0.0f;
    float score = 0.0f;
};

} // namespace

@implementation RubikNeuralSolver {
    RubikCoreMLModel *_model;
    std::atomic<bool> _cancelled;
    NSUInteger _lastEvaluatedStates;
}

- (instancetype)init {
    return [self initWithModel:[RubikCoreMLModel sharedInstance]];
}

- (instancetype)initWithModel:(RubikCoreMLModel *)model {
    self = [super init];
    if (self) {
        _model = model;
        _cancelled.store(false);
        _lastEvaluatedStates = 0;
    }
    return self;
}

- (BOOL)modelAvailable {
    return _model != nil && _model.model != nil;
}

- (void)cancel {
    _cancelled.store(true);
}

- (RubikSolveResult)solveCube:(const RubikCube &)cube
                     options:(const RubikSolverOptions &)options {
    using Clock = std::chrono::steady_clock;

    RubikSolveResult result;
    result.engineUsed = RubikSolverKind::Neural;
    _cancelled.store(false);
    _lastEvaluatedStates = 0;
    const auto start = Clock::now();

    auto finish = [&](RubikSolveStatus status, const std::string &message) {
        result.status = status;
        result.message = message;
        result.timeMs = std::chrono::duration<double, std::milli>(Clock::now() - start).count();
        result.nodesExpanded = (int)_lastEvaluatedStates;
        return result;
    };

    result.validation = RubikValidateCube(cube);
    if (!result.validation.valid) {
        result.status = RubikSolveStatus::InvalidState;
        result.message = result.validation.message;
        result.timeMs = std::chrono::duration<double, std::milli>(Clock::now() - start).count();
        return result;
    }

    if (cube.isSolved()) {
        result.status = RubikSolveStatus::AlreadySolved;
        result.alreadySolved = true;
        result.verified = true;
        result.message = "The cube is already solved.";
        result.timeMs = std::chrono::duration<double, std::milli>(Clock::now() - start).count();
        return result;
    }

    if (!self.modelAvailable) {
        return finish(RubikSolveStatus::InternalError,
                      "The Core ML model is not loaded. Fall back to the exact solver.");
    }

    const int beamWidth = std::max(1, options.neuralBeamWidth);
    const int maxDepth = std::max(1, options.neuralMaxDepth);
    const int maxNodes = std::max(beamWidth, options.neuralMaxNodes);
    const float policyWeight = std::max(0.0f, options.neuralPolicyWeight);
    const double budgetSeconds = options.neuralTimeBudgetSeconds > 0.0f
                                     ? static_cast<double>(options.neuralTimeBudgetSeconds)
                                     : 4.0;

    auto timeExceeded = [&]() {
        const double elapsed = std::chrono::duration<double>(Clock::now() - start).count();
        return elapsed >= budgetSeconds;
    };

    auto verifySolution = [&](const std::vector<int> &moves) -> bool {
        RubikCube replay = cube;
        replay.applyMoves(moves);
        return replay.isSolved();
    };

    // 1. Evaluate the root to get policy guidance.
    std::vector<RubikCube> rootStates{ cube };
    std::vector<const uint8_t *> rootPointers{ cube.getFacelets() };
    NSError *modelError = nil;
    NSArray<RubikMLPrediction *> *rootPredictions =
        [_model predictBatchForFaceletsList:rootPointers error:&modelError];
    if (!rootPredictions || rootPredictions.count == 0) {
        return finish(RubikSolveStatus::InternalError,
                      modelError.localizedDescription.UTF8String ?: "Core ML inference failed.");
    }
    _lastEvaluatedStates += 1;

    BeamNode root;
    root.cube = cube;
    root.value = rootPredictions.firstObject.costToGo;
    for (int i = 0; i < 18; ++i) {
        root.policyLogits[i] = rootPredictions.firstObject.policyLogits[i].floatValue;
    }

    std::vector<BeamNode> beam{ root };
    std::unordered_set<std::string> visited;
    visited.reserve(static_cast<size_t>(maxNodes) * 2);
    visited.insert(cube.toFaceletString());

    for (int depth = 0; depth < maxDepth; ++depth) {
        if (_cancelled.load()) {
            return finish(RubikSolveStatus::Cancelled, "Neural search cancelled.");
        }
        if (timeExceeded()) {
            return finish(RubikSolveStatus::Timeout,
                          "The neural search reached its time budget.");
        }

        std::vector<Candidate> candidates;
        candidates.reserve(beam.size() * 18);

        for (const BeamNode &node : beam) {
            for (int move = 0; move < NUM_MOVES; ++move) {
                // Consecutive turns of the same face are always reducible.
                if (node.lastMove >= 0 && node.lastMove / 3 == move / 3) continue;

                Candidate candidate;
                candidate.node.cube = node.cube;
                candidate.node.cube.applyMove(move);
                candidate.node.path = node.path;
                candidate.node.path.push_back(move);
                candidate.node.lastMove = move;
                candidate.policyLogit = node.policyLogits[move];

                if (candidate.node.cube.isSolved()) {
                    if (verifySolution(candidate.node.path)) {
                        result.moves = candidate.node.path;
                        result.verified = true;
                        return finish(RubikSolveStatus::Success,
                                      "Solved with the Core ML GPU beam search.");
                    }
                    continue;
                }

                const std::string key = candidate.node.cube.toFaceletString();
                if (!visited.insert(key).second) continue;

                candidates.push_back(std::move(candidate));
                if ((int)_lastEvaluatedStates + (int)candidates.size() >= maxNodes) break;
            }
            if ((int)_lastEvaluatedStates + (int)candidates.size() >= maxNodes) break;
        }

        if (candidates.empty()) {
            return finish(RubikSolveStatus::NoSolution,
                          "The neural search exhausted its reachable states.");
        }
        if (_cancelled.load()) {
            return finish(RubikSolveStatus::Cancelled, "Neural search cancelled.");
        }
        if (timeExceeded()) {
            return finish(RubikSolveStatus::Timeout,
                          "The neural search reached its time budget.");
        }

        // 2. One true GPU batch for every candidate at this depth.
        std::vector<const uint8_t *> pointers;
        pointers.reserve(candidates.size());
        for (const Candidate &candidate : candidates) {
            pointers.push_back(candidate.node.cube.getFacelets());
        }

        NSArray<RubikMLPrediction *> *predictions =
            [_model predictBatchForFaceletsList:pointers error:&modelError];
        if (!predictions || predictions.count != candidates.size()) {
            return finish(RubikSolveStatus::InternalError,
                          modelError.localizedDescription.UTF8String ?: "Core ML batch inference failed.");
        }
        _lastEvaluatedStates += candidates.size();

        for (size_t i = 0; i < candidates.size(); ++i) {
            RubikMLPrediction *prediction = predictions[i];
            candidates[i].node.value = prediction.costToGo;
            for (int k = 0; k < 18; ++k) {
                candidates[i].node.policyLogits[k] = prediction.policyLogits[k].floatValue;
            }
            // Lower value is better; the policy term breaks ties toward moves
            // the network believes are useful.
            candidates[i].score = prediction.costToGo - policyWeight * candidates[i].policyLogit;
        }

        std::sort(candidates.begin(), candidates.end(),
                  [](const Candidate &a, const Candidate &b) {
                      if (a.score == b.score) return a.node.path.size() < b.node.path.size();
                      return a.score < b.score;
                  });

        if ((int)candidates.size() > beamWidth) {
            candidates.resize(beamWidth);
        }

        beam.clear();
        beam.reserve(candidates.size());
        for (Candidate &candidate : candidates) {
            beam.push_back(std::move(candidate.node));
        }
    }

    return finish(RubikSolveStatus::NoSolution,
                  "The neural search did not find a verified solution within its depth budget.");
}

@end
