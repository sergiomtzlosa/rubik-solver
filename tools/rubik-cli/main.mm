//
//  main.mm
//  rubik-cli - RubikSolver command-line interface
//
//  Three commands share the exact same core as the macOS app:
//    solve   validate, then solve with exact / neural / hybrid search
//    verify  full cubie validation and color/center checks
//    orient  recover in-plane face rotations with the 4^6 search
//    state   apply moves or a deterministic scramble to a fresh cube
//
//  Machine output is stable JSON; diagnostics go to stderr.
//

#import <Foundation/Foundation.h>

#include "RubikCube.h"
#include "RubikMetalSolver.h"
#include "RubikOrientation.h"
#include "RubikSolveResult.h"
#include "RubikSolverEngine.h"
#include "RubikValidation.h"

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <random>
#include <sstream>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

// Exit codes are part of the CLI contract (see tools/rubik-cli/README.md).
enum ExitCode {
    kExitSuccess = 0,
    kExitUsage = 2,
    kExitInvalidState = 3,
    kExitNoSolution = 4,
    kExitTimeout = 5,
    kExitCancelled = 6,
    kExitBusy = 7,
    kExitOrientation = 8
};

struct CliOptions {
    std::string command;
    std::string facelets;
    std::string moves;
    std::string engine = "hybrid";
    std::string cacheDir;
    double timeoutSeconds = 30.0;
    double neuralBudgetSeconds = 4.0;
    int maxDepth = 24;
    int beamWidth = 0;
    int maxNodes = 0;
    int scrambleLength = 0;
    long long seed = -1;
    bool json = false;
    bool verify = true;
    bool simplify = true;
};

void PrintUsage(FILE* out) {
    std::fprintf(out,
        "rubik-cli - verified Rubik's Cube solving for scripts and OpenCode\n"
        "\n"
        "Usage:\n"
        "  rubik-cli solve  --facelets <54 chars> [options]\n"
        "  rubik-cli verify --facelets <54 chars> [--json]\n"
        "  rubik-cli orient --facelets <54 chars> [--json]\n"
        "  rubik-cli state  [--facelets <54 chars>] [--moves \"R U R' ...\"] [--scramble N] [--seed N] [--json]\n"
        "\n"
        "Facelets: 54 characters, face order U R F D L B, row-major per face.\n"
        "Accepted letters: U/R/F/D/L/B or W/R/G/Y/O/B (plus digits 0-5).\n"
        "\n"
        "Solve options:\n"
        "  --engine exact|neural|hybrid   Solver selection (default: hybrid)\n"
        "  --timeout <seconds>            Exact solver timeout (default: 30)\n"
        "  --neural-budget <seconds>      Neural search time budget (default: 4)\n"
        "  --max-depth <n>                Exact solver max depth (default: 24)\n"
        "  --beam-width <n>               Neural beam width override\n"
        "  --max-nodes <n>                Neural node budget override\n"
        "  --cache-dir <path>             Pruning-table cache directory\n"
        "  --no-verify                    Skip replay verification (not recommended)\n"
        "  --no-simplify                  Keep the raw two-phase move sequence\n"
        "\n"
        "Global options:\n"
        "  --json                         Emit machine-readable JSON\n"
        "  -h, --help                     Show this help\n"
        "  --version                      Show the version\n"
        "\n"
        "Exit codes:\n"
        "  0 success/valid   2 usage   3 invalid cube   4 no solution\n"
        "  5 timeout         6 cancelled   7 busy   8 orientation failed\n");
}

std::string ToLower(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return value;
}

bool ParseDouble(const std::string& text, double* out) {
    if (text.empty()) return false;
    char* end = nullptr;
    errno = 0;
    const double value = std::strtod(text.c_str(), &end);
    if (errno != 0 || !end || *end != '\0' || !std::isfinite(value)) return false;
    *out = value;
    return true;
}

bool ParseInt(const std::string& text, int* out) {
    if (text.empty()) return false;
    char* end = nullptr;
    errno = 0;
    const long value = std::strtol(text.c_str(), &end, 10);
    if (errno != 0 || !end || *end != '\0') return false;
    *out = static_cast<int>(value);
    return true;
}

