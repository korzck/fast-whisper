#!/usr/bin/env bash
# Check system requirements. Errors stop installation; warnings do not.
set -uo pipefail
fail=0
ok()   { printf "  ✓ %s\n" "$1"; }
warn() { printf "  ! %s\n" "$1"; }
err()  { printf "  ✗ %s\n" "$1"; fail=1; }

echo "→ Checking system requirements"

if [ "$(uname -m)" = "arm64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null || echo 0)" != "1" ]; then
  ok "Apple Silicon ($(sysctl -n machdep.cpu.brand_string))"
else
  err "Requires an Apple Silicon Mac (M1 or later), running natively without Rosetta"
fi

ver="$(sw_vers -productVersion)"
if [ "${ver%%.*}" -ge 14 ]; then ok "macOS $ver"; else err "Requires macOS 14 Sonoma or later (current: $ver)"; fi

if "$(dirname "$0")/check_swift.sh"; then
  ok "Swift compiler, SDK and SwiftUI macro preflight"
else
  err "No compatible SwiftUI developer tools found (see diagnostics above)"
fi

ram=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [ "$ram" -ge 16 ]; then ok "Memory: ${ram} GB"
else warn "Memory: ${ram} GB; models use ~4-5.5 GB, so 8 GB systems may run low"; fi

free_gb=$(df -g "$HOME" | awk 'NR==2 {print $4}')
if [ "$free_gb" -ge 10 ]; then ok "Free disk space: ${free_gb} GB"
else warn "Free: ${free_gb} GB; models need ~6 GB (~12 GB for benchmarks)"; fi

[ "$fail" = 0 ] || { echo "Installation stopped."; exit 1; }
