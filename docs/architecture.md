# Architecture

Fast Whisper is a native macOS menu-bar app plus two local Python workers.
Swift owns the user session, audio capture and macOS integrations. Python owns
model inference. The Makefile exposes commands; shell scripts perform packaging
and native dependency setup. There is no web server or network request in the
normal inference path. Missing models can be downloaded explicitly or on load.

## Data flow and ownership

```text
AppDelegate / HotKey / MainView
              │
              ▼
           AppState ──────────────► Paster
              │                      ▲
        AudioRecorder                │
       WAV / partial WAV             │
              │                      │
              ▼                      │
      ModelProcess("asr")            │
              │ JSON lines           │
      backend.server → ASR           │
              │ raw text             │
              ▼                      │
      ModelProcess("llm")            │
              │ JSON lines           │
      backend.server → LLM → guard   │
              │ corrected or raw     │
              ▼                      │
       AppState / Segment ───────────┘
              │
     TranscriptView / OverlayView
```

`AppState` is the session coordinator: queues, partial recognition, correction,
completion and paste timing. `AudioRecorder` handles capture/resampling and
segments; it does not invoke models. `ModelProcess` owns one child process and
pending callbacks; it does not contain recognition rules. Views observe state.
`Settings` persists preferences in UserDefaults. Platform adapters handle Carbon,
Accessibility, clipboard events and microphone permissions.

Python modules have narrow boundaries:

- `cli`: parse arguments, configure offline defaults, choose download or worker.
- `protocol`: serialize messages and preserve a dedicated stdout descriptor before
  redirecting native-library output to stderr. Only the worker CLI activates this.
- `server`: dispatch commands, correlate request IDs and report exceptions.
- `asr`: Whisper/Core ML and GigaAM adapters; weights loaded only on `load`.
- `llm`: MLX generation, prefix cache and conservative fallback through `guard`.
- `guard`: pure cleanup and acceptance rules, independently testable.
- `prompts`: language instructions and default glossary.
- `models`: repository identifiers, project-relative model paths and downloads.

`backend.py` remains a stable launcher for existing installed app binaries. New
callers may also use `.venv/bin/python -m backend asr` (or `llm`, `--download`).

## Worker contract

Each process handles one role (`asr` or `llm`) and reads one JSON object per line
from stdin. Every output line on stdout is a JSON object; diagnostics go to stderr.
Both languages use the same contract:

| Input | Output |
| --- | --- |
| Process starts | `{"event":"started","pid":123}` |
| `{"id":0,"cmd":"load","language":"ru","glossary":"...","engine":"whisper"}` | Stage events, then `{"event":"ready","load_s":1.2}` |
| `{"id":1,"cmd":"transcribe","path":"/tmp/clip.wav","language":"ru"}` | `{"id":1,"ok":true,"text":"...","ms":42}` |
| `{"id":2,"cmd":"correct","text":"...","context":"...","language":"ru"}` | Same response fields |
| `{"cmd":"quit"}` | Process exits |
| Failed request / wrong command | `{"id":1,"ok":false,"event":"error","message":"..."}` |

Stage events contain `event`, `stage`, `progress`. Load completion uses events,
not a normal text response. `transcribe` is only supported by ASR, `correct` only
by LLM. Malformed JSON is ignored; non-object JSON receives an error. A failed
request does not terminate the loop. EOF terminates the worker. Do not add stdout
prints to model code. Change both Swift parsing and Python tests when changing
this contract. User text is correction data, not an instruction to the model.

## Build and runtime files

`make build` compiles all `Sources/**/*.swift` with `swiftc`, creates the plist
and signs `build/fast-whisper.app`. No Xcode project or Swift package is required.
`make app` copies it to `~/Applications`. Adding a Swift file in `Sources/` requires
no manual source-list update. `make test` uses Python's standard unittest runner.
The end-to-end self-test keeps stderr and propagates failures.

The app currently reads `FWProjectRoot` from its plist and runs
`<root>/.venv/bin/python <root>/backend.py`. Model files are in `models/coreml`,
Gemma and GigaAM also use the Hugging Face cache. Logs are in
`~/Library/Logs/fast-whisper`; preferences use `com.fastwhisper.app`.

This is a developer/local installation, not a portable app bundle: the source
folder and Python environment must remain available. Moving the project requires
recreating its virtual environment and rebuilding the app. A later standalone
packaging change should bundle a relocatable Python runtime, move persistent
models into Application Support and test on a clean Mac. File organization alone
does not solve runtime distribution.

## Where to extend

Add an ASR engine in `backend/asr.py`; add the corresponding option in
`Sources/Settings/Settings.swift` and `Sources/UI/ModelCard.swift`. Change pause
handling in `AudioRecorder`; sequencing belongs in `AppState`. Edit correction
instructions in `prompts.py`, acceptance rules in `guard.py`, with fast regression
tests. Keep model-loading tests separate from the lightweight default test suite.