bool ParseLongLong(const std::string& text, long long* out) {
    if (text.empty()) return false;
    char* end = nullptr;
    errno = 0;
    const long long value = std::strtoll(text.c_str(), &end, 10);
    if (errno != 0 || !end || *end != '\0') return false;
    *out = value;
    return true;
}

std::string JsonString(const std::string& value);

int FailUsage(const std::string& message, bool json) {
    if (json) {
        std::printf("{\"ok\":false,\"error\":\"usage\",\"message\":%s}\n",
                    JsonString(message).c_str());
    }
    std::fprintf(stderr, "rubik-cli: %s\n\n", message.c_str());
    PrintUsage(stderr);
    return kExitUsage;
}

bool IsFaceChar(char c, uint8_t* color) {
    switch (c) {
        case 'U': case 'W': case '0': *color = 0; return true;
        case 'R': case '1': *color = 1; return true;
        case 'F': case 'G': case '2': *color = 2; return true;
        case 'D': case 'Y': case '3': *color = 3; return true;
        case 'L': case 'O': case '4': *color = 4; return true;
        case 'B': case '5': *color = 5; return true;
        default: return false;
    }
}

bool ParseFacelets(const std::string& input, uint8_t out[54], std::string* error) {
    std::string compact;
    compact.reserve(input.size());
    for (char c : input) {
        if (!std::isspace(static_cast<unsigned char>(c))) {
            compact.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(c))));
        }
    }

    if (compact.size() != 54) {
        *error = "Expected 54 facelet characters, got " + std::to_string(compact.size()) + ".";
        return false;
    }

    for (int i = 0; i < 54; ++i) {
        uint8_t color = 0;
        if (!IsFaceChar(compact[i], &color)) {
            *error = std::string("Unknown facelet character '") + compact[i] +
                     "' at index " + std::to_string(i) + ".";
            return false;
        }
        out[i] = color;
    }
    return true;
}

bool ParseMoves(const std::string& input, std::vector<int>* out, std::string* error) {
    std::istringstream stream(input);
    std::string token;
    while (stream >> token) {
        int move = RubikCube::stringToMove(token);
        if (move < 0 && token.size() == 1) {
            // Accept single-letter lowercase faces as a convenience.
            std::string upper(1, static_cast<char>(std::toupper(static_cast<unsigned char>(token[0]))));
            move = RubikCube::stringToMove(upper);
        }
        if (move < 0) {
            *error = "Unknown move \"" + token + "\".";
            return false;
        }
        out->push_back(move);
    }
    return true;
}

std::vector<std::string> MoveNames(const std::vector<int>& moves) {
    std::vector<std::string> names;
    names.reserve(moves.size());
    for (int move : moves) names.push_back(RubikCube::moveToString(move));
    return names;
}

std::string JsonEscape(const std::string& value) {
    std::string out;
    out.reserve(value.size() + 8);
    for (unsigned char c : value) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\b': out += "\\b"; break;
            case '\f': out += "\\f"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buffer[7];
                    std::snprintf(buffer, sizeof(buffer), "\\u%04x", c);
                    out += buffer;
                } else {
                    out.push_back(static_cast<char>(c));
                }
                break;
        }
    }
    return out;
}

std::string JsonString(const std::string& value) {
    return "\"" + JsonEscape(value) + "\"";
}

std::string JsonStringArray(const std::vector<std::string>& values) {
    std::string out = "[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) out += ",";
        out += JsonString(values[i]);
    }
    out += "]";
    return out;
}

std::string JsonIntArray(const std::vector<int>& values) {
    std::string out = "[";
    for (size_t i = 0; i < values.size(); ++i) {
        if (i) out += ",";
        out += std::to_string(values[i]);
    }
    out += "]";
    return out;
}

std::string ValidationJson(const RubikValidationResult& validation) {
    std::string out = "{";
    out += "\"valid\":" + std::string(validation.valid ? "true" : "false");
    out += ",\"code\":" + JsonString(RubikValidationCodeName(validation.code));
    out += ",\"message\":" + JsonString(validation.message);
    out += "}";
    return out;
}

