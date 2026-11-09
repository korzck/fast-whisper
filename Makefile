# fast-whisper: one-command setup and build.
#
# Clone the repository, enter its directory and run `make install`.
# Stamp files let repeated installs skip completed steps.
# Compatible with the system GNU Make 3.81 on macOS.

SHELL       := /bin/bash
ROOT        := $(CURDIR)
PY          := .venv/bin/python
APP_NAME    := fast-whisper.app
APP_BUILD   := build/$(APP_NAME)
APP_BIN     := $(APP_BUILD)/Contents/MacOS/fast-whisper
INSTALL_DIR ?= $(HOME)/Applications
APP_INST    := $(INSTALL_DIR)/$(APP_NAME)
BUNDLE_ID   := com.fastwhisper.app
OPEN        ?= 1
# Resolve uv on each use: installation may make it available later.
UV           = $(shell command -v uv 2>/dev/null || echo $(HOME)/.local/bin/uv)
SWIFT_SRC   := $(shell find Sources -name '*.swift' -type f | sort)

.DEFAULT_GOAL := help
.PHONY: FORCE doctor build test help install check uv app run selftest update uninstall clean clean-models installed-check

help:
	@echo "fast-whisper - dictation for Apple Silicon Macs"
	@echo ""
	@echo "  make install      set up Python, whisper.cpp, models (~6 GB) and install to $(INSTALL_DIR)"
	@echo "  make doctor       check Swift compiler, SDK and macro plugins"
	@echo "  make build        build the .app without installing"
	@echo "  make test         run fast tests without models or microphone"
	@echo "  make app          rebuild and reinstall the application only"
	@echo "  make run          launch the application"
	@echo "  make selftest     test the pipeline without a microphone (English; SELFTEST_LANG=ru for Russian)"
	@echo "  make update       git pull + make install"
	@echo "  make uninstall    remove app, preferences and permissions; keep environment and models"
	@echo "  make clean        remove environment and build; keep models"
	@echo "  make clean-models remove models from the project directory"

# ---------------------------------------------------------------- Setup

install: check .venv/.deps .venv/.whispercpp models/.ready build/.installed
	@[ -d "$(APP_INST)" ] || { rm -f build/.installed; $(MAKE) --no-print-directory app; }
	@echo ""
	@echo "✓ fast-whisper installed: $(APP_INST)"
	@echo "  Runtime files are in $(ROOT). Keep this directory available; reinstall after moving it."
	@if [ "$(OPEN)" = "1" ]; then open "$(APP_INST)"; fi

check:
	@scripts/check_system.sh

uv:
	@if ! command -v uv >/dev/null 2>&1 && [ ! -x "$(HOME)/.local/bin/uv" ]; then \
		echo "→ Installing uv (Python environment manager)"; \
		if command -v brew >/dev/null 2>&1; then brew install uv; \
		else curl -LsSf https://astral.sh/uv/install.sh | sh; fi; \
	fi

# Python 3.12 and model worker dependencies.
.venv/.deps: requirements.txt | uv
	@echo "→ Python environment (.venv) and dependencies"
	@[ -x $(PY) ] || "$(UV)" venv --python 3.12 .venv
	@"$(UV)" pip install --python .venv -r requirements.txt
	@touch $@

# Build whisper.cpp with Metal and Core ML (Neural Engine encoder).
.venv/.whispercpp: scripts/install_whispercpp.sh .venv/.deps
	@echo "→ Building whisper.cpp with Core ML (1-4 minutes)"
	@UV="$(UV)" scripts/install_whispercpp.sh
	@touch $@

# Whisper large-v3-turbo q5_0, Core ML encoder and Gemma 3 4B.
models/.ready: backend/models.py .venv/.deps
	@echo "→ Models (~6 GB on first install; existing downloads are reused)"
	@$(PY) backend.py --download
	@touch $@

# ---------------------------------------------------------------- Application

# Recheck toolchain selection on every build; change the stamp only when it changes.
FORCE:

