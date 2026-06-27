"""
DeepCubeA Evaluation & Search Benchmark
=======================================
1. Evaluates solving performance of DeepCubeA using Greedy Best-First Search & Batch A*.
2. Verifies numerical parity between PyTorch checkpoint and converted Core ML model.
"""

import os
import sys
import time
import argparse
import heapq
import numpy as np
import torch
from typing import List, Tuple, Optional

from model import DeepCubeA
from cube_env import RubikCubeEnv, MOVE_NAMES, INVERSE_MOVES


class RubikSearchNode:
    """Search node for A* / Best-First Search."""
    def __init__(self, state: np.ndarray, g: int, h: float, path: List[int], last_face: int = -1):
        self.state = state
        self.g = g          # Path cost from root
        self.h = h          # Heuristic cost-to-go predicted by model
        self.f = g + h      # Total estimated cost
        self.path = path    # List of move indices
        self.last_face = last_face

    def __lt__(self, other):
        if self.f != other.f:
            return self.f < other.f
        return self.h < other.h


def solve_greedy(
    model: torch.nn.Module,
    scramble_moves: List[int],
    max_steps: int = 50,
    device: torch.device = torch.device("cpu")
) -> Tuple[bool, List[int], int]:
    """
    Greedy best-first search guided by DeepCubeA value & policy.
    Returns: (is_solved, solution_moves, expanded_nodes)
    """
    env = RubikCubeEnv()
    env.apply_moves(scramble_moves)

    if env.is_solved():
        return True, [], 0

    solution = []
    visited = set()
    visited.add(env.state.tobytes())

    model.eval()
    nodes_expanded = 0

    with torch.no_grad():
        for step in range(max_steps):
            nodes_expanded += 1
            current_state = env.state.copy()

            # Expand all 18 successor states
            successor_states = [env.apply_move_to_state(current_state, a) for a in range(18)]

            # Check if any successor is solved
            for a, s_next in enumerate(successor_states):
                env_test = RubikCubeEnv()
                env_test.state = s_next.copy()
                if env_test.is_solved():
                    solution.append(a)
                    return True, solution, nodes_expanded

            # Compute heuristics for successors
            batch_one_hot = RubikCubeEnv.batch_to_one_hot(np.array(successor_states))
            tensor_inputs = torch.from_numpy(batch_one_hot).to(device)
            v_preds, _ = model(tensor_inputs)
            v_vals = v_preds.squeeze(-1).cpu().numpy()

            # Choose neighbor with minimum estimated heuristic not already in visited loop
            best_move = -1
            best_val = float("inf")
            for a in range(18):
                succ_bytes = successor_states[a].tobytes()
                if succ_bytes not in visited:
                    if v_vals[a] < best_val:
                        best_val = v_vals[a]
                        best_move = a

            if best_move == -1:
                # Local minimum or loop trapped
                break

            env.apply_move(best_move)
            visited.add(env.state.tobytes())
            solution.append(best_move)

            if env.is_solved():
                return True, solution, nodes_expanded

    return False, solution, nodes_expanded


