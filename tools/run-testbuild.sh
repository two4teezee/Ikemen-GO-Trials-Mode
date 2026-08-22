#!/usr/bin/env bash
# Launch testbuild for the trials test loop and capture stdout.
#
# The shipped macOS binary links /opt/homebrew/opt/sdl2-compat/lib/libSDL2-2.0.0.dylib.
# If only `sdl2` is installed, DYLD_FALLBACK_LIBRARY_PATH resolves it without touching
# the system — the two have the same compatibility version (3201.0.0).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$ROOT/testbuild"
LOG="${LOG:-$BUILD/save/logs/run.log}"

BIN="$BUILD/I.K.E.M.E.N-Go.app/Contents/MacOS/Ikemen_GO_MacOSARM"
[ -x "$BIN" ] || { echo "No testbuild binary at $BIN" >&2; exit 1; }

for candidate in sdl2-compat sdl2; do
    if [ -d "/opt/homebrew/opt/$candidate/lib" ]; then
        export DYLD_FALLBACK_LIBRARY_PATH="/opt/homebrew/opt/$candidate/lib"
        break
    fi
done

mkdir -p "$(dirname "$LOG")"
cd "$BUILD"
echo "Logging to $LOG"
exec "$BIN" "$@" 2>&1 | tee "$LOG"
