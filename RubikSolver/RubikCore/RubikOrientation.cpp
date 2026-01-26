//
//  RubikOrientation.cpp
//  RubikSolver - Face Orientation Recovery
//

#include "RubikOrientation.h"
#include "RubikValidation.h"

#include <array>
#include <set>
#include <string>
#include <vector>

void RubikRotateFaceClockwise(uint8_t facelets[54], int face, int turns) {
    if (!facelets || face < 0 || face >= 6) return;
    turns = ((turns % 4) + 4) % 4;
    if (turns == 0) return;

    const int offset = face * 9;
    uint8_t source[9];
    for (int i = 0; i < 9; ++i) source[i] = facelets[offset + i];

    for (int turn = 0; turn < turns; ++turn) {
        for (int row = 0; row < 3; ++row) {
            for (int col = 0; col < 3; ++col) {
                // Clockwise: new[col][2-row] = old[row][col]
                facelets[offset + col * 3 + (2 - row)] = source[row * 3 + col];
            }
        }
        for (int i = 0; i < 9; ++i) source[i] = facelets[offset + i];
    }
}

static std::string StateKey(const uint8_t facelets[54]) {
    std::string key;
    key.resize(54);
    for (int i = 0; i < 54; ++i) key[i] = static_cast<char>(facelets[i]);
    return key;
}

RubikOrientationResult RubikRecoverOrientation(const uint8_t facelets[54]) {
    RubikOrientationResult result;
    if (!facelets) {
        result.message = "No facelet data was provided.";
        return result;
    }

    // Check color counts once before the expensive search.
    const RubikValidationResult base = RubikValidateFacelets(facelets);
    if (base.code == RubikValidationCode::ColorCount ||
        base.code == RubikValidationCode::CenterColor ||
        base.code == RubikValidationCode::Unknown) {
        result.message = base.message;
        return result;
    }

    std::set<std::string> seenStates;
    int bestCost = 1 << 30;
    uint8_t bestState[54] = {0};
    int bestRotations[6] = {0};
    int distinctValid = 0;

    for (int mask = 0; mask < 4096; ++mask) {
        int rotations[6];
        int encoded = mask;
        int cost = 0;
        for (int face = 0; face < 6; ++face) {
            rotations[face] = encoded & 3;
            encoded >>= 2;
            cost += rotations[face];
        }

        uint8_t candidate[54];
        for (int i = 0; i < 54; ++i) candidate[i] = facelets[i];
        for (int face = 0; face < 6; ++face) {
            RubikRotateFaceClockwise(candidate, face, rotations[face]);
        }

        const RubikValidationResult validation = RubikValidateFacelets(candidate);
        if (!validation.valid) continue;

        ++result.validCandidates;
        const std::string key = StateKey(candidate);
        if (seenStates.insert(key).second) {
            ++distinctValid;
        }

        if (cost < bestCost) {
            bestCost = cost;
            for (int i = 0; i < 54; ++i) bestState[i] = candidate[i];
            for (int face = 0; face < 6; ++face) bestRotations[face] = rotations[face];
        }
    }

    if (seenStates.empty()) {
        result.message = "No valid cube orientation was found. Check the face colors and scan order.";
        return result;
    }

    result.success = true;
    result.ambiguous = (distinctValid > 1);
    for (int i = 0; i < 54; ++i) result.facelets[i] = bestState[i];
    for (int face = 0; face < 6; ++face) result.rotations[face] = bestRotations[face];

    if (result.ambiguous) {
        result.message = "The scan has more than one valid orientation. Review and correct the faces.";
    } else {
        result.message = "Cube orientation recovered.";
    }
    return result;
}
