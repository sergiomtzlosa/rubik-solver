"""
DeepCubeA Neural Network Architecture
Dual-head Residual Multi-Layer Perceptron (ResMLP) for Rubik's Cube state evaluation.
Input:  cube_state [batch_size, 324] (one-hot encoded 54 facelets x 6 colors)
Output: value [batch_size, 1]   - Estimated distance heuristic (cost-to-go)
        policy [batch_size, 18] - Action logits over 18 Singmaster moves
"""

import torch
import torch.nn as nn


class ResBlock(nn.Module):
    """Residual block with two Linear layers, ReLU activation, and a skip connection."""
    def __init__(self, hidden_dim: int = 1024):
        super().__init__()
        self.fc1 = nn.Linear(hidden_dim, hidden_dim)
        self.relu1 = nn.ReLU()
        self.fc2 = nn.Linear(hidden_dim, hidden_dim)
        self.relu2 = nn.ReLU()

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        residual = x
        out = self.fc1(x)
        out = self.relu1(out)
        out = self.fc2(out)
        out = self.relu2(residual + out)
        return out


class DeepCubeA(nn.Module):
    """
    DeepCubeA Dual-Head Model matching the exact topology in DeepCubeA.mlmodelc:
    - 7 Linear layers
    - 5 ReLU activations
    - 2 Add operations (Residual skip additions)
    """
    def __init__(self, state_dim: int = 324, hidden_dim: int = 1024, num_actions: int = 18):
        super().__init__()
        # Input projection layer (Linear 1 + ReLU 1)
        self.input_layer = nn.Linear(state_dim, hidden_dim)
        self.input_relu = nn.ReLU()

        # Residual Block 1 (Linear 2 & 3 + ReLU 2 & 3 + Add 1)
        self.res_block1 = ResBlock(hidden_dim)

        # Residual Block 2 (Linear 4 & 5 + ReLU 4 & 5 + Add 2)
        self.res_block2 = ResBlock(hidden_dim)

        # Value Head (Linear 6 -> 1)
        self.value_head = nn.Linear(hidden_dim, 1)

        # Policy Head (Linear 7 -> 18)
        self.policy_head = nn.Linear(hidden_dim, num_actions)

    def forward(self, x: torch.Tensor):
        # x shape: [batch_size, 324]
        h = self.input_layer(x)
        h = self.input_relu(h)

        h = self.res_block1(h)
        h = self.res_block2(h)

        value = self.value_head(h)     # [batch_size, 1]
        policy = self.policy_head(h)   # [batch_size, 18]

        return value, policy


if __name__ == "__main__":
    model = DeepCubeA()
    dummy_input = torch.zeros(1, 324, dtype=torch.float32)
    val, pol = model(dummy_input)
    print("DeepCubeA model initialized successfully.")
    print(f"Input shape:  {dummy_input.shape}")
    print(f"Value shape:  {val.shape}")
    print(f"Policy shape: {pol.shape}")
    print(f"Total parameters: {sum(p.numel() for p in model.parameters()):,}")
