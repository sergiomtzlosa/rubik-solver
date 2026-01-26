"""
DeepCubeA PyTorch to Core ML Converter
======================================
Converts a trained PyTorch DeepCubeA checkpoint into an optimized Float16 Core ML model:
- Input:  cube_state [1, 324] (Float32)
- Output: value [1, 1] (Float32 / Float16)
- Output: policy [1, 18] (Float32 / Float16)
- Target: macOS 13.0+ / iOS 16.0+ (MIL/ANE backend)

Compiles to DeepCubeA.mlpackage and DeepCubeA.mlmodelc.
"""

import os
import sys
import shutil
import argparse
import subprocess
import numpy as np
import torch
import coremltools as ct

from model import DeepCubeA


def export_to_coreml(
    checkpoint_path: str = None,
    output_package: str = "DeepCubeA.mlpackage",
    compiled_output_dir: str = "./",
    install_to_app: bool = False,
    app_resources_dir: str = "../RubikSolver/Resources",
    flexible_batch: bool = False,
    max_batch_size: int = 512,
    fixed_batch_size: int = 0,
):
    print("=== DeepCubeA Core ML Exporter ===")
    model = DeepCubeA()
    model.eval()

    if checkpoint_path and os.path.exists(checkpoint_path):
        print(f"Loading weights from checkpoint: {checkpoint_path}")
        checkpoint = torch.load(checkpoint_path, map_location="cpu")
        state_dict = checkpoint["model_state"] if "model_state" in checkpoint else checkpoint
        model.load_state_dict(state_dict)
    else:
        print("No checkpoint specified or file not found; exporting with initialized model architecture.")

    # 1. Trace PyTorch Model
    dummy_input = torch.zeros(1, 324, dtype=torch.float32)
    print(f"Tracing PyTorch model with dummy input {dummy_input.shape}...")
    traced_model = torch.jit.trace(model, dummy_input)

    # 2. Convert to Core ML using MIL / Float16 precision
    print("Converting to Core ML with Float16 compute precision...")
    if fixed_batch_size > 0:
        # A fixed batch shape is important: Core ML's compute planner only
        # prefers the GPU for this model when the batch dimension is large and
        # static. Dynamic batch shapes are planned onto the CPU.
        print(f"Using a fixed batch dimension of {fixed_batch_size} for GPU placement.")
        input_shape = (fixed_batch_size, 324)
        deployment_target = ct.target.macOS14
    elif flexible_batch:
        print(f"Using a flexible batch dimension (1...{max_batch_size}).")
        input_shape = ct.Shape(shape=[ct.RangeDim(1, max_batch_size), 324])
        deployment_target = ct.target.macOS14
    else:
        input_shape = (1, 324)
        deployment_target = ct.target.macOS13

    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(
                name="cube_state",
                shape=input_shape,
                dtype=np.float32
            )
        ],
        outputs=[
            ct.TensorType(name="value"),
            ct.TensorType(name="policy")
        ],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=deployment_target,
    )

    # 3. Add Human-Readable Metadata
    mlmodel.author = "RubikSolver DeepCubeA Team"
    mlmodel.license = "MIT"
    mlmodel.short_description = "Dual-head DeepCubeA ResMLP for Rubik's Cube heuristic search and policy guidance."
    mlmodel.input_description["cube_state"] = "One-hot representation of 54 facelets x 6 colors [1, 324]."
    mlmodel.output_description["value"] = "Estimated cost-to-go (distance heuristic) to solved state [1, 1]."
    mlmodel.output_description["policy"] = "Logits for 18 Singmaster moves [1, 18]."

    # 4. Save .mlpackage
    if os.path.exists(output_package):
        if os.path.isdir(output_package):
            shutil.rmtree(output_package)
        else:
            os.remove(output_package)

    print(f"Saving Core ML package to: {output_package}...")
    mlmodel.save(output_package)
    print(f"Successfully saved {output_package}.")

    # 5. Compile to .mlmodelc with xcrun coremlc compile
    compiled_name = os.path.splitext(os.path.basename(output_package))[0] + ".mlmodelc"
    compiled_target = os.path.join(compiled_output_dir, compiled_name)

    print(f"Compiling Core ML model via 'xcrun coremlc compile'...")
    try:
        res = subprocess.run(
            ["xcrun", "coremlc", "compile", output_package, compiled_output_dir],
            check=True,
            capture_output=True,
            text=True
        )
        print(f"Successfully compiled model to: {compiled_target}")
    except subprocess.CalledProcessError as e:
        print(f"Warning: coremlc compilation returned error:\n{e.stderr}")
        print("Note: The .mlpackage is valid and can be dragged directly into Xcode.")

    # 6. Optional: Copy to App Bundle Resources
    if install_to_app:
        dest_dir = os.path.abspath(app_resources_dir)
        if os.path.exists(dest_dir):
            app_mlmodelc_target = os.path.join(dest_dir, "DeepCubeA.mlmodelc")
            app_mlpackage_target = os.path.join(dest_dir, "DeepCubeA.mlpackage")

            if os.path.exists(compiled_target):
                if os.path.exists(app_mlmodelc_target):
                    shutil.rmtree(app_mlmodelc_target)
                shutil.copytree(compiled_target, app_mlmodelc_target)
                print(f"Installed {compiled_name} -> {app_mlmodelc_target}")

            if os.path.exists(output_package):
                if os.path.exists(app_mlpackage_target):
                    shutil.rmtree(app_mlpackage_target)
                shutil.copytree(output_package, app_mlpackage_target)
                print(f"Installed {output_package} -> {app_mlpackage_target}")
        else:
            print(f"Warning: App resources directory '{dest_dir}' does not exist.")

    print("=== Core ML Export Completed Successfully ===")


def parse_args():
    parser = argparse.ArgumentParser(description="Export DeepCubeA to Core ML")
    parser.add_argument("--checkpoint", type=str, default="checkpoints/deepcubea_checkpoint.pt", help="Path to PyTorch checkpoint")
    parser.add_argument("--output", type=str, default="DeepCubeA.mlpackage", help="Output .mlpackage filename")
    parser.add_argument("--compile-dir", type=str, default="./", help="Directory for compiled .mlmodelc")
    parser.add_argument("--install", action="store_true", help="Copy compiled model to RubikSolver/Resources")
    parser.add_argument("--flexible-batch", action="store_true",
                        help="Export with a dynamic batch dimension for GPU-batched inference")
    parser.add_argument("--max-batch-size", type=int, default=512,
                        help="Upper bound for the dynamic batch dimension")
    parser.add_argument("--fixed-batch-size", type=int, default=0,
                        help="Export a fixed batch dimension (required for GPU placement)")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    export_to_coreml(
        checkpoint_path=args.checkpoint,
        output_package=args.output,
        compiled_output_dir=args.compile_dir,
        install_to_app=args.install,
        flexible_batch=args.flexible_batch,
        max_batch_size=args.max_batch_size,
        fixed_batch_size=args.fixed_batch_size,
    )
