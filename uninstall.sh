#!/usr/bin/env bash
# Removes everything Friday added to your desktop: links, shortcuts, autostart, app-menu entries, reminders.
# Your repo (with brain/me.md, memory/, config.env) and the packages it installed stay; remove those yourself if you want.
#   ./uninstall.sh            remove Friday's hooks
#   ./uninstall.sh --voice    also delete the downloaded speech models and Python env (~700 MB)
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$REPO/brain/bin"
say() { printf '\033[1;38;5;173m▸\033[0m %s\n' "$*"; }

"$BIN/friday-start" --stop >/dev/null 2>&1 || true
[ -d "$HOME/.config/quickshell/ii" ] && { "$BIN/friday-integrate" --revert || true; }

# marked blocks in compositor configs
for f in "$HOME/.config/hypr/custom/keybinds.conf" "$HOME/.config/hypr/custom/execs.conf" "$HOME/.config/hypr/custom/rules.conf" \
         "$HOME/.config/hypr/hyprland.conf" "$HOME/.config/sway/config" "$HOME/.config/labwc/autostart" "$HOME/.config/river/init"; do
  [ -f "$f" ] && python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
n = re.sub(r"\n?# >>> friday\n.*?# <<< friday\n?", "\n", s, flags=re.S)
if n != s:
    open(p, "w").write(n.rstrip("\n") + "\n"); print("▸ cleaned", p)
PY
done

# autostart, systemd unit, app-menu entries, icon
if [ -f "$HOME/.config/systemd/user/friday.service" ]; then
  systemctl --user disable --now friday.service >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/friday.service"; say "removed the systemd user service"
fi
for f in "$HOME/.config/autostart/friday.desktop" "$HOME/.local/share/applications/friday.desktop" \
         "$HOME/.local/share/applications/friday-selection.desktop" "$HOME/.local/share/applications/friday-talk.desktop" \
         "$HOME/.local/share/icons/hicolor/scalable/apps/friday.svg"; do
  [ -e "$f" ] && rm -f "$f" && say "removed $f"
done

# GNOME / XFCE shortcuts
if command -v gsettings >/dev/null 2>&1 && gsettings list-schemas 2>/dev/null | grep -q media-keys; then
  python3 - <<'PY'
import ast, subprocess
K = "org.gnome.settings-daemon.plugins.media-keys"
raw = subprocess.run(["gsettings", "get", K, "custom-keybindings"], capture_output=True, text=True).stdout.strip()
try:
    cur = ast.literal_eval(raw.replace("@as ", "")) if raw else []
except Exception:
    cur = []
keep = [p for p in cur if "/friday-" not in p]
if keep != cur:
    subprocess.run(["gsettings", "set", K, "custom-keybindings", str(keep)])
    print("▸ removed GNOME shortcuts")
PY
fi
if command -v xfconf-query >/dev/null 2>&1; then
  for k in "<Super><Alt>space" "<Shift><Super><Alt>space"; do
    xfconf-query -c xfce4-keyboard-shortcuts -p "/commands/custom/$k" -r >/dev/null 2>&1 || true
  done
fi

# pending reminders and timers
for u in $(systemctl --user list-timers 'friday-remind-*' --all --no-legend --plain 2>/dev/null | grep -o 'friday-remind-[0-9]*\.timer'); do
  systemctl --user stop "$u" >/dev/null 2>&1
done

# links
for l in "$HOME/.config/quickshell/friday" "$HOME/.local/share/friday"; do
  [ -L "$l" ] && rm "$l" && say "removed link $l"
done

if [ "${1:-}" = "--voice" ]; then
  rm -rf "$REPO/brain/.voice" "$REPO/brain/.venv" && say "deleted speech models and the Python env"
fi
command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && hyprctl reload >/dev/null 2>&1
command -v swaymsg >/dev/null 2>&1 && [ -n "${SWAYSOCK:-}" ] && swaymsg reload >/dev/null 2>&1
say "Friday removed. Your files in $REPO/brain are untouched."
