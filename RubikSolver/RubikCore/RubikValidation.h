//
//  RubikValidation.h
//  RubikSolver - Full Cubie-Level Validation
//

#ifndef RubikValidation_h
#define RubikValidation_h

#include "RubikCube.h"
#include <string>

enum class RubikValidationCode {
    Valid = 0,
    ColorCount = 1,
    EdgeExistence = 2,
    EdgeFlip = 3,
    CornerExistence = 4,
    CornerTwist = 5,
    Parity = 6,
    CenterColor = 7,
    Unknown = 99
};

struct RubikValidationResult {
    bool valid = false;
    RubikValidationCode code = RubikValidationCode::Unknown;
    std::string message;
};

/// Validate a raw 54-facelet state using ckociemba's full cubie checks.
RubikValidationResult RubikValidateFacelets(const uint8_t facelets[54]);

/// Validate a cube model.
RubikValidationResult RubikValidateCube(const RubikCube& cube);

/// Human-readable name for a validation code.
const char* RubikValidationCodeName(RubikValidationCode code);

/// Human-readable explanation for a validation code.
const char* RubikValidationCodeDescription(RubikValidationCode code);

#endif /* RubikValidation_h */
