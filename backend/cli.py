"""Explicit entry points for downloads and isolated model workers."""
import argparse
import os
import sys

def main(argv=None):
    parser = argparse.ArgumentParser(description="Fast Whisper local backend")
    parser.add_argument("kind", nargs="?", choices=("asr", "llm"))
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args(argv)
    if args.download:
        if args.kind:
            parser.error("--download cannot be combined with a worker kind")
        from .models import ensure_whisper, ensure_llm
        print(f"Whisper: {ensure_whisper()}", flush=True)
        print(f"Gemma: {ensure_llm()}", flush=True)
    elif args.kind:
        os.environ["HF_HUB_OFFLINE"] = "1"
        os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")
        from .protocol import configure_worker_output
        configure_worker_output()
        from .server import serve
        serve(args.kind, sys.stdin)
    else:
        parser.error("choose asr, llm or --download")
