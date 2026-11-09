# Fast Whisper

Local dictation for macOS 14+ on Apple Silicon: Whisper/Core ML or GigaAM,
Gemma correction, a global keyboard shortcut, and pasting into the active field.

```sh
make install                   # Set up the environment, models and app (~6 GB initially)
make build                     # Build and sign the .app without installing
make app                       # Build and install to ~/Applications
make run                       # Launch the installed app
make test                      # Run fast tests without models or microphone input
make selftest                  # Test the pipeline with synthetic English speech
make selftest SELFTEST_LANG=ru  # Test the pipeline with synthetic Russian speech
```

Building requires Command Line Tools. The backend uses Python 3.12 in `.venv`.
`make install` sets up the environment with uv and builds whisper.cpp with Core ML.
Run `make help` for maintenance commands.

## Code navigation

| Directory | Responsibility |
| --- | --- |
| `Sources/App`, `Sources/main.swift` | Startup, windows and menu bar |
| `Sources/Pipeline` | Dictation sessions, queues and segment state |
| `Sources/Audio` | Microphone, resampling and pause-based segmentation |
| `Sources/Backend` | Python processes and the JSON protocol |
| `Sources/Platform` | Permissions, global shortcut and system paste |
| `Sources/Settings` | Preferences and text replacements |
| `Sources/UI` | SwiftUI interface and floating overlay |
| `Sources/Diagnostics` | End-to-end self-test |
| `backend` | ASR, LLM, prompts, correction guard, models and protocol |
| `scripts` | App packaging, system checks and whisper.cpp installation |
| `tests` | Fast backend boundary tests |

[Agent guide](AGENTS.md) · [Architecture and protocol](docs/architecture.md)

The app uses `.venv` and models from the project directory: this is a local
installation, not a portable standalone `.app`. Keep the project directory in
place after installing. The build is in `build/fast-whisper.app`; logs are in
`~/Library/Logs/fast-whisper`.
Research, recordings and benchmarks live in the parent directory and are not
part of the application source.
