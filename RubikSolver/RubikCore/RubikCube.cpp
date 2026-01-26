//
//  RubikCube.cpp
//  RubikSolver - Pure C++ Cube Model
//

#include "RubikCube.h"
#include "RubikValidation.h"
#include <sstream>
#include <algorithm>
#include <random>
#include <chrono>

// Include exact precomputed 18x54 move permutation table
const uint8_t RubikCube::s_moveTable[NUM_MOVES][54] = {
    { // Move 0: U
        6, 3, 0, 7, 4, 1, 8, 5, 2, 
        45, 46, 47, 12, 13, 14, 15, 16, 17, 
        9, 10, 11, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 33, 34, 35, 
        18, 19, 20, 39, 40, 41, 42, 43, 44, 
        36, 37, 38, 48, 49, 50, 51, 52, 53
    },
    { // Move 1: U'
        2, 5, 8, 1, 4, 7, 0, 3, 6, 
        18, 19, 20, 12, 13, 14, 15, 16, 17, 
        36, 37, 38, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 33, 34, 35, 
        45, 46, 47, 39, 40, 41, 42, 43, 44, 
        9, 10, 11, 48, 49, 50, 51, 52, 53
    },
    { // Move 2: U2
        8, 7, 6, 5, 4, 3, 2, 1, 0, 
        36, 37, 38, 12, 13, 14, 15, 16, 17, 
        45, 46, 47, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 33, 34, 35, 
        9, 10, 11, 39, 40, 41, 42, 43, 44, 
        18, 19, 20, 48, 49, 50, 51, 52, 53
    },
    { // Move 3: R
        0, 1, 20, 3, 4, 23, 6, 7, 26, 
        15, 12, 9, 16, 13, 10, 17, 14, 11, 
        18, 19, 29, 21, 22, 32, 24, 25, 35, 
        27, 28, 51, 30, 31, 48, 33, 34, 45, 
        36, 37, 38, 39, 40, 41, 42, 43, 44, 
        8, 46, 47, 5, 49, 50, 2, 52, 53
    },
    { // Move 4: R'
        0, 1, 51, 3, 4, 48, 6, 7, 45, 
        11, 14, 17, 10, 13, 16, 9, 12, 15, 
        18, 19, 2, 21, 22, 5, 24, 25, 8, 
        27, 28, 20, 30, 31, 23, 33, 34, 26, 
        36, 37, 38, 39, 40, 41, 42, 43, 44, 
        35, 46, 47, 32, 49, 50, 29, 52, 53
    },
    { // Move 5: R2
        0, 1, 29, 3, 4, 32, 6, 7, 35, 
        17, 16, 15, 14, 13, 12, 11, 10, 9, 
        18, 19, 51, 21, 22, 48, 24, 25, 45, 
        27, 28, 2, 30, 31, 5, 33, 34, 8, 
        36, 37, 38, 39, 40, 41, 42, 43, 44, 
        26, 46, 47, 23, 49, 50, 20, 52, 53
    },
    { // Move 6: F
        0, 1, 2, 3, 4, 5, 44, 41, 38, 
        6, 10, 11, 7, 13, 14, 8, 16, 17, 
        24, 21, 18, 25, 22, 19, 26, 23, 20, 
        15, 12, 9, 30, 31, 32, 33, 34, 35, 
        36, 37, 27, 39, 40, 28, 42, 43, 29, 
        45, 46, 47, 48, 49, 50, 51, 52, 53
    },
    { // Move 7: F'
        0, 1, 2, 3, 4, 5, 9, 12, 15, 
        29, 10, 11, 28, 13, 14, 27, 16, 17, 
        20, 23, 26, 19, 22, 25, 18, 21, 24, 
        38, 41, 44, 30, 31, 32, 33, 34, 35, 
        36, 37, 8, 39, 40, 7, 42, 43, 6, 
        45, 46, 47, 48, 49, 50, 51, 52, 53
    },
    { // Move 8: F2
        0, 1, 2, 3, 4, 5, 29, 28, 27, 
        44, 10, 11, 41, 13, 14, 38, 16, 17, 
        26, 25, 24, 23, 22, 21, 20, 19, 18, 
        8, 7, 6, 30, 31, 32, 33, 34, 35, 
        36, 37, 15, 39, 40, 12, 42, 43, 9, 
        45, 46, 47, 48, 49, 50, 51, 52, 53
    },
    { // Move 9: D
        0, 1, 2, 3, 4, 5, 6, 7, 8, 
        9, 10, 11, 12, 13, 14, 24, 25, 26, 
        18, 19, 20, 21, 22, 23, 42, 43, 44, 
        33, 30, 27, 34, 31, 28, 35, 32, 29, 
        36, 37, 38, 39, 40, 41, 51, 52, 53, 
        45, 46, 47, 48, 49, 50, 15, 16, 17
    },
    { // Move 10: D'
        0, 1, 2, 3, 4, 5, 6, 7, 8, 
        9, 10, 11, 12, 13, 14, 51, 52, 53, 
        18, 19, 20, 21, 22, 23, 15, 16, 17, 
        29, 32, 35, 28, 31, 34, 27, 30, 33, 
        36, 37, 38, 39, 40, 41, 24, 25, 26, 
        45, 46, 47, 48, 49, 50, 42, 43, 44
    },
    { // Move 11: D2
        0, 1, 2, 3, 4, 5, 6, 7, 8, 
        9, 10, 11, 12, 13, 14, 42, 43, 44, 
        18, 19, 20, 21, 22, 23, 51, 52, 53, 
        35, 34, 33, 32, 31, 30, 29, 28, 27, 
        36, 37, 38, 39, 40, 41, 15, 16, 17, 
        45, 46, 47, 48, 49, 50, 24, 25, 26
    },
    { // Move 12: L
        53, 1, 2, 50, 4, 5, 47, 7, 8, 
        9, 10, 11, 12, 13, 14, 15, 16, 17, 
        0, 19, 20, 3, 22, 23, 6, 25, 26, 
        18, 28, 29, 21, 31, 32, 24, 34, 35, 
        42, 39, 36, 43, 40, 37, 44, 41, 38, 
        45, 46, 33, 48, 49, 30, 51, 52, 27
    },
    { // Move 13: L'
        18, 1, 2, 21, 4, 5, 24, 7, 8, 
        9, 10, 11, 12, 13, 14, 15, 16, 17, 
        27, 19, 20, 30, 22, 23, 33, 25, 26, 
        53, 28, 29, 50, 31, 32, 47, 34, 35, 
        38, 41, 44, 37, 40, 43, 36, 39, 42, 
        45, 46, 6, 48, 49, 3, 51, 52, 0
    },
    { // Move 14: L2
        27, 1, 2, 30, 4, 5, 33, 7, 8, 
        9, 10, 11, 12, 13, 14, 15, 16, 17, 
        53, 19, 20, 50, 22, 23, 47, 25, 26, 
        0, 28, 29, 3, 31, 32, 6, 34, 35, 
        44, 43, 42, 41, 40, 39, 38, 37, 36, 
        45, 46, 24, 48, 49, 21, 51, 52, 18
    },
    { // Move 15: B
        11, 14, 17, 3, 4, 5, 6, 7, 8, 
        9, 10, 35, 12, 13, 34, 15, 16, 33, 
        18, 19, 20, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 36, 39, 42, 
        2, 37, 38, 1, 40, 41, 0, 43, 44, 
        51, 48, 45, 52, 49, 46, 53, 50, 47
    },
    { // Move 16: B'
        42, 39, 36, 3, 4, 5, 6, 7, 8, 
        9, 10, 0, 12, 13, 1, 15, 16, 2, 
        18, 19, 20, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 17, 14, 11, 
        33, 37, 38, 34, 40, 41, 35, 43, 44, 
        47, 50, 53, 46, 49, 52, 45, 48, 51
    },
    { // Move 17: B2
        35, 34, 33, 3, 4, 5, 6, 7, 8, 
        9, 10, 42, 12, 13, 39, 15, 16, 36, 
        18, 19, 20, 21, 22, 23, 24, 25, 26, 
        27, 28, 29, 30, 31, 32, 2, 1, 0, 
        17, 37, 38, 14, 40, 41, 11, 43, 44, 
        53, 52, 51, 50, 49, 48, 47, 46, 45
    }
};

