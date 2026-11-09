"""Model identifiers, project paths and explicit downloads."""
from __future__ import annotations
import os
import shutil
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS_DIR = ROOT / "models" / "coreml"

WHISPER_REPO = "ggerganov/whisper.cpp"
WHISPER_FILE = "ggml-large-v3-turbo-q5_0.bin"
WHISPER_ENCODER_ZIP = "ggml-large-v3-turbo-encoder.mlmodelc.zip"
WHISPER_PATH = MODELS_DIR / WHISPER_FILE

LLM_REPO = "mlx-community/gemma-3-4b-it-4bit"


def ensure_whisper() -> Path:
    """Store both files in models/coreml/: whisper.cpp looks for the Core ML
    encoder beside the .bin after removing the -q5_0 suffix."""
    from huggingface_hub import hf_hub_download
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    if not WHISPER_PATH.exists():
        src = Path(hf_hub_download(WHISPER_REPO, WHISPER_FILE)).resolve()
        # Use a hard link: whisper.cpp resolves symlinks and would look for the
        # encoder beside the cached HF file. Copy instead when linking across disks.
        try:
            os.link(src, WHISPER_PATH)
        except OSError:
            shutil.copy2(src, WHISPER_PATH)
    encoder = MODELS_DIR / WHISPER_ENCODER_ZIP.removesuffix(".zip")
    if not encoder.exists():
        z = hf_hub_download(WHISPER_REPO, WHISPER_ENCODER_ZIP)
        with zipfile.ZipFile(z) as f:
            f.extractall(MODELS_DIR)
        shutil.rmtree(MODELS_DIR / "__MACOSX", ignore_errors=True)
    return WHISPER_PATH


def ensure_llm() -> str:
    from huggingface_hub import snapshot_download
    return snapshot_download(LLM_REPO)
