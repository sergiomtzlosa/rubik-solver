"""
Autodidactic Iteration (ADI) Training Pipeline for DeepCubeA
===========================================================
Trains the dual-head DeepCubeA model to predict:
1. Value heuristic: Estimated cost-to-go (number of moves to solved state)
2. Policy: Distribution over 18 Singmaster moves pointing toward the solution

Based on the DeepCubeA paper (McAleer et al., Nature Machine Intelligence 2019):
"Solving the Rubik's Cube with Deep Reinforcement Learning and Search"
"""

import os
import sys
import time
import argparse
import copy
import math
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
from typing import Tuple, List

from model import DeepCubeA
from cube_env import RubikCubeEnv, MOVE_TABLE, MOVE_NAMES


def get_device(requested: str = "auto") -> torch.device:
    """Select appropriate device: cuda, mps (Apple Silicon), or cpu."""
    if requested != "auto":
        return torch.device(requested)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if hasattr(torch.backends, "mps") and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def check_solved_batch(states: np.ndarray) -> np.ndarray:
    """
    Vectorized check if cubes are in solved state.
    states: [N, 54] with values in 0..5.
    Returns: boolean array [N] where True indicates solved.
    """
    # In solved cube, each face (9 facelets) has color == face_index
    # Face 0: 0..8, Face 1: 9..17, Face 2: 18..26, Face 3: 27..35, Face 4: 36..44, Face 5: 45..53
    solved = np.ones(states.shape[0], dtype=bool)
    for face in range(6):
        face_colors = states[:, face * 9 : (face + 1) * 9]
        # All 9 facelets must equal the first facelet of that face
        face_matches = np.all(face_colors == face, axis=1)
        solved = solved & face_matches
    return solved


def generate_scramble_batch(batch_size: int, max_scramble_depth: int = 30) -> np.ndarray:
    """
    Generates a batch of scrambled cube states.
    For each cube in the batch, samples a random scramble depth k ~ Uniform(1, max_scramble_depth).
    Returns states array of shape [batch_size, 54].
    """
    states = np.tile(np.repeat(np.arange(6, dtype=np.uint8), 9), (batch_size, 1))
    scramble_depths = np.random.randint(1, max_scramble_depth + 1, size=batch_size)
    max_k = np.max(scramble_depths)

    # Scramble each cube k times
    last_faces = np.full(batch_size, -1, dtype=np.int32)
    for step in range(max_k):
        active_mask = step < scramble_depths
        num_active = np.sum(active_mask)
        if num_active == 0:
            break

        # Pick random move avoiding same face consecutively
        valid_moves = np.random.randint(0, 18, size=num_active)
        faces = valid_moves // 3

        # Redo for any collisions
        collision = faces == last_faces[active_mask]
        while np.any(collision):
            valid_moves[collision] = np.random.randint(0, 18, size=np.sum(collision))
            faces = valid_moves // 3
            collision = faces == last_faces[active_mask]

        last_faces[active_mask] = faces

        # Apply permutation
        active_indices = np.where(active_mask)[0]
        for idx, m in zip(active_indices, valid_moves):
            states[idx] = states[idx, MOVE_TABLE[m]]

    return states


