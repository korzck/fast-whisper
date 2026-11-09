"""JSON-lines output; isolate native stdout logs only in worker entry points."""
import json
import os
import sys

_output = None

def configure_worker_output():
    global _output
    _output = os.fdopen(os.dup(1), "w", buffering=1)
    os.dup2(2, 1)
    sys.stdout = sys.stderr

def send(**message):
    output = _output if _output is not None else sys.stdout
    output.write(json.dumps(message, ensure_ascii=False) + "\n")
    output.flush()

def stage(text: str, progress: float):
    send(event="stage", stage=text, progress=progress)
