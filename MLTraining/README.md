# Machine Learning Models for RubikSolver

This folder contains the complete, self-contained Python training and export pipeline for the Machine Learning models used in **RubikSolver**:

1. **DeepCubeA**: Deep Reinforcement Learning dual-head neural network trained via **Autodidactic Iteration (ADI)** to evaluate cube states and guide heuristic search.
2. **StickerColorClassifier**: Neural network color classifier recognizing facelet sticker colors under varying lighting and camera noise.

---

## 📁 Folder Structure

| File | Description |
|---|---|
| [`model.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/model.py) | PyTorch definition of the **DeepCubeA ResMLP** architecture (7 Linear layers, 5 ReLUs, 2 Residual additions, 4.55M parameters). |
| [`cube_env.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/cube_env.py) | Vectorized 3x3 Rubik's Cube simulator matching the exact 18-move permutation table from `RubikCube.cpp`. Converts 54 facelets to `[1, 324]` one-hot tensors. |
| [`train_adi.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/train_adi.py) | **Autodidactic Iteration (ADI)** training pipeline with Bellman value/policy updates, target network synchronization, Huber loss, and checkpoint saving. |
| [`export_coreml.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/export_coreml.py) | Traces PyTorch checkpoints, converts to Apple Silicon **Float16 Core ML** (`.mlpackage`), compiles via `xcrun coremlc`, and installs into `RubikSolver/Resources/`. |
| [`evaluate_model.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/evaluate_model.py) | Solves scrambled cubes using Best-First Search and verifies numerical parity between PyTorch (`.pt`) and Core ML (`.mlpackage` / `.mlmodelc`). |
| [`train_color_classifier.py`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/train_color_classifier.py) | Synthetic dataset generator and training script for the 6-class sticker color classifier (RGB + HSV inputs). |
| [`requirements.txt`](file:///Users/sid/Downloads/rubik-lazy/MLTraining/requirements.txt) | Python dependencies (`torch`, `coremltools`, `numpy`, `tqdm`). |

---

## 🚀 Quick Start Guide

### 1. Environment Setup

```bash
cd MLTraining
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

### 2. Verify Simulator & Model Architecture

Run standalone tests on the environment and model:
```bash
python3 cube_env.py
python3 model.py
```
Expected output:
- Vectorized permutation cycles passed (`R U R' U'` 6 times returns to solved state).
- Total parameter count: **4,550,675**.

---

### 3. Train DeepCubeA with Autodidactic Iteration (ADI)

To train on Apple Silicon GPU (`mps`) or CPU:
```bash
# Quick test training (e.g. 50 iterations)
python3 train_adi.py --batch-size 128 --max-scramble 10 --iterations 50 --log-interval 5 --device auto

# Full production training (e.g. 10,000 iterations)
python3 train_adi.py --batch-size 1000 --max-scramble 30 --iterations 10000 --save-interval 500 --device auto
```

#### Key Arguments:
- `--batch-size`: Number of scrambled cubes per batch (default: `1000`).
- `--max-scramble`: Maximum scramble depth $K_{\max}$ (default: `30`).
- `--iterations`: Total iterations (default: `5000`).
- `--lr`: Learning rate (default: `1e-3` with Cosine Annealing).
- `--device`: `auto`, `mps`, `cuda`, or `cpu`.
- `--resume`: Resume training from `checkpoints/deepcubea_checkpoint.pt`.

---

### 4. Evaluate & Solve Scrambles

Test the model's solving performance across different scramble depths:
```bash
python3 evaluate_model.py --checkpoint checkpoints/deepcubea_checkpoint.pt --depths 1 2 3 5 8 10
```

---

### 5. Export to Float16 Core ML & Install to macOS App

Convert the trained PyTorch checkpoint to a Core ML package and compile directly into the Xcode app bundle:
```bash
# Export and automatically copy to RubikSolver/Resources/DeepCubeA.mlmodelc
python3 export_coreml.py --checkpoint checkpoints/deepcubea_checkpoint.pt --install
```

#### Core ML Specifications Produced:
- **Input Name**: `cube_state` `[1, 324]` (Float32)
- **Output 1 Name**: `value` `[1, 1]` (Float16/Float32 cost-to-go)
- **Output 2 Name**: `policy` `[1, 18]` (Float16/Float32 action logits)
- **Target OS**: macOS 13.0+ / iOS 16.0+

---

### 6. Verify Numerical Parity (PyTorch vs Core ML)

Verify that the Core ML model reproduces PyTorch outputs within Float16 tolerance:
```bash
python3 evaluate_model.py --check-parity --checkpoint checkpoints/deepcubea_checkpoint.pt --coreml-package DeepCubeA.mlpackage
```

---

### 7. Train Facelet Color Recognition Model (Optional)

To train and export the 6-color sticker classifier:
```bash
python3 train_color_classifier.py
```
This trains a compact neural network on synthetic photometric variations (glare, illuminant temperature, shadows, camera noise) and exports `StickerColorClassifier.mlpackage`.
