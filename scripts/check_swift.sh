#!/usr/bin/env bash
# Validate the actual SwiftUI state and bindings before building or downloading models.
set -euo pipefail
source "$(dirname "$0")/swift_toolchain.sh"
fw_select_swift_toolchain
fw_print_swift_toolchain
if [ "${1:-}" = "--stamp" ]; then
  stamp="$FW_PROJECT_ROOT/build/swift-toolchain.stamp"
  signature="$(fw_print_swift_toolchain)"
  if [ ! -f "$stamp" ] || [ "$(cat "$stamp")" != "$signature" ]; then
    printf '%s\n' "$signature" >"$stamp"
  fi
fi
