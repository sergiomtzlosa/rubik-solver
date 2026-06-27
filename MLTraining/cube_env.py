"""
Rubik's Cube Environment & Fast Vectorized Simulator
Uses the exact 18x54 permutation move table matching RubikCube.cpp.
Provides state one-hot encoding into [1, 324] tensors for DeepCubeA inference.
"""

import numpy as np
import torch
from typing import List, Tuple

# Move Names in order 0..17
MOVE_NAMES = [
    "U", "U'", "U2",
    "R", "R'", "R2",
    "F", "F'", "F2",
    "D", "D'", "D2",
    "L", "L'", "L2",
    "B", "B'", "B2"
]

# Inverse moves mapping: invert_move[m]
INVERSE_MOVES = [
    1, 0, 2,   # U <-> U', U2 <-> U2
    4, 3, 5,   # R <-> R', R2 <-> R2
    7, 6, 8,   # F <-> F', F2 <-> F2
    10, 9, 11, # D <-> D', D2 <-> D2
    13, 12, 14,# L <-> L', L2 <-> L2
    16, 15, 17 # B <-> B', B2 <-> B2
]

# Exact 18x54 permutation table: new_state[i] = old_state[perm_table[move][i]]
MOVE_TABLE = np.array([
    # Move 0: U
    [ 6, 3, 0, 7, 4, 1, 8, 5, 2,
     45, 46, 47, 12, 13, 14, 15, 16, 17,
      9, 10, 11, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 33, 34, 35,
     18, 19, 20, 39, 40, 41, 42, 43, 44,
     36, 37, 38, 48, 49, 50, 51, 52, 53],

    # Move 1: U'
    [ 2, 5, 8, 1, 4, 7, 0, 3, 6,
     18, 19, 20, 12, 13, 14, 15, 16, 17,
     36, 37, 38, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 33, 34, 35,
     45, 46, 47, 39, 40, 41, 42, 43, 44,
      9, 10, 11, 48, 49, 50, 51, 52, 53],

    # Move 2: U2
    [ 8, 7, 6, 5, 4, 3, 2, 1, 0,
     36, 37, 38, 12, 13, 14, 15, 16, 17,
     45, 46, 47, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 33, 34, 35,
      9, 10, 11, 39, 40, 41, 42, 43, 44,
     18, 19, 20, 48, 49, 50, 51, 52, 53],

    # Move 3: R
    [ 0, 1, 20, 3, 4, 23, 6, 7, 26,
     15, 12, 9, 16, 13, 10, 17, 14, 11,
     18, 19, 29, 21, 22, 32, 24, 25, 35,
     27, 28, 51, 30, 31, 48, 33, 34, 45,
     36, 37, 38, 39, 40, 41, 42, 43, 44,
      8, 46, 47, 5, 49, 50, 2, 52, 53],

    # Move 4: R'
    [ 0, 1, 51, 3, 4, 48, 6, 7, 45,
     11, 14, 17, 10, 13, 16, 9, 12, 15,
     18, 19, 2, 21, 22, 5, 24, 25, 8,
     27, 28, 20, 30, 31, 23, 33, 34, 26,
     36, 37, 38, 39, 40, 41, 42, 43, 44,
     35, 46, 47, 32, 49, 50, 29, 52, 53],

    # Move 5: R2
    [ 0, 1, 29, 3, 4, 32, 6, 7, 35,
     17, 16, 15, 14, 13, 12, 11, 10, 9,
     18, 19, 51, 21, 22, 48, 24, 25, 45,
     27, 28, 2, 30, 31, 5, 33, 34, 8,
     36, 37, 38, 39, 40, 41, 42, 43, 44,
     26, 46, 47, 23, 49, 50, 20, 52, 53],

    # Move 6: F
    [ 0, 1, 2, 3, 4, 5, 44, 41, 38,
      6, 10, 11, 7, 13, 14, 8, 16, 17,
     24, 21, 18, 25, 22, 19, 26, 23, 20,
     15, 12, 9, 30, 31, 32, 33, 34, 35,
     36, 37, 27, 39, 40, 28, 42, 43, 29,
     45, 46, 47, 48, 49, 50, 51, 52, 53],

    # Move 7: F'
    [ 0, 1, 2, 3, 4, 5, 9, 12, 15,
     29, 10, 11, 28, 13, 14, 27, 16, 17,
     20, 23, 26, 19, 22, 25, 18, 21, 24,
     38, 41, 44, 30, 31, 32, 33, 34, 35,
     36, 37, 8, 39, 40, 7, 42, 43, 6,
     45, 46, 47, 48, 49, 50, 51, 52, 53],

    # Move 8: F2
    [ 0, 1, 2, 3, 4, 5, 29, 28, 27,
     44, 10, 11, 41, 13, 14, 38, 16, 17,
     26, 25, 24, 23, 22, 21, 20, 19, 18,
      8, 7, 6, 30, 31, 32, 33, 34, 35,
     36, 37, 15, 39, 40, 12, 42, 43, 9,
     45, 46, 47, 48, 49, 50, 51, 52, 53],

    # Move 9: D
    [ 0, 1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 24, 25, 26,
     18, 19, 20, 21, 22, 23, 42, 43, 44,
     33, 30, 27, 34, 31, 28, 35, 32, 29,
     36, 37, 38, 39, 40, 41, 51, 52, 53,
     45, 46, 47, 48, 49, 50, 15, 16, 17],

    # Move 10: D'
    [ 0, 1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 51, 52, 53,
     18, 19, 20, 21, 22, 23, 15, 16, 17,
     29, 32, 35, 28, 31, 34, 27, 30, 33,
     36, 37, 38, 39, 40, 41, 24, 25, 26,
     45, 46, 47, 48, 49, 50, 42, 43, 44],

    # Move 11: D2
    [ 0, 1, 2, 3, 4, 5, 6, 7, 8,
      9, 10, 11, 12, 13, 14, 42, 43, 44,
     18, 19, 20, 21, 22, 23, 51, 52, 53,
     35, 34, 33, 32, 31, 30, 29, 28, 27,
     36, 37, 38, 39, 40, 41, 15, 16, 17,
     45, 46, 47, 48, 49, 50, 24, 25, 26],

    # Move 12: L
    [53, 1, 2, 50, 4, 5, 47, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16, 17,
      0, 19, 20, 3, 22, 23, 6, 25, 26,
     18, 28, 29, 21, 31, 32, 24, 34, 35,
     42, 39, 36, 43, 40, 37, 44, 41, 38,
     45, 46, 33, 48, 49, 30, 51, 52, 27],

    # Move 13: L'
    [18, 1, 2, 21, 4, 5, 24, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16, 17,
     27, 19, 20, 30, 22, 23, 33, 25, 26,
     53, 28, 29, 50, 31, 32, 47, 34, 35,
     38, 41, 44, 37, 40, 43, 36, 39, 42,
     45, 46, 6, 48, 49, 3, 51, 52, 0],

    # Move 14: L2
    [27, 1, 2, 30, 4, 5, 33, 7, 8,
      9, 10, 11, 12, 13, 14, 15, 16, 17,
     53, 19, 20, 50, 22, 23, 47, 25, 26,
      0, 28, 29, 3, 31, 32, 6, 34, 35,
     44, 43, 42, 41, 40, 39, 38, 37, 36,
     45, 46, 24, 48, 49, 21, 51, 52, 18],

    # Move 15: B
    [11, 14, 17, 3, 4, 5, 6, 7, 8,
      9, 10, 35, 12, 13, 34, 15, 16, 33,
     18, 19, 20, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 36, 39, 42,
      2, 37, 38, 1, 40, 41, 0, 43, 44,
     51, 48, 45, 52, 49, 46, 53, 50, 47],

    # Move 16: B'
    [42, 39, 36, 3, 4, 5, 6, 7, 8,
      9, 10, 0, 12, 13, 1, 15, 16, 2,
     18, 19, 20, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 17, 14, 11,
     33, 37, 38, 34, 40, 41, 35, 43, 44,
     47, 50, 53, 46, 49, 52, 45, 48, 51],

    # Move 17: B2
    [35, 34, 33, 3, 4, 5, 6, 7, 8,
      9, 10, 42, 12, 13, 39, 15, 16, 36,
     18, 19, 20, 21, 22, 23, 24, 25, 26,
     27, 28, 29, 30, 31, 32, 2, 1, 0,
     17, 37, 38, 14, 40, 41, 11, 43, 44,
     53, 52, 51, 50, 49, 48, 47, 46, 45]
], dtype=np.uint8)