int ExitCodeForSolve(RubikSolveStatus status) {
    switch (status) {
        case RubikSolveStatus::Success:
        case RubikSolveStatus::AlreadySolved:
            return kExitSuccess;
        case RubikSolveStatus::InvalidState:
            return kExitInvalidState;
        case RubikSolveStatus::Timeout:
            return kExitTimeout;
        case RubikSolveStatus::Cancelled:
            return kExitCancelled;
        case RubikSolveStatus::Busy:
            return kExitBusy;
        case RubikSolveStatus::NoSolution:
        case RubikSolveStatus::InternalError:
        default:
            return kExitNoSolution;
    }
}

bool ParseCommonArguments(int argc, char** argv, CliOptions* options, std::string* error) {
    for (int i = 2; i < argc; ++i) {
        const std::string argument = argv[i];
        auto requireValue = [&](const char* name) -> const char* {
            if (i + 1 >= argc) {
                *error = std::string("Option ") + name + " requires a value.";
                return nullptr;
            }
            return argv[++i];
        };

        if (argument == "--json") {
            options->json = true;
        } else if (argument == "--facelets") {
            const char* value = requireValue("--facelets");
            if (!value) return false;
            options->facelets = value;
        } else if (argument == "--moves") {
            const char* value = requireValue("--moves");
            if (!value) return false;
            options->moves = value;
        } else if (argument == "--engine") {
            const char* value = requireValue("--engine");
            if (!value) return false;
            options->engine = ToLower(value);
            if (options->engine != "exact" && options->engine != "neural" &&
                options->engine != "hybrid") {
                *error = "Unknown engine \"" + std::string(value) + "\". Use exact, neural, or hybrid.";
                return false;
            }
        } else if (argument == "--timeout") {
            const char* value = requireValue("--timeout");
            if (!value || !ParseDouble(value, &options->timeoutSeconds) ||
                options->timeoutSeconds <= 0.0) {
                *error = "Invalid --timeout value.";
                return false;
            }
        } else if (argument == "--neural-budget") {
            const char* value = requireValue("--neural-budget");
            if (!value || !ParseDouble(value, &options->neuralBudgetSeconds) ||
                options->neuralBudgetSeconds <= 0.0) {
                *error = "Invalid --neural-budget value.";
                return false;
            }
        } else if (argument == "--max-depth") {
            const char* value = requireValue("--max-depth");
            if (!value || !ParseInt(value, &options->maxDepth) ||
                options->maxDepth < 1 || options->maxDepth > 30) {
                *error = "Invalid --max-depth value (expected 1-30).";
                return false;
            }
        } else if (argument == "--beam-width") {
            const char* value = requireValue("--beam-width");
            if (!value || !ParseInt(value, &options->beamWidth) || options->beamWidth < 1) {
                *error = "Invalid --beam-width value.";
                return false;
            }
        } else if (argument == "--max-nodes") {
            const char* value = requireValue("--max-nodes");
            if (!value || !ParseInt(value, &options->maxNodes) || options->maxNodes < 1) {
                *error = "Invalid --max-nodes value.";
                return false;
            }
        } else if (argument == "--scramble") {
            const char* value = requireValue("--scramble");
            if (!value || !ParseInt(value, &options->scrambleLength) ||
                options->scrambleLength < 1 || options->scrambleLength > 100) {
                *error = "Invalid --scramble value (expected 1-100).";
                return false;
            }
        } else if (argument == "--seed") {
            const char* value = requireValue("--seed");
            if (!value || !ParseLongLong(value, &options->seed)) {
                *error = "Invalid --seed value.";
                return false;
            }
        } else if (argument == "--cache-dir") {
            const char* value = requireValue("--cache-dir");
            if (!value) return false;
            options->cacheDir = value;
        } else if (argument == "--no-verify") {
            options->verify = false;
        } else if (argument == "--no-simplify") {
            options->simplify = false;
        } else if (argument == "-h" || argument == "--help") {
            PrintUsage(stdout);
            std::exit(kExitSuccess);
        } else if (argument == "--version") {
            std::printf("rubik-cli 1.0.0\n");
            std::exit(kExitSuccess);
        } else {
            *error = "Unknown option \"" + argument + "\".";
            return false;
        }
    }
    return true;
}

