#!/usr/bin/env bash
# Project Friday installer. Idempotent: safe to re-run after every pull.
#
#   ~/.config/quickshell/friday  ->  <repo>/shell   (the UI)
#   ~/.local/share/friday        ->  <repo>/brain   (Claude bridge, helpers, your private files)
#   ~/.config/hypr/custom/rules.conf gets one marked `source` line for hypr/friday.conf
#
# Your personal files (me.md, memory/, config.env, device-profile.md, audit.log) are kept and moved
# into <repo>/brain, where .gitignore keeps them out of git.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QS="$HOME/.config/quickshell/friday"
DATA="$HOME/.local/share/friday"
HYPR="$HOME/.config/hypr/custom"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\033[1;38;5;173m▸\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*"; }

# ---- dependencies (warn, never block)
for dep in qs claude python3 wl-paste wl-copy grim notify-send hyprctl; do
  command -v "$dep" >/dev/null 2>&1 || warn "missing: $dep"
done
for dep in playerctl wpctl brightnessctl nmcli systemd-run; do
  command -v "$dep" >/dev/null 2>&1 || warn "optional, missing: $dep (some instant controls won't work)"
done

# ---- point a path at the repo, keeping anything that was there
link() {
  local src="$1" dst="$2"
  if [ -L "$dst" ]; then
    [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ] && { say "ok: $dst"; return; }
    rm "$dst"
  elif [ -e "$dst" ]; then
    mv "$dst" "$dst.bak-$STAMP"
    say "backed up existing $dst -> $dst.bak-$STAMP"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  say "linked $dst -> $src"
}

# ---- carry your private brain files over from an existing install
if [ -d "$DATA" ] && [ ! -L "$DATA" ]; then
  for f in me.md config.env device-profile.md audit.log memory .claude; do
    if [ -e "$DATA/$f" ] && [ ! -e "$REPO/brain/$f" ]; then
      cp -a "$DATA/$f" "$REPO/brain/$f"
      say "kept your $f"
    fi
  done
fi

link "$REPO/shell" "$QS"
link "$REPO/brain" "$DATA"

# ---- first-run personal files
[ -f "$REPO/brain/me.md" ] || { cp "$REPO/brain/me.example.md" "$REPO/brain/me.md"; warn "edit brain/me.md so Friday knows who you are"; }
[ -f "$REPO/brain/config.env" ] || cp "$REPO/brain/config.example.env" "$REPO/brain/config.env"
mkdir -p "$REPO/brain/memory"
[ -f "$REPO/brain/memory/notes.md" ] || printf '# Notes Friday keeps about how you work\n' > "$REPO/brain/memory/notes.md"
[ -f "$REPO/brain/device-profile.md" ] || printf '# Device profile\n(not generated yet)\n' > "$REPO/brain/device-profile.md"
chmod +x "$REPO"/brain/bin/*

# ---- Hyprland: replace any old inline blocks with one source line
if [ -d "$HYPR" ]; then
  for f in keybinds.conf execs.conf rules.conf; do
    [ -f "$HYPR/$f" ] || continue
    if grep -q '^# >>> friday' "$HYPR/$f"; then
      cp "$HYPR/$f" "$HYPR/$f.bak-$STAMP"
      python3 - "$HYPR/$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"\n?# >>> friday\n.*?# <<< friday\n?", "\n", s, flags=re.S)
open(p, "w").write(s.rstrip("\n") + "\n")
PY
    fi
  done
  printf '\n# >>> friday\nsource = %s\n# <<< friday\n' "$REPO/hypr/friday.conf" >> "$HYPR/rules.conf"
  say "Hyprland: sourced hypr/friday.conf from custom/rules.conf"
else
  warn "no ~/.config/hypr/custom; add 'source = $REPO/hypr/friday.conf' to your Hyprland config yourself"
fi

# ---- hook into illogical-impulse (search row, sidebar model, Claude usage in the bar)
"$REPO/brain/bin/friday-integrate" || warn "ii integration skipped; Friday itself still works"

say "done. Now run:  hyprctl reload && $REPO/brain/bin/friday-start --restart"
say "then press Super+Space."
