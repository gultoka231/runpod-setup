#!/bin/bash
# ============================================================
# RunPod Setup: AI Influencer Pipeline
# GPU: RTX 4090 24GB | ComfyUI + SDXL + InstantID + Wan2.1
# IMPORTANT: Volume Disk >= 200GB
# Launch: python3 /workspace/ComfyUI/main.py --listen 0.0.0.0 --port 8188 --bf16-vae
# Stop pod with STOP (not Terminate!) to preserve data
# LoRA files -> /workspace/ComfyUI/models/loras/
# ============================================================
set -euo pipefail

purge_cache() {
  pip cache purge 2>/dev/null || true
}

dl() {
  local url=$1
  local dest=$2
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    echo "  -> Уже есть: $(basename $dest), пропускаем."
    return
  fi
  echo "  -> Скачиваем: $(basename $dest)..."
  wget -q --show-progress -O "$dest" "$url" || echo "  WARNING: не удалось скачать $url"
}

WORKSPACE="/workspace"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
CUSTOM_NODES="$COMFYUI_DIR/custom_nodes"
MODELS="$COMFYUI_DIR/models"
HF="https://huggingface.co"

# ============================================================
echo ""
echo "=== [1/8] ComfyUI ==="
if [ ! -d "$COMFYUI_DIR" ]; then
  cd "$WORKSPACE"
  git clone https://github.com/comfyanonymous/ComfyUI
  pip install -r "$COMFYUI_DIR/requirements.txt" -q
  purge_cache
else
  echo "ComfyUI уже установлен, пропускаем."
fi

# ============================================================
echo ""
echo "=== [2/8] Кастомные ноды ==="

install_node() {
  local repo_url=$1
  local dir_name=$(basename "$repo_url" .git)
  local target="$CUSTOM_NODES/$dir_name"
  if [ ! -d "$target" ]; then
    echo "  -> Клонируем $dir_name..."
    git clone "$repo_url" "$target"
    if [ -f "$target/requirements.txt" ]; then
      pip install -r "$target/requirements.txt" --quiet
      purge_cache
    fi
    if [ -f "$target/install.py" ]; then
      python3 "$target/install.py" || true
    fi
  else
    echo "  -> $dir_name уже есть"
  fi
}

install_node "https://github.com/Comfy-Org/ComfyUI-Manager"
install_node "https://github.com/cubiq/ComfyUI_InstantID"
install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
install_node "https://github.com/Fannovel16/comfyui_controlnet_aux"
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper"
install_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
install_node "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
install_node "https://github.com/rgthree/rgthree-comfy"

pip install -r "$CUSTOM_NODES/comfyui_controlnet_aux/requirements.txt" --quiet || true
cd "$CUSTOM_NODES/ComfyUI-Impact-Pack" && python3 install.py || true
cd "$WORKSPACE"
purge_cache

# ============================================================
echo ""
echo "=== [3/8] Python зависимости (InstantID) ==="
pip install insightface onnxruntime-gpu -q
pip install timm==0.9.16 --force-reinstall -q
pip install -r "$CUSTOM_NODES/ComfyUI_InstantID/requirements.txt" -q
purge_cache
echo "  -> insightface + onnxruntime-gpu + timm установлены"

# ============================================================
echo ""
echo "=== [4/8] Создаём папки для моделей ==="
mkdir -p "$MODELS/checkpoints"
mkdir -p "$MODELS/vae"
mkdir -p "$MODELS/loras"
mkdir -p "$MODELS/instantid"
mkdir -p "$MODELS/controlnet"
mkdir -p "$MODELS/clip_vision"
mkdir -p "$MODELS/ipadapter"
mkdir -p "$MODELS/diffusion_models"
mkdir -p "$MODELS/text_encoders"
mkdir -p "$MODELS/upscale_models"
mkdir -p "$MODELS/ultralytics/bbox"
mkdir -p "$MODELS/insightface/models/antelopev2"

# ============================================================
echo ""
echo "=== [5/8] Скачиваем SDXL модели ==="

dl "$HF/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors" \
   "$MODELS/checkpoints/RealVisXL_V5.0_fp16.safetensors"

dl "$HF/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
   "$MODELS/checkpoints/sd_xl_base_1.0.safetensors"

dl "$HF/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
   "$MODELS/vae/sdxl_vae.safetensors"

# InstantID
dl "$HF/InstantX/InstantID/resolve/main/ip-adapter.bin" \
   "$MODELS/instantid/ip-adapter.bin"

dl "$HF/InstantX/InstantID/resolve/main/ControlNetModel/diffusion_pytorch_model.safetensors" \
   "$MODELS/controlnet/instantid-controlnet.safetensors"

# CLIP Vision (нужен и для InstantID и для IPAdapter)
dl "$HF/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" \
   "$MODELS/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors"

# IPAdapter PLUS FACE для SDXL
dl "$HF/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
   "$MODELS/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors"