RubikSolverOptions MakeSolverOptions(const CliOptions& cli) {
    RubikSolverOptions options;
    if (cli.engine == "exact") {
        options.kind = RubikSolverKind::Exact;
    } else if (cli.engine == "neural") {
        options.kind = RubikSolverKind::Neural;
    } else {
        options.kind = RubikSolverKind::Hybrid;
    }
    options.timeoutSeconds = static_cast<long>(std::llround(cli.timeoutSeconds));
    options.maxDepth = cli.maxDepth;
    options.simplify = cli.simplify;
    options.verify = cli.verify;
    options.neuralTimeBudgetSeconds = static_cast<float>(cli.neuralBudgetSeconds);
    if (cli.beamWidth > 0) options.neuralBeamWidth = cli.beamWidth;
    if (cli.maxNodes > 0) options.neuralMaxNodes = cli.maxNodes;
    return options;
}

std::vector<int> GenerateScramble(int length, long long seed, long long* usedSeed) {
    if (seed < 0) {
        seed = static_cast<long long>(
            std::chrono::system_clock::now().time_since_epoch().count());
    }
    *usedSeed = seed;

    std::mt19937 rng(static_cast<uint32_t>(seed));
    std::uniform_int_distribution<int> faceDist(0, 5);
    std::uniform_int_distribution<int> suffixDist(0, 2);

    std::vector<int> moves;
    moves.reserve(length);
    int lastFace = -1;
    int secondLastFace = -1;
    for (int i = 0; i < length; ++i) {
        int face = faceDist(rng);
        while (face == lastFace || (face == secondLastFace && face % 3 == lastFace % 3)) {
            face = faceDist(rng);
        }
        moves.push_back(face * 3 + suffixDist(rng));
        secondLastFace = lastFace;
        lastFace = face;
    }
    return moves;
}

int CommandVerify(const CliOptions& cli, const uint8_t facelets[54]) {
    const RubikValidationResult validation = RubikValidateFacelets(facelets);

    if (cli.json) {
        std::printf("{\"ok\":%s,\"command\":\"verify\",\"facelets\":%s,\"valid\":%s,"
                    "\"code\":%s,\"message\":%s}\n",
                    validation.valid ? "true" : "false",
                    JsonString(RubikCube(facelets).toFaceletString()).c_str(),
                    validation.valid ? "true" : "false",
                    JsonString(RubikValidationCodeName(validation.code)).c_str(),
                    JsonString(validation.message).c_str());
    } else if (validation.valid) {
        std::printf("Valid cube (%s).\n", RubikValidationCodeName(validation.code));
    } else {
        std::fprintf(stderr, "Invalid cube [%s]: %s\n",
                     RubikValidationCodeName(validation.code), validation.message.c_str());
    }

    return validation.valid ? kExitSuccess : kExitInvalidState;
}

int CommandOrient(const CliOptions& cli, const uint8_t facelets[54]) {
    const RubikOrientationResult result = RubikRecoverOrientation(facelets);

    if (cli.json) {
        std::printf("{\"ok\":%s,\"command\":\"orient\",\"success\":%s,\"ambiguous\":%s,"
                    "\"validCandidates\":%d,\"rotations\":%s,\"facelets\":%s,"
                    "\"message\":%s}\n",
                    result.success ? "true" : "false",
                    result.success ? "true" : "false",
                    result.ambiguous ? "true" : "false",
                    result.validCandidates,
                    JsonIntArray(std::vector<int>(result.rotations, result.rotations + 6)).c_str(),
                    JsonString(RubikCube(result.facelets).toFaceletString()).c_str(),
                    JsonString(result.message).c_str());
    } else if (result.success) {
        std::printf("Orientation recovered (%d valid candidate%s%s).\n",
                    result.validCandidates,
                    result.validCandidates == 1 ? "" : "s",
                    result.ambiguous ? ", ambiguous" : "");
        std::printf("Rotations (clockwise quarter-turns per face U R F D L B): %s\n",
                    JsonIntArray(std::vector<int>(result.rotations, result.rotations + 6)).c_str());
        std::printf("Facelets: %s\n", RubikCube(result.facelets).toFaceletString().c_str());
    } else {
        std::fprintf(stderr, "Orientation failed: %s\n", result.message.c_str());
    }

    return result.success ? kExitSuccess : kExitOrientation;
}

