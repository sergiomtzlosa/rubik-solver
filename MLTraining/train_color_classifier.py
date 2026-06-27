"""
Rubik's Cube Facelet Color Classifier Trainer
=============================================
Trains a lightweight Neural Network classifier to accurately recognize the 6 Rubik's Cube
facelet colors (White, Red, Green, Yellow, Orange, Blue) under varying lighting, shadows,
glare, and camera white balance shifts.

Features:
- Inputs: Normalized [R, G, B, H, S, V] (6 features)
- Outputs: Class logits for 6 colors (0: White, 1: Red, 2: Green, 3: Yellow, 4: Orange, 5: Blue)
- Exports directly to Core ML Float16 format.
"""

import os
import argparse
from typing import Tuple
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F
import coremltools as ct


COLOR_NAMES = ["White", "Red", "Green", "Yellow", "Orange", "Blue"]

# Base nominal RGB values for typical Rubik stickers (0..1)
NOMINAL_RGB = np.array([
    [0.92, 0.92, 0.92],  # 0: White
    [0.85, 0.12, 0.14],  # 1: Red
    [0.05, 0.65, 0.22],  # 2: Green
    [0.95, 0.88, 0.08],  # 3: Yellow
    [0.98, 0.45, 0.05],  # 4: Orange
    [0.08, 0.35, 0.85],  # 5: Blue
], dtype=np.float32)


def rgb_to_hsv_numpy(rgb: np.ndarray) -> np.ndarray:
    """Converts RGB in [0, 1] to HSV in [0, 1]."""
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    maxc = np.maximum(np.maximum(r, g), b)
    minc = np.minimum(np.minimum(r, g), b)
    v = maxc
    deltac = maxc - minc

    s = np.zeros_like(v)
    non_zero = maxc > 1e-5
    s[non_zero] = deltac[non_zero] / maxc[non_zero]

    h = np.zeros_like(v)
    mask = deltac > 1e-5

    idx = mask & (maxc == r)
    h[idx] = (g[idx] - b[idx]) / deltac[idx] % 6.0

    idx = mask & (maxc == g)
    h[idx] = (b[idx] - r[idx]) / deltac[idx] + 2.0

    idx = mask & (maxc == b)
    h[idx] = (r[idx] - g[idx]) / deltac[idx] + 4.0

    h = h / 6.0  # Normalized to [0, 1]
    return np.stack([h, s, v], axis=1)


def generate_synthetic_dataset(num_samples_per_class: int = 5000) -> Tuple[np.ndarray, np.ndarray]:
    """
    Generates synthetic color patches with realistic photometric augmentations:
    - Illuminant color temperature shifts (warm/cool lighting)
    - Specular highlights & reflections
    - Ambient shadow / low light
    - Gaussian camera sensor noise
    """
    all_features = []
    all_labels = []

    for label in range(6):
        base = NOMINAL_RGB[label]
        # Base replication
        rgb = np.tile(base, (num_samples_per_class, 1))

        # 1. Random illumination / brightness multiplier [0.4, 1.4]
        brightness = np.random.uniform(0.4, 1.35, size=(num_samples_per_class, 1))
        rgb = rgb * brightness

        # 2. White balance / ambient tint
        tint = np.random.normal(loc=1.0, scale=0.08, size=(num_samples_per_class, 3))
        rgb = rgb * tint

        # 3. Specular glare (additive white light)
        glare_prob = np.random.uniform(0, 1, size=(num_samples_per_class, 1))
        glare_intensity = np.where(glare_prob > 0.85, np.random.uniform(0.05, 0.35, size=(num_samples_per_class, 1)), 0.0)
        rgb = rgb + glare_intensity

        # 4. Sensor noise
        noise = np.random.normal(loc=0.0, scale=0.025, size=(num_samples_per_class, 3))
        rgb = np.clip(rgb + noise, 0.0, 1.0)

        # 5. Extract HSV
        hsv = rgb_to_hsv_numpy(rgb)

        # Feature vector: [R, G, B, H, S, V] (6 dims)
        feats = np.concatenate([rgb, hsv], axis=1)

        all_features.append(feats)
        all_labels.append(np.full(num_samples_per_class, label, dtype=np.int64))

    X = np.concatenate(all_features, axis=0).astype(np.float32)
    y = np.concatenate(all_labels, axis=0)

    # Shuffle
    perm = np.random.permutation(len(y))
    return X[perm], y[perm]


class StickerColorClassifier(nn.Module):
    """Compact MLP classifier for sticker RGB+HSV features."""
    def __init__(self, in_features: int = 6, hidden_dim: int = 64, num_classes: int = 6):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(in_features, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.ReLU(),
            nn.Linear(hidden_dim, num_classes)
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


def train_and_export(epochs: int = 15, batch_size: int = 128, lr: float = 0.005, output_dir: str = "./"):
    print("=== Training Rubik Sticker Color Classifier ===")
    X_train, y_train = generate_synthetic_dataset(num_samples_per_class=6000)
    X_val, y_val = generate_synthetic_dataset(num_samples_per_class=1000)

    train_dataset = torch.utils.data.TensorDataset(torch.from_numpy(X_train), torch.from_numpy(y_train))
    train_loader = torch.utils.data.DataLoader(train_dataset, batch_size=batch_size, shuffle=True)

    model = StickerColorClassifier()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = nn.CrossEntropyLoss()

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        correct = 0
        total = 0

        for feats, labels in train_loader:
            optimizer.zero_grad()
            logits = model(feats)
            loss = criterion(logits, labels)
            loss.backward()
            optimizer.step()

            total_loss += loss.item() * feats.size(0)
            preds = torch.argmax(logits, dim=1)
            correct += (preds == labels).sum().item()
            total += feats.size(0)

        # Validation
        model.eval()
        with torch.no_grad():
            val_logits = model(torch.from_numpy(X_val))
            val_loss = criterion(val_logits, torch.from_numpy(y_val)).item()
            val_preds = torch.argmax(val_logits, dim=1)
            val_acc = (val_preds.numpy() == y_val).mean() * 100.0

        train_acc = (correct / total) * 100.0
        print(f"Epoch {epoch:2d}/{epochs} | Train Loss: {total_loss/total:.4f} | Train Acc: {train_acc:.2f}% | Val Acc: {val_acc:.2f}%")

    # Export to Core ML
    print("\nExporting StickerColorClassifier to Core ML...")
    os.makedirs(output_dir, exist_ok=True)
    pkg_path = os.path.join(output_dir, "StickerColorClassifier.mlpackage")

    dummy_input = torch.zeros(1, 6, dtype=torch.float32)
    traced = torch.jit.trace(model, dummy_input)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="color_features", shape=(1, 6), dtype=np.float32)],
        outputs=[ct.TensorType(name="color_logits")],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS13,
    )
    mlmodel.author = "RubikSolver Team"
    mlmodel.short_description = "Classifies normalized [R, G, B, H, S, V] sticker patches into 6 Rubik colors."
    mlmodel.save(pkg_path)
    print(f"Saved Core ML model to {pkg_path}")


if __name__ == "__main__":
    from typing import Tuple
    train_and_export()