RubikCube::RubikCube() {
    reset();
}

RubikCube::RubikCube(const uint8_t facelets[54]) {
    setFacelets(facelets);
}

RubikCube::RubikCube(const std::string& faceletString) {
    reset();
    if (faceletString.length() == 54) {
        for (int i = 0; i < 54; i++) {
            char c = faceletString[i];
            switch (c) {
                case 'U': case 'W': m_state.facelets[i] = COLOR_WHITE; break;
                case 'R': m_state.facelets[i] = COLOR_RED; break;
                case 'F': case 'G': m_state.facelets[i] = COLOR_GREEN; break;
                case 'D': case 'Y': m_state.facelets[i] = COLOR_YELLOW; break;
                case 'L': case 'O': m_state.facelets[i] = COLOR_ORANGE; break;
                case 'B': m_state.facelets[i] = COLOR_BLUE; break;
                default: m_state.facelets[i] = (uint8_t)(i / 9); break;
            }
        }
    }
}

void RubikCube::reset() {
    for (int i = 0; i < 54; i++) {
        m_state.facelets[i] = (uint8_t)(i / 9);
    }
}

bool RubikCube::isSolved() const {
    for (int face = 0; face < 6; face++) {
        uint8_t centerColor = m_state.facelets[face * 9 + 4];
        for (int i = 0; i < 9; i++) {
            if (m_state.facelets[face * 9 + i] != centerColor) {
                return false;
            }
        }
    }
    return true;
}