def test_pytorch_coreml_parity(
    pytorch_checkpoint: str,
    coreml_package: str,
    num_samples: int = 100
):
    """Verifies that PyTorch and Core ML produce identical outputs within Float16 precision."""
    print("\n--- Verifying PyTorch <-> Core ML Parity ---")
    if not os.path.exists(pytorch_checkpoint):
        print(f"Skipping parity check: PyTorch checkpoint {pytorch_checkpoint} not found.")
        return
    if not os.path.exists(coreml_package):
        print(f"Skipping parity check: Core ML package {coreml_package} not found.")
        return

    import coremltools as ct

    # Load PyTorch
    model = DeepCubeA()
    ckpt = torch.load(pytorch_checkpoint, map_location="cpu")
    state_dict = ckpt["model_state"] if "model_state" in ckpt else ckpt
    model.load_state_dict(state_dict)
    model.eval()

    # Load Core ML
    coreml_model = ct.models.MLModel(coreml_package)

    max_v_diff = 0.0
    max_p_diff = 0.0

    print(f"Testing parity across {num_samples} randomly scrambled cube states...")
    env = RubikCubeEnv()

    for i in range(num_samples):
        env.reset()
        env.scramble(num_moves=np.random.randint(1, 25))
        one_hot = env.to_one_hot()

        # PyTorch prediction
        with torch.no_grad():
            pt_input = torch.from_numpy(one_hot).unsqueeze(0)
            pt_v, pt_p = model(pt_input)
            pt_v = pt_v.numpy().flatten()
            pt_p = pt_p.numpy().flatten()

        # Core ML prediction
        cml_input = {"cube_state": one_hot.reshape(1, 324)}
        cml_out = coreml_model.predict(cml_input)
        cml_v = np.array(cml_out["value"]).flatten()
        cml_p = np.array(cml_out["policy"]).flatten()

        v_diff = np.max(np.abs(pt_v - cml_v))
        p_diff = np.max(np.abs(pt_p - cml_p))

        if v_diff > max_v_diff:
            max_v_diff = v_diff
        if p_diff > max_p_diff:
            max_p_diff = p_diff

    print(f"Max Value Output Difference:  {max_v_diff:.6f} (Tolerance: < 0.05)")
    print(f"Max Policy Output Difference: {max_p_diff:.6f} (Tolerance: < 0.05)")

    if max_v_diff < 0.05 and max_p_diff < 0.05:
        print("✅ Numerical Parity Verification Passed: PyTorch and Core ML match within Float16 precision!")
    else:
        print("⚠️ Parity discrepancy exceeds expected bounds.")


def run_benchmark(checkpoint_path: str, depths: List[int], trials_per_depth: int = 10):
    print("=== DeepCubeA Benchmark Suite ===")
    device = torch.device("cpu")
    model = DeepCubeA()
    if os.path.exists(checkpoint_path):
        print(f"Loading weights from {checkpoint_path}...")
        ckpt = torch.load(checkpoint_path, map_location=device)
        state_dict = ckpt["model_state"] if "model_state" in ckpt else ckpt
        model.load_state_dict(state_dict)
    else:
        print(f"Note: Checkpoint {checkpoint_path} not found. Running benchmark with baseline architecture.")

    model.eval()

    print(f"\n{'Depth':<8} | {'Solved Rate':<12} | {'Avg Nodes':<12} | {'Avg Time (ms)':<14} | {'Example Moves'}")
    print("-" * 75)

    for depth in depths:
        solved_count = 0
        total_nodes = 0
        total_time_ms = 0.0
        example_solution = ""

        for trial in range(trials_per_depth):
            env = RubikCubeEnv()
            scramble = env.scramble(num_moves=depth)

            t0 = time.time()
            solved, sol_moves, nodes = solve_greedy(model, scramble, max_steps=depth * 3)
            dt_ms = (time.time() - t0) * 1000.0

            if solved:
                solved_count += 1
                if not example_solution:
                    example_solution = " ".join([MOVE_NAMES[m] for m in sol_moves[:8]])
                    if len(sol_moves) > 8:
                        example_solution += "..."

            total_nodes += nodes
            total_time_ms += dt_ms

        rate = (solved_count / trials_per_depth) * 100.0
        avg_nodes = total_nodes / trials_per_depth
        avg_time = total_time_ms / trials_per_depth

        print(f"{depth:<8} | {rate:6.1f}%      | {avg_nodes:<12.1f} | {avg_time:<14.1f} | {example_solution or 'N/A'}")


def parse_args():
    parser = argparse.ArgumentParser(description="Evaluate DeepCubeA Model")
    parser.add_argument("--checkpoint", type=str, default="checkpoints/deepcubea_checkpoint.pt", help="Path to PyTorch checkpoint")
    parser.add_argument("--coreml-package", type=str, default="DeepCubeA.mlpackage", help="Path to Core ML package")
    parser.add_argument("--check-parity", action="store_true", help="Run numerical parity test between PyTorch and Core ML")
    parser.add_argument("--depths", nargs="+", type=int, default=[1, 2, 3, 5, 8], help="Scramble depths to benchmark")
    parser.add_argument("--trials", type=int, default=5, help="Trials per scramble depth")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    if args.check_parity:
        test_pytorch_coreml_parity(args.checkpoint, args.coreml_package)
    else:
        run_benchmark(args.checkpoint, args.depths, args.trials)
