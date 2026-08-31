#!/usr/bin/env bash
# Update-only: refresh the game files in /var/www/back-of-dreams from the
# branch. Touches nothing else — no nginx, no firewall. Run after each new
# build is pushed.
set -euo pipefail
BRANCH="claude/3d-game-development-yi52wn"
BASE="https://raw.githubusercontent.com/liuzifengxjj1028/browser-use/${BRANCH}/game/dist/web"
DEST=/var/www/back-of-dreams
mkdir -p "$DEST"
for f in index.html index.js index.pck index.wasm index.audio.worklet.js \
         index.png index.icon.png index.apple-touch-icon.png; do
  echo "updating $f"
  curl -fsSL "$BASE/$f" -o "$DEST/$f.tmp" && mv "$DEST/$f.tmp" "$DEST/$f"
done
echo "Done. Hard-refresh https://atisbo.ai/dream/ (Cmd+Shift+R) to bypass cache."
