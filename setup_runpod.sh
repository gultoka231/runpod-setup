#!/bin/bash
# ============================================================
# RunPod Setup: Wan AI Influencer Pipeline
# GPU: RTX 4090 24GB | ComfyUI + Wan2.1 + IPAdapter + Video
# ============================================================
set -euo pipefail

WORKSPACE="/workspace"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
CUSTOM_NODES="$COMFYUI_DIR/custom_nodes"
MODELS="$COMFYUI_DIR/models"

echo "=== [1/5] Installing ComfyUI ==="
if [ ! -d "$COMFYUI_DIR" ]; then
  cd "$WORKSPACE"
  git clone https://github.com/comfyanonymous/ComfyUI
  pip install -r "$COMFYUI_DIR/requirements.txt"
else
  echo "ComfyUI already installed, skipping."
fi

echo ""
echo "=== [2/5] Installing custom nodes ==="

install_node() {
  local repo_url=$1
  local dir_name=$(basename "$repo_url" .git)
  local target="$CUSTOM_NODES/$dir_name"
  if [ ! -d "$target" ]; then
    echo "  -> Cloning $dir_name..."
    git clone "$repo_url" "$target"
    if [ -f "$target/requirements.txt" ]; then
      pip install -r "$target/requirements.txt" --quiet
    fi
    if [ -f "$target/install.py" ]; then
      python3 "$target/install.py"
    fi
  else
    echo "  -> $dir_name already exists, pulling latest..."
    git -C "$target" pull --quiet
  fi
}

install_node "https://github.com/Comfy-Org/ComfyUI-Manager"
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
install_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
install_node "https://github.com/rgthree/rgthree-comfy"
install_node "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"

# Impact Pack dependencies
cd "$CUSTOM_NODES/ComfyUI-Impact-Pack" && python3 install.py || true
cd "$WORKSPACE"

echo ""
echo "=== [3/5] Creating model directories ==="
mkdir -p "$MODELS/diffusion_models"
mkdir -p "$MODELS/text_encoders"
mkdir -p "$MODELS/vae"
mkdir -p "$MODELS/clip_vision"
mkdir -p "$MODELS/ipadapter"
mkdir -p "$MODELS/loras"
mkdir -p "$MODELS/upscale_models"
mkdir -p "$MODELS/ultralytics/bbox"

# Install huggingface-cli if missing
pip install "huggingface_hub[cli]" --quiet

echo ""
echo "=== [4/5] Downloading Wan 2.1 models ==="

HF_BASE="https://huggingface.co"

# --- Wan 2.1 T2I 1.3B (image generation) ---
echo "  -> wan2.1_t2i_1.3B_bf16.safetensors"
huggingface-cli download Comfy-Org/Wan_2.1_ComfyUI_repackaged \
  --include "split_files/diffusion_models/wan2.1_t2i_1.3B_bf16.safetensors" \
  --local-dir "$MODELS"

# --- Wan 2.1 T2V 1.3B (video generation, fits 24GB) ---
echo "  -> wan2.1_t2v_1.3B_bf16.safetensors"
huggingface-cli download Comfy-Org/Wan_2.1_ComfyUI_repackaged \
  --include "split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" \
  --local-dir "$MODELS"

# --- Wan 2.1 I2V 480p 1.3B (image-to-video, consistent character) ---
echo "  -> wan2.1_i2v_480p_1.3B_bf16.safetensors"
huggingface-cli download Comfy-Org/Wan_2.1_ComfyUI_repackaged \
  --include "split_files/diffusion_models/wan2.1_i2v_480p_1.3B_bf16.safetensors" \
  --local-dir "$MODELS"

# --- VAE ---
echo "  -> wan_2.1_vae.safetensors"
huggingface-cli download Comfy-Org/Wan_2.1_ComfyUI_repackaged \
  --include "split_files/vae/wan_2.1_vae.safetensors" \
  --local-dir "$MODELS"

