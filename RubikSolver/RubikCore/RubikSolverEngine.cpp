//
//  RubikSolverEngine.cpp
//  RubikSolver - Exact Two-Phase Solver Engine
//

#include "RubikSolverEngine.h"

extern "C" {
#include "ckociemba/include/search.h"
}

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <iostream>
#include <vector>

const char* RubikSolveStatusName(RubikSolveStatus status) {
    switch (status) {
        case RubikSolveStatus::AlreadySolved: return "already-solved";
        case RubikSolveStatus::Success: return "success";
        case RubikSolveStatus::InvalidState: return "invalid-state";
        case RubikSolveStatus::Timeout: return "timeout";
        case RubikSolveStatus::Cancelled: return "cancelled";
        case RubikSolveStatus::Busy: return "busy";
        case RubikSolveStatus::NoSolution: return "no-solution";
        default: return "internal-error";
    }
}

const char* RubikSolverKindName(RubikSolverKind kind) {
    switch (kind) {
        case RubikSolverKind::Exact: return "exact";
        case RubikSolverKind::Neural: return "neural";
        default: return "hybrid";
    }
}

RubikSolverEngine::RubikSolverEngine(std::string cacheDir) : m_cacheDir(std::move(cacheDir)) {
    if (!m_cacheDir.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(m_cacheDir, ec);
        if (ec) {
            std::cerr << "[RubikSolverEngine] Could not create cache directory "
                      << m_cacheDir << ": " << ec.message() << "\n";
            m_cacheDir.clear();
        }
    }
}

RubikSolverEngine::~RubikSolverEngine() {
    cancel();
}

void RubikSolverEngine::setCacheDir(const std::string& cacheDir) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_cacheDir = cacheDir;
    if (!m_cacheDir.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(m_cacheDir, ec);
        if (ec) {
            std::cerr << "[RubikSolverEngine] Could not create cache directory "
                      << m_cacheDir << ": " << ec.message() << "\n";
            m_cacheDir.clear();
        }
    }
}

void RubikSolverEngine::cancel() {
    m_cancel.store(true);
    cancel_search();
}

RubikSolveResult RubikSolverEngine::solveExact(const RubikCube& cube,
                                               const RubikSolverOptions& options) {
    RubikSolveResult result;
    result.engineUsed = RubikSolverKind::Exact;

    std::unique_lock<std::mutex> lock(m_mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
        result.status = RubikSolveStatus::Busy;
        result.message = "Another solve is already running.";
        return result;
    }

    m_solving.store(true);
    m_cancel.store(false);
    reset_cancel_search();

    const auto start = std::chrono::steady_clock::now();
    auto finish = [&](RubikSolveStatus status, const std::string& message) {
        result.status = status;
        result.message = message;
        result.timeMs = std::chrono::duration<double, std::milli>(
                            std::chrono::steady_clock::now() - start).count();
        m_solving.store(false);
        return result;
    };

    result.validation = RubikValidateCube(cube);
    if (!result.validation.valid) {
        result.status = RubikSolveStatus::InvalidState;
        result.message = result.validation.message;
        result.timeMs = std::chrono::duration<double, std::milli>(
                            std::chrono::steady_clock::now() - start).count();
        m_solving.store(false);
        return result;
    }

    if (cube.isSolved()) {
        result.status = RubikSolveStatus::AlreadySolved;
        result.alreadySolved = true;
        result.verified = true;
        result.message = "The cube is already solved.";
        result.timeMs = std::chrono::duration<double, std::milli>(
                            std::chrono::steady_clock::now() - start).count();
        m_solving.store(false);
        return result;
    }

    if (m_cancel.load()) {
        return finish(RubikSolveStatus::Cancelled, "Solve cancelled before it started.");
    }

    const std::string facelets = cube.toFaceletString();
    const long timeout = options.timeoutSeconds > 0 ? options.timeoutSeconds : 10;
    char* rawSolution = solution(const_cast<char*>(facelets.c_str()),
                                 options.maxDepth,
                                 timeout,
                                 0,
                                 m_cacheDir.empty() ? nullptr : m_cacheDir.c_str());

    if (m_cancel.load()) {
        if (rawSolution) free(rawSolution);
        return finish(RubikSolveStatus::Cancelled, "Solve cancelled.");
    }

    if (!rawSolution) {
        const double elapsed = std::chrono::duration<double>(
                                   std::chrono::steady_clock::now() - start).count();
        if (elapsed >= static_cast<double>(timeout) - 0.25) {
            return finish(RubikSolveStatus::Timeout, "The exact solver timed out.");
        }
        return finish(RubikSolveStatus::NoSolution,
                      "No solution was found for this cube state.");
    }

    std::vector<int> moves = RubikCube::stringToMoves(rawSolution);
    free(rawSolution);

    if (options.simplify) {
        moves = RubikCube::simplifyMoves(moves);
    }

    if (options.verify) {
        RubikCube verification = cube;
        verification.applyMoves(moves);
        if (!verification.isSolved()) {
            return finish(RubikSolveStatus::InternalError,
                          "The solver returned a sequence that does not solve the cube.");
        }
        result.verified = true;
    }

    result.moves = std::move(moves);
    return finish(RubikSolveStatus::Success,
                  "Solved with the exact two-phase solver.");
}
