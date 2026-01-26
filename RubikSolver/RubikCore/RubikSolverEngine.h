//
//  RubikSolverEngine.h
//  RubikSolver - Exact Two-Phase Solver Engine
//

#ifndef RubikSolverEngine_h
#define RubikSolverEngine_h

#include "RubikCube.h"
#include "RubikSolveResult.h"
#include <atomic>
#include <mutex>
#include <string>

class RubikSolverEngine {
public:
    explicit RubikSolverEngine(std::string cacheDir = std::string());
    ~RubikSolverEngine();

    RubikSolveResult solveExact(const RubikCube& cube,
                                const RubikSolverOptions& options = RubikSolverOptions());

    void cancel();
    bool isSolving() const { return m_solving.load(); }

    void setCacheDir(const std::string& cacheDir);
    const std::string& cacheDir() const { return m_cacheDir; }

private:
    std::string m_cacheDir;
    std::atomic<bool> m_solving{false};
    std::atomic<bool> m_cancel{false};
    std::mutex m_mutex;
};

#endif /* RubikSolverEngine_h */
