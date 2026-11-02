#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
BIN_DIR="$HOME/bin"
TARGET="$HS_DIR/focus_lock.lua"
INIT="$HS_DIR/init.lua"

mkdir -p "$HS_DIR" "$BIN_DIR"
touch "$INIT"

if [ -f "$TARGET" ]; then
    cp "$TARGET" "$TARGET.backup.$(date +%Y%m%d-%H%M%S)"
fi

cp "$HERE/focus_lock.lua" "$TARGET"
cp "$HERE/focus-lock" "$BIN_DIR/focus-lock"
cp "$HERE/focus-unlock" "$BIN_DIR/focus-unlock"
cp "$HERE/focus-status" "$BIN_DIR/focus-status"
chmod +x "$BIN_DIR/focus-lock" "$BIN_DIR/focus-unlock" "$BIN_DIR/focus-status"

if ! grep -Fq 'require("focus_lock")' "$INIT"; then
    {
        echo
        echo '-- Focus-lock module'
        echo 'require("focus_lock")'
    } >> "$INIT"
fi

cat <<EOF

Installed Focus Lock v5:
  $TARGET

Shell commands:
  $BIN_DIR/focus-lock
  $BIN_DIR/focus-unlock
  $BIN_DIR/focus-status

Now choose:
  Hammerspoon menu -> Reload Config

Then verify:
  focus-status

Expected version:
  5.0-interaction-lock

Use:
  focus-lock 50

Emergency unlock:
  Ctrl+Option+Cmd+Esc
EOF