void RubikCube::applyMove(int move) {
    if (move < 0 || move >= NUM_MOVES) return;
    GPURubikState nextState;
    for (int i = 0; i < 54; i++) {
        nextState.facelets[i] = m_state.facelets[s_moveTable[move][i]];
    }
    m_state = nextState;
}

void RubikCube::applyMoves(const std::vector<int>& moves) {
    for (int m : moves) {
        applyMove(m);
    }
}

void RubikCube::applyAlgorithm(const std::string& algorithm) {
    std::vector<int> moves = stringToMoves(algorithm);
    applyMoves(moves);
}

std::vector<int> RubikCube::scramble(int numMoves) {
    std::vector<int> moves;
    moves.reserve(numMoves);

    unsigned seed = (unsigned)std::chrono::system_clock::now().time_since_epoch().count();
    std::mt19937 rng(seed);
    std::uniform_int_distribution<int> faceDist(0, 5);
    std::uniform_int_distribution<int> suffixDist(0, 2);

    int lastFace = -1;
    int secondLastFace = -1;

    for (int i = 0; i < numMoves; i++) {
        int face = faceDist(rng);
        // Avoid redundant moves (e.g. U U', or U D U)
        while (face == lastFace || (face == secondLastFace && (face % 3 == lastFace % 3))) {
            face = faceDist(rng);
        }
        int suffix = suffixDist(rng);
        int move = face * 3 + suffix;
        moves.push_back(move);
        applyMove(move);

        secondLastFace = lastFace;
        lastFace = face;
    }
    return moves;
}

void RubikCube::setFacelets(const uint8_t facelets[54]) {
    for (int i = 0; i < 54; i++) {
        m_state.facelets[i] = facelets[i];
    }
}

bool RubikCube::isValidCube(std::string* errorMsg) const {
    const RubikValidationResult validation = RubikValidateCube(*this);
    if (!validation.valid && errorMsg) {
        *errorMsg = validation.message;
    }
    return validation.valid;
}

std::string RubikCube::toFaceletString() const {
    static const char faceChars[6] = {'U', 'R', 'F', 'D', 'L', 'B'};
    std::string s(54, ' ');
    for (int i = 0; i < 54; i++) {
        uint8_t color = m_state.facelets[i];
        s[i] = (color < 6) ? faceChars[color] : '?';
    }
    return s;
}