# --- T5 Text Encoder (fp8 saves ~8GB VRAM vs fp32) ---
echo "  -> umt5_xxl_fp8_e4m3fn_scaled.safetensors"
huggingface-cli download Comfy-Org/Wan_2.1_ComfyUI_repackaged \
  --include "split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
  --local-dir "$MODELS"

# --- CLIP Vision for IPAdapter + WanVideo I2V ---
echo "  -> clip_vision (ViT-H)"
huggingface-cli download h94/IP-Adapter \
  --include "models/image_encoder/model.safetensors" \
  --local-dir "/tmp/ipadapter_dl"
cp "/tmp/ipadapter_dl/models/image_encoder/model.safetensors" \
   "$MODELS/clip_vision/clip_vision_vit_h.safetensors"

# --- IPAdapter models (for SD/SDXL consistent character) ---
echo "  -> ip-adapter-plus-face_sdxl_vit-h.safetensors"
huggingface-cli download h94/IP-Adapter \
  --include "sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
  --local-dir "/tmp/ipadapter_dl"
cp "/tmp/ipadapter_dl/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
   "$MODELS/ipadapter/"

# --- Face detection models for Impact Pack FaceDetailer ---
echo "  -> face_yolov8m.pt (bbox detector)"
huggingface-cli download Bingsu/adetailer \
  --include "face_yolov8m.pt" \
  --local-dir "$MODELS/ultralytics/bbox"

# --- ESRGAN upscaler (optional quality boost) ---
echo "  -> 4x-UltraSharp.pth (upscaler)"
wget -q -O "$MODELS/upscale_models/4x-UltraSharp.pth" \
  "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" || \
  echo "  Warning: upscaler download failed, skipping."

echo ""
echo "=== [5/5] Fixing file paths (moving from split_files subfolders) ==="

# huggingface-cli downloads into split_files/... structure — flatten it
flatten_models() {
  local src_dir=$1
  local dst_dir=$2
  if [ -d "$src_dir" ]; then
    find "$src_dir" -maxdepth 1 -name "*.safetensors" -exec mv {} "$dst_dir/" \;
    find "$src_dir" -maxdepth 1 -name "*.gguf" -exec mv {} "$dst_dir/" \;
  fi
}

flatten_models "$MODELS/split_files/diffusion_models" "$MODELS/diffusion_models"
flatten_models "$MODELS/split_files/vae" "$MODELS/vae"
flatten_models "$MODELS/split_files/text_encoders" "$MODELS/text_encoders"

# Cleanup
rm -rf "$MODELS/split_files" 2>/dev/null || true
rm -rf /tmp/ipadapter_dl 2>/dev/null || true

echo ""
echo "============================================"
echo "  Setup complete!"
echo ""
echo "  Installed nodes:"
echo "   - ComfyUI-Manager"
echo "   - ComfyUI-WanVideoWrapper (kijai)"
echo "   - ComfyUI-VideoHelperSuite"
echo "   - ComfyUI-Impact-Pack"
echo "   - ComfyUI_IPAdapter_plus"
echo "   - rgthree-comfy"
echo ""
echo "  Models downloaded:"
echo "   - wan2.1_t2i_1.3B_bf16      -> diffusion_models/"
echo "   - wan2.1_t2v_1.3B_bf16      -> diffusion_models/"
echo "   - wan2.1_i2v_480p_1.3B_bf16 -> diffusion_models/"
echo "   - wan_2.1_vae               -> vae/"
echo "   - umt5_xxl_fp8_e4m3fn_scaled-> text_encoders/"
echo "   - clip_vision_vit_h         -> clip_vision/"
echo "   - ip-adapter-plus-face_sdxl -> ipadapter/"
echo "   - face_yolov8m              -> ultralytics/bbox/"
echo ""
echo "  Launch ComfyUI with:"
echo "  python3 $COMFYUI_DIR/main.py --listen 0.0.0.0 --port 8188 --fp16-vae"
echo "============================================"
