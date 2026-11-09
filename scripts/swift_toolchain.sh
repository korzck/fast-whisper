#!/usr/bin/env bash
# Sourced by build and diagnostic scripts. Keep compatible with macOS Bash 3.2.
# Resolve compiler, SDK and macro plugins from one developer installation.

fw_try_swift_toolchain() {
  local developer="$1" compiler sdk platform toolchain server directory identity
  compiler="$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --find swiftc 2>>"$FW_SWIFT_LOG")" || return 1
  sdk="$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --show-sdk-path 2>>"$FW_SWIFT_LOG")" || return 1
  [ -x "$compiler" ] && [ -d "$sdk" ] || return 1

  FW_SWIFT_VERSION="$("$compiler" --version 2>>"$FW_SWIFT_LOG")" || return 1
  toolchain="$(cd "$(dirname "$compiler")/.." && pwd)" || return 1
  # CLT has no PlatformPath; its platform plugins may live under SDK/usr/lib.
  platform="$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --show-sdk-platform-path 2>/dev/null)" || platform=""
  server="$toolchain/bin/swift-plugin-server"
  FW_SWIFT_PLUGIN_FLAGS=()
  for directory in \
    "${platform:+$platform/Developer/usr/lib/swift/host/plugins}" \
    "$developer/usr/lib/swift/host/plugins" \
    "$sdk/usr/lib/swift/host/plugins" \
    "$toolchain/lib/swift/host/plugins"; do
    [ -n "$directory" ] && [ -d "$directory" ] || continue
    if [ -x "$server" ]; then
      FW_SWIFT_PLUGIN_FLAGS+=(-external-plugin-path "$directory#$server")
    else
      FW_SWIFT_PLUGIN_FLAGS+=(-plugin-path "$directory")
    fi
  done

  identity="$(printf '%s\n' "$developer" "$compiler" "$FW_SWIFT_VERSION" "$sdk" \
    "$(DEVELOPER_DIR="$developer" xcrun --sdk macosx --show-sdk-version 2>/dev/null)" \
    ${FW_SWIFT_PLUGIN_FLAGS[@]+"${FW_SWIFT_PLUGIN_FLAGS[@]}"} | cksum)"
  FW_SWIFT_CACHE="$FW_PROJECT_ROOT/build/ModuleCache/${identity%% *}"
  mkdir -p "$FW_SWIFT_CACHE"
  FW_SWIFT_FLAGS=(-swift-version 5 -target arm64-apple-macos14.0 -sdk "$sdk"
    -module-cache-path "$FW_SWIFT_CACHE")
  printf '\nDeveloper directory: %s\nCompiler: %s\nSDK: %s\n' "$developer" "$compiler" "$sdk" >>"$FW_SWIFT_LOG"
  # Exercise the app's state ownership, mutation and bindings, not just SwiftUI import.
  DEVELOPER_DIR="$developer" "$compiler" "${FW_SWIFT_FLAGS[@]}" \
    ${FW_SWIFT_PLUGIN_FLAGS[@]+"${FW_SWIFT_PLUGIN_FLAGS[@]}"} -typecheck \
    "$FW_PROJECT_ROOT/scripts/probes/SwiftUIState.swift" >>"$FW_SWIFT_LOG" 2>&1 || return 1
  FW_DEVELOPER_DIR="$developer"
  FW_SWIFTC="$compiler"
  FW_SWIFT_SDK="$sdk"
  export DEVELOPER_DIR="$developer"
}

fw_select_swift_toolchain() {
  local selected candidate
  FW_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  mkdir -p "$FW_PROJECT_ROOT/build"
  FW_SWIFT_LOG="$FW_PROJECT_ROOT/build/swift-toolchain.log"
  : >"$FW_SWIFT_LOG"
  selected="${DEVELOPER_DIR:-$(xcode-select -p 2>/dev/null || true)}"
  if [ -n "$selected" ] && fw_try_swift_toolchain "$selected"; then
    return 0
  fi
  # Respect an explicit developer choice. Do not silently mix different SDKs.
  if [ -z "${DEVELOPER_DIR:-}" ]; then
    for candidate in /Applications/Xcode*.app/Contents/Developer \
      "$HOME"/Applications/Xcode*.app/Contents/Developer; do
      [ -d "$candidate" ] && [ "$candidate" != "$selected" ] || continue
      if fw_try_swift_toolchain "$candidate"; then
        printf 'Using compatible Xcode: %s\n' "$candidate"
        return 0
      fi
    done
  fi
  cat "$FW_SWIFT_LOG" >&2
  cat >&2 <<'ERROR'
SwiftUI toolchain preflight failed. The compiler, macOS SDK and macro plugins
must come from a compatible Apple developer installation. SwiftUI macros are
provided by Apple developer tools, not by pip, Homebrew or a Swift package.

Install/update Command Line Tools with `xcode-select --install` or Software Update.
If they lack SwiftUIMacros, install full Xcode from the Mac App Store, open it once
to finish setup, then run:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build

Unset stale SDKROOT or TOOLCHAINS overrides if compiler/SDK versions disagree.
Run `make doctor` to retry and report compiler, SDK and plugin paths.
Full diagnostics: build/swift-toolchain.log
ERROR
  return 1
}

fw_print_swift_toolchain() {
  printf 'Developer: %s\nCompiler: %s\n%s\nSDK: %s\nModule cache: %s\n' \
    "$FW_DEVELOPER_DIR" "$FW_SWIFTC" "$FW_SWIFT_VERSION" "$FW_SWIFT_SDK" "$FW_SWIFT_CACHE"
  if [ "${#FW_SWIFT_PLUGIN_FLAGS[@]}" -gt 0 ]; then
    printf 'Macro plugin arguments:\n'
    printf '  %s\n' ${FW_SWIFT_PLUGIN_FLAGS[@]+"${FW_SWIFT_PLUGIN_FLAGS[@]}"}
  fi
  printf 'SwiftUI state and bindings compilation: OK\n'
}
