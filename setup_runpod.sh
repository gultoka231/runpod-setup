#!/bin/bash
# ============================================================
# RunPod Setup: LUMI AI Influencer Pipeline v5
# GPU: RTX 4090 24GB VRAM | Volume >= 200GB
#
# ПАЙПЛАЙНЫ:
#   1. ФОТО  — SDXL + Juggernaut XL + InstantID + IPAdapter + LoRA + FaceDetailer + HandDetailer + Upscale
#   2. ВИДЕО — Wan2.1 i2v / t2v / fun_control
#
# ЗАПУСК (--bf16-vae ОБЯЗАТЕЛЕН для InstantID!):
#   python3 /workspace/ComfyUI/main.py --listen 0.0.0.0 --port 8188 --bf16-vae &
#
# ВАЖНО: STOP = пауза (данные живы). TERMINATE = удалено навсегда!
# LoRA вручную: sh_woman_v1.safetensors -> /workspace/ComfyUI/models/loras/
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
echo "=== [1/9] ComfyUI ==="
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
echo "=== [2/9] Кастомные ноды ==="

install_node() {
  local repo_url=$1
  local dir_name=${2:-$(basename "$repo_url" .git)}
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

# --- Базовые ---
install_node "https://github.com/Comfy-Org/ComfyUI-Manager"
install_node "https://github.com/pythongosssss/ComfyUI-Custom-Scripts"
install_node "https://github.com/rgthree/rgthree-comfy"

# --- ФОТО: InstantID + IPAdapter + FaceDetailer + HandDetailer ---
install_node "https://github.com/cubiq/ComfyUI_InstantID"
install_node "https://github.com/cubiq/ComfyUI_IPAdapter_plus"
install_node "https://github.com/Fannovel16/comfyui_controlnet_aux"
install_node "https://github.com/ltdrdata/ComfyUI-Impact-Pack"
install_node "https://github.com/ltdrdata/ComfyUI-Impact-Subpack" "comfyui-impact-subpack"

# --- ВИДЕО: Wan ---
install_node "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite"
install_node "https://github.com/kijai/ComfyUI-WanVideoWrapper"
install_node "https://github.com/kijai/ComfyUI-KJNodes"

pip install -r "$CUSTOM_NODES/comfyui_controlnet_aux/requirements.txt" --quiet || true
cd "$CUSTOM_NODES/ComfyUI-Impact-Pack" && python3 install.py || true
cd "$WORKSPACE"
purge_cache

# ============================================================
echo ""
echo "=== [3/9] Python зависимости ==="
pip install insightface onnxruntime-gpu -q
pip install timm==0.9.16 --force-reinstall -q
pip install -r "$CUSTOM_NODES/ComfyUI_InstantID/requirements.txt" -q
# Пакеты для Impact Pack / Manager / WanVideoWrapper
pip install toml piexif gguf dill ftfy ultralytics -q
purge_cache
echo "  -> Все Python зависимости установлены"

# ============================================================
echo ""
echo "=== [4/9] Папки для моделей ==="
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
mkdir -p "$COMFYUI_DIR/user/default/workflows"
echo "  -> Папки созданы"

# ============================================================
echo ""
echo "=== [5/9] SDXL модели (фото) ==="

dl "$HF/SG161222/RealVisXL_V5.0/resolve/main/RealVisXL_V5.0_fp16.safetensors" \
   "$MODELS/checkpoints/RealVisXL_V5.0_fp16.safetensors"

dl "$HF/RunDiffusion/Juggernaut-XL-v9/resolve/main/Juggernaut-XL_v9_RunDiffusionPhoto_v2.safetensors" \
   "$MODELS/checkpoints/juggernautXL_v9Rdphoto2Lightning.safetensors"

dl "$HF/stabilityai/sdxl-vae/resolve/main/sdxl_vae.safetensors" \
   "$MODELS/vae/sdxl_vae.safetensors"

dl "$HF/InstantX/InstantID/resolve/main/ip-adapter.bin" \
   "$MODELS/instantid/ip-adapter.bin"

dl "$HF/InstantX/InstantID/resolve/main/ControlNetModel/diffusion_pytorch_model.safetensors" \
   "$MODELS/controlnet/instantid-controlnet.safetensors"

dl "$HF/h94/IP-Adapter/resolve/main/models/image_encoder/model.safetensors" \
   "$MODELS/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors"

dl "$HF/h94/IP-Adapter/resolve/main/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors" \
   "$MODELS/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors"

dl "$HF/Bingsu/adetailer/resolve/main/face_yolov8m.pt" \
   "$MODELS/ultralytics/bbox/face_yolov8m.pt"

dl "$HF/Bingsu/adetailer/resolve/main/hand_yolov8s.pt" \
   "$MODELS/ultralytics/bbox/hand_yolov8s.pt"

dl "$HF/lokCX/4x-Ultrasharp/resolve/main/4x-UltraSharp.pth" \
   "$MODELS/upscale_models/4x-UltraSharp.pth"

# ============================================================
echo ""
echo "=== [6/9] Wan 2.1 модели (видео) ==="

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

dl "$HF/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" \
   "$MODELS/clip_vision/clip_vision_h.safetensors"

# ============================================================
echo ""
echo "=== [7/9] Скачиваем antelopev2 ==="

python3 -c "
import insightface, os
root = os.path.expanduser('~/.insightface/models')
os.makedirs(root, exist_ok=True)
insightface.utils.storage.download('antelopev2', root=root, force=False)
print('  antelopev2 downloaded')
" || true

# Фикс вложенной папки (частая проблема)
if [ -d "$HOME/.insightface/models/antelopev2/antelopev2" ]; then
  mv ~/.insightface/models/antelopev2/antelopev2/* ~/.insightface/models/antelopev2/
  rmdir ~/.insightface/models/antelopev2/antelopev2
  echo "  -> Исправлена вложенная папка antelopev2"
fi

cp ~/.insightface/models/antelopev2/*.onnx "$MODELS/insightface/models/antelopev2/" 2>/dev/null || true
echo "  -> antelopev2 скопирован в ComfyUI/models/insightface/"

# ============================================================
echo ""
echo "=== [8/9] buffalo_l (InsightFace) ==="

python3 -c "
import insightface
app = insightface.app.FaceAnalysis(name='buffalo_l')
app.prepare(ctx_id=0)
print('  buffalo_l OK')
" || true

# ============================================================
echo ""
echo "=== [9/9] Финальная проверка ==="

python3 -c "
import os, torch

print(f'  torch: {torch.__version__} | CUDA: {torch.cuda.is_available()}')

libs = {'insightface': 'insightface', 'onnxruntime': 'onnxruntime', 'timm': 'timm', 'ultralytics': 'ultralytics', 'dill': 'dill', 'toml': 'toml'}
for name, mod in libs.items():
    try:
        m = __import__(mod)
        ver = getattr(m, '__version__', 'OK')
        print(f'  {name}: {ver}')
    except:
        print(f'  {name}: ОШИБКА')

models = {
    'RealVisXL fp16':       '/workspace/ComfyUI/models/checkpoints/RealVisXL_V5.0_fp16.safetensors',
    'Juggernaut XL v9':     '/workspace/ComfyUI/models/checkpoints/juggernautXL_v9Rdphoto2Lightning.safetensors',
    'SDXL VAE':             '/workspace/ComfyUI/models/vae/sdxl_vae.safetensors',
    'InstantID adapter':    '/workspace/ComfyUI/models/instantid/ip-adapter.bin',
    'InstantID controlnet': '/workspace/ComfyUI/models/controlnet/instantid-controlnet.safetensors',
    'CLIP Vision ViT-H':    '/workspace/ComfyUI/models/clip_vision/ViT-H-14-laion2B-s32B-b79K.safetensors',
    'IPAdapter PLUS FACE':  '/workspace/ComfyUI/models/ipadapter/ip-adapter-plus-face_sdxl_vit-h.safetensors',
    'Face YOLOv8m':         '/workspace/ComfyUI/models/ultralytics/bbox/face_yolov8m.pt',
    'Hand YOLOv8s':         '/workspace/ComfyUI/models/ultralytics/bbox/hand_yolov8s.pt',
    '4x-UltraSharp':        '/workspace/ComfyUI/models/upscale_models/4x-UltraSharp.pth',
    'antelopev2':           '/workspace/ComfyUI/models/insightface/models/antelopev2/scrfd_10g_bnkps.onnx',
    'Wan T2V 1.3B':         '/workspace/ComfyUI/models/diffusion_models/wan2.1_t2v_1.3B_bf16.safetensors',
    'Wan I2V 14B fp8':      '/workspace/ComfyUI/models/diffusion_models/wan2.1_i2v_480p_14B_fp8_scaled.safetensors',
    'Wan Fun Control 1.3B': '/workspace/ComfyUI/models/diffusion_models/wan2.1_fun_control_1.3B_bf16.safetensors',
    'Wan VAE':              '/workspace/ComfyUI/models/vae/wan_2.1_vae.safetensors',
    'T5 fp16':              '/workspace/ComfyUI/models/text_encoders/umt5_xxl_fp16.safetensors',
    'CLIP Vision Wan':      '/workspace/ComfyUI/models/clip_vision/clip_vision_h.safetensors',
}
print()
all_ok = True
for name, path in models.items():
    ok = os.path.exists(path) and os.path.getsize(path) > 1000
    status = 'OK     ' if ok else 'MISSING'
    if not ok: all_ok = False
    print(f'  [{status}]  {name}')

lora = '/workspace/ComfyUI/models/loras/sh_woman_v1.safetensors'
lora_ok = os.path.exists(lora)
print(f\"  [{'OK     ' if lora_ok else 'UPLOAD!'}]  LoRA sh_woman_v1\")

print()
if all_ok and lora_ok:
    print('  === ВСЁ ГОТОВО К РАБОТЕ ===')
else:
    print('  !!! Некоторые файлы отсутствуют — см. выше !!!')
"

echo ""
echo "============================================================"
echo "  УСТАНОВКА ЗАВЕРШЕНА!"
echo ""
echo "  ВРУЧНУЮ загрузи через JupyterLab (Upload):"
echo "    sh_woman_v1.safetensors      -> $MODELS/loras/"
echo "    lumi_photo_studio_pro.json   -> $COMFYUI_DIR/user/default/workflows/"
echo ""
echo "  Запуск ComfyUI:"
echo "    python3 $COMFYUI_DIR/main.py --listen 0.0.0.0 --port 8188 --bf16-vae &"
echo ""
echo "  После запуска открывать ТОЛЬКО через RunPod:"
echo "    My Pods -> Connect -> HTTP Service [8188]"
echo ""
echo "  lumi_photo_studio_pro.json — настройки:"
echo "    Checkpoint : juggernautXL_v9Rdphoto2Lightning.safetensors"
echo "    LoRA       : sh_woman_v1.safetensors  strength 0.8"
echo "    InstantID  : weight 0.65"
echo "    KSampler Base  : cfg 3.5 / dpmpp_2m_sde / karras / 30 steps"
echo "    KSampler Hires : cfg 4.0 / dpmpp_2m_sde / karras / 20 steps / denoise 0.45"
echo "    FaceDetailer   : denoise 0.35"
echo "    HandDetailer   : denoise 0.4"
echo "    Upscale    : 4x-UltraSharp -> 1664x2432"
echo ""
echo "  STOP (не Terminate!) чтобы сохранить данные"
echo "============================================================"
