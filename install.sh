#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
TARGET="$HS_DIR/focus_lock.lua"
INIT="$HS_DIR/init.lua"

mkdir -p "$HS_DIR"
touch "$INIT"

if [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
fi

cp "$HERE/focus_lock.lua" "$TARGET"

if ! grep -Fq 'require("focus_lock")' "$INIT"; then
    {
        echo
        echo '-- Focus-lock module'
        echo 'require("focus_lock")'
    } >> "$INIT"
fi

echo
echo "Installed Focus Lock v4:"
echo "  $TARGET"
echo
echo "Reload Hammerspoon:"
echo "  Hammerspoon menu -> Reload Config"
echo
echo "Verify:"
echo "  focus-status"
echo
echo "Expected version:"
echo "  4.0-input-gate"
echo
echo "Use:"
echo "  focus-lock 50"
echo
echo "Emergency unlock:"
echo "  Ctrl+Option+Cmd+Esc"