std::string RubikCube::moveToString(int move) {
    static const char* const moveNames[NUM_MOVES] = {
        "U", "U'", "U2",
        "R", "R'", "R2",
        "F", "F'", "F2",
        "D", "D'", "D2",
        "L", "L'", "L2",
        "B", "B'", "B2"
    };
    if (move >= 0 && move < NUM_MOVES) {
        return moveNames[move];
    }
    return "";
}

int RubikCube::stringToMove(const std::string& moveStr) {
    for (int i = 0; i < NUM_MOVES; i++) {
        if (moveToString(i) == moveStr) {
            return i;
        }
    }
    return -1;
}

std::string RubikCube::movesToString(const std::vector<int>& moves) {
    std::string s;
    for (size_t i = 0; i < moves.size(); i++) {
        s += moveToString(moves[i]);
        if (i + 1 < moves.size()) s += " ";
    }
    return s;
}

std::vector<int> RubikCube::stringToMoves(const std::string& movesStr) {
    std::vector<int> moves;
    std::stringstream ss(movesStr);
    std::string token;
    while (ss >> token) {
        int m = stringToMove(token);
        if (m != -1) {
            moves.push_back(m);
        }
    }
    return moves;
}

std::string RubikCube::moveDescription(int move) {
    static const char* const descriptions[NUM_MOVES] = {
        "Rotate Top (White) 90° Clockwise",
        "Rotate Top (White) 90° Counter-Clockwise",
        "Rotate Top (White) 180° Half Turn",
        "Rotate Right (Red) 90° Clockwise",
        "Rotate Right (Red) 90° Counter-Clockwise",
        "Rotate Right (Red) 180° Half Turn",
        "Rotate Front (Green) 90° Clockwise",
        "Rotate Front (Green) 90° Counter-Clockwise",
        "Rotate Front (Green) 180° Half Turn",
        "Rotate Bottom (Yellow) 90° Clockwise",
        "Rotate Bottom (Yellow) 90° Counter-Clockwise",
        "Rotate Bottom (Yellow) 180° Half Turn",
        "Rotate Left (Orange) 90° Clockwise",
        "Rotate Left (Orange) 90° Counter-Clockwise",
        "Rotate Left (Orange) 180° Half Turn",
        "Rotate Back (Blue) 90° Clockwise",
        "Rotate Back (Blue) 90° Counter-Clockwise",
        "Rotate Back (Blue) 180° Half Turn"
    };
    if (move >= 0 && move < NUM_MOVES) {
        return descriptions[move];
    }
    return "Unknown Move";
}

int RubikCube::invertMove(int move) {
    if (move < 0 || move >= NUM_MOVES) return -1;
    int base = (move / 3) * 3;
    int suffix = move % 3;
    if (suffix == 0) return base + 1; // X -> X'
    if (suffix == 1) return base + 0; // X' -> X
    return base + 2;                 // X2 -> X2
}

std::vector<int> RubikCube::simplifyMoves(const std::vector<int>& moves) {
    if (moves.size() <= 1) return moves;

    std::vector<int> result;
    result.reserve(moves.size());

    for (int move : moves) {
        if (move < 0 || move >= NUM_MOVES) continue;
        if (result.empty()) {
            result.push_back(move);
            continue;
        }

        const int lastMove = result.back();
        const int face1 = lastMove / 3;
        const int face2 = move / 3;

        if (face1 == face2) {
            // Suffix 0 -> +1 (90 CW), suffix 1 -> +3 (90 CCW), suffix 2 -> +2 (180)
            static const int turnAmounts[3] = {1, 3, 2};
            const int totalTurn = (turnAmounts[lastMove % 3] + turnAmounts[move % 3]) % 4;
            result.pop_back();
            if (totalTurn == 1) result.push_back(face1 * 3 + 0);
            else if (totalTurn == 2) result.push_back(face1 * 3 + 2);
            else if (totalTurn == 3) result.push_back(face1 * 3 + 1);
        } else {
            result.push_back(move);
        }
    }

    return result;
}