def compute_bellman_targets(
    model: nn.Module,
    states: np.ndarray,
    device: torch.device,
    tau: float = 0.5,
    eval_batch_size: int = 4096
) -> Tuple[torch.Tensor, torch.Tensor]:
    """
    Computes Bellman update targets for value and policy.
    For each state s in states [B, 54]:
      1. Expand all 18 successor states s' = s * a for a in 0..17
      2. Evaluate V(s') using model
      3. Cost c(s, a) = 0 if s' is solved, else 1
      4. Q(s, a) = c(s, a) + (0 if is_solved(s') else V(s'))
      5. Target value y_v = min_a Q(s, a)
      6. Target policy y_p = argmin_a Q(s, a)
    """
    B = states.shape[0]

    # Generate all 18 successor states for each cube: [B, 18, 54]
    successor_states = np.empty((B, 18, 54), dtype=np.uint8)
    for a in range(18):
        successor_states[:, a, :] = states[:, MOVE_TABLE[a]]

    # Flatten successors to [B * 18, 54]
    flat_successors = successor_states.reshape(-1, 54)
    num_successors = flat_successors.shape[0]

    # Check solved status
    solved_flat = check_solved_batch(flat_successors) # [B * 18]
    solved_matrix = solved_flat.reshape(B, 18)

    # Convert to one-hot for neural network inference
    pred_values = np.zeros(num_successors, dtype=np.float32)

    model.eval()
    with torch.no_grad():
        for i in range(0, num_successors, eval_batch_size):
            chunk = flat_successors[i : i + eval_batch_size]
            chunk_one_hot = RubikCubeEnv.batch_to_one_hot(chunk)
            chunk_tensor = torch.from_numpy(chunk_one_hot).to(device)
            v_chunk, _ = model(chunk_tensor)
            pred_values[i : i + eval_batch_size] = v_chunk.squeeze(-1).cpu().numpy()

    pred_values_matrix = pred_values.reshape(B, 18)

    # Q(s, a): if successor is solved, cost-to-go from successor is 0, total cost is 1.0.
    # Otherwise cost is 1.0 + V(s').
    # (If initial state was already solved, target value is 0.0)
    is_initial_solved = check_solved_batch(states)

    q_values = np.where(solved_matrix, 1.0, 1.0 + pred_values_matrix)

    # Target value: min over all 18 moves
    target_values = np.min(q_values, axis=1)
    target_values[is_initial_solved] = 0.0

    # Target policy: argmin over Q-values (the move that minimizes cost-to-go)
    target_policies = np.argmin(q_values, axis=1)

    target_values_tensor = torch.from_numpy(target_values.astype(np.float32)).to(device)
    target_policies_tensor = torch.from_numpy(target_policies.astype(np.int64)).to(device)

    return target_values_tensor, target_policies_tensor


