//
//  RubikTypes.h
//  RubikSolver - Core Types & Apple Silicon Acceleration Definitions
//

#ifndef RubikTypes_h
#define RubikTypes_h

#ifdef __METAL_VERSION__
#include <metal_stdlib>
using namespace metal;
#elif defined(__cplusplus)
#include <cstdint>
#include <cstddef>
#else
#include <stdint.h>
#include <stddef.h>
#endif

// Cube Faces
#define FACE_U 0  // Up (White)
#define FACE_R 1  // Right (Red)
#define FACE_F 2  // Front (Green)
#define FACE_D 3  // Down (Yellow)
#define FACE_L 4  // Left (Orange)
#define FACE_B 5  // Back (Blue)
#define NUM_FACES 6

// Cube Colors
#define COLOR_WHITE  0
#define COLOR_RED    1
#define COLOR_GREEN  2
#define COLOR_YELLOW 3
#define COLOR_ORANGE 4
#define COLOR_BLUE   5
#define NUM_COLORS   6

// 18 Standard Singmaster Moves
#define MOVE_U       0
#define MOVE_U_PRIME 1
#define MOVE_U2      2
#define MOVE_R       3
#define MOVE_R_PRIME 4
#define MOVE_R2      5
#define MOVE_F       6
#define MOVE_F_PRIME 7
#define MOVE_F2      8
#define MOVE_D       9
#define MOVE_D_PRIME 10
#define MOVE_D2      11
#define MOVE_L       12
#define MOVE_L_PRIME 13
#define MOVE_L2      14
#define MOVE_B       15
#define MOVE_B_PRIME 16
#define MOVE_B2      17
#define NUM_MOVES    18

// 54 Facelets representation (9 facelets per face, 6 faces)
// U: 0..8, R: 9..17, F: 18..26, D: 27..35, L: 36..44, B: 45..53
struct GPURubikState {
    uint8_t facelets[54];
};

#endif /* RubikTypes_h */