int CommandState(const CliOptions& cli) {
    RubikCube cube;
    if (!cli.facelets.empty()) {
        uint8_t parsed[54];
        std::string error;
        if (!ParseFacelets(cli.facelets, parsed, &error)) {
            return FailUsage(error, cli.json);
        }
        cube.setFacelets(parsed);
    }

    std::vector<int> scramble;
    long long usedSeed = -1;

    if (cli.scrambleLength > 0) {
        scramble = GenerateScramble(cli.scrambleLength, cli.seed, &usedSeed);
        cube.applyMoves(scramble);
    }

    std::vector<int> moves;
    if (!cli.moves.empty()) {
        std::string error;
        if (!ParseMoves(cli.moves, &moves, &error)) {
            return FailUsage(error, cli.json);
        }
        cube.applyMoves(moves);
    }

    const std::string facelets = cube.toFaceletString();
    if (cli.json) {
        std::string json = "{";
        json += "\"ok\":true,\"command\":\"state\"";
        json += ",\"facelets\":" + JsonString(facelets);
        json += ",\"solved\":" + std::string(cube.isSolved() ? "true" : "false");
        json += ",\"moveCount\":" + std::to_string(moves.size());
        json += ",\"moves\":" + JsonStringArray(MoveNames(moves));
        if (cli.scrambleLength > 0) {
            json += ",\"scramble\":" + JsonStringArray(MoveNames(scramble));
            json += ",\"seed\":" + std::to_string(usedSeed);
        }
        json += "}";
        std::printf("%s\n", json.c_str());
    } else {
        std::printf("%s\n", facelets.c_str());
    }
    return kExitSuccess;
}