# ============================================================
echo ""
echo "=== [6/8] Скачиваем Wan 2.1 модели ==="

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors" \
   "$MODELS/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors"

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_i2v_480p_14B_fp8_scaled.safetensors" \
   "$MODELS/diffusion_models/wan2.1_i2v_480p_14B_fp8_scaled.safetensors"

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_fun_control_1.3B_bf16.safetensors" \
   "$MODELS/diffusion_models/wan2.1_fun_control_1.3B_bf16.safetensors"

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
   "$MODELS/vae/wan_2.1_vae.safetensors"

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors" \
   "$MODELS/text_encoders/umt5_xxl_fp16.safetensors"

# Upscaler + Face detector
dl "$HF/Bingsu/adetailer/resolve/main/face_yolov8m.pt" \
   "$MODELS/ultralytics/bbox/face_yolov8m.pt"

dl "https://huggingface.co/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
   "$MODELS/upscale_models/4x-UltraSharp.pth"

# ============================================================
echo ""
echo "=== [7/8] Face модели для InstantID ==="

python3 -c "
import insightface
for name in ['buffalo_l', 'antelopev2']:
    app = insightface.app.FaceAnalysis(name=name)
    app.prepare(ctx_id=0)
    print(f'  {name} OK')
"

# Фикс вложенной папки antelopev2 (частая проблема при скачивании)
if [ -d "$HOME/.insightface/models/antelopev2/antelopev2" ]; then
  mv ~/.insightface/models/antelopev2/antelopev2/* ~/.insightface/models/antelopev2/
  rmdir ~/.insightface/models/antelopev2/antelopev2
  echo "  -> Исправлена вложенная папка antelopev2"
fi

# Копируем antelopev2 в папку ComfyUI (InstantID ищет ЗДЕСЬ, не в ~/.insightface!)
cp ~/.insightface/models/antelopev2/*.onnx "$MODELS/insightface/models/antelopev2/"
echo "  -> antelopev2 скопирован в ComfyUI/models/insightface/"

# ============================================================
echo ""
echo "=== [8/8] Финальная проверка ==="

python3 -c "
import os, torch

print(f'  torch: {torch.__version__} | CUDA: {torch.cuda.is_available()}')

libs = {'insightface': 'insightface', 'onnxruntime': 'onnxruntime', 'timm': 'timm'}
for name, mod in libs.items():
    try:
        m = __import__(mod)
        ver = getattr(m, '__version__', 'OK')
        print(f'  {name}: {ver}')
    except:
        print(f'  {name}: ОШИБКА — переустанови')

models = {
    'RealVisXL':        '/workspace/ComfyUI/models/checkpoints/RealVisXL_V5.0_fp16.safetensors',
    'SDXL Base':        '/workspace/ComfyUI/models/checkpoints/sd_xl_base_1.0.safetensors',
    'SDXL VAE':         '/workspace/ComfyUI/models/vae/sdxl_vae.safetensors',
    'InstantID':        '/workspace/ComfyUI/models/instantid/ip-adapter.bin',
    'InstantID CN':     '/workspace/ComfyUI/models/controlnet/instantid-controlnet.safetensors',
    'CLIP Vision':      '/workspace/ComfyUI/models/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors',
    'antelopev2':       '/workspace/ComfyUI/models/insightface/models/antelopev2/scrfd_10g_bnkps.onnx',
    'Wan T2V 1.3B':     '/workspace/ComfyUI/models/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors',
    'Wan VAE':          '/workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors',
}
print()
all_ok = True
for name, path in models.items():
    ok = os.path.exists(path) and os.path.getsize(path) > 1000
    status = '✓' if ok else '✗ ОТСУТСТВУЕТ'
    if not ok: all_ok = False
    print(f'  {status}  {name}')

print()
print('  === ВСЁ ОК ===' if all_ok else '  !!! Некоторые файлы отсутствуют !!!')
"

echo ""
echo "============================================================"
echo "  УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "  ⚠️  ВРУЧНУЮ загрузи через JupyterLab (Upload ↑):"
echo "     sh_woman_v1.safetensors -> $MODELS/loras/"
echo "     sdxl_instantid_lora.json -> /workspace/workflows/"
echo ""
echo "  Запуск ComfyUI (--bf16-vae ОБЯЗАТЕЛЕН!):"
echo "  python3 $COMFYUI_DIR/main.py --listen 0.0.0.0 --port 8188 --bf16-vae &"
echo ""
echo "  Настройки воркфлоу:"
echo "    Checkpoint : RealVisXL_V5.0_fp16.safetensors"
echo "    cfg        : 3.0-3.5"
echo "    steps      : 35"
echo "    sampler    : dpmpp_2m_sde / karras"
echo "    InstantID  : weight 0.65"
echo ""
echo "  STOP (не Terminate!) чтобы сохранить данные"
echo "============================================================"