class RubikCubeEnv:
    """
    Pure Python simulator of a 3x3 Rubik's Cube with fast NumPy vectorization.
    Solved state: 9 of 0s, 9 of 1s, 9 of 2s, 9 of 3s, 9 of 4s, 9 of 5s.
    """
    def __init__(self):
        # 54 facelets array
        self.state = np.repeat(np.arange(6, dtype=np.uint8), 9)

    def reset(self):
        """Reset to solved cube."""
        self.state = np.repeat(np.arange(6, dtype=np.uint8), 9)
        return self.state.copy()

    def apply_move(self, move_idx: int) -> np.ndarray:
        """Apply a Singmaster move (0..17) to the current state."""
        self.state = self.state[MOVE_TABLE[move_idx]]
        return self.state.copy()

    def apply_moves(self, moves: List[int]) -> np.ndarray:
        """Apply a sequence of moves."""
        for m in moves:
            self.apply_move(m)
        return self.state.copy()

    def is_solved(self) -> bool:
        """Returns True if all 6 faces are monochromatic."""
        for face in range(6):
            if not np.all(self.state[face * 9 : (face + 1) * 9] == face):
                return False
        return True

    def scramble(self, num_moves: int = 20) -> List[int]:
        """Scramble the cube with random moves (avoiding consecutive self-inverses)."""
        moves = []
        last_face = -1
        for _ in range(num_moves):
            while True:
                m = np.random.randint(0, 18)
                face = m // 3
                if face != last_face:
                    last_face = face
                    moves.append(m)
                    self.apply_move(m)
                    break
        return moves

    def to_one_hot(self) -> np.ndarray:
        """Encode 54 facelets into [324] one-hot float32 array."""
        one_hot = np.zeros(324, dtype=np.float32)
        for i, color in enumerate(self.state):
            one_hot[i * 6 + int(color)] = 1.0
        return one_hot

    @staticmethod
    def batch_to_one_hot(states: np.ndarray) -> np.ndarray:
        """
        Encode batch of states [N, 54] into [N, 324] one-hot float32 array.
        """
        N = states.shape[0]
        one_hot = np.zeros((N, 324), dtype=np.float32)
        for i in range(54):
            colors = states[:, i].astype(np.int64)
            indices = i * 6 + colors
            one_hot[np.arange(N), indices] = 1.0
        return one_hot

    @staticmethod
    def apply_move_to_state(state: np.ndarray, move_idx: int) -> np.ndarray:
        """Pure function applying move to state."""
        return state[MOVE_TABLE[move_idx]]


if __name__ == "__main__":
    cube = RubikCubeEnv()
    print("Initialized solved cube:")
    print("Is solved:", cube.is_solved())
    print("Applying R U R' U'...")
    moves = [3, 0, 4, 1] # R, U, R', U'
    cube.apply_moves(moves)
    print("Is solved:", cube.is_solved())
    print("Applying sequence 5 more times (total 6 cycles should solve)...")
    for _ in range(5):
        cube.apply_moves(moves)
    print("Is solved after 6 cycles:", cube.is_solved())
    assert cube.is_solved(), "Cycle test failed!"
    print("One-hot encoding shape:", cube.to_one_hot().shape)
    print("All cube environment checks passed!")