def train(args):
    device = get_device(args.device)
    print(f"=== DeepCubeA Autodidactic Iteration (ADI) Training ===")
    print(f"Device:           {device}")
    print(f"Batch size:       {args.batch_size}")
    print(f"Max scramble:     {args.max_scramble}")
    print(f"Total iterations: {args.iterations}")
    print(f"Learning rate:    {args.lr}")
    print(f"Save directory:   {args.save_dir}")
    print("=" * 55)

    os.makedirs(args.save_dir, exist_ok=True)
    checkpoint_path = os.path.join(args.save_dir, "deepcubea_checkpoint.pt")

    # Initialize model and target model
    model = DeepCubeA().to(device)
    target_model = copy.deepcopy(model).to(device)
    target_model.eval()

    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)

    start_iteration = 0
    if args.resume and os.path.exists(checkpoint_path):
        print(f"Loading checkpoint from {checkpoint_path}...")
        checkpoint = torch.load(checkpoint_path, map_location=device)
        model.load_state_dict(checkpoint["model_state"])
        target_model.load_state_dict(checkpoint["model_state"])
        optimizer.load_state_dict(checkpoint["optimizer_state"])
        start_iteration = checkpoint.get("iteration", 0)
        print(f"Resumed from iteration {start_iteration}.")

    # Compute the learning rate manually from the absolute iteration number
    # instead of using a stateful scheduler. Resuming restores the optimizer's
    # last learning rate (often eta_min), which freezes a naive scheduler at
    # 1e-6 forever. This cosine schedule always reflects the new run length.
    eta_min = 1e-6

    def learning_rate_for(iteration: int) -> float:
        if args.iterations <= 1:
            return args.lr
        progress = min(1.0, max(0.0, (iteration - 1) / (args.iterations - 1)))
        return eta_min + 0.5 * (args.lr - eta_min) * (1.0 + math.cos(math.pi * progress))

    for param_group in optimizer.param_groups:
        param_group["lr"] = learning_rate_for(start_iteration + 1)

    loss_history = []
    start_time = time.time()

    for iteration in range(start_iteration + 1, args.iterations + 1):
        step_start = time.time()

        # 1. Generate scramble batch
        states = generate_scramble_batch(args.batch_size, args.max_scramble)

        # 2. Compute Bellman targets using target network
        target_v, target_p = compute_bellman_targets(
            target_model, states, device, tau=args.temperature
        )

        # 3. Model forward pass
        model.train()
        states_one_hot = RubikCubeEnv.batch_to_one_hot(states)
        states_tensor = torch.from_numpy(states_one_hot).to(device)

        pred_v, pred_p = model(states_tensor)

        # 4. Multi-task Loss: Huber (Smooth L1) for value + Cross Entropy for policy
        loss_v = F.smooth_l1_loss(pred_v.squeeze(-1), target_v)
        loss_p = F.cross_entropy(pred_p, target_p)
        total_loss = loss_v + args.policy_weight * loss_p

        # 5. Backprop & optimize
        current_lr = learning_rate_for(iteration)
        for param_group in optimizer.param_groups:
            param_group["lr"] = current_lr
        optimizer.zero_grad()
        total_loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=1.0)
        optimizer.step()

        # 6. Target network update (periodic copy)
        if iteration % args.target_update_interval == 0:
            target_model.load_state_dict(model.state_dict())

        step_duration = time.time() - step_start

        # 7. Logging & Checkpointing
        if iteration % args.log_interval == 0 or iteration == 1:
            elapsed = time.time() - start_time
            print(
                f"Iter [{iteration:6d}/{args.iterations}] | "
                f"Loss: {total_loss.item():.4f} (V: {loss_v.item():.4f}, P: {loss_p.item():.4f}) | "
                f"LR: {current_lr:.6f} | "
                f"Step: {step_duration:.2f}s | "
                f"Elapsed: {elapsed:.1f}s"
            )

        if iteration % args.save_interval == 0 or iteration == args.iterations:
            print(f"Saving checkpoint to {checkpoint_path}...")
            torch.save({
                "iteration": iteration,
                "model_state": model.state_dict(),
                "optimizer_state": optimizer.state_dict(),
                "loss": total_loss.item(),
            }, checkpoint_path)

    print("=== Training Complete ===")
    print(f"Model checkpoint saved to: {checkpoint_path}")


def parse_args():
    parser = argparse.ArgumentParser(description="DeepCubeA Autodidactic Iteration (ADI) Training")
    parser.add_argument("--batch-size", type=int, default=1000, help="Number of scrambled cubes per batch")
    parser.add_argument("--max-scramble", type=int, default=30, help="Maximum scramble depth (K_max)")
    parser.add_argument("--iterations", type=int, default=5000, help="Total training iterations")
    parser.add_argument("--lr", type=float, default=1e-3, help="Peak learning rate")
    parser.add_argument("--weight-decay", type=float, default=1e-4, help="AdamW weight decay")
    parser.add_argument("--policy-weight", type=float, default=0.1, help="Weight for policy cross-entropy loss")
    parser.add_argument("--temperature", type=float, default=0.5, help="Temperature for target policy distribution")
    parser.add_argument("--target-update-interval", type=int, default=100, help="Iterations between target network sync")
    parser.add_argument("--log-interval", type=int, default=10, help="Iterations between console logs")
    parser.add_argument("--save-interval", type=int, default=500, help="Iterations between checkpoint saves")
    parser.add_argument("--save-dir", type=str, default="checkpoints", help="Output directory for checkpoints")
    parser.add_argument("--device", type=str, default="auto", help="Compute device ('auto', 'cuda', 'mps', 'cpu')")
    parser.add_argument("--resume", action="store_true", help="Resume training from existing checkpoint")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    train(args)
