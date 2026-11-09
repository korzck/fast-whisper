# Fast Whisper: guide for coding agents

This directory is the application. Its parent contains research, recordings and
benchmarks: do not treat those as application code or remove them during cleanup.
Read `docs/architecture.md` before changing boundaries or the worker protocol.

## Find the right code

| Task | Start here |
| --- | --- |
| Startup, windows, menu bar, application lifecycle | `Sources/App/AppDelegate.swift`, `Sources/main.swift` |
| Dictation lifecycle, queues, partial results, final paste | `Sources/Pipeline/AppState.swift` |
| Transcript and overlay state types | `Sources/Pipeline/Transcript.swift` |
| Microphone, resampling, pause detection, WAV segments | `Sources/Audio/AudioRecorder.swift` |
| Python processes, JSON requests, progress, process memory | `Sources/Backend/ModelProcess.swift` |
| Settings and replacement dictionary | `Sources/Settings/Settings.swift` |
| Transient shortcut editor state | `Sources/Settings/ShortcutCaptureState.swift` |
| Global shortcut, microphone permissions, system paste | `Sources/Platform/` |
| Windows, transcript rendering, overlay | `Sources/UI/` |
| End-to-end synthetic speech test | `Sources/Diagnostics/SelfTest.swift` |
| ASR engines (Whisper, GigaAM) | `backend/asr.py` |
| Correction model and prompt cache | `backend/llm.py` |
| Correction prompts and glossary | `backend/prompts.py` |
| Rejecting hallucinated corrections | `backend/guard.py` |
| Model identifiers, paths and downloads | `backend/models.py` |
| JSON serialization / dispatch / CLI | `backend/protocol.py`, `backend/server.py`, `backend/cli.py` |
| Build, packaging, dependency installation | `Makefile`, `scripts/` |

## Change rules

- Write developer documentation, code comments, docstrings and build/CLI messages
  in English. Keep localized UI text, language-specific model prompts, recognition
  patterns and speech test fixtures in their intended language.

- Prefer one responsibility per file. Add files in the existing feature folders;
  do not create generic `utils` modules or merge unrelated components.
- `AppState` owns dictation sequencing; views render state and invoke actions.
  Keep recognition and correction implementation in Python.
- Keep heavy Python imports inside model operations. Importing the backend must
  neither load weights nor download models nor redirect stdout.
- `backend.py` is a compatibility launcher used by installed app versions. Keep it
  thin; implementation belongs in the package. `python -m backend` is equivalent.
- Worker stdout is exclusively JSON lines. Native/model logs belong on stderr.
  Request IDs and existing message fields are a cross-language contract.
- Keep settings-window state in `ShortcutCaptureState` with `@StateObject`. Newer
  SDKs implement `@State` as a macro requiring SwiftUIMacros, which may be absent
  in Command Line Tools installations. Extend the SwiftUI probe when changing
  state ownership or introducing macros. See `docs/build-troubleshooting.md`.
- Preserve raw ASR fallback when correction fails the guard.
- Preserve separate ASR/LLM process lifetimes (load/unload and memory reporting).
- No model/runtime/generated files in source changes. Do not edit `.venv/`,
  `models/`, `build/`, or recordings as part of a normal code change.

## Verify

- `make test`: fast Python boundary tests, no model dependencies or downloads.
- `make doctor`: validate the selected Apple compiler, SDK, plugins and SwiftUI bindings.
- `make build`: compile and sign the macOS app without installing or launching it.
- `make selftest` / `make selftest SELFTEST_LANG=ru`: optional real model pipeline;
  requires installed dependencies, downloaded models and a working macOS session.
- `make app`: installs the built app and stops its running process. Use when the
  user asks to install or update the running application.

Do not use `make install` for routine verification: it can install dependencies,
compile whisper.cpp, download gigabytes and open the app. Report which checks ran
and distinguish compilation from actual microphone/model validation.
