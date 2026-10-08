#!/usr/bin/env bash
# Removes Friday's hooks and links. Your repo (and brain/me.md, memory/) stay where they are.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HYPR="$HOME/.config/hypr/custom"

"$REPO/brain/bin/friday-integrate" --revert || true
pkill -f "qs -c friday" 2>/dev/null || true
for l in "$HOME/.config/quickshell/friday" "$HOME/.local/share/friday"; do
  [ -L "$l" ] && rm "$l" && echo "removed link $l"
done
for f in keybinds.conf execs.conf rules.conf; do
  [ -f "$HYPR/$f" ] && python3 - "$HYPR/$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
n = re.sub(r"\n?# >>> friday\n.*?# <<< friday\n?", "\n", s, flags=re.S)
if n != s: open(p, "w").write(n.rstrip("\n") + "\n"); print("cleaned", p)
PY
done
echo "Friday removed. Run: hyprctl reload"
