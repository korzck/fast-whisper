"""Worker command dispatch; model adapters do not own the request loop."""
import json
import os
import time
import traceback
from .asr import ASR
from .llm import LLM
from .prompts import DEFAULT_GLOSSARY
from .protocol import send

def serve(kind, input_stream, engine=None):
    if engine is None:
        engine = ASR() if kind == "asr" else LLM()
    send(event="started", pid=os.getpid())
    for line in input_stream:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        if not isinstance(msg, dict):
            send(ok=False, event="error", message="Expected a JSON object")
            continue
        mid, cmd = msg.get("id"), msg.get("cmd")
        try:
            if cmd == "load":
                t = time.perf_counter()
                if kind == "asr":
                    engine.load(msg.get("glossary") or DEFAULT_GLOSSARY, msg.get("language") or "en",
                                msg.get("engine") or "whisper")
                else:
                    engine.load(msg.get("glossary") or DEFAULT_GLOSSARY, msg.get("language") or "en")
                send(event="ready", load_s=round(time.perf_counter() - t, 2))
            elif cmd == "transcribe" and kind == "asr":
                t = time.perf_counter()
                text = engine.transcribe(msg["path"], msg.get("language"))
                send(id=mid, ok=True, text=text, ms=round((time.perf_counter() - t) * 1000))
            elif cmd == "correct" and kind == "llm":
                t = time.perf_counter()
                text = engine.correct(msg["text"], msg.get("context", ""), msg.get("language"))
                send(id=mid, ok=True, text=text, ms=round((time.perf_counter() - t) * 1000))
            elif cmd == "quit":
                break
            else:
                raise ValueError(f"Unsupported {kind} command: {cmd!r}")
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            send(id=mid, ok=False, event="error", message=f"{type(e).__name__}: {e}")
