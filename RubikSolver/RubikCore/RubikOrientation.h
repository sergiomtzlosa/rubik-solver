//
//  RubikOrientation.h
//  RubikSolver - Face Orientation Recovery
//

#ifndef RubikOrientation_h
#define RubikOrientation_h

#include "RubikTypes.h"
#include <string>

struct RubikOrientationResult {
    bool success = false;
    bool ambiguous = false;
    int validCandidates = 0;
    uint8_t facelets[54] = {0};
    int rotations[6] = {0}; // clockwise quarter-turns applied per face
    std::string message;
};

/// Recover the most likely orientation of a captured cube.
///
/// A photo of each face can be rotated arbitrarily in-plane. Trying all
/// 4^6 face rotations and keeping the cubie-valid results recovers the
/// canonical layout. If several distinct valid states remain, the result is
/// marked ambiguous and the candidate with the fewest rotations is returned.
RubikOrientationResult RubikRecoverOrientation(const uint8_t facelets[54]);

/// Rotate one 3x3 face grid clockwise by `turns` quarter-turns.
void RubikRotateFaceClockwise(uint8_t facelets[54], int face, int turns);

#endif /* RubikOrientation_h */