build/swift-toolchain.stamp: FORCE scripts/check_swift.sh scripts/swift_toolchain.sh scripts/probes/SwiftUIState.swift
	@scripts/check_swift.sh --stamp

doctor:
	@scripts/check_swift.sh

$(APP_BIN): $(SWIFT_SRC) scripts/build_app.sh scripts/swift_toolchain.sh build/swift-toolchain.stamp
	@echo "→ Building the application (swiftc)"
	@scripts/build_app.sh

# Keep the install stamp in build/: extra files inside the .app invalidate its signature.
build/.installed: $(APP_BIN)
	@echo "→ Installing to $(INSTALL_DIR)"
	@pkill -x fast-whisper 2>/dev/null || true
	@mkdir -p "$(INSTALL_DIR)"
	@rm -rf "$(APP_INST)"
	@ditto "$(APP_BUILD)" "$(APP_INST)"
	@touch $@
	@echo "  After rebuilding, macOS may request microphone and Accessibility permissions again."

build: $(APP_BIN)

app: build/.installed

test:
	@PYTHONDONTWRITEBYTECODE=1 $(PY) -m unittest discover -s tests -v

run:
	@open "$(APP_INST)"

installed-check:
	@[ -x "$(APP_BIN)" ] && [ -f models/.ready ] && [ -f .venv/.whispercpp ] || \
		{ echo "Run make install first"; exit 1; }

# Synthetic macOS speech uses the same models and VAD as microphone input.
# make selftest                    English (Samantha)
# make selftest SELFTEST_LANG=ru   Russian (Milena)
SELFTEST_LANG ?= en
ifeq ($(SELFTEST_LANG),ru)
SELFTEST_VOICE := Milena
SELFTEST_1     := Открой Claude Code в терминале и запусти npm install.
SELFTEST_2     := Мы развернули PostgreSQL в Kubernetes, а перед ним стоит Nginx.
else
SELFTEST_VOICE := Samantha
SELFTEST_1     := Open Claude Code in the terminal and run npm install.
SELFTEST_2     := We deployed PostgreSQL in Kubernetes, and Nginx sits in front of it.
endif
SELFTEST_DIR   := build/selftest/$(SELFTEST_LANG)

selftest: installed-check
	@mkdir -p $(SELFTEST_DIR)
	@if say -v '?' | grep -q '^$(SELFTEST_VOICE) '; then V="-v $(SELFTEST_VOICE)"; else V=""; \
		echo "  (voice $(SELFTEST_VOICE) is unavailable - System Settings > Accessibility > Spoken Content > Voices)"; fi; \
	[ -f $(SELFTEST_DIR)/1.wav ] || say $$V --data-format=LEI16@16000 -o $(SELFTEST_DIR)/1.wav "$(SELFTEST_1)"; \
	[ -f $(SELFTEST_DIR)/2.wav ] || say $$V --data-format=LEI16@16000 -o $(SELFTEST_DIR)/2.wav "$(SELFTEST_2)"
	@"$(APP_BIN)" --selftest --language $(SELFTEST_LANG) $(SELFTEST_DIR)/1.wav $(SELFTEST_DIR)/2.wav

update:
	@git pull --ff-only
	@$(MAKE) --no-print-directory install

uninstall:
	@pkill -x fast-whisper 2>/dev/null || true
	@rm -rf "$(APP_INST)" build/.installed
	@defaults delete $(BUNDLE_ID) 2>/dev/null || true
	@tccutil reset All $(BUNDLE_ID) >/dev/null 2>&1 || true
	@rm -rf "$(HOME)/Library/Logs/fast-whisper"
	@echo "✓ Application, preferences and permissions removed. Environment and models remain (make clean, make clean-models)."

clean:
	@rm -rf .venv build
	@echo "✓ Environment and build removed"

clean-models:
	@rm -rf models
	@echo "✓ Project models/ removed. Cached files remain in ~/.cache/huggingface/hub."
