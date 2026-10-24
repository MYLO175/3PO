#!/bin/bash
# Explicit setup only. Never called on app launch or automatically by the bridge.
set -euo pipefail
umask 077
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_ROOT="${1:-$HOME/Library/Application Support/com.mylomichael.missioncontrol/Graphiti/runtime}"
PYTHON="${THREEPO_GRAPHITI_PYTHON:-python3}"
"$PYTHON" -c 'import sys; assert sys.version_info >= (3,12), "Graphiti requires Python 3.12 or newer"'
mkdir -p "$RUNTIME_ROOT"
chmod 700 "$RUNTIME_ROOT"
"$PYTHON" -m venv "$RUNTIME_ROOT"
"$RUNTIME_ROOT/bin/python3" -m pip install --disable-pip-version-check -r "$SOURCE_DIR/requirements.lock.txt"
cp "$SOURCE_DIR/bridge.py" "$RUNTIME_ROOT/helper.py"
# Model setup downloads public weights only. No private text or credentials are needed.
HF_HOME="$RUNTIME_ROOT/huggingface" HF_HUB_DISABLE_TELEMETRY=1 HF_HUB_DISABLE_IMPLICIT_TOKEN=1 HF_HUB_DISABLE_XET=1 \
THREEPO_GRAPHITI_MODEL_CACHE="$RUNTIME_ROOT/models" "$RUNTIME_ROOT/bin/python3" - <<'PY'
import os
import onnxruntime
onnxruntime.disable_telemetry_events()
from huggingface_hub import snapshot_download
from fastembed import TextEmbedding
path = snapshot_download('Qdrant/bge-small-en-v1.5-onnx-Q',
    revision='aa8f8b060edb00e03bfdd08813a2949946c8ba55',
    cache_dir=os.environ['THREEPO_GRAPHITI_MODEL_CACHE'],
    allow_patterns=['config.json', 'tokenizer.json', 'tokenizer_config.json', 'special_tokens_map.json', 'model_optimized.onnx'])
model = TextEmbedding('BAAI/bge-small-en-v1.5', cache_dir=os.environ['THREEPO_GRAPHITI_MODEL_CACHE'],
                      providers=['CPUExecutionProvider'], threads=2, specific_model_path=path)
assert len(next(model.embed(['Fictional installation check']))) == 384
print('Graphiti runtime and local embeddings are ready.')
PY
printf 'Runtime: %s\n' "$RUNTIME_ROOT"
