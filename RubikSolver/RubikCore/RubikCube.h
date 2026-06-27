//
//  RubikCube.h
//  RubikSolver - Pure C++ Cube Model
//

#ifndef RubikCube_h
#define RubikCube_h

#include "RubikTypes.h"
#include <string>
#include <vector>

class RubikCube {
public:
    RubikCube();
    explicit RubikCube(const uint8_t facelets[54]);
    explicit RubikCube(const std::string& faceletString);

    void reset();
    bool isSolved() const;
    
    // Move execution
    void applyMove(int move);
    void applyMoves(const std::vector<int>& moves);
    void applyAlgorithm(const std::string& algorithm);
    
    // Scramble
    std::vector<int> scramble(int numMoves = 20);

    // State getters and setters
    const uint8_t* getFacelets() const { return m_state.facelets; }
    uint8_t getFacelet(int index) const { return m_state.facelets[index]; }
    void setFacelet(int index, uint8_t color) { m_state.facelets[index] = color; }
    void setFacelets(const uint8_t facelets[54]);

    const GPURubikState& getState() const { return m_state; }
    void setState(const GPURubikState& state) { m_state = state; }

    // Helpers & validation
    bool isValidCube(std::string* errorMsg = nullptr) const;
    std::string toFaceletString() const;
    
    // Move notation helpers
    static std::string moveToString(int move);
    static int stringToMove(const std::string& moveStr);
    static std::string movesToString(const std::vector<int>& moves);
    static std::vector<int> stringToMoves(const std::string& movesStr);
    static std::string moveDescription(int move);
    static int invertMove(int move);

    /// Combine consecutive same-face moves (U U -> U2, U U' -> nothing).
    static std::vector<int> simplifyMoves(const std::vector<int>& moves);

    // Permutation table: permTable[move][destIdx] = srcIdx
    // such that new_state[i] = old_state[permTable[move][i]]
    static const uint8_t s_moveTable[NUM_MOVES][54];

private:
    GPURubikState m_state;
};

#endif /* RubikCube_h */
