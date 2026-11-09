#!/usr/bin/env bash
# Build pywhispercpp (whisper.cpp) from source for Apple Silicon.
# GGML_METAL=1: GPU encoder and decoder through Metal.
# WHISPER_COREML=1: Neural Engine encoder when *-encoder.mlmodelc is beside the model.
# WHISPER_COREML_ALLOW_FALLBACK=1: fall back to Metal if the Core ML encoder is absent.
# The same binary supports GPU-only and Neural Engine comparisons.
# Called by make install; UV can override the uv executable path.
set -euo pipefail
cd "$(dirname "$0")/.."

UV="${UV:-$(command -v uv || echo "$HOME/.local/bin/uv")}"

WHISPER_COREML=1 WHISPER_COREML_ALLOW_FALLBACK=1 GGML_METAL=1 \
  "$UV" pip install --python .venv --reinstall --no-binary pywhispercpp --no-cache pywhispercpp

# Source distributions omit the libwhisper/libggml rpath; add @loader_path.
SP="$(.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
for f in "$SP"/_pywhispercpp*.so "$SP"/libwhisper*.dylib "$SP"/libggml*.dylib; do
  [ -e "$f" ] || continue
  [ -L "$f" ] && continue
  install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true
  codesign -f -s - "$f" 2>/dev/null || true
done

if .venv/bin/python -c "import _pywhispercpp as w; print(w.whisper_print_system_info())" 2>/dev/null | grep -q "COREML = 1"; then
  echo "  ✓ whisper.cpp built with Core ML"
else
  echo "  ✗ whisper.cpp lacks Core ML support or failed to load"; exit 1
fi