int CommandSolve(const CliOptions& cli, const uint8_t facelets[54]) {
    const RubikCube cube(facelets);
    const RubikSolverOptions options = MakeSolverOptions(cli);

    BOOL neuralModelAvailable = NO;
    RubikSolveResult result;

    // Third-party pruning-table generation prints progress on stdout. Keep
    // stdout reserved for the JSON/document output, even on first run.
    std::fflush(stdout);
    const int savedStdout = dup(STDOUT_FILENO);
    if (savedStdout >= 0) {
        dup2(STDERR_FILENO, STDOUT_FILENO);
    }

    if (options.kind == RubikSolverKind::Exact) {
        NSString* cacheDir = nil;
        if (!cli.cacheDir.empty()) {
            cacheDir = [NSString stringWithUTF8String:cli.cacheDir.c_str()];
        } else {
            NSArray<NSString*>* paths = NSSearchPathForDirectoriesInDomains(
                NSApplicationSupportDirectory, NSUserDomainMask, YES);
            NSString* base = paths.firstObject
                                 ?: [NSHomeDirectory() stringByAppendingPathComponent:
                                         @"Library/Application Support"];
            cacheDir = [base stringByAppendingPathComponent:@"RubikSolver/ckociemba-cache"];
        }
        RubikSolverEngine engine(cacheDir.UTF8String ?: "");
        result = engine.solveExact(cube, options);
    } else {
        RubikMetalSolver* solver =
            cli.cacheDir.empty()
                ? [[RubikMetalSolver alloc] init]
                : [[RubikMetalSolver alloc] initWithCacheDir:
                      [NSString stringWithUTF8String:cli.cacheDir.c_str()]];
        neuralModelAvailable = solver.neuralSolver.modelAvailable;
        result = [solver solveCubeTyped:cube options:options];
    }

    std::fflush(stdout);
    if (savedStdout >= 0) {
        dup2(savedStdout, STDOUT_FILENO);
        close(savedStdout);
    }

    const bool ok = result.status == RubikSolveStatus::Success ||
                    result.status == RubikSolveStatus::AlreadySolved;
    const std::vector<std::string> moves = MoveNames(result.moves);

    if (cli.json) {
        std::string json = "{";
        json += "\"ok\":" + std::string(ok ? "true" : "false");
        json += ",\"command\":\"solve\"";
        json += ",\"status\":" + JsonString(RubikSolveStatusName(result.status));
        json += ",\"engineRequested\":" + JsonString(cli.engine);
        json += ",\"engineUsed\":" + JsonString(RubikSolverKindName(result.engineUsed));
        json += ",\"usedFallback\":" + std::string(result.usedFallback ? "true" : "false");
        json += ",\"verified\":" + std::string(result.verified ? "true" : "false");
        json += ",\"alreadySolved\":" + std::string(result.alreadySolved ? "true" : "false");
        json += ",\"moveCount\":" + std::to_string(result.moves.size());
        json += ",\"moves\":" + JsonStringArray(moves);
        json += ",\"solution\":" + JsonString(RubikCube::movesToString(result.moves));
        json += ",\"timeMs\":" + std::to_string(result.timeMs);
        json += ",\"nodesExpanded\":" + std::to_string(result.nodesExpanded);
        json += ",\"neuralModelAvailable\":" +
                std::string(neuralModelAvailable ? "true" : "false");
        json += ",\"validation\":" + ValidationJson(result.validation);
        json += ",\"message\":" + JsonString(result.message);
        json += "}";
        std::printf("%s\n", json.c_str());
    } else if (result.status == RubikSolveStatus::AlreadySolved) {
        std::printf("Cube is already solved.\n");
    } else if (result.status == RubikSolveStatus::Success) {
        std::printf("Solved in %.1f ms with %s%s (%zu moves%s).\n",
                    result.timeMs,
                    RubikSolverKindName(result.engineUsed),
                    result.usedFallback ? " fallback" : "",
                    result.moves.size(),
                    result.verified ? ", verified" : "");
        std::printf("%s\n", RubikCube::movesToString(result.moves).c_str());
    } else {
        std::fprintf(stderr, "Solve failed [%s]: %s\n",
                     RubikSolveStatusName(result.status), result.message.c_str());
    }

    return ExitCodeForSolve(result.status);
}

} // namespace

int main(int argc, char** argv) {
    @autoreleasepool {
        if (argc < 2) {
            PrintUsage(stderr);
            return kExitUsage;
        }

        CliOptions cli;
        cli.command = ToLower(argv[1]);
        if (cli.command == "-h" || cli.command == "--help" || cli.command == "help") {
            PrintUsage(stdout);
            return kExitSuccess;
        }
        if (cli.command == "--version" || cli.command == "version") {
            std::printf("rubik-cli 1.0.0\n");
            return kExitSuccess;
        }

        if (cli.command != "solve" && cli.command != "verify" &&
            cli.command != "orient" && cli.command != "state") {
            std::fprintf(stderr, "rubik-cli: unknown command \"%s\"\n\n", argv[1]);
            PrintUsage(stderr);
            return kExitUsage;
        }

        // Detect --json before parsing so usage failures can honour it.
        for (int i = 2; i < argc; ++i) {
            if (std::strcmp(argv[i], "--json") == 0) cli.json = true;
        }

        std::string error;
        if (!ParseCommonArguments(argc, argv, &cli, &error)) {
            return FailUsage(error, cli.json);
        }

        if (cli.command == "state") {
            return CommandState(cli);
        }

        if (cli.facelets.empty()) {
            return FailUsage("--facelets is required for " + cli.command + ".", cli.json);
        }

        uint8_t facelets[54];
        if (!ParseFacelets(cli.facelets, facelets, &error)) {
            return FailUsage(error, cli.json);
        }

        if (cli.command == "verify") return CommandVerify(cli, facelets);
        if (cli.command == "orient") return CommandOrient(cli, facelets);
        return CommandSolve(cli, facelets);
    }
}
