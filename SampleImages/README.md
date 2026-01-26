# Rubik's Cube Sample Test Images

This directory contains test images created specifically for testing the **Photo Recognition & Upload** feature in **RubikSolver**.

---

## Included Sample Images

| Filename | Description | Target Face |
| :--- | :--- | :--- |
| **`sample_scramble_photo.jpg`** | High-resolution realistic photograph of a real scrambled 3x3 cube face | Auto-detected: **Down Face (Yellow)** |
| **`face_0_top_white.png`** | Crisp render of Top Face (White center) from a 10-move scramble | Auto-detected: **Top Face (U)** |
| **`face_1_right_red.png`** | Crisp render of Right Face (Red center) | Auto-detected: **Right Face (R)** |
| **`face_2_front_green.png`** | Crisp render of Front Face (Green center) | Auto-detected: **Front Face (F)** |
| **`face_3_down_yellow.png`** | Crisp render of Down Face (Yellow center) | Auto-detected: **Down Face (D)** |
| **`face_4_left_orange.png`** | Crisp render of Left Face (Orange center) | Auto-detected: **Left Face (L)** |
| **`face_5_back_blue.png`** | Crisp render of Back Face (Blue center) | Auto-detected: **Back Face (B)** |
| **`cube_unfolded_scramble.png`** | 2D Unfolded Net showing all 6 faces together | Visual reference |

---

## How to Test the Upload Feature

### 6-Face Photo Upload & Solving Test
1. Launch **RubikSolver**.
2. Click the **`🖼️ Photo`** button on the top-left toolbar (or press **`⌘U`** / Menu: *File -> Upload Cube Face Photos...*).
3. The **6-Face Photo Upload** sheet will appear displaying cards for all 6 faces:
   - **Top Face (U)** — White center
   - **Front Face (F)** — Green center
   - **Right Face (R)** — Red center
   - **Down Face (D)** — Yellow center
   - **Left Face (L)** — Orange center
   - **Back Face (B)** — Blue center

### Testing Methods
- **1-Click Instant Demo**: Click **`🎲 Load Sample Photos`** in the top bar. All 6 face photos will be automatically loaded, recognized, and validated as a valid 10-move scramble (`R U R' U' F' U F R U2 R'`).
- **Batch Upload**: Click **`📁 Upload Multiple Images...`** and select all 6 PNG files (`face_0` through `face_5`) at once. Faces are automatically matched based on their center sticker color.
- **Drag & Drop**: Drag image files from Finder directly onto any face card.
- **Per-Face Upload**: Click **`Choose Photo...`** on any individual face card.
- **Adjust / Fine-Tune**: Click **`✏️ Adjust`** on any face to drag the ROI frame, adjust grid size, or override sticker colors. You can also tap any sticker on the mini 3x3 grid to quickly cycle colors.
- **Solve**: Click **`⚡ Apply & Solve`** to apply the faces and let the Core ML neural network and GPU solver solve the cube in milliseconds!
