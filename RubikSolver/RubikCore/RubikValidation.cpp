//
//  RubikValidation.cpp
//  RubikSolver - Full Cubie-Level Validation
//

#include "RubikValidation.h"

extern "C" {
#include "ckociemba/include/facecube.h"
#include "ckociemba/include/cubiecube.h"
}

#include <cstdlib>
#include <cstring>

const char* RubikValidationCodeName(RubikValidationCode code) {
    switch (code) {
        case RubikValidationCode::Valid: return "valid";
        case RubikValidationCode::ColorCount: return "color-count";
        case RubikValidationCode::EdgeExistence: return "edge-existence";
        case RubikValidationCode::EdgeFlip: return "edge-flip";
        case RubikValidationCode::CornerExistence: return "corner-existence";
        case RubikValidationCode::CornerTwist: return "corner-twist";
        case RubikValidationCode::Parity: return "parity";
        case RubikValidationCode::CenterColor: return "center-color";
        default: return "unknown";
    }
}

const char* RubikValidationCodeDescription(RubikValidationCode code) {
    switch (code) {
        case RubikValidationCode::Valid:
            return "The cube state is valid.";
        case RubikValidationCode::ColorCount:
            return "Each of the six colors must appear exactly nine times.";
        case RubikValidationCode::EdgeExistence:
            return "The edge pieces do not match a real cube (duplicate or missing edge).";
        case RubikValidationCode::EdgeFlip:
            return "One edge is flipped. A real cube cannot have a single flipped edge.";
        case RubikValidationCode::CornerExistence:
            return "The corner pieces do not match a real cube (duplicate or missing corner).";
        case RubikValidationCode::CornerTwist:
            return "One corner is twisted. A real cube cannot have a single twisted corner.";
        case RubikValidationCode::Parity:
            return "The corner and edge permutations have different parity.";
        case RubikValidationCode::CenterColor:
            return "The center stickers do not match the standard color scheme.";
        default:
            return "The cube state could not be validated.";
    }
}

static RubikValidationCode CodeFromVerifyResult(int result) {
    int code = result < 0 ? -result : result;
    switch (code) {
        case 0: return RubikValidationCode::Valid;
        case 1: return RubikValidationCode::ColorCount;
        case 2: return RubikValidationCode::EdgeExistence;
        case 3: return RubikValidationCode::EdgeFlip;
        case 4: return RubikValidationCode::CornerExistence;
        case 5: return RubikValidationCode::CornerTwist;
        case 6: return RubikValidationCode::Parity;
        default: return RubikValidationCode::Unknown;
    }
}

RubikValidationResult RubikValidateFacelets(const uint8_t facelets[54]) {
    RubikValidationResult result;
    if (!facelets) {
        result.code = RubikValidationCode::Unknown;
        result.message = "No facelet data was provided.";
        return result;
    }

    char faceletString[55];
    static const char faceChars[6] = {'U', 'R', 'F', 'D', 'L', 'B'};
    int colorCounts[6] = {0};
    for (int i = 0; i < 54; ++i) {
        if (facelets[i] >= 6) {
            result.code = RubikValidationCode::Unknown;
            result.message = "Invalid color index at facelet " + std::to_string(i) + ".";
            return result;
        }
        faceletString[i] = faceChars[facelets[i]];
        ++colorCounts[facelets[i]];
    }
    faceletString[54] = '\0';

    for (int color = 0; color < 6; ++color) {
        if (colorCounts[color] != 9) {
            result.code = RubikValidationCode::ColorCount;
            result.message = std::string("Color ") + faceChars[color] + " appears " +
                             std::to_string(colorCounts[color]) +
                             " times; every color must appear exactly 9 times.";
            return result;
        }
    }

    // Centers define the color scheme. A state whose centers are swapped or
    // duplicated cannot be mapped onto the standard U/R/F/D/L/B frame.
    for (int face = 0; face < 6; ++face) {
        if (facelets[face * 9 + 4] != face) {
            result.code = RubikValidationCode::CenterColor;
            result.message = std::string("The ") + faceChars[face] +
                             " center is not the expected color (" +
                             faceChars[face] + ").";
            return result;
        }
    }

    facecube_t* facecube = get_facecube_fromstring(faceletString);
    if (!facecube) {
        result.code = RubikValidationCode::Unknown;
        result.message = "Could not build a facelet cube from the supplied state.";
        return result;
    }

    cubiecube_t* cubiecube = toCubieCube(facecube);
    if (!cubiecube) {
        free(facecube);
        result.code = RubikValidationCode::Unknown;
        result.message = "Could not build a cubie cube from the supplied state.";
        return result;
    }

    const int verifyResult = verify(cubiecube);
    free(facecube);
    free(cubiecube);

    result.code = CodeFromVerifyResult(verifyResult);
    result.valid = (result.code == RubikValidationCode::Valid);
    if (result.valid) {
        result.message = RubikValidationCodeDescription(result.code);
    } else {
        result.message = std::string(RubikValidationCodeDescription(result.code)) +
                         " (" + RubikValidationCodeName(result.code) + ")";
    }
    return result;
}

RubikValidationResult RubikValidateCube(const RubikCube& cube) {
    return RubikValidateFacelets(cube.getFacelets());
}
